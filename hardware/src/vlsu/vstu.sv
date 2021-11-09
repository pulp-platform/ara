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
    parameter  int  unsigned NrLanes = 0,
    parameter  type          vaddr_t = logic,  // Type used to address vector register file elements
    // AXI Interface parameters
    parameter  int  unsigned AxiDataWidth = 0,
    parameter  int  unsigned AxiAddrWidth = 0,
    parameter  type          axi_w_t      = logic,
    parameter  type          axi_b_t      = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           DataWidth    = $bits(elen_t),
    localparam type          strb_t       = logic[DataWidth/8-1:0],
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
    // Interface with the lanes
    input  elen_t            [NrLanes-1:0] stu_operand_i,
    input  logic             [NrLanes-1:0] stu_operand_valid_i,
    output logic             [NrLanes-1:0] stu_operand_ready_o,
    // Interface with the Mask unit
    input  strb_t            [NrLanes-1:0] mask_i,
    input  logic             [NrLanes-1:0] mask_valid_i,
    output logic                           mask_ready_o
  );

  import cf_math_pkg::idx_width;
  import axi_pkg::beat_lower_byte;
  import axi_pkg::beat_upper_byte;
  import axi_pkg::BURST_INCR;

  ///////////////////////
  //  Spill registers  //
  ///////////////////////

  elen_t [NrLanes-1:0] stu_operand;
  logic  [NrLanes-1:0] stu_operand_valid;
  logic                stu_operand_ready;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_regs
    fall_through_register #(
      .T(elen_t)
    ) i_register (
      .clk_i     (clk_i                    ),
      .rst_ni    (rst_ni                   ),
      .clr_i     (1'b0                     ),
      .testmode_i(1'b0                     ),
      .data_i    (stu_operand_i[lane]      ),
      .valid_i   (stu_operand_valid_i[lane]),
      .ready_o   (stu_operand_ready_o[lane]),
      .data_o    (stu_operand[lane]        ),
      .valid_o   (stu_operand_valid[lane]  ),
      .ready_i   (stu_operand_ready        )
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

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // Remaining bytes of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;

  // Pointers
  //
  // We need several pointers to copy data to the memory interface
  // from the VRF. Namely, we need:
  // - A counter of how many beats are left in the current AXI burst
  axi_pkg::len_t len_d, len_q;
  // - A pointer to which byte in the full VRF word we are reading data from.
  logic [idx_width(DataWidth*NrLanes/8):0] vrf_pnt_d, vrf_pnt_q;

  always_comb begin: p_vstu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_d   = issue_cnt_q;

    len_d     = len_q;
    vrf_pnt_d = vrf_pnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // We are not ready, by default
    axi_addrgen_req_ready_o = 1'b0;
    pe_resp                 = '0;
    axi_w_o                 = '0;
    axi_w_valid_o           = 1'b0;
    axi_b_ready_o           = 1'b0;
    stu_operand_ready       = 1'b0;
    mask_ready_o            = 1'b0;
    store_complete_o        = 1'b0;

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
    if (vinsn_issue_valid && &stu_operand_valid && (vinsn_issue_q.vm || (|mask_valid_i)) &&
        axi_addrgen_req_valid_i && !axi_addrgen_req_i.is_load && axi_w_ready_i) begin
      // Bytes valid in the current W beat
      automatic shortint unsigned lower_byte = beat_lower_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, len_q);
      automatic shortint unsigned upper_byte = beat_upper_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, len_q);

      // Account for the issued bytes
      // How many bytes are valid in this VRF word
      automatic vlen_t vrf_valid_bytes   = NrLanes * 8 - vrf_pnt_q;
      // How many bytes are valid in this instruction
      automatic vlen_t vinsn_valid_bytes = issue_cnt_q - vrf_pnt_q;
      // How many bytes are valid in this AXI word
      automatic vlen_t axi_valid_bytes   = upper_byte - lower_byte + 1;

      // How many bytes are we committing?
      automatic logic [idx_width(DataWidth*NrLanes/8):0] valid_bytes;
      valid_bytes = issue_cnt_q < NrLanes * 8     ? vinsn_valid_bytes : vrf_valid_bytes;
      valid_bytes = valid_bytes < axi_valid_bytes ? valid_bytes       : axi_valid_bytes;

      vrf_pnt_d = vrf_pnt_q + valid_bytes;

      // Copy data from the operands into the W channel
      for (int axi_byte = 0; axi_byte < AxiDataWidth/8; axi_byte++) begin
        // Is this byte a valid byte in the W beat?
        if (axi_byte >= lower_byte && axi_byte <= upper_byte) begin
          // Map axy_byte to the corresponding byte in the VRF word (sequential)
          automatic int vrf_seq_byte = axi_byte - lower_byte + vrf_pnt_q;
          // And then shuffle it
          automatic int vrf_byte     = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue_q.eew_vs1);

          // Is this byte a valid byte in the VRF word?
          if (vrf_seq_byte < issue_cnt_q) begin
            // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
            automatic int vrf_lane   = vrf_byte >> 3;
            automatic int vrf_offset = vrf_byte[2:0];

            // Copy data
            axi_w_o.data[8*axi_byte +: 8] = stu_operand[vrf_lane][8*vrf_offset +: 8];
            axi_w_o.strb[axi_byte]        = vinsn_issue_q.vm || mask_i[vrf_lane][vrf_offset];
          end
        end
      end

      // Send the W beat
      axi_w_valid_o = 1'b1;
      // Account for the beat we sent
      len_d         = len_q + 1;
      // We wrote all the beats for this AW burst
      if ($unsigned(len_d) == axi_pkg::len_t'($unsigned(axi_addrgen_req_i.len) + 1)) begin
        axi_w_o.last            = 1'b1;
        // Ask for another burst by the address generator
        axi_addrgen_req_ready_o = 1'b1;
        // Reset AXI pointers
        len_d                   = '0;
      end

      // We consumed a whole word from the lanes
      if (vrf_pnt_d == NrLanes*8 || vrf_pnt_d == issue_cnt_q) begin
        // Reset the pointer in the VRF word
        vrf_pnt_d         = '0;
        // Acknowledge the operands with the lanes
        stu_operand_ready = '1;
        // Acknowledge the mask operand
        mask_ready_o      = !vinsn_issue_q.vm;
        // Account for the results that were issued
        issue_cnt_d       = issue_cnt_q - NrLanes * 8;
        if (issue_cnt_q < NrLanes * 8)
          issue_cnt_d = '0;
      end
    end

    // Finished issuing W beats for this vector store
    if (vinsn_issue_valid && issue_cnt_d == 0) begin
      // Bump issue counters and pointers of the vector instruction queue
      vinsn_queue_d.issue_cnt -= 1;
      if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1)
        vinsn_queue_d.issue_pnt = 0;
      else
        vinsn_queue_d.issue_pnt += 1;

      if (vinsn_queue_d.issue_cnt != 0)
        issue_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl <<
          int'(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew);
    end

    ////////////////////////////
    //  Handle the B channel  //
    ////////////////////////////

    // TODO: We cannot handle errors on the B channel.
    // We just acknowledge any AXI requests that come on the B channel.
    if (axi_b_valid_i) begin
      // Acknowledge the B beat
      axi_b_ready_o = 1'b1;

      // Mark the vector instruction as being done
      if (vinsn_queue_d.issue_pnt != vinsn_queue_d.commit_pnt) begin
        // Signal complete store
        store_complete_o = 1'b1;

        pe_resp.vinsn_done[vinsn_commit.id] = 1'b1;

        // Update the commit counters and pointers
        vinsn_queue_d.commit_cnt -= 1;
        if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
          vinsn_queue_d.commit_pnt = '0;
        else
          vinsn_queue_d.commit_pnt += 1;
      end
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] &&
      pe_req_i.vfu == VFU_StoreUnit) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d = pe_req_i.vl << int'(pe_req_i.vtype.vsew);

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

      len_q     <= '0;
      vrf_pnt_q <= '0;

      pe_resp_o <= '0;
    end else begin
      vinsn_running_q <= vinsn_running_d;
      issue_cnt_q     <= issue_cnt_d;

      len_q     <= len_d;
      vrf_pnt_q <= vrf_pnt_d;

      pe_resp_o <= pe_resp;
    end
  end

endmodule : vstu
