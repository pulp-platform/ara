// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's slide unit. It is responsible for running the vector slide (up/down)
// instructions, which need access to the whole Vector Register File.

module sldu import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes   = 0,
    parameter  type          vaddr_t   = logic,                // Type used to address vector register file elements
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t),        // Width of the lane datapath
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0] // Byte-strobe type
  ) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    // Interface with the main sequencer
    input  pe_req_t                pe_req_i,
    input  logic                   pe_req_valid_i,
    output logic                   pe_req_ready_o,
    output pe_resp_t               pe_resp_o,
    // Interface with the lanes
    input  elen_t    [NrLanes-1:0] sldu_operand_i,
    input  logic     [NrLanes-1:0] sldu_operand_valid_i,
    output logic                   sldu_operand_ready_o,
    output logic     [NrLanes-1:0] sldu_result_req_o,
    output vid_t     [NrLanes-1:0] sldu_result_id_o,
    output vaddr_t   [NrLanes-1:0] sldu_result_addr_o,
    output elen_t    [NrLanes-1:0] sldu_result_wdata_o,
    output strb_t    [NrLanes-1:0] sldu_result_be_o,
    input  logic     [NrLanes-1:0] sldu_result_gnt_i,
    // Interface with the Mask Unit
    input  strb_t    [NrLanes-1:0] mask_i,
    input  logic     [NrLanes-1:0] mask_valid_i,
    output logic                   mask_ready_o
  );

  import cf_math_pkg::idx_width;

  /******************************
   *  Vector instruction queue  *
   ******************************/

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = 2;

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

  // Is the vector instruction queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  pe_req_t vinsn_issue_d, vinsn_issue_q;
  logic    vinsn_issue_valid;
  assign vinsn_issue_d     = vinsn_queue_d.vinsn[vinsn_queue_d.issue_pnt];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

  // Do we have a vector instruction with results being committed?
  pe_req_t vinsn_commit;
  logic    vinsn_commit_valid;
  assign vinsn_commit       = vinsn_queue_q.vinsn[vinsn_queue_q.commit_pnt];
  assign vinsn_commit_valid = (vinsn_queue_q.commit_cnt != '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_queue_q <= '0;
      vinsn_issue_q <= '0;
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
      vinsn_issue_q <= vinsn_issue_d;
    end
  end

  /*******************
   *  Result queues  *
   *******************/

  localparam int unsigned ResultQueueDepth = 2;

  // There is a result queue per lane, holding the results that were not
  // yet accepted by the corresponding lane.
  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } payload_t;

  // Result queue
  payload_t [ResultQueueDepth-1:0][NrLanes-1:0] result_queue_d, result_queue_q;
  logic     [ResultQueueDepth-1:0][NrLanes-1:0] result_queue_valid_d, result_queue_valid_q;
  // We need two pointers in the result queue. One pointer to
  // indicate with `payload_t` we are currently writing into (write_pnt),
  // and one pointer to indicate which `payload_t` we are currently
  // reading from and writing into the lanes (read_pnt).
  logic     [idx_width(ResultQueueDepth)-1:0]   result_queue_write_pnt_d, result_queue_write_pnt_q;
  logic     [idx_width(ResultQueueDepth)-1:0]   result_queue_read_pnt_d, result_queue_read_pnt_q;
  // We need to count how many valid elements are there in this result queue.
  logic     [idx_width(ResultQueueDepth):0]     result_queue_cnt_d, result_queue_cnt_q;

  // Is the result queue full?
  logic result_queue_full;
  assign result_queue_full = (result_queue_cnt_q == ResultQueueDepth);
  // Is the result queue empty?
  logic result_queue_empty;
  assign result_queue_empty = (result_queue_cnt_q == '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_result_queue_ff
    if (!rst_ni) begin
      result_queue_q           <= '0;
      result_queue_valid_q     <= '0;
      result_queue_write_pnt_q <= '0;
      result_queue_read_pnt_q  <= '0;
      result_queue_cnt_q       <= '0;
    end else begin
      result_queue_q           <= result_queue_d;
      result_queue_valid_q     <= result_queue_valid_d;
      result_queue_write_pnt_q <= result_queue_write_pnt_d;
      result_queue_read_pnt_q  <= result_queue_read_pnt_d;
      result_queue_cnt_q       <= result_queue_cnt_d;
    end
  end

  /****************
   *  Slide unit  *
   ****************/

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // Remaining bytes of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining bytes of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  always_comb begin: p_sldu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_d   = issue_cnt_q;
    commit_cnt_d  = commit_cnt_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_req_i.vinsn_running;

    // We are not ready, by default
    pe_resp              = '0;
    mask_ready_o         = 1'b0;
    sldu_operand_ready_o = 1'b0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    /********************************
     *  Write results into the VRF  *
     ********************************/

    for (int lane = 0; lane < NrLanes; lane++) begin: result_write
      sldu_result_req_o[lane]   = result_queue_valid_q[result_queue_read_pnt_q][lane];
      sldu_result_addr_o[lane]  = result_queue_q[result_queue_read_pnt_q][lane].addr;
      sldu_result_id_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].id;
      sldu_result_wdata_o[lane] = result_queue_q[result_queue_read_pnt_q][lane].wdata;
      sldu_result_be_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].be;

      // Received a grant from the VRF.
      // Deactivate the request, but do not bump the pointers for now.
      if (sldu_result_gnt_i[lane]) begin
        result_queue_valid_d[result_queue_read_pnt_q][lane] = 1'b0;
        result_queue_d[result_queue_read_pnt_q][lane]       = '0;
      end
    end: result_write

    // All lanes accepted the VRF request
    if (!(|result_queue_valid_d[result_queue_read_pnt_q]))
      // There is something waiting to be written
      if (!result_queue_empty) begin
        // Increment the read pointer
        if (result_queue_read_pnt_q == ResultQueueDepth-1)
          result_queue_read_pnt_d = 0;
        else
          result_queue_read_pnt_d = result_queue_read_pnt_q + 1;

        // Decrement the counter of results waiting to be written
        result_queue_cnt_d -= 1;

        // Decrement the counter of remaining vector elements waiting to be written
        commit_cnt_d = commit_cnt_q - NrLanes * 8;
        if (commit_cnt_q < (NrLanes * 8))
          commit_cnt_d = '0;
      end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && commit_cnt_d == '0) begin
      // Mark the vector instruction as being done
      pe_resp.vinsn_done[vinsn_commit.id] = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
        vinsn_queue_d.commit_pnt = '0;
      else
        vinsn_queue_d.commit_pnt += 1;

      // Update the commit counter for the next instruction
      if (vinsn_queue_d.commit_cnt != '0)
        commit_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl << int'(vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vtype.vsew);
    end

    /****************************
     *  Accept new instruction  *
     ****************************/

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] && pe_req_i.vfu == VFU_SlideUnit) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d = pe_req_i.vl << int'(pe_req_i.vtype.vsew);
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = pe_req_i.vl << int'(pe_req_i.vtype.vsew);

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_sldu

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


endmodule: sldu
