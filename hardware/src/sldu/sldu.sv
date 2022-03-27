// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's slide unit. It is responsible for running the vector slide (up/down)
// instructions, which need access to the whole Vector Register File.

module sldu import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes = 0,
    parameter  type          vaddr_t = logic, // Type used to address vector register file elements
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t), // Width of the lane datapath
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0] // Byte-strobe type
  ) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    // Interface with the main sequencer
    input  pe_req_t                pe_req_i,
    input  logic                   pe_req_valid_i,
    input  logic     [NrVInsn-1:0] pe_vinsn_running_i,
    output logic                   pe_req_ready_o,
    output pe_resp_t               pe_resp_o,
    // Interface with the lanes
    input  elen_t    [NrLanes-1:0] sldu_operand_i,
    input  target_fu_e [NrLanes-1:0] sldu_operand_target_fu_i,
    input  logic     [NrLanes-1:0] sldu_operand_valid_i,
    output logic     [NrLanes-1:0] sldu_operand_ready_o,
    output logic     [NrLanes-1:0] sldu_result_req_o,
    output vid_t     [NrLanes-1:0] sldu_result_id_o,
    output vaddr_t   [NrLanes-1:0] sldu_result_addr_o,
    output elen_t    [NrLanes-1:0] sldu_result_wdata_o,
    output strb_t    [NrLanes-1:0] sldu_result_be_o,
    input  logic     [NrLanes-1:0] sldu_result_gnt_i,
    input  logic     [NrLanes-1:0] sldu_result_final_gnt_i,
    // Support for reductions
    output sldu_mux_e              sldu_mux_sel_o,
    output logic     [NrLanes-1:0] sldu_red_valid_o,
    // Interface with the Mask Unit
    input  strb_t    [NrLanes-1:0] mask_i,
    input  logic     [NrLanes-1:0] mask_valid_i,
    output logic                   mask_ready_o
  );

  `include "common_cells/registers.svh"

  import cf_math_pkg::idx_width;

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = SlduInsnQueueDepth;

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
  pe_req_t vinsn_issue_q;
  logic    vinsn_issue_valid_q;
  `FF(vinsn_issue_q, vinsn_queue_d.vinsn[vinsn_queue_d.issue_pnt], '0)
  `FF(vinsn_issue_valid_q, vinsn_queue_d.issue_cnt != '0, 1'b0)

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

  /////////////////////
  //  Result queues  //
  /////////////////////

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
  // Vector to register the final grants from the operand requesters, which indicate
  // that the result was actually written in the VRF (while the normal grant just says
  // that the result was accepted by the operand requester stage
  logic     [NrLanes-1:0]                       result_final_gnt_d, result_final_gnt_q;

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

  //////////////////
  //  Reductions  //
  //////////////////

  // Inter-lane reductions are performed with a logarithmic tree, and the result is
  // accumulated in the last Lane. Then, in the end, the result is passed to the first
  // lane for SIMD reduction
  logic [idx_width(NrLanes)-1:0] red_stride_cnt_d, red_stride_cnt_q;
  logic [idx_width(NrLanes):0] red_stride_cnt_d_wide;

  always_comb begin
    sldu_mux_sel_o = NO_RED;
    if ((vinsn_issue_valid_q && vinsn_issue_q.vfu == VFU_Alu && !(vinsn_commit_valid && vinsn_commit.vfu != VFU_Alu)) || (vinsn_commit_valid && vinsn_commit.vfu == VFU_Alu)) begin
      sldu_mux_sel_o = ALU_RED;
    end
  end

  //////////////////
  //  Slide unit  //
  //////////////////

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // State of the slide FSM
  typedef enum logic [1:0] {
    SLIDE_IDLE,
    SLIDE_RUN,
    SLIDE_RUN_VSLIDE1UP_FIRST_WORD
  } slide_state_e;
  slide_state_e state_d, state_q;

  // Pointers in the input operand and the output result
  logic   [idx_width(NrLanes*StrbWidth):0] in_pnt_d, in_pnt_q;
  logic   [idx_width(NrLanes*StrbWidth):0] out_pnt_d, out_pnt_q;
  vaddr_t                                  vrf_pnt_d, vrf_pnt_q;

  // Remaining bytes of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining bytes of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  always_comb begin: p_sldu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_d   = issue_cnt_q;
    commit_cnt_d  = commit_cnt_q;
    in_pnt_d      = in_pnt_q;
    out_pnt_d     = out_pnt_q;
    vrf_pnt_d     = vrf_pnt_q;
    state_d       = state_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    result_final_gnt_d = result_final_gnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // We are not ready, by default
    pe_resp              = '0;
    mask_ready_o         = 1'b0;
    sldu_operand_ready_o = '0;

    red_stride_cnt_d = red_stride_cnt_q;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    /////////////////
    //  Slide FSM  //
    /////////////////

    unique case (state_q)
      SLIDE_IDLE: begin
        if (vinsn_issue_valid_q) begin
          state_d   = SLIDE_RUN;
          vrf_pnt_d = '0;

          unique case (vinsn_issue_q.op)
            VSLIDEUP: begin
              // vslideup starts reading the source operand from its beginning
              in_pnt_d  = '0;
              // vslideup starts writing the destination vector at the slide offset
              out_pnt_d = vinsn_issue_q.stride[idx_width(8*NrLanes)-1:0];

              // Initialize counters
              issue_cnt_d = vinsn_issue_q.vl << int'(vinsn_issue_q.vtype.vsew);

              // Trim vector elements which are not touched by the slide unit
              issue_cnt_d -= vinsn_issue_q.stride;

              // Start writing at the middle of the destination vector
              vrf_pnt_d = vinsn_issue_q.stride >> $clog2(8*NrLanes);

              // Go to SLIDE_RUN_VSLIDE1UP_FIRST_WORD if this is a vslide1up instruction
              if (vinsn_issue_q.use_scalar_op)
                state_d = SLIDE_RUN_VSLIDE1UP_FIRST_WORD;
            end
            VSLIDEDOWN: begin
              // vslidedown starts reading the source operand from the slide offset
              in_pnt_d  = vinsn_issue_q.stride[idx_width(8*NrLanes)-1:0];
              // vslidedown starts writing the destination vector at its beginning
              out_pnt_d = '0;

              // Initialize counters
              issue_cnt_d = vinsn_issue_q.vl << int'(vinsn_issue_q.vtype.vsew);

              // Trim the last element of vslide1down, which does not come from the VRF
              if (vinsn_issue_q.use_scalar_op)
                issue_cnt_d -= 1 << int'(vinsn_issue_q.vtype.vsew);
            end
            // Reductions
            default: begin
              // Read from the beginning
              in_pnt_d  = '0;
              // Writes
              out_pnt_d = {'0, red_stride_cnt_q, 3'b0};

              // Initialize issue cnt. Pretend to move NrLanes 64-bit elements for (clog2(NrLanes) + 1) times.
              issue_cnt_d  = (NrLanes * ($clog2(NrLanes) + 1)) << EW64;
            end
          endcase
        end
      end

      SLIDE_RUN, SLIDE_RUN_VSLIDE1UP_FIRST_WORD: begin
        // Are we ready?
        // During a reduction (vinsn_issue_q.vfu == VFU_Alu) don't wait for mask bits
        if (&sldu_operand_valid_i && (sldu_operand_target_fu_i[0] == SLDU) && !result_queue_full && (vinsn_issue_q.vm || vinsn_issue_q.vfu == VFU_Alu || (|mask_valid_i)))
        begin
          // How many bytes are we copying from the operand to the destination, in this cycle?
          automatic int in_byte_count = NrLanes * 8 - in_pnt_q;
          automatic int out_byte_count = NrLanes * 8 - out_pnt_q;
          automatic int byte_count = in_byte_count < out_byte_count ? in_byte_count : out_byte_count;

          for (int b = 0; b < NrLanes*8; b++) begin
            // Input byte
            automatic int in_seq_byte = in_pnt_q + b;
            // A reduction always operates on the target vsew
            automatic int in_byte  = shuffle_index(in_seq_byte, NrLanes, (vinsn_issue_q.vfu == VFU_Alu) ? vinsn_issue_q.vtype.vsew : vinsn_issue_q.eew_vs2);
            // Output byte
            automatic int out_seq_byte = out_pnt_q + b;
            automatic int out_byte = shuffle_index(out_seq_byte, NrLanes, vinsn_issue_q.vtype.vsew);

            // Is this a valid byte? (Allow wrap-up only with reductions!)
            if (b < issue_cnt_q && in_seq_byte < NrLanes * 8 && (vinsn_issue_q.vfu == VFU_Alu || out_seq_byte < NrLanes * 8)) begin
              // At which lane, and what is the offset in that lane, are the input and output bytes?
              automatic int src_lane        = in_byte[3 +: $clog2(NrLanes)];
              automatic int src_lane_offset = in_byte[2:0];
              automatic int tgt_lane        = out_byte[3 +: $clog2(NrLanes)];
              automatic int tgt_lane_offset = out_byte[2:0];

              result_queue_d[result_queue_write_pnt_q][tgt_lane].wdata[8*tgt_lane_offset +: 8] =
                sldu_operand_i[src_lane][8*src_lane_offset +: 8];
              result_queue_d[result_queue_write_pnt_q][tgt_lane].be[tgt_lane_offset] =
                vinsn_issue_q.vm || mask_i[tgt_lane][tgt_lane_offset];
            end
          end

          // Initialize id and addr fields of the result queue requests
          for (int lane = 0; lane < NrLanes; lane++) begin
            result_queue_d[result_queue_write_pnt_q][lane].id   = vinsn_issue_q.id;
            result_queue_d[result_queue_write_pnt_q][lane].addr =
              vaddr(vinsn_issue_q.vd, NrLanes) + vrf_pnt_q;
          end

          // Bump pointers (reductions always finish in one shot)
          in_pnt_d    = vinsn_issue_q.vfu == VFU_Alu ? NrLanes * 8                  : in_pnt_q  + byte_count;
          out_pnt_d   = vinsn_issue_q.vfu == VFU_Alu ? NrLanes * 8                  : out_pnt_q + byte_count;
          issue_cnt_d = vinsn_issue_q.vfu == VFU_Alu ? issue_cnt_q - (NrLanes * 8)  : issue_cnt_q - byte_count;

          // Jump to SLIDE_RUN
          state_d = SLIDE_RUN;
          // If this is a vslide1up instruction, copy the scalar operand to the first word
          if (state_q == SLIDE_RUN_VSLIDE1UP_FIRST_WORD)
            unique case (vinsn_issue_q.vtype.vsew)
              EW8: begin
                result_queue_d[result_queue_write_pnt_q][0].wdata[7:0] =
                  vinsn_issue_q.scalar_op[7:0];
                result_queue_d[result_queue_write_pnt_q][0].be[0:0] =
                  vinsn_issue_q.vm || mask_i[0][0];
              end
              EW16: begin
                result_queue_d[result_queue_write_pnt_q][0].wdata[15:0] =
                  vinsn_issue_q.scalar_op[15:0];
                result_queue_d[result_queue_write_pnt_q][0].be[1:0] =
                  {2{vinsn_issue_q.vm || mask_i[0][0]}};
              end
              EW32: begin
                result_queue_d[result_queue_write_pnt_q][0].wdata[31:0] =
                  vinsn_issue_q.scalar_op[31:0];
                result_queue_d[result_queue_write_pnt_q][0].be[3:0] =
                  {4{vinsn_issue_q.vm || mask_i[0][0]}};
              end
              EW64: begin
                result_queue_d[result_queue_write_pnt_q][0].wdata[63:0] =
                  vinsn_issue_q.scalar_op[63:0];
                result_queue_d[result_queue_write_pnt_q][0].be[7:0] =
                  {8{vinsn_issue_q.vm || mask_i[0][0]}};
              end
            endcase

          // Read a full word from the VRF or finished the instruction
          if (in_pnt_d == NrLanes * 8 || issue_cnt_q <= byte_count) begin
            // Reset the pointer and ask for a new operand
            in_pnt_d             = '0;
            sldu_operand_ready_o = '1;
            // Left-rotate the logarithmic counter. Hacky way to write it, but it's to
            // deal with the 2-lanes design without complaints from Verilator...
            // wide signal to please the tool
            red_stride_cnt_d_wide = {red_stride_cnt_q, red_stride_cnt_q[idx_width(NrLanes)-1]};
            red_stride_cnt_d      = red_stride_cnt_d_wide[idx_width(NrLanes)-1:0];
            // We used all the bits of the mask
            if (vinsn_issue_q.op == VSLIDEUP)
              mask_ready_o = !vinsn_issue_q.vm;
          end

          // Filled up a word to the VRF or finished the instruction
          if (out_pnt_d == NrLanes * 8 || issue_cnt_q <= byte_count) begin
            // Reset the pointer
            out_pnt_d = vinsn_issue_q.vfu == VFU_Alu ? {'0, red_stride_cnt_d, 3'b0} : '0;
            // We used all the bits of the mask
            if (vinsn_issue_q.op == VSLIDEDOWN)
              mask_ready_o = !vinsn_issue_q.vm;

            // Increment VRF address
            vrf_pnt_d = vrf_pnt_q + 1;

            // Send result to the VRF
            result_queue_cnt_d += 1;
            result_queue_valid_d[result_queue_write_pnt_q] = '1;
            result_queue_write_pnt_d                       = result_queue_write_pnt_q + 1;
            if (result_queue_write_pnt_q == ResultQueueDepth-1)
              result_queue_write_pnt_d = '0;
          end

          // Finished the operation
          if (issue_cnt_q <= byte_count || (vinsn_issue_q.vfu == VFU_Alu && issue_cnt_q <= 8 * NrLanes)) begin
            // Back to idle
            state_d = SLIDE_IDLE;
            // Reset the logarighmic counter
            red_stride_cnt_d = 1;

            // If this is a vslide1down, fill up the last position with the scalar operand
            if (vinsn_issue_q.op == VSLIDEDOWN && vinsn_issue_q.use_scalar_op) begin
              // Copy the scalar operand to the last word
              automatic int out_seq_byte = issue_cnt_q;
              automatic int out_byte = shuffle_index(out_seq_byte, NrLanes, vinsn_issue_q.vtype.vsew);
              automatic int tgt_lane = out_byte[3 +: $clog2(NrLanes)];
              automatic int tgt_lane_offset = out_byte[2:0];

              unique case (vinsn_issue_q.vtype.vsew)
                EW8: begin
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].wdata[8*tgt_lane_offset +: 8]
                    = vinsn_issue_q.scalar_op[7:0];
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].be[tgt_lane_offset +: 1] =
                    vinsn_issue_q.vm || mask_i[tgt_lane][tgt_lane_offset];
                end
                EW16: begin
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].wdata[8*tgt_lane_offset +: 16]
                    = vinsn_issue_q.scalar_op[15:0];
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].be[tgt_lane_offset +: 2] =
                    {2{vinsn_issue_q.vm || mask_i[tgt_lane][tgt_lane_offset]}};
                end
                EW32: begin
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].wdata[8*tgt_lane_offset +: 32]
                    = vinsn_issue_q.scalar_op[31:0];
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].be[tgt_lane_offset +: 4] =
                    {4{vinsn_issue_q.vm || mask_i[tgt_lane][tgt_lane_offset]}};
                end
                EW64: begin
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].wdata[8*tgt_lane_offset +: 64]
                    = vinsn_issue_q.scalar_op[63:0];
                  result_queue_d[result_queue_write_pnt_q][tgt_lane].be[tgt_lane_offset +: 8] =
                    {8{vinsn_issue_q.vm || mask_i[tgt_lane][tgt_lane_offset]}};
                end
              endcase
            end

            // Increment vector instruction queue pointers and counters
            vinsn_queue_d.issue_pnt += 1;
            vinsn_queue_d.issue_cnt -= 1;
          end
        end
      end
      default:;
    endcase

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

    for (int lane = 0; lane < NrLanes; lane++) begin: result_write
      sldu_result_req_o[lane]   = result_queue_valid_q[result_queue_read_pnt_q][lane] & (vinsn_commit.vfu != VFU_Alu);
      sldu_red_valid_o[lane]    = result_queue_valid_q[result_queue_read_pnt_q][lane] & (vinsn_commit.vfu == VFU_Alu);
      sldu_result_addr_o[lane]  = result_queue_q[result_queue_read_pnt_q][lane].addr;
      sldu_result_id_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].id;
      sldu_result_wdata_o[lane] = result_queue_q[result_queue_read_pnt_q][lane].wdata;
      sldu_result_be_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].be;

      // Update the final gnt vector
      result_final_gnt_d[lane] |= sldu_result_final_gnt_i[lane];

      // Received a grant from the VRF (slide) or from the FUs (reduction).
      // Deactivate the request, but do not bump the pointers for now.
      if (((vinsn_commit.vfu == VFU_Alu && sldu_red_valid_o) || sldu_result_req_o[lane]) && sldu_result_gnt_i[lane]) begin
        result_queue_valid_d[result_queue_read_pnt_q][lane] = 1'b0;
        result_queue_d[result_queue_read_pnt_q][lane]       = '0;
        // Reset the final gnt vector since we are now waiting for another final gnt
        result_final_gnt_d[lane] = 1'b0;
      end
    end: result_write

    // All lanes accepted the VRF request
    // If this was the last request, wait for all the final grants!
    // If this is a reduction, no need for the final grants
    if (!(|result_queue_valid_d[result_queue_read_pnt_q]) &&
      (vinsn_commit.vfu == VFU_Alu || (&result_final_gnt_d || commit_cnt_q > (NrLanes * 8))))
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
      if (vinsn_queue_d.commit_cnt != '0) begin
        commit_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].op inside {VSLIDEUP, VSLIDEDOWN}
                     ? vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl << int'(vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vtype.vsew)
                     : (NrLanes * ($clog2(NrLanes) + 1)) << EW64;

        // Trim vector elements which are not written by the slide unit
        if (vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].op == VSLIDEUP)
          commit_cnt_d -= vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].stride;
      end
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] &&
      (pe_req_i.vfu == VFU_SlideUnit || pe_req_i.op inside {[VREDSUM:VWREDSUM]})) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Calculate the slide offset inside the vector register
      if (pe_req_i.op inside {VSLIDEUP, VSLIDEDOWN})
        vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].stride = pe_req_i.stride <<
          int'(pe_req_i.vtype.vsew);
      // Always move 64-bit packs of data from one lane to the other
      if (pe_req_i.vfu == VFU_Alu)
        vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].vtype.vsew = EW64;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d  = pe_req_i.op inside {VSLIDEUP, VSLIDEDOWN}
                     ? pe_req_i.vl << int'(pe_req_i.vtype.vsew)
                     : (NrLanes * ($clog2(NrLanes) + 1)) << EW64;
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = pe_req_i.op inside {VSLIDEUP, VSLIDEDOWN}
                     ? pe_req_i.vl << int'(pe_req_i.vtype.vsew)
                     : (NrLanes * ($clog2(NrLanes) + 1)) << EW64;

      // Trim vector elements which are not written by the slide unit
      if (pe_req_i.op == VSLIDEUP) begin
        issue_cnt_d -= vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].stride;
        commit_cnt_d -= vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].stride;
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_sldu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q    <= '0;
      issue_cnt_q        <= '0;
      commit_cnt_q       <= '0;
      in_pnt_q           <= '0;
      out_pnt_q          <= '0;
      vrf_pnt_q          <= '0;
      state_q            <= SLIDE_IDLE;
      pe_resp_o          <= '0;
      result_final_gnt_q <= '0;
      red_stride_cnt_q   <= 1;
    end else begin
      vinsn_running_q    <= vinsn_running_d;
      issue_cnt_q        <= issue_cnt_d;
      commit_cnt_q       <= commit_cnt_d;
      in_pnt_q           <= in_pnt_d;
      out_pnt_q          <= out_pnt_d;
      vrf_pnt_q          <= vrf_pnt_d;
      state_q            <= state_d;
      pe_resp_o          <= pe_resp;
      result_final_gnt_q <= result_final_gnt_d;
      red_stride_cnt_q   <= red_stride_cnt_d;
    end
  end

endmodule: sldu
