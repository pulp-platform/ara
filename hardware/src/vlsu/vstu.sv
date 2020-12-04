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
// File:   vstu.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   04.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is Ara's vector store unit. It sends transactions on the W bus,
// upon receiving vector memory operations.

module vstu import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes      = 0,
    parameter type          vaddr_t      = logic,                   // Type used to address vector register file elements
    // AXI Interface parameters
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_w_t      = logic,
    parameter type          axi_b_t      = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter int           DataWidth    = $bits(elen_t),
    parameter type          strb_t       = logic[DataWidth/8-1:0],
    parameter type          axi_addr_t   = logic [AxiAddrWidth-1:0]
  )(
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Memory interface
    output axi_w_t                         axi_w_o,
    output logic                           axi_w_valid_o,
    input  logic                           axi_w_ready_i,
    input  axi_b_t                         axi_b_i,
    input  logic                           axi_b_valid_i,
    output logic                           axi_b_ready_o,
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
    input  elen_t            [NrLanes-1:0] stu_operand_i,
    input  logic             [NrLanes-1:0] stu_operand_valid_i,
    output logic                           stu_operand_ready_o
  );

  import cf_math_pkg::idx_width;

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
  assign vinsn_issue       = vinsn_queue_q.vinsn[vinsn_queue_q.issue_pnt];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

  // Do we have a vector instruction with results being committed?
  pe_req_t vinsn_commit;
  logic    vinsn_commit_valid;
  assign vinsn_commit       = vinsn_queue_q.vinsn[vinsn_queue_q.commit_pnt];
  assign vinsn_commit_valid = (vinsn_queue_q.commit_cnt != '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_queue_q <= '0;
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
    end
  end

  /****************
   *  Store Unit  *
   ****************/

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // Remaining elements of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining elements of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  always_comb begin: p_vstu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_d   = issue_cnt_q;
    commit_cnt_d  = commit_cnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_req_i.vinsn_running;

    // We are not ready, by default
    axi_addrgen_req_ready_o = 1'b0;
    pe_resp                 = '0;
    axi_w_o                 = '0;
    axi_w_valid_o           = 1'b0;
    axi_b_ready_o           = 1'b0;
    stu_operand_ready_o     = 1'b0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    /***********************************
     *  Write data into the W channel  *
     ***********************************/


    /****************************
     *  Accept new instruction  *
     ****************************/

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] && pe_req_i.vfu == VFU_StoreUnit) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Unused fields
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].vs1           = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].use_vs1       = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].vs2           = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].use_vs2       = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op     = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].use_scalar_op = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].stride        = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].vinsn_running = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].hazard_vs1    = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].hazard_vs2    = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].hazard_vm     = '0;
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].hazard_vd     = '0;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d = pe_req_i.vl;
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = pe_req_i.vl;

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_vstu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q <= '0;
      issue_cnt_q     <= '0;
      commit_cnt_q    <= '0;
      pe_resp_o       <= '0;
    end else begin
      vinsn_running_q <= vinsn_running_d;
      issue_cnt_q     <= issue_cnt_d;
      commit_cnt_q    <= commit_cnt_d;
      pe_resp_o       <= pe_resp;
    end
  end

/*

 struct packed {
 // Pointers
 voffset_full_t result_pnt;
 voffset_full_t axi_pnt ;
 vsize_full_t burst_pnt ;

 logic b_ready;
 } obuf_q, obuf_d;

 vsize_full_t issue_cnt_d, issue_cnt_q;
 vsize_full_t commit_cnt_d, commit_cnt_q;

 word_t      [1:0][NR_LANES-1:0] st_operand_transposed;
 word_full_t [1:0]               st_operand_deshuffled;

 always_comb begin: transpose
 for (int l = 0; l < NR_LANES; l++) begin
 st_operand_transposed[0][l] = st_operand_i[l][0];
 st_operand_transposed[1][l] = st_operand_i[l][1];
 end
 end

 assign st_operand_deshuffled[0] = operation_issue_q.mask == riscv::NOMASK ? '1 : deshuffle(st_operand_transposed[0], width_i);
 assign st_operand_deshuffled[1] = deshuffle(st_operand_transposed[1], width_i);

 `define MIN2(a,b) (((a) < (b)) ? (a) : (b))
 `define MIN3(a,b,c) (((`MIN2(a,b)) < (c)) ? (`MIN2(a,b)) : (c))

 // How many bytes are being written
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


 // W Channel
 begin: w_channel
 ara_axi_req_o.w_valid = issue_valid & (st_operand_deshuffled[0].valid || operation_issue_q.mask == riscv::NOMASK) & st_operand_deshuffled[1].valid & addr_valid_i;

 // Copy data
 for (int b = 0; b < StrbWidth; b++)
 // Bound check
 if (b >= obuf_q.axi_pnt + addr_i.addr[$clog2(StrbWidth)-1:0] && b < commit_cnt + obuf_q.axi_pnt + addr_i.addr[$clog2(StrbWidth)-1:0]) begin
 ara_axi_req_o.w.data[8*b +: 8] = st_operand_deshuffled[1].word.w8[obuf_q.result_pnt + b - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]] ;
 ara_axi_req_o.w.strb[b]        = st_operand_deshuffled[0].word.w8[obuf_q.result_pnt + b - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]][0] ;
 end

 if (ara_axi_resp_i.w_ready && ara_axi_req_o.w_valid) begin
 obuf_d.result_pnt += commit_cnt;
 obuf_d.axi_pnt += commit_cnt ;
 obuf_d.burst_pnt += commit_cnt ;

 if (obuf_d.axi_pnt == StrbWidth)
 obuf_d.axi_pnt = -addr_i.addr[$clog2(StrbWidth)-1:0];

 if (obuf_d.burst_pnt == addr_i.burst_length) begin
 ara_axi_req_o.w.last = 1'b1;
 obuf_d.axi_pnt       = '0 ;
 obuf_d.burst_pnt     = '0 ;
 obuf_d.b_ready       = 1'b1; // Send B_READY
 addr_ready_o         = 1'b1;
 end

 if (obuf_d.result_pnt == (NR_LANES * 8) || obuf_d.result_pnt == issue_cnt_q) begin
 obuf_d.result_pnt  = '0 ;
 st_operand_ready_o = 1'b1;
 issue_cnt_d -= (NR_LANES * 8) ;
 commit_cnt_d -= (NR_LANES * 8);
 end
 end
 end: w_channel

 // B Channel
 begin: b_channel
 ara_axi_req_o.b_ready = obuf_d.b_ready;
 if (ara_axi_resp_i.b_valid)
 obuf_d.b_ready = 1'b0;

 // Finished issuing micro-operations
 if (issue_valid && $signed(issue_cnt_d) <= 0) begin
 opqueue_d.issue_cnt -= 1;
 opqueue_d.issue_pnt += 1;

 if (opqueue_d.issue_cnt != 0)
 issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].vd.length;
 end
 end: b_channel

 // Finished committing results
 if (commit_valid && $signed(commit_cnt_d) <= 0) begin
 opqueue_d.loop_done[operation_commit_q.id] = 1'b1;

 opqueue_d.commit_cnt -= 1;
 opqueue_d.commit_pnt += 1;

 if (opqueue_d.commit_cnt != 0)
 commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].vd.length;
 end

 // Accept new instruction
 if (!opqueue_full && operation_i.valid && !loop_running_q[operation_i.id] && operation_i.fu == VFU_ST) begin
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
 */
endmodule : vstu
