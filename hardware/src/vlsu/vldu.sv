// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File:   vldu.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   03.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is Ara's vector load unit. It receives transactions on the R bus,
// upon receiving vector memory operations.

module vldu import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes      = 0,
    parameter type          vaddr_t      = logic,                   // Type used to address vector register file elements
    // AXI Interface parameters
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_r_t      = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter int           DataWidth    = $bits(elen_t),
    parameter type          strb_t       = logic[DataWidth/8-1:0],
    parameter type          axi_addr_t   = logic [AxiAddrWidth-1:0]
  ) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Memory interface
    input  axi_r_t                         axi_r_i,
    input  logic                           axi_r_valid_i,
    output logic                           axi_r_ready_o,
    // Interface with the main sequencer
    input  pe_req_t                        pe_req_i,
    input  logic                           pe_req_valid_i,
    output logic                           pe_req_ready_o,
    output pe_resp_t                       pe_resp_o,
    // Interface with the address generator
    input  addrgen_axi_req_t               axi_addrgen_req_i,
    input  logic                           axi_addrgen_req_valid_i,
    output logic                           axi_addrgen_req_ready_o,
    // Interface with the lanes
    output logic             [NrLanes-1:0] ldu_result_req_o,
    output vid_t             [NrLanes-1:0] ldu_result_id_o,
    output vaddr_t           [NrLanes-1:0] ldu_result_addr_o,
    output elen_t            [NrLanes-1:0] ldu_result_wdata_o,
    output strb_t            [NrLanes-1:0] ldu_result_be_o,
    input  logic             [NrLanes-1:0] ldu_result_gnt_i
  );

  import cf_math_pkg::idx_width;

  /*******************
   *  Result queues  *
   *******************/

  // There is a FIFO per lane, holding the results that were not
  // yet accepted by the corresponding lane.

  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } payload_t;

  payload_t [NrLanes-1:0] result_queue;
  logic     [NrLanes-1:0] result_queue_push;
  logic     [NrLanes-1:0] result_queue_full;
  logic     [NrLanes-1:0] result_queue_empty;

  assign ldu_result_req_o = ~result_queue_empty;
  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_result_queue
    fifo_v3 #(
      .DEPTH     (2               ),
      .DATA_WIDTH($bits(payload_t))
    ) i_result_queue (
      .clk_i     (clk_i                                                                                            ),
      .rst_ni    (rst_ni                                                                                           ),
      .flush_i   (1'b0                                                                                             ),
      .testmode_i(1'b0                                                                                             ),
      .data_i    (result_queue[lane]                                                                               ),
      .push_i    (result_queue_push                                                                                ),
      .full_o    (result_queue_full                                                                                ),
      .data_o    ({ldu_result_id_o[lane], ldu_result_addr_o[lane], ldu_result_wdata_o[lane], ldu_result_be_o[lane]}),
      .empty_o   (result_queue_empty[lane]                                                                         ),
      .pop_i     (ldu_result_gnt_i[lane]                                                                           ),
      .usage_o   (/* Unused */                                                                                     )
    );
  end: gen_result_queue

  /******************************
   *  Vector instruction queue  *
   ******************************/

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = 4;

  struct packed {
    pe_req_t [VInsnQueueDepth-1:0] vinsn;

    // Each instruction can be in one of the three execution phases.
    // - Being accepted (i.e., it is being stored for future execution in this
    //   vector functional unit).
    // - Being issued (i.e., its micro-operations are currently being issued
    //   to the corresponding functional units).
    // - Being committed (i.e., its results are being written to the vector
    //   register file).
    // We need pointers to index which instruction is at each execution phase
    // between the VInsnQueueDepth instructions in memory.
    logic [idx_width(VInsnQueueDepth)-1:0] accept_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] issue_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] commit_pnt;

    // We also need to count how many instructions are queueing to be
    // issued/committed, to avoid accepting more instructions than
    // we can handle.
    logic [idx_width(VInsnQueueDepth):0] issue_cnt;
    logic [idx_width(VInsnQueueDepth):0] commit_cnt;
  } vinsn_queue_d, vinsn_queue_q;

  // Is the vector instructoin queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  pe_req_t vinsn_issue;
  logic    vinsn_issue_valid;
  assign vinsn_issue       = vinsn_queue_q.vinsn[vinsn_queue_q.issue_cnt];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

  // Do we have a vector instruction with results being committed?
  pe_req_t vinsn_commit;
  logic    vinsn_commit_valid;
  assign vinsn_commit       = vinsn_queue_q.vinsn[vinsn_queue_q.commit_cnt];
  assign vinsn_commit_valid = (vinsn_queue_q.commit_cnt != '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_queue_q <= '0;
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
    end
  end

  /***************
   *  Load Unit  *
   ***************/

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  always_comb begin: p_vldu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_req_i.vinsn_running;

    // We are not ready, by default
    result_queue            = '0;
    result_queue_push       = '0;
    axi_addrgen_req_ready_o = 1'b0;
    pe_resp_o               = '0;
    axi_r_ready_o           = 1'b0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;


  end: p_vldu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q <= '0;
    end else begin
      vinsn_running_q <= vinsn_running_d;
    end
  end

/*
  struct packed {
    // AXI pointers
    logic [$clog2(StrbWidth):0] axi_pnt;
    vsize_full_t burst_pnt ;
    logic first_word ;
  } obuf_d, obuf_q;

  logic [NR_LANES-1:0] lane_req_d, lane_req_q;


  struct packed {
    logic [VLOOP_ID-1:0] loop_done;
  } opqueue_d, opqueue_q;


  riscv::vwidth_t width_i;
  assign width_i = opqueue_q.insn[opqueue_q.issue_pnt].vd.dstt.width;

  // Running loops
  logic [VLOOP_ID-1:0] loop_running_d, loop_running_q;


  word_full_t ld_operand;

  vsize_full_t issue_cnt_d, issue_cnt_q;
  vsize_full_t commit_cnt_d, commit_cnt_q;

  `define MIN2(a,b) (((a) < (b)) ? (a) : (b))
  `define MIN3(a,b,c) (((`MIN2(a,b)) < (c)) ? (`MIN2(a,b)) : (c))

  // Number of bytes being committed
  vsize_full_t vrf_commit_cnt;
  vsize_full_t axi_commit_cnt;
  vsize_full_t burst_commit_cnt;
  vsize_full_t commit_cnt;

  assign vrf_commit_cnt   = (8 * NR_LANES) - obuf_q.result_pnt ;                             // Bytes remaining to fill a VRF word
  assign axi_commit_cnt   = StrbWidth - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]; // Bytes remaining to use a whole AXI word
  assign burst_commit_cnt = addr_i.burst_length - obuf_q.burst_pnt ;                         // Bytes remaining in the current AXI burst
  assign commit_cnt       = `MIN3(burst_commit_cnt, axi_commit_cnt, vrf_commit_cnt) ;        // Bytes effectively being read

  always_comb begin
    // Maintain state

    // Operands
    ld_operand = operation_issue_q.mask == riscv::NOMASK ? '1 : deshuffle(ld_operand_i, width_i);

    // R Channel
    begin: r_channel
      if (ara_axi_resp_i.r_valid) begin
        if (issue_valid && !obuf_full && (ld_operand.valid || operation_issue_q.mask == riscv::NOMASK) & addr_valid_i) begin

          // Copy data
          for (int b = 0; b < StrbWidth; b++)
            if (b < commit_cnt) begin
              obuf_d.result[obuf_q.write_pnt].w8[obuf_q.result_pnt + b] = ara_axi_resp_i.r.data[8*b + 8*obuf_q.axi_pnt + 8*addr_i.addr[$clog2(StrbWidth)-1:0] +: 8] & ld_operand.word.w8[obuf_q.result_pnt + b];
            end

          // Bump pointers
          obuf_d.axi_pnt += commit_cnt ;
          obuf_d.burst_pnt += commit_cnt ;
          obuf_d.result_pnt += commit_cnt;

          if (obuf_d.axi_pnt == StrbWidth) begin
            ara_axi_req_o.r_ready = 1'b1 ;
            obuf_d.axi_pnt        = -addr_i.addr[$clog2(StrbWidth)-1:0];
            obuf_d.first_word     = 1'b0 ;
          end

          if (obuf_d.burst_pnt == addr_i.burst_length) begin
            ara_axi_req_o.r_ready = 1'b1;
            obuf_d.axi_pnt        = '0 ;
            obuf_d.burst_pnt      = '0 ;
            obuf_d.first_word     = 1'b1;
            addr_ready_o          = 1'b1;
          end

          // Filled up a word.
          if (obuf_d.result_pnt == (NR_LANES * 8) || obuf_d.result_pnt == issue_cnt_q) begin
            obuf_d.write_pnt += 1;
            obuf_d.cnt += 1 ;
            obuf_d.result_pnt = '0;
            issue_cnt_d -= (NR_LANES * 8);
            ld_operand_ready_o = 1'b1;
          end
        end
      end
    end: r_channel

    // Output interface
    for (int l = 0; l < NR_LANES; l++) begin
      ld_result_o[l].req   = obuf_q.lane_result[l].valid;
      ld_result_o[l].wdata = obuf_q.lane_result[l].word ;
      ld_result_o[l].prio  = 1'b0 ;
      ld_result_o[l].we    = 1'b1 ;
      ld_result_o[l].addr  = operation_commit_q.vd.addr ;
      ld_result_o[l].id    = operation_commit_q.id ;

      if (ld_result_gnt_i[l]) begin
        obuf_d.lane_result[l].word  = '0 ;
        obuf_d.lane_result[l].valid = 1'b0;
      end
    end

    // Idle output interfaces
    for (int l = 0; l < NR_LANES; l++) begin
      lane_req_d[l] = obuf_d.lane_result[l].valid;
      lane_req_q[l] = obuf_q.lane_result[l].valid;
    end

    if (~(|lane_req_d)) begin
      // There is something waiting to be written
      if (!obuf_empty) begin
        obuf_d.lane_result             = shuffle(obuf_q.result[obuf_q.read_pnt], opqueue_q.insn[opqueue_q.commit_pnt].vd.dstt.width);
        obuf_d.result[obuf_q.read_pnt] = '0 ;

        // If this is a scalar, broadcast result into all lanes.
        if (operation_commit_q.vd.dstt.shape == riscv::SH_SCALAR) begin
          for (int l = 0; l < NR_LANES; l++)
            obuf_d.lane_result[l] = obuf_d.lane_result[0];
        end

        obuf_d.read_pnt += 1;
        obuf_d.cnt -= 1 ;
      end

      // Finished writing
      if (|lane_req_q) begin
        commit_cnt_d -= 8 * NR_LANES;
        opqueue_d.insn[opqueue_q.commit_pnt].vd.addr = increment_addr(operation_commit_q.vd.addr, operation_commit_q.vd.id);
      end
    end

    // Finished issuing micro-operations
    if (issue_valid && $signed(issue_cnt_d) <= 0) begin
      opqueue_d.issue_cnt -= 1;
      opqueue_d.issue_pnt += 1;

      if (opqueue_d.issue_cnt != 0)
        issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].vd.length;
    end

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      opqueue_d.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].vd.length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && !loop_running_q[operation_i.id] && operation_i.fu == VFU_LD) begin
      opqueue_d.insn[opqueue_q.accept_pnt] = operation_i;
      loop_running_d[operation_i.id]       = 1'b1 ;

      // Unused
      begin
        opqueue_d.insn[opqueue_q.accept_pnt].loop_running = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].rs1          = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].rs2          = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].imm          = '0;
      end

      // Initialize issue and commit counters
      if (opqueue_d.issue_cnt == 0)
        issue_cnt_d = operation_i.vd.length;
      if (opqueue_d.commit_cnt == 0)
        commit_cnt_d = operation_i.vd.length;

      // Bump pointers
      opqueue_d.accept_pnt += 1;
      opqueue_d.issue_cnt += 1 ;
      opqueue_d.commit_cnt += 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      obuf_q         <= '0;
      opqueue_q      <= '0;
      loop_running_q <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      obuf_q         <= obuf_d ;
      opqueue_q      <= opqueue_d ;
      loop_running_q <= loop_running_d;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;
    end
  end
*/
endmodule : vldu
