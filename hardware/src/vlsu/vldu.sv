// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's vector load unit. It receives transactions on the R bus,
// upon receiving vector memory operations.

module vldu import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes   = 0,
    parameter  int  unsigned VLEN      = 0,
    parameter  type          vaddr_t   = logic,  // Type used to address vector register file elements
    parameter  type          pe_req_t  = logic,
    parameter  type          pe_resp_t = logic,
    // AXI Interface parameters
    parameter  int  unsigned AxiDataWidth = 0,
    parameter  int  unsigned AxiAddrWidth = 0,
    parameter  type          axi_r_t      = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           DataWidth    = $bits(elen_t),
    localparam type          strb_t       = logic[DataWidth/8-1:0],
    localparam type          vlen_t       = logic[$clog2(VLEN+1)-1:0],
    localparam type          axi_addr_t   = logic [AxiAddrWidth-1:0]
  ) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Memory interface
    input  axi_r_t                         axi_r_i,
    input  logic                           axi_r_valid_i,
    output logic                           axi_r_ready_o,
    // Interface with dispatcher
    output logic                           load_complete_o,
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
    input  logic                           addrgen_illegal_load_i,
    // Interface with the lanes
    output logic             [NrLanes-1:0] ldu_result_req_o,
    output vid_t             [NrLanes-1:0] ldu_result_id_o,
    output vaddr_t           [NrLanes-1:0] ldu_result_addr_o,
    output elen_t            [NrLanes-1:0] ldu_result_wdata_o,
    output strb_t            [NrLanes-1:0] ldu_result_be_o,
    input  logic             [NrLanes-1:0] ldu_result_gnt_i,
    input  logic             [NrLanes-1:0] ldu_result_final_gnt_i,
    // Interface with the Mask unit
    input  strb_t            [NrLanes-1:0] mask_i,
    input  logic             [NrLanes-1:0] mask_valid_i,
    output logic                           mask_ready_o
  );

  import cf_math_pkg::idx_width;
  import axi_pkg::beat_lower_byte;
  import axi_pkg::beat_upper_byte;
  import axi_pkg::BURST_INCR;

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = VlduInsnQueueDepth;

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
  // We need to count how many valid elements (payload_t) are there in this result queue.
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

  /////////////////
  //  Load Unit  //
  /////////////////

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp_d;

  // Remaining bytes of the current instruction in the issue phase
  vlen_t issue_cnt_bytes_d, issue_cnt_bytes_q;
  // Remaining bytes of the current instruction in the commit phase
  vlen_t commit_cnt_bytes_d, commit_cnt_bytes_q;

  // Pointers
  //
  // We need several pointers to copy data from the memory interface
  // into the VRF. Namely, we need:
  // - A counter of how many beats are left in the current AXI burst
  axi_pkg::len_t                           axi_len_d, axi_len_q;
  // - A pointer to which byte in the current R beat we are reading data from.
  logic [idx_width(AxiDataWidth/8):0]      axi_r_byte_pnt_d, axi_r_byte_pnt_q;
  // - A pointer to which byte in the full VRF word we are writing data into.
  logic [idx_width(DataWidth*NrLanes/8):0] vrf_word_byte_pnt_d, vrf_word_byte_pnt_q;
  // - A pointer that indicates the start byte in the vrf word.
  logic [$clog2(8*NrLanes)-1:0] vrf_word_start_byte;

  // A counter that follows the vrf_word_byte_pnt pointer, but without the vstart information
  // We can compare this counter witht the issue_cnt_bytes counter to find the last byte in
  // our transaction
  logic [idx_width(DataWidth*NrLanes/8):0] vrf_word_byte_cnt_d, vrf_word_byte_cnt_q;

  // When vstart > 0, the very first payload written to the VRF contains less than
  // (8 * NrLanes) bytes.
  logic [$clog2(8*NrLanes):0] first_payload_byte_d, first_payload_byte_q;
  logic [$clog2(8*NrLanes):0] vrf_eff_write_bytes;

  // Counter to increase the VRF write address.
  vlen_t seq_word_wr_offset_d, seq_word_wr_offset_q;

  localparam unsigned DataWidthB = DataWidth / 8;

  always_comb begin: p_vldu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_bytes_d   = issue_cnt_bytes_q;
    commit_cnt_bytes_d  = commit_cnt_bytes_q;

    axi_len_d           = axi_len_q;
    axi_r_byte_pnt_d    = axi_r_byte_pnt_q;
    vrf_word_byte_pnt_d = vrf_word_byte_pnt_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    result_final_gnt_d = result_final_gnt_q;

    seq_word_wr_offset_d = seq_word_wr_offset_q;
    first_payload_byte_d = first_payload_byte_q;
    vrf_word_byte_cnt_d  = vrf_word_byte_cnt_q;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // We are not ready, by default
    axi_addrgen_req_ready_o = 1'b0;
    pe_resp_d               = '0;
    axi_r_ready_o           = 1'b0;
    mask_ready_o            = 1'b0;
    load_complete_o         = 1'b0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    ////////////////////////////////////
    //  Read data from the R channel  //
    ////////////////////////////////////

    // We are ready to accept the R beats if all the following are respected:
    // - There is an R beat available.
    // - The Address Generator sent us the data about the corresponding AR beat
    // - There is place in the result queue to write the data read from the R channel
    // - This request did not generate an exception
    if (axi_r_valid_i && axi_addrgen_req_valid_i
        && axi_addrgen_req_i.is_load && !axi_addrgen_req_i.is_exception
        && !result_queue_full) begin : axi_r_beat_read
      // Bytes valid in the current R beat
      // If non-unit strided load, we do not progress within the beat
      automatic shortint unsigned lower_byte = beat_lower_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);
      automatic shortint unsigned upper_byte = beat_upper_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);

      // Is there a vector instruction ready to be issued?
      // Do we have the operands for it?
      if (vinsn_issue_valid && (vinsn_issue_q.vm || (|mask_valid_i))) begin : operands_valid
        // Account for the issued bytes
        // How many bytes are valid in this VRF word
        automatic vlen_t vrf_valid_bytes   = (NrLanes * DataWidthB) - vrf_word_byte_pnt_q;
        // How many bytes are valid in this instruction
        automatic vlen_t vinsn_valid_bytes = issue_cnt_bytes_q - vrf_word_byte_cnt_q;
        // How many bytes are valid in this AXI word
        automatic vlen_t axi_valid_bytes   = upper_byte - lower_byte - axi_r_byte_pnt_q + 1;


        // How many bytes are we committing?
        automatic logic [idx_width(DataWidth*NrLanes/8):0] valid_bytes;
        valid_bytes = (issue_cnt_bytes_q < (NrLanes * DataWidthB)) ? vinsn_valid_bytes : vrf_valid_bytes;
        valid_bytes = (valid_bytes       < axi_valid_bytes       ) ? valid_bytes       : axi_valid_bytes;

        // Bump R beat and VRF word pointers
        axi_r_byte_pnt_d    = axi_r_byte_pnt_q + valid_bytes;
        vrf_word_byte_pnt_d = vrf_word_byte_pnt_q + valid_bytes;
        vrf_word_byte_cnt_d = vrf_word_byte_cnt_q + valid_bytes;

        // Copy data from the R channel into the result queue
        for (int unsigned axi_byte = 0; axi_byte < AxiDataWidth/8; axi_byte++) begin : axi_r_to_result_queue
          // Is this byte a valid byte in the R beat?
          if ((axi_byte >= (lower_byte + axi_r_byte_pnt_q)) && (axi_byte <= upper_byte)) begin : is_axi_r_byte
            // Map axi_byte to the corresponding byte in the VRF word (sequential)
            automatic int unsigned vrf_seq_byte = axi_byte - lower_byte - axi_r_byte_pnt_q + vrf_word_byte_pnt_q;
            // Follow the vrf_seq_byte, but without the vstart information
            automatic int unsigned vrf_seq_byte_cnt = axi_byte - lower_byte - axi_r_byte_pnt_q + vrf_word_byte_cnt_q;
            // And then shuffle it
            automatic int unsigned vrf_byte = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue_q.vtype.vsew);

            // Is this byte a valid byte in the VRF word?
            // We compare vrf_seq_byte_cnt since vrf_seq_byte contains also the vstart contribution, while the issue_cnt_bytes
            // counter does not.
            if (vrf_seq_byte_cnt < issue_cnt_bytes_q && vrf_seq_byte < (NrLanes * DataWidthB)) begin : is_vrf_byte
              // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
              automatic int unsigned vrf_offset = vrf_byte[2:0];
              // Make sure this index wraps around the number of lane
              automatic int unsigned vrf_lane = (vrf_byte >> 3);

              // Copy data and byte strobe
              result_queue_d[result_queue_write_pnt_q][vrf_lane].wdata[8*vrf_offset +: 8] =
                axi_r_i.data[8*axi_byte +: 8];
              result_queue_d[result_queue_write_pnt_q][vrf_lane].be[vrf_offset] =
                vinsn_issue_q.vm || mask_i[vrf_lane][vrf_offset];
            end : is_vrf_byte
          end : is_axi_r_byte
        end : axi_r_to_result_queue

        for (int unsigned lane = 0; lane < NrLanes; lane++) begin : compute_vrf_addr
          // vstart value local ot the lane
          automatic vlen_t vstart_lane;

          // vstart of the lanes that we are writing to in this cycle
          vstart_lane = vinsn_issue_q.vstart / NrLanes;

          // Store in result queue
          result_queue_d[result_queue_write_pnt_q][lane].addr = vaddr(vinsn_issue_q.vd, NrLanes, VLEN) + (vstart_lane >> (EW64 - vinsn_issue_q.vtype.vsew)) + seq_word_wr_offset_q;
          result_queue_d[result_queue_write_pnt_q][lane].id   = vinsn_issue_q.id;
        end : compute_vrf_addr
      end : operands_valid

      // We have a word ready to be sent to the lanes
      if (vrf_word_byte_pnt_d == (NrLanes * DataWidthB) || vrf_word_byte_cnt_d == issue_cnt_bytes_q) begin : vrf_word_ready
        // Increment result queue pointers and counters
        result_queue_cnt_d += 1;
        if (result_queue_write_pnt_q == ResultQueueDepth-1) begin : result_queue_write_pnt_overflow
          result_queue_write_pnt_d = '0;
        end : result_queue_write_pnt_overflow
        else begin : result_queue_write_pnt_increment
          result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
        end : result_queue_write_pnt_increment

        // Trigger the request signal
        result_queue_valid_d[result_queue_write_pnt_q] = {NrLanes{1'b1}};

        // Increase the VRF-write sequential counter
        seq_word_wr_offset_d = seq_word_wr_offset_q + 1;

        // Acknowledge the mask operands
        mask_ready_o = !vinsn_issue_q.vm;

        // Reset the pointer in the VRF word
        vrf_word_byte_pnt_d   = '0;
        vrf_word_byte_cnt_d   = '0;
        // Account for the results that were issued
        if (seq_word_wr_offset_q) begin
          vrf_eff_write_bytes = (NrLanes * DataWidthB);
        end else begin
          // First payload of the vector instruction
          vrf_eff_write_bytes = first_payload_byte_q;
        end
        issue_cnt_bytes_d = issue_cnt_bytes_q - vrf_eff_write_bytes;
        if (issue_cnt_bytes_q < vrf_eff_write_bytes) begin : issue_cnt_bytes_overflow
          issue_cnt_bytes_d = '0;
        end : issue_cnt_bytes_overflow
      end : vrf_word_ready

      // Consumed all valid bytes in this R beat
      if ((axi_r_byte_pnt_d == (upper_byte - lower_byte + 1)) || (issue_cnt_bytes_d == '0)) begin : axi_r_beat_finish
        // Request another beat
        axi_r_ready_o = 1'b1;
        axi_r_byte_pnt_d   = '0;
        // Account for the beat we consumed
        axi_len_d     = axi_len_q + 1;
      end : axi_r_beat_finish

      // Consumed all beats from this burst
      if ($unsigned(axi_len_d) == axi_pkg::len_t'($unsigned(axi_addrgen_req_i.len) + 1)) begin : axi_finish
        // Reset AXI pointers
        axi_len_d               = '0;
        axi_r_byte_pnt_d             = '0;
        // Wait for another AXI request
        axi_addrgen_req_ready_o = 1'b1;
      end : axi_finish

      // Finished issuing results
      if (vinsn_issue_valid && issue_cnt_bytes_d == '0 ) begin : vrf_results_finish
        // Increment vector instruction queue pointers and counters
        vinsn_queue_d.issue_cnt -= 1;
        if (vinsn_queue_q.issue_pnt == (VInsnQueueDepth-1)) begin : issue_pnt_overflow
          vinsn_queue_d.issue_pnt = '0;
        end : issue_pnt_overflow
        else begin : issue_pnt_increment
          vinsn_queue_d.issue_pnt += 1;
        end : issue_pnt_increment

        // Prepare for the next vector instruction
        if (vinsn_queue_d.issue_cnt != 0) begin : issue_cnt_bytes_update
          issue_cnt_bytes_d = (
                                vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl
                                - vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vstart
                              ) << unsigned'(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew);
          // Prepare the VRF start pointer
          vrf_word_start_byte  = vinsn_issue_d.vstart[$clog2(8*NrLanes)-1:0] << vinsn_issue_d.vtype.vsew;
          vrf_word_byte_pnt_d  = {1'b0, vrf_word_start_byte[$clog2(8*NrLanes)-1:0]};
          vrf_word_byte_cnt_d  = '0;
          seq_word_wr_offset_d = '0;
          // The first payload byte width for this vload
          first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0];
        end : issue_cnt_bytes_update
      end : vrf_results_finish
    end : axi_r_beat_read

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

    for (int unsigned lane = 0; lane < NrLanes; lane++) begin: vrf_result_write
      ldu_result_req_o[lane]   = result_queue_valid_q[result_queue_read_pnt_q][lane];
      ldu_result_addr_o[lane]  = result_queue_q[result_queue_read_pnt_q][lane].addr;
      ldu_result_id_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].id;
      ldu_result_wdata_o[lane] = result_queue_q[result_queue_read_pnt_q][lane].wdata;
      ldu_result_be_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].be;

      // Update the final gnt vector
      result_final_gnt_d[lane] |= ldu_result_final_gnt_i[lane];

      // Received a grant from the VRF.
      // Deactivate the request, but do not bump the pointers for now.
      if (ldu_result_req_o[lane] && ldu_result_gnt_i[lane]) begin : vrf_grant
        result_queue_valid_d[result_queue_read_pnt_q][lane] = 1'b0;
        result_queue_d[result_queue_read_pnt_q][lane]       = '0;
        // Reset the final gnt vector since we are now waiting for another final gnt
        result_final_gnt_d[lane] = 1'b0;
      end : vrf_grant
    end: vrf_result_write

    // All lanes accepted the VRF request
    // Wait for all the final grants, to be sure that all the results were written back
    if (!(|result_queue_valid_d[result_queue_read_pnt_q]) &&
      (&result_final_gnt_d || commit_cnt_bytes_q > (NrLanes * DataWidthB))) begin : wait_for_write_back
      // There is something waiting to be written
      if (!result_queue_empty) begin : result_available
        // Increment the read pointer
        if (result_queue_read_pnt_q == (ResultQueueDepth-1)) begin : result_queue_read_pnt_overflow
          result_queue_read_pnt_d = 0;
        end : result_queue_read_pnt_overflow
        else begin  : result_queue_read_pnt_increment
          result_queue_read_pnt_d = result_queue_read_pnt_q + 1;
        end : result_queue_read_pnt_increment

        // Decrement the counter of results waiting to be written
        result_queue_cnt_d -= 1;

        // Decrement the counter of remaining vector elements waiting to be written
        commit_cnt_bytes_d = commit_cnt_bytes_q - (NrLanes * DataWidthB);
        if (commit_cnt_bytes_q < (NrLanes * DataWidthB)) begin : commit_cnt_bytes_overflow
          commit_cnt_bytes_d = '0;
        end : commit_cnt_bytes_overflow
      end : result_available
    end : wait_for_write_back

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && commit_cnt_bytes_d == '0) begin : vinsn_done
      // Mark the vector instruction as being done
      pe_resp_d.vinsn_done[vinsn_commit.id] = 1'b1;

      // Signal complete load
      load_complete_o = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
        vinsn_queue_d.commit_pnt = '0;
      else
        vinsn_queue_d.commit_pnt += 1;

      // Update the commit counter for the next instruction
      if (vinsn_queue_d.commit_cnt != '0)
        commit_cnt_bytes_d = (
                               vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl
                                - vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vstart
                              ) << unsigned'(vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vtype.vsew);
    end : vinsn_done

    /////////////////////////
    //  Handle exceptions  //
    /////////////////////////

    // Clear instruction queue in case of exceptions from addrgen
    if (vinsn_issue_valid && ((axi_addrgen_req_valid_i && axi_addrgen_req_i.is_exception) || addrgen_illegal_load_i)) begin : exception
      // Signal done to sequencer
      pe_resp_d.vinsn_done[vinsn_commit.id] = 1'b1;

      // Signal complete load
      load_complete_o = 1'b1;

      // Ack the addrgen for this last faulty request
      axi_addrgen_req_ready_o = axi_addrgen_req_valid_i;
      // Reset axi state
      axi_len_d               = '0;
      axi_r_byte_pnt_d        = '0;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
        vinsn_queue_d.commit_pnt = '0;
      else
        vinsn_queue_d.commit_pnt += 1;

      // Increment vector instruction queue pointers and counters
      vinsn_queue_d.issue_cnt -= 1;
      if (vinsn_queue_q.issue_pnt == (VInsnQueueDepth-1)) begin : issue_pnt_overflow
        vinsn_queue_d.issue_pnt = '0;
      end : issue_pnt_overflow
      else begin : issue_pnt_increment
        vinsn_queue_d.issue_pnt += 1;
      end : issue_pnt_increment
    end : exception

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] &&
      pe_req_i.vfu == VFU_LoadUnit) begin : pe_req_valid
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = pe_req_i;
      vinsn_running_d[pe_req_i.id]                  = 1'b1;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0) begin : issue_cnt_bytes_init
        issue_cnt_bytes_d = (pe_req_i.vl - pe_req_i.vstart) << unsigned'(pe_req_i.vtype.vsew);
      end : issue_cnt_bytes_init
      if (vinsn_queue_d.commit_cnt == '0) begin : commit_cnt_bytes_init
        commit_cnt_bytes_d = (pe_req_i.vl - pe_req_i.vstart) << unsigned'(pe_req_i.vtype.vsew);
      end : commit_cnt_bytes_init

      // New instruction with new vstart. Initialize the vrf byte ptr
      if (vinsn_queue_d.issue_cnt == '0) begin
        vrf_word_start_byte  = pe_req_i.vstart[$clog2(8*NrLanes)-1:0] << pe_req_i.vtype.vsew;
        vrf_word_byte_pnt_d  = {1'b0, vrf_word_start_byte[$clog2(8*NrLanes)-1:0]};
        vrf_word_byte_cnt_d  = '0;
        seq_word_wr_offset_d = '0;
        // The first payload byte width for this vload
        first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0];
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end : pe_req_valid
  end: p_vldu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q      <= '0;
      issue_cnt_bytes_q    <= '0;
      commit_cnt_bytes_q   <= '0;
      axi_len_q            <= '0;
      axi_r_byte_pnt_q     <= '0;
      vrf_word_byte_pnt_q  <= '0;
      pe_resp_o            <= '0;
      result_final_gnt_q   <= '0;
      seq_word_wr_offset_q <= '0;
      first_payload_byte_q <= '0;
      vrf_word_byte_cnt_q  <= '0;
    end else begin
      vinsn_running_q      <= vinsn_running_d;
      issue_cnt_bytes_q    <= issue_cnt_bytes_d;
      commit_cnt_bytes_q   <= commit_cnt_bytes_d;
      axi_len_q            <= axi_len_d;
      axi_r_byte_pnt_q     <= axi_r_byte_pnt_d;
      vrf_word_byte_pnt_q  <= vrf_word_byte_pnt_d;
      pe_resp_o            <= pe_resp_d;
      result_final_gnt_q   <= result_final_gnt_d;
      seq_word_wr_offset_q <= seq_word_wr_offset_d;
      first_payload_byte_q <= first_payload_byte_d;
      vrf_word_byte_cnt_q  <= vrf_word_byte_cnt_d;
    end
  end

endmodule : vldu
