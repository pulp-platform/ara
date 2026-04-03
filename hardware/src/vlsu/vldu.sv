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
    localparam int           DataWidth         = $bits(elen_t),
    localparam type          strb_t            = logic[DataWidth/8-1:0],
    localparam type          vlen_t            = logic[$clog2(VLEN+1)-1:0],
    localparam type          axi_addr_t        = logic [AxiAddrWidth-1:0],
    localparam int unsigned  NrVRFWordsPerBeat = AxiDataWidth / (NrLanes * DataWidth)
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
    output logic                           ldu_current_burst_exception_o,
    // Interface with the address generator
    input  addrgen_axi_req_t               axi_addrgen_req_i,
    input  logic                           axi_addrgen_req_valid_i,
    output logic                           axi_addrgen_req_ready_o,
    input  logic                           addrgen_illegal_load_i,
    // Interface with the lanes
    output logic             [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_req_o,
    output vid_t             [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_id_o,
    output vaddr_t           [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_addr_o,
    output elen_t            [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_wdata_o,
    output strb_t            [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_be_o,
    input  logic             [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_gnt_i,
    input  logic             [NrLanes-1:0][NrVRFWordsPerBeat-1:0] ldu_result_final_gnt_i,
    // LSU exception support
    input  logic                           lsu_ex_flush_i,
    // Interface with the Mask unit
    input  strb_t            [NrLanes-1:0] mask_i,
    input  logic             [NrLanes-1:0] mask_valid_i,
    output logic                           mask_ready_o
  );

  import cf_math_pkg::idx_width;
  import axi_pkg::beat_lower_byte;
  import axi_pkg::beat_upper_byte;
  import axi_pkg::BURST_INCR;

  ////////////////
  //  MASK cut  //
  ////////////////

  strb_t [NrLanes-1:0] mask_q;
  logic  [NrLanes-1:0] mask_valid_d, mask_valid_q;
  logic                mask_ready_d;
  logic  [NrLanes-1:0] mask_ready_q;
  // Insn queue related signal
  pe_req_t vinsn_issue_d, vinsn_issue_q;
  logic vinsn_issue_valid;

  // Flush support
  logic lsu_ex_flush_q;

  for (genvar l = 0; l < NrLanes; l++) begin
    spill_register_flushable #(
      .T(strb_t)
    ) i_vldu_mask_register (
      .clk_i     (clk_i           ),
      .rst_ni    (rst_ni          ),
      .flush_i   (lsu_ex_flush_q  ),
      .data_o    (mask_q[l]       ),
      .valid_o   (mask_valid_q[l] ),
      .ready_i   (mask_ready_d    ),
      .data_i    (mask_i[l]       ),
      .valid_i   (mask_valid_d[l] ),
      .ready_o   (mask_ready_q[l] )
    );

    // Sample only SLDU mask valid
    assign mask_valid_d[l] = mask_valid_i[l] & ~vinsn_issue_q.vm & vinsn_issue_valid;
  end

  // Don't upset the masku with a spurious ready
  assign mask_ready_o = mask_ready_q[0] & mask_valid_i[0] & ~vinsn_issue_q.vm & vinsn_issue_valid;

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

  // There are NrVRFWordsPerBeat independent result queues, one per VRF word slot per beat.
  // Write pointers advance together (one AXI beat fills one entry in every queue).
  // Read pointers advance independently as each word is granted by the VRF arbiter.
  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } payload_t;

  // NrVRFWordsPerBeat independent result queues
  payload_t [NrVRFWordsPerBeat-1:0][ResultQueueDepth-1:0][NrLanes-1:0] result_queue_d, result_queue_q;
  logic     [NrVRFWordsPerBeat-1:0][ResultQueueDepth-1:0][NrLanes-1:0] result_queue_valid_d, result_queue_valid_q;
  // Write pointers (all advance together when AXI beat is consumed)
  logic     [NrVRFWordsPerBeat-1:0][idx_width(ResultQueueDepth)-1:0] result_queue_write_pnt_d, result_queue_write_pnt_q;
  // Read pointers (each advances independently based on VRF grants)
  logic     [NrVRFWordsPerBeat-1:0][idx_width(ResultQueueDepth)-1:0] result_queue_read_pnt_d, result_queue_read_pnt_q;
  // Per-queue entry count
  logic     [NrVRFWordsPerBeat-1:0][idx_width(ResultQueueDepth):0]   result_queue_cnt_d, result_queue_cnt_q;
  // Per-queue final-grant tracking (one bit per lane per queue)
  logic     [NrVRFWordsPerBeat-1:0][NrLanes-1:0]                     result_final_gnt_d, result_final_gnt_q;

  // Any queue full stalls accepting a new AXI beat
  logic [NrVRFWordsPerBeat-1:0] result_queue_full_w, result_queue_empty_w;
  for (genvar w = 0; w < NrVRFWordsPerBeat; w++) begin : gen_result_queue_status
    assign result_queue_full_w[w]  = (result_queue_cnt_q[w] == ResultQueueDepth);
    assign result_queue_empty_w[w] = (result_queue_cnt_q[w] == '0);
  end : gen_result_queue_status
  logic result_queue_full;
  assign result_queue_full = |result_queue_full_w;
  logic result_queue_empty;
  assign result_queue_empty = &result_queue_empty_w;

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
  // - A pointer to which byte in the NrVRFWordsPerBeat-word group we are writing data into.
  // Tracks byte offset within the NrVRFWordsPerBeat-word group being filled from the current beat
  logic [idx_width(NrVRFWordsPerBeat*DataWidth*NrLanes/8):0] vrf_word_byte_pnt_d, vrf_word_byte_pnt_q;
  // - A pointer that indicates the start byte in the vrf word.
  logic [$clog2(8*NrLanes)-1:0] vrf_word_start_byte;

  // A counter that follows the vrf_word_byte_pnt pointer, but without the vstart information
  // We can compare this counter witht the issue_cnt_bytes counter to find the last byte in
  // our transaction
  logic [idx_width(NrVRFWordsPerBeat*DataWidth*NrLanes/8):0] vrf_word_byte_cnt_d, vrf_word_byte_cnt_q;

  // When vstart > 0, the very first payload written to the VRF contains less than
  // (NrVRFWordsPerBeat * 8 * NrLanes) bytes.
  // first_payload_byte: valid bytes in the first word-group (queue 0 partial + queues 1..N-1 full)
  logic [$clog2(NrVRFWordsPerBeat*8*NrLanes):0] first_payload_byte_d, first_payload_byte_q;
  logic [$clog2(NrVRFWordsPerBeat*8*NrLanes):0] vrf_eff_write_bytes;
  // Same thing, but for the commit (resqueue -> VRF)
  // Track if this VRF write is the first one for this instruction
  logic first_result_queue_read_d, first_result_queue_read_q;
  logic [$clog2(NrVRFWordsPerBeat*8*NrLanes):0] res_queue_eff_write_bytes;

  // Signal that the current burst is having an exception
  logic ldu_current_burst_exception_d;

  // Counter to increase the VRF write address.
  vlen_t seq_word_wr_offset_d, seq_word_wr_offset_q;

  // Exception handling FSM
  // Needed because of the result queue buffer, which can contain partial
  // results upon exception.
  enum logic [1:0] {
    IDLE,
    VALID_RESULT_QUEUE,
    WAIT_RESULT_QUEUE,
    HANDLE_EXCEPTION
  } ldu_ex_state_d, ldu_ex_state_q;

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
    mask_ready_d            = 1'b0;
    load_complete_o         = 1'b0;

    first_result_queue_read_d = first_result_queue_read_q;

    ldu_ex_state_d = ldu_ex_state_q;

    // Normally write multiple of resqueue width
    vrf_eff_write_bytes       = (NrVRFWordsPerBeat * NrLanes * DataWidthB);
    res_queue_eff_write_bytes = (NrLanes * DataWidthB);

    ldu_current_burst_exception_d = 1'b0;

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
      automatic logic [idx_width(AxiDataWidth/8)-1:0] lower_byte = beat_lower_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);
      automatic logic [idx_width(AxiDataWidth/8)-1:0] upper_byte = beat_upper_byte(axi_addrgen_req_i.addr,
        axi_addrgen_req_i.size, axi_addrgen_req_i.len, BURST_INCR, AxiDataWidth/8, axi_len_q);

      // Is there a vector instruction ready to be issued?
      // Do we have the operands for it?
      if (vinsn_issue_valid && (vinsn_issue_q.vm || (|mask_valid_q))) begin : operands_valid
        // Account for the issued bytes
        // How many bytes are valid in this NrVRFWordsPerBeat-word group
        automatic vlen_t vrf_valid_bytes   = (NrVRFWordsPerBeat * NrLanes * DataWidthB) - vrf_word_byte_pnt_q;
        // How many bytes are valid in this instruction
        automatic vlen_t vinsn_valid_bytes = issue_cnt_bytes_q - vrf_word_byte_cnt_q;
        // How many bytes are valid in this AXI word
        automatic vlen_t axi_valid_bytes   = upper_byte - lower_byte - axi_r_byte_pnt_q + 1;


        // How many bytes are we committing?
        automatic logic [idx_width(NrVRFWordsPerBeat*DataWidth*NrLanes/8):0] valid_bytes;
        valid_bytes = (issue_cnt_bytes_q < (NrVRFWordsPerBeat * NrLanes * DataWidthB)) ? vinsn_valid_bytes : vrf_valid_bytes;
        valid_bytes = (valid_bytes       < axi_valid_bytes       ) ? valid_bytes       : axi_valid_bytes;

        // Bump R beat and VRF word pointers
        axi_r_byte_pnt_d    = axi_r_byte_pnt_q + valid_bytes;
        vrf_word_byte_pnt_d = vrf_word_byte_pnt_q + valid_bytes;
        vrf_word_byte_cnt_d = vrf_word_byte_cnt_q + valid_bytes;

        // Copy data from the R channel into the result queue
        for (int unsigned axi_byte = 0; axi_byte < AxiDataWidth/8; axi_byte++) begin : axi_r_to_result_queue
          // Is this byte a valid byte in the R beat?
          if ((axi_byte >= (lower_byte + axi_r_byte_pnt_q)) && (axi_byte <= upper_byte)) begin : is_axi_r_byte
            // Total sequential byte offset across the NrVRFWordsPerBeat-word group
            automatic int unsigned total_vrf_seq_byte = axi_byte - lower_byte - axi_r_byte_pnt_q + vrf_word_byte_pnt_q;
            automatic int unsigned total_vrf_seq_byte_cnt = axi_byte - lower_byte - axi_r_byte_pnt_q + vrf_word_byte_cnt_q;
            // Which VRF word segment (queue) does this byte belong to?
            automatic int unsigned vrf_word_seg     = total_vrf_seq_byte / (NrLanes * DataWidthB);
            automatic int unsigned vrf_word_seg_cnt = total_vrf_seq_byte_cnt / (NrLanes * DataWidthB);
            // Byte position within that VRF word
            automatic int unsigned vrf_seq_byte     = total_vrf_seq_byte % (NrLanes * DataWidthB);
            automatic int unsigned vrf_seq_byte_cnt = total_vrf_seq_byte_cnt % (NrLanes * DataWidthB);
            // Shuffle into lane-striped VRF layout
            automatic int unsigned vrf_byte         = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue_q.vtype.vsew);

            // Is this byte a valid byte in the VRF word?
            // We compare vrf_seq_byte_cnt since vrf_seq_byte contains also the vstart contribution, while the issue_cnt_bytes
            // counter does not.
            if (total_vrf_seq_byte_cnt < issue_cnt_bytes_q && vrf_word_seg < NrVRFWordsPerBeat &&
                total_vrf_seq_byte < (NrVRFWordsPerBeat * NrLanes * DataWidthB)) begin : is_vrf_byte
              // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
              automatic int unsigned vrf_offset = vrf_byte[2:0];
              // Make sure this index wraps around the number of lanes
              automatic int unsigned vrf_lane   = (vrf_byte >> 3);

              // Copy data and byte strobe
              result_queue_d[vrf_word_seg][result_queue_write_pnt_q[vrf_word_seg]][vrf_lane].wdata[8*vrf_offset +: 8] =
                axi_r_i.data[8*axi_byte +: 8];
              result_queue_d[vrf_word_seg][result_queue_write_pnt_q[vrf_word_seg]][vrf_lane].be[vrf_offset] =
                vinsn_issue_q.vm || mask_q[vrf_lane][vrf_offset];
            end : is_vrf_byte
          end : is_axi_r_byte
        end : axi_r_to_result_queue

        for (int unsigned lane = 0; lane < NrLanes; lane++) begin : compute_vrf_addr
          // vstart value local to the lane
          automatic vlen_t vstart_lane;
          vstart_lane = vinsn_issue_q.vstart / NrLanes;
          for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++) begin : compute_vrf_addr_per_word
            result_queue_d[w][result_queue_write_pnt_q[w]][lane].addr =
              vaddr(vinsn_issue_q.vd, NrLanes, VLEN) + (vstart_lane >> (EW64 - vinsn_issue_q.vtype.vsew))
              + seq_word_wr_offset_q + w;
            result_queue_d[w][result_queue_write_pnt_q[w]][lane].id = vinsn_issue_q.id;
          end : compute_vrf_addr_per_word
        end : compute_vrf_addr
      end : operands_valid

      // We have a word-group ready to be sent to the lanes
      if (vrf_word_byte_pnt_d == (NrVRFWordsPerBeat * NrLanes * DataWidthB) || vrf_word_byte_cnt_d == issue_cnt_bytes_q) begin : vrf_word_ready
        // All NrVRFWordsPerBeat write pointers advance together
        for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++) begin : advance_write_ptrs
          result_queue_cnt_d[w] += 1;
          if (result_queue_write_pnt_q[w] == ResultQueueDepth-1) begin
            result_queue_write_pnt_d[w] = '0;
          end else begin
            result_queue_write_pnt_d[w] = result_queue_write_pnt_q[w] + 1;
          end
          result_queue_valid_d[w][result_queue_write_pnt_q[w]] = {NrLanes{1'b1}};
        end : advance_write_ptrs

        // Increase the VRF-write sequential counter by NrVRFWordsPerBeat
        seq_word_wr_offset_d = seq_word_wr_offset_q + NrVRFWordsPerBeat;

        // Acknowledge the mask operands
        mask_ready_d = !vinsn_issue_q.vm;

        // Reset the pointer in the VRF word
        vrf_word_byte_pnt_d   = '0;
        vrf_word_byte_cnt_d   = '0;
        // Account for the results that were issued
        if (seq_word_wr_offset_q) begin
          vrf_eff_write_bytes = (NrVRFWordsPerBeat * NrLanes * DataWidthB);
        end else begin
          // First payload of the vector instruction (queue 0 partial + queues 1..N-1 full)
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
          // Queue 0's first entry may be partial due to vstart; queues 1..NrVRFWordsPerBeat-1 are always full
          first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0]
                                 + (NrVRFWordsPerBeat - 1) * (NrLanes * DataWidthB);
        end : issue_cnt_bytes_update
      end : vrf_results_finish
    end : axi_r_beat_read

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

    for (int unsigned lane = 0; lane < NrLanes; lane++) begin: vrf_result_write
      for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++) begin : vrf_result_write_per_word
        ldu_result_req_o[lane][w]   = result_queue_valid_q[w][result_queue_read_pnt_q[w]][lane];
        ldu_result_addr_o[lane][w]  = result_queue_q[w][result_queue_read_pnt_q[w]][lane].addr;
        ldu_result_id_o[lane][w]    = result_queue_q[w][result_queue_read_pnt_q[w]][lane].id;
        ldu_result_wdata_o[lane][w] = result_queue_q[w][result_queue_read_pnt_q[w]][lane].wdata;
        ldu_result_be_o[lane][w]    = result_queue_q[w][result_queue_read_pnt_q[w]][lane].be;

        // Update the final gnt vector
        result_final_gnt_d[w][lane] |= ldu_result_final_gnt_i[lane][w];

        // Received a grant from the VRF — deactivate request, do not bump pointer yet
        if (ldu_result_req_o[lane][w] && ldu_result_gnt_i[lane][w]) begin : vrf_grant
          result_queue_valid_d[w][result_queue_read_pnt_q[w]][lane] = 1'b0;
          result_queue_d[w][result_queue_read_pnt_q[w]][lane]       = '0;
          result_final_gnt_d[w][lane] = 1'b0;
        end : vrf_grant
      end : vrf_result_write_per_word
    end: vrf_result_write

    // Advance each queue's read pointer independently when all its lanes are granted
    for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++) begin : advance_read_ptrs
      if (first_result_queue_read_q && w == 0) begin
        // first_payload_byte accounts for ALL segments (partial queue 0 + full queues 1..N-1).
        // Only w=0 subtracts it; w>0 subtracts 0 to avoid double-counting.
        res_queue_eff_write_bytes = first_payload_byte_q;
      end else if (first_result_queue_read_q) begin
        res_queue_eff_write_bytes = '0;
      end else begin
        res_queue_eff_write_bytes = (NrLanes * DataWidthB);
      end

      if (!(|result_queue_valid_d[w][result_queue_read_pnt_q[w]]) &&
          (&result_final_gnt_d[w] || commit_cnt_bytes_q > (NrLanes * DataWidthB))) begin : wait_for_write_back
        if (!result_queue_empty_w[w]) begin : result_available
          if (result_queue_read_pnt_q[w] == (ResultQueueDepth-1)) begin : result_queue_read_pnt_overflow
            result_queue_read_pnt_d[w] = 0;
          end : result_queue_read_pnt_overflow
          else begin : result_queue_read_pnt_increment
            result_queue_read_pnt_d[w] = result_queue_read_pnt_q[w] + 1;
          end : result_queue_read_pnt_increment

          result_queue_cnt_d[w] -= 1;

          if (w == 0) begin
            first_result_queue_read_d = 1'b0;
          end

          commit_cnt_bytes_d = commit_cnt_bytes_d - res_queue_eff_write_bytes;
          if (commit_cnt_bytes_d > commit_cnt_bytes_q) begin : commit_cnt_bytes_overflow
            commit_cnt_bytes_d = '0;
          end : commit_cnt_bytes_overflow
        end : result_available
      end : wait_for_write_back
    end : advance_read_ptrs

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
      if (vinsn_queue_d.commit_cnt != '0) begin
        first_result_queue_read_d = 1'b1;
        commit_cnt_bytes_d = (
                               vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl
                                - vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vstart
                              ) << unsigned'(vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vtype.vsew);
      end
    end : vinsn_done

    /////////////////////////
    //  Handle exceptions  //
    /////////////////////////

    // Handle exceptions in the clean way
    // We cannot just abort the instruction since results can be in the result queue, waiting.
    unique case (ldu_ex_state_q)
      IDLE: begin
        // Handle the exception only if this is the last instruction committing results
        if (vinsn_issue_valid && (vinsn_queue_q.commit_cnt == 1) &&
            ((axi_addrgen_req_valid_i && axi_addrgen_req_i.is_exception) || addrgen_illegal_load_i)) begin
          ldu_ex_state_d = VALID_RESULT_QUEUE;
        end
      end
      // Write the partial results to the VRF
      VALID_RESULT_QUEUE: begin
        ldu_ex_state_d = WAIT_RESULT_QUEUE;
        // Send to the lanes what we had written in the resqueue before the exception.
        // If this is empty, the byte-enable signals should be zero, so no write happens.
        for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++)
          result_queue_valid_d[w][result_queue_write_pnt_q[w]] |= {NrLanes{1'b1}};
      end
      // Wait until the resqueue is empty
      WAIT_RESULT_QUEUE: begin
        begin : check_all_queues_drained
          automatic logic all_queues_drained;
          all_queues_drained = 1'b1;
          for (int unsigned w = 0; w < NrVRFWordsPerBeat; w++)
            all_queues_drained &= !(|result_queue_valid_q[w][result_queue_read_pnt_q[w]]);
          if (all_queues_drained) begin
            ldu_ex_state_d = HANDLE_EXCEPTION;
          end
        end : check_all_queues_drained
      end
      // Handle the exception
      HANDLE_EXCEPTION: begin
        ldu_ex_state_d = IDLE;

        // Signal done to sequencer
        pe_resp_d.vinsn_done[vinsn_commit.id] = 1'b1;

        // Signal complete load
        load_complete_o = 1'b1;

        // Reset axi state
        axi_len_d        = '0;
        axi_r_byte_pnt_d = '0;

        // Ack the addrgen for this last faulty request
        axi_addrgen_req_ready_o = axi_addrgen_req_valid_i;

        // Abort the main sequencer -> operand-req request
        ldu_current_burst_exception_d = 1'b1;

        // Increment vector instruction queue pointers and counters
        vinsn_queue_d.issue_cnt -= 1;
        if (vinsn_queue_q.issue_pnt == (VInsnQueueDepth-1)) begin : issue_pnt_overflow
          vinsn_queue_d.issue_pnt = '0;
        end : issue_pnt_overflow
        else begin : issue_pnt_increment
          vinsn_queue_d.issue_pnt += 1;
        end : issue_pnt_increment

        // Update the commit counters and pointers
        vinsn_queue_d.commit_cnt -= 1;
        if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
          vinsn_queue_d.commit_pnt = '0;
        else
          vinsn_queue_d.commit_pnt += 1;
      end
      default:;
    endcase

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
        first_result_queue_read_d = 1'b1;
        commit_cnt_bytes_d = (pe_req_i.vl - pe_req_i.vstart) << unsigned'(pe_req_i.vtype.vsew);
      end : commit_cnt_bytes_init

      // New instruction with new vstart. Initialize the vrf byte ptr
      if (vinsn_queue_d.issue_cnt == '0) begin
        vrf_word_start_byte  = pe_req_i.vstart[$clog2(8*NrLanes)-1:0] << pe_req_i.vtype.vsew;
        vrf_word_byte_pnt_d  = {1'b0, vrf_word_start_byte[$clog2(8*NrLanes)-1:0]};
        vrf_word_byte_cnt_d  = '0;
        seq_word_wr_offset_d = '0;
        // Queue 0's first entry may be partial due to vstart; queues 1..NrVRFWordsPerBeat-1 are always full
        first_payload_byte_d = (NrLanes * DataWidthB) - vrf_word_start_byte[$clog2(8*NrLanes)-1:0]
                               + (NrVRFWordsPerBeat - 1) * (NrLanes * DataWidthB);
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end : pe_req_valid
  end: p_vldu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q               <= '0;
      issue_cnt_bytes_q             <= '0;
      commit_cnt_bytes_q            <= '0;
      axi_len_q                     <= '0;
      axi_r_byte_pnt_q              <= '0;
      vrf_word_byte_pnt_q           <= '0;
      pe_resp_o                     <= '0;
      result_final_gnt_q            <= '0;
      seq_word_wr_offset_q          <= '0;
      first_payload_byte_q          <= '0;
      vrf_word_byte_cnt_q           <= '0;
      lsu_ex_flush_q                <= 1'b0;
      ldu_current_burst_exception_o <= 1'b0;
      ldu_ex_state_q                <= IDLE;
      first_result_queue_read_q     <= 1'b0;
    end else begin
      vinsn_running_q               <= vinsn_running_d;
      issue_cnt_bytes_q             <= issue_cnt_bytes_d;
      commit_cnt_bytes_q            <= commit_cnt_bytes_d;
      axi_len_q                     <= axi_len_d;
      axi_r_byte_pnt_q              <= axi_r_byte_pnt_d;
      vrf_word_byte_pnt_q           <= vrf_word_byte_pnt_d;
      pe_resp_o                     <= pe_resp_d;
      result_final_gnt_q            <= result_final_gnt_d;
      seq_word_wr_offset_q          <= seq_word_wr_offset_d;
      first_payload_byte_q          <= first_payload_byte_d;
      vrf_word_byte_cnt_q           <= vrf_word_byte_cnt_d;
      lsu_ex_flush_q                <= lsu_ex_flush_i;
      ldu_current_burst_exception_o <= ldu_current_burst_exception_d;
      ldu_ex_state_q                <= ldu_ex_state_d;
      first_result_queue_read_q     <= first_result_queue_read_d;
    end
  end

endmodule : vldu
