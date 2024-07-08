// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
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
    parameter  int  unsigned NrLanes   = 0,
    parameter  int  unsigned VLEN      = 0,
    parameter  type          vaddr_t   = logic,  // Type used to address vector register file elements
    parameter  type          pe_req_t  = logic,
    parameter  type          pe_resp_t = logic,
    // AXI Interface parameters
    parameter  int  unsigned AxiDataWidth = 0,
    parameter  int  unsigned AxiAddrWidth = 0,
    parameter  type          axi_w_t      = logic,
    parameter  type          axi_b_t      = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           DataWidth    = $bits(elen_t),
    localparam type          strb_t       = logic[DataWidth/8-1:0],
    localparam type          vlen_t       = logic[$clog2(VLEN+1)-1:0],
    localparam type          axi_addr_t   = logic [AxiAddrWidth-1:0]
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
    // Interface with the dispatcher
    output logic                           store_pending_o,
    output logic                           store_complete_o,
    // Interface with the main sequencer
    input  pe_req_t                        pe_req_i,
    input  logic                           pe_req_valid_i,
    input  logic             [NrVInsn-1:0] pe_vinsn_running_i,
    output logic                           pe_req_ready_o,
    output pe_resp_t                       pe_resp_o,
    // Interface with the address generator
    input  addrgen_axi_req_t               axi_addrgen_req_i,
    input  logic                           axi_addrgen_req_valid_i,
    output logic                           axi_addrgen_req_ready_o,
    input  logic                           addrgen_illegal_store_i,
    // Interface with the lanes
    input  elen_t            [NrLanes-1:0] stu_operand_i,
    input  logic             [NrLanes-1:0] stu_operand_valid_i,
    output logic             [NrLanes-1:0] stu_operand_ready_o,
    output logic                           stu_exception_flush_o,
    // Interface with the Mask unit
    input  strb_t            [NrLanes-1:0] mask_i,
    input  logic             [NrLanes-1:0] mask_valid_i,
    output logic                           mask_ready_o
  );

  import cf_math_pkg::idx_width;
  import axi_pkg::beat_lower_byte;
  import axi_pkg::beat_upper_byte;
  import axi_pkg::BURST_INCR;

  localparam unsigned DataWidthB = DataWidth / 8;

  ///////////////////////
  //  Spill registers  //
  ///////////////////////

  elen_t [NrLanes-1:0] stu_operand;
  logic  [NrLanes-1:0] stu_operand_valid;
  logic  [NrLanes-1:0] stu_operand_ready;
  logic stu_operand_flush;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_regs
    fall_through_register #(
      .T(elen_t)
    ) i_register (
      .clk_i     (clk_i                    ),
      .rst_ni    (rst_ni                   ),
      .clr_i     (stu_operand_flush        ),
      .testmode_i(1'b0                     ),
      .data_i    (stu_operand_i[lane]      ),
      .valid_i   (stu_operand_valid_i[lane]),
      .ready_o   (stu_operand_ready_o[lane]),
      .data_o    (stu_operand[lane]        ),
      .valid_o   (stu_operand_valid[lane]  ),
      .ready_i   (stu_operand_ready[lane]  )
    );
  end: gen_regs

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = VstuInsnQueueDepth;

  struct packed {
    pe_req_t [VInsnQueueDepth-1:0] vinsn;

    // Each instruction can be in one of the three execution phases.
    // - Being accepted (i.e., it is being stored for future execution in this
    //   vector functional unit).
    // - Being issued (i.e., its micro-operations are currently being issued
    //   to the corresponding functional units).
    // - Being committed (i.e., waiting for acknowledgment from the
    //   memory system).
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

  // Is the vector instruction queue empty?
  logic vinsn_queue_empty;
  assign vinsn_queue_empty = (vinsn_queue_q.commit_cnt == '0);
  assign store_pending_o   = !vinsn_queue_empty;

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

  //////////////////
  //  Store Unit  //
  //////////////////

  // NOTE: these are out here only for debug visibility, they could go in p_vldu as automatic variables
  int unsigned vrf_seq_byte;
  int unsigned vrf_seq_byte_cnt;
  int unsigned vrf_byte ;
  vlen_t vrf_valid_bytes ;
  vlen_t vinsn_valid_bytes;
  vlen_t axi_valid_bytes   ;
  logic [idx_width(DataWidth*NrLanes/8):0] valid_bytes;


  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp_d;

  // Remaining bytes of the current instruction in the issue phase
  vlen_t issue_cnt_bytes_d, issue_cnt_bytes_q;

  // Pointers
  //
  // We need several pointers to copy data to the memory interface
  // from the VRF. Namely, we need:
  // - A counter of how many beats are left in the current AXI burst
  axi_pkg::len_t axi_len_d, axi_len_q;
  // - A pointer to which byte in the full VRF word we are reading data from.
  logic [idx_width(DataWidth*NrLanes/8):0] vrf_pnt_d, vrf_pnt_q;

  // When vstart > 0, the very first payload written to the VRF contains less than
  // (8 * NrLanes) bytes.
  logic [$clog2(8*NrLanes):0] first_payload_byte_d, first_payload_byte_q;
  logic [$clog2(8*NrLanes):0] vrf_eff_write_bytes;

  // A counter that follows the vrf_word_byte_pnt pointer, but without the vstart information
  // We can compare this counter witht the issue_cnt_bytes counter to find the last byte in
  // our transaction
  logic [idx_width(DataWidth*NrLanes/8):0] vrf_cnt_d, vrf_cnt_q;
  // - A pointer that indicates the start byte in the vrf word.
  logic [$clog2(8*NrLanes)-1:0] vrf_word_start_byte;
  // First payload from the lanes? If yes, it can be offset by vstart.
  logic first_lane_payload_d, first_lane_payload_q;
  // When an exception occurs, the operand queues will be flushed after StuExLat cycles.
  // Therefore, the input register of the store unit needs to be flushed at the same time
  // not to sample non-flushed data.
  // We implement this mechanism with a simple counter.
  logic stu_op_flush_cnt_en;
  logic [idx_width(StuExLat):0] stu_op_flush_cnt_d, stu_op_flush_cnt_q;
  // Flush when we have reached the threshold
  assign stu_operand_flush = StuExLat == 0 ? stu_op_flush_cnt_en : stu_op_flush_cnt_q == StuExLat;

  always_comb begin: p_vstu
    // NOTE: these are out here only for debug visibility, they could go in p_vldu as automatic variables
    vrf_seq_byte = '0;
    vrf_seq_byte_cnt = '0;
    vrf_byte  = '0;
    vrf_valid_bytes  = '0;
    vinsn_valid_bytes = '0;
    axi_valid_bytes    = '0;
    valid_bytes = '0;

    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_bytes_d   = issue_cnt_bytes_q;

    axi_len_d     = axi_len_q;
    vrf_pnt_d = vrf_pnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // We are not ready, by default
    axi_addrgen_req_ready_o = 1'b0;
    pe_resp_d               = '0;
    axi_w_o                 = '0;
    axi_w_valid_o           = 1'b0;
    axi_b_ready_o           = 1'b0;
    stu_operand_ready       = 1'b0;
    mask_ready_o            = 1'b0;
    store_complete_o        = 1'b0;
    vrf_word_start_byte     = '0;

    first_payload_byte_d = first_payload_byte_q;
    stu_op_flush_cnt_d   = stu_op_flush_cnt_q;

    stu_op_flush_cnt_en = 1'b0;

    vrf_cnt_d = vrf_cnt_q;
    first_lane_payload_d = first_lane_payload_q;

    stu_exception_flush_o = 1'b0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    /////////////////////////////////////
    //  Write data into the W channel  //
    /////////////////////////////////////

    // We are ready to send a W beat if
    // - There is an instruction ready to be issued
    // - We received all the operands from the lanes
    // - The address generator generated an AXI AW request for this write beat
    // - The AXI subsystem is ready to accept this W beat
    // - The current addrgen request has not generated an exception
    if (vinsn_issue_valid &&
        axi_addrgen_req_valid_i && !axi_addrgen_req_i.is_load
     && !axi_addrgen_req_i.is_exception && axi_w_ready_i) begin : issue_valid
      // Bytes valid in the current W beat
      automatic shortint unsigned lower_byte = beat_lower_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);
      automatic shortint unsigned upper_byte = beat_upper_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);

      // For non-zero vstart values, the last operand read is not going to involve all the lanes
      automatic logic [NrLanes-1:0] mask_valid;

      // How many bytes are we committing?
      // automatic logic [idx_width(DataWidth*NrLanes/8):0] valid_bytes;

      // Account for the issued bytes
      // How many bytes are valid in this VRF word
      vrf_valid_bytes   = (NrLanes * DataWidthB) - vrf_pnt_q;
      // How many bytes are valid in this instruction
      vinsn_valid_bytes = issue_cnt_bytes_q - vrf_cnt_q;
      // How many bytes are valid in this AXI word
      axi_valid_bytes   = upper_byte - lower_byte + 1;

      valid_bytes = (issue_cnt_bytes_q < (NrLanes * DataWidthB)) ? vinsn_valid_bytes : vrf_valid_bytes;
      valid_bytes = (valid_bytes       < axi_valid_bytes       ) ? valid_bytes       : axi_valid_bytes;

      // TODO: apply the same vstart logic also to mask_valid_i
      // For now, assume (vstart % NrLanes == 0)
      mask_valid = mask_valid_i;

      // Wait for all expected operands from the lanes
      if (&stu_operand_valid && (vinsn_issue_q.vm || (|mask_valid_i))) begin : operands_ready
        vrf_pnt_d = vrf_pnt_q + valid_bytes;
        vrf_cnt_d = vrf_cnt_q + valid_bytes;

        // Copy data from the operands into the W channel
        for (int unsigned axi_byte = 0; axi_byte < AxiDataWidth/8; axi_byte++) begin : stu_operand_to_axi_w
          // Is this byte a valid byte in the W beat?
          if (axi_byte >= lower_byte && axi_byte <= upper_byte) begin
            // Map axy_byte to the corresponding byte in the VRF word (sequential)
            vrf_seq_byte = axi_byte - lower_byte + vrf_pnt_q;
            // Follow the vrf_seq_byte, but without the vstart information
            vrf_seq_byte_cnt = axi_byte - lower_byte + vrf_cnt_q;
            // And then shuffle it
            vrf_byte     = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue_q.old_eew_vs1);

            // Is this byte a valid byte in the VRF word?
            if (vrf_seq_byte_cnt < issue_cnt_bytes_q) begin
              // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
              automatic int unsigned vrf_offset = vrf_byte[2:0];
              // automatic logic [$clog2(NrLanes)-1:0] vrf_lane = (vrf_byte >> 3) + vinsn_issue_q.vstart[idx_width(NrLanes)-1:0];
              automatic int unsigned vrf_lane = (vrf_byte >> 3);

              // Copy data
              axi_w_o.data[8*axi_byte +: 8] = stu_operand[vrf_lane][8*vrf_offset +: 8];
              axi_w_o.strb[axi_byte]        = vinsn_issue_q.vm || mask_i[vrf_lane][vrf_offset];
            end
          end
        end : stu_operand_to_axi_w

        // Send the W beat
        axi_w_valid_o = 1'b1;
        // Account for the beat we sent
        axi_len_d     = axi_len_q + 1;
        // We wrote all the beats for this AW burst
        if ($unsigned(axi_len_d) == axi_pkg::len_t'($unsigned(axi_addrgen_req_i.len) + 1)) begin : beats_complete
          axi_w_o.last            = 1'b1;
          // Ask for another burst by the address generator
          axi_addrgen_req_ready_o = 1'b1;
          // Reset AXI pointers
          axi_len_d                   = '0;
        end : beats_complete

        // We consumed a whole word from the lanes
        if (vrf_pnt_d == NrLanes*8 || vrf_cnt_d == issue_cnt_bytes_q) begin : vrf_word_done
          // Reset the pointer in the VRF word
          vrf_pnt_d         = '0;
          vrf_cnt_d         = '0;
          // Next payloads will not be affected by vstart anymore
          first_lane_payload_d = 1'b0;
          // Acknowledge the operands with the lanes
          stu_operand_ready = '1;
          // Acknowledge the mask operand
          mask_ready_o      = !vinsn_issue_q.vm;
          // Account for the results that were issued
          if (first_lane_payload_q) begin
            vrf_eff_write_bytes = first_payload_byte_q;
          end else begin
            // First payload of the vector instruction
            vrf_eff_write_bytes = (NrLanes * DataWidthB);
          end
          issue_cnt_bytes_d = issue_cnt_bytes_q - vrf_eff_write_bytes;
          if (issue_cnt_bytes_q < vrf_eff_write_bytes) begin : issue_cnt_bytes_overflow
            issue_cnt_bytes_d = '0;
          end : issue_cnt_bytes_overflow
        end : vrf_word_done
      end : operands_ready
    end : issue_valid

    // Finished issuing W beats for this vector store
    if (vinsn_issue_valid && issue_cnt_bytes_d == 0) begin : axi_w_beat_finish
      // Bump issue counters and pointers of the vector instruction queue
      vinsn_queue_d.issue_cnt -= 1;
      if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1) begin : issue_pnt_overflow
        vinsn_queue_d.issue_pnt = 0;
      end : issue_pnt_overflow
      else begin : issue_pnt_increment
        vinsn_queue_d.issue_pnt += 1;
      end : issue_pnt_increment

      // Load issue_cnt_bytes_d for next instruction (if any)
      if (vinsn_queue_d.issue_cnt != 0) begin : issue_cnt_bytes_update
        issue_cnt_bytes_d = (vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl - vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vstart)
                            << unsigned'(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew);
        // Prepare the VRF start pointer
        vrf_word_start_byte = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vstart[$clog2(8*NrLanes)-1:0] <<
          vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew;
        vrf_pnt_d           = {1'b0, vrf_word_start_byte[$clog2(8*NrLanes)-1:0]};
        vrf_cnt_d           = '0;
        // The first payload byte width for this vload
        first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0];
        // The next payload will be the first one for this store
        first_lane_payload_d = 1'b1;
      end : issue_cnt_bytes_update
    end : axi_w_beat_finish

    ////////////////////////////
    //  Handle the B channel  //
    ////////////////////////////

    // TODO: We cannot handle errors on the B channel.
    // We just acknowledge any AXI requests that come on the B channel.
    if (axi_b_valid_i) begin : axi_b_valid
      // Acknowledge the B beat
      axi_b_ready_o = 1'b1;

      // Mark the vector instruction as being done
      if (vinsn_queue_d.issue_pnt != vinsn_queue_d.commit_pnt) begin : instr_done
        // Signal complete store
        store_complete_o = 1'b1;

        pe_resp_d.vinsn_done[vinsn_commit.id] = 1'b1;

        // Update the commit counters and pointers
        vinsn_queue_d.commit_cnt -= 1;
        if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1) begin : commit_pnt_overflow
          vinsn_queue_d.commit_pnt = '0;
        end : commit_pnt_overflow
        else begin : commit_pnt_increment
          vinsn_queue_d.commit_pnt += 1;
        end : commit_pnt_increment
      end : instr_done
    end : axi_b_valid

    ////////////////////////
    //  Handle exceptions //
    ////////////////////////

    // Clear instruction from queue and data in case of exceptions from addrgen
    if (vinsn_issue_valid && ((axi_addrgen_req_valid_i && axi_addrgen_req_i.is_exception) || addrgen_illegal_store_i)) begin : exception
      // Bump issue counters and pointers of the vector instruction queue
      vinsn_queue_d.issue_cnt -= 1;
      issue_cnt_bytes_d = '0;
      if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1) begin : issue_pnt_overflow
        vinsn_queue_d.issue_pnt = 0;
      end : issue_pnt_overflow
      else begin : issue_pnt_increment
        vinsn_queue_d.issue_pnt += 1;
      end : issue_pnt_increment

      // Clean the input data, the opreq, and the opqueues after StuExLat cycles
      stu_exception_flush_o = 1'b1;
      stu_op_flush_cnt_en   = 1'b1;

      // Ack the addrgen for this last faulty request
      axi_addrgen_req_ready_o = axi_addrgen_req_valid_i;
      // Reset AXI pointers
      axi_len_d = '0;

      // Mark the vector instruction as being done
      // if (vinsn_queue_d.issue_pnt != vinsn_queue_d.commit_pnt) begin : instr_done
        // Signal done to sequencer
        store_complete_o = 1'b1;

        pe_resp_d.vinsn_done[vinsn_commit.id] = 1'b1;

        // Update the commit counters and pointers
        vinsn_queue_d.commit_cnt -= 1;
        if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1) begin : commit_pnt_overflow
          vinsn_queue_d.commit_pnt = '0;
        end : commit_pnt_overflow
        else begin : commit_pnt_increment
          vinsn_queue_d.commit_pnt += 1;
        end : commit_pnt_increment
      // end : instr_done
    end : exception

    // Increase the flush counter until the threshold if we enabled it.
    if (stu_op_flush_cnt_en || stu_op_flush_cnt_q != '0) begin
      stu_op_flush_cnt_d = stu_op_flush_cnt_q + 1;
    end
    // Reset the counter if we are flushing the input operands.
    if (stu_operand_flush) begin
      stu_op_flush_cnt_d = '0;
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] &&
      pe_req_i.vfu == VFU_StoreUnit) begin : pe_req_valid
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0) begin : issue_cnt_bytes_init
        issue_cnt_bytes_d = (pe_req_i.vl - pe_req_i.vstart) << unsigned'(pe_req_i.vtype.vsew);
      end : issue_cnt_bytes_init

      // Setup pointers and counters with vstart
      if (vinsn_queue_d.issue_cnt == '0) begin
        vrf_word_start_byte = pe_req_i.vstart[$clog2(8*NrLanes)-1:0] << pe_req_i.vtype.vsew;
        vrf_pnt_d           = {1'b0, vrf_word_start_byte[$clog2(8*NrLanes)-1:0]};
        vrf_cnt_d           = '0;
        // The first payload byte width for this vload
        first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0];
        // The next payload will be the first one for this store
        first_lane_payload_d = 1'b1;
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end : pe_req_valid
  end: p_vstu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q   <= '0;
      issue_cnt_bytes_q <= '0;

      axi_len_q <= '0;
      vrf_pnt_q <= '0;

      pe_resp_o <= '0;

      first_payload_byte_q <= '0;
      first_lane_payload_q <= '0;
      stu_op_flush_cnt_q   <= '0;

      vrf_cnt_q <= '0;
    end else begin
      vinsn_running_q   <= vinsn_running_d;
      issue_cnt_bytes_q <= issue_cnt_bytes_d;

      axi_len_q <= axi_len_d;
      vrf_pnt_q <= vrf_pnt_d;

      pe_resp_o <= pe_resp_d;

      first_payload_byte_q <= first_payload_byte_d;
      first_lane_payload_q <= first_lane_payload_d;
      stu_op_flush_cnt_q   <= stu_op_flush_cnt_d;

      vrf_cnt_q <= vrf_cnt_d;
    end
  end

endmodule : vstu
