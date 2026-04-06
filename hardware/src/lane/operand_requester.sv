// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This stage is responsible for requesting individual elements from the vector
// register file, in order, and sending them to the corresponding operand
// queues. This stage also includes the VRF arbiter.

module operand_requester import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes               = 0,
    parameter  int  unsigned VLEN                  = 0,
    parameter  int  unsigned NrBanks               = 0,     // Number of banks in the vector register file
    parameter  int  unsigned AxiDataWidth          = 0,
    parameter  type          vaddr_t               = logic, // Type used to address vector register file elements
    parameter  type          operand_request_cmd_t = logic,
    parameter  type          operand_queue_cmd_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned NrVRFWordsPerBeat = AxiDataWidth / (NrLanes * $bits(elen_t)),
    localparam type          strb_t  = logic[$bits(elen_t)/8-1:0],
    localparam type          vlen_t  = logic[$clog2(VLEN+1)-1:0]
  ) (
    input  logic                                       clk_i,
    input  logic                                       rst_ni,
    // Interface with the main sequencer
    input  logic            [NrVInsn-1:0][NrVInsn-1:0] global_hazard_table_i,
    // Interface with the lane sequencer
    input  operand_request_cmd_t [NrOperandQueues-1:0] operand_request_i,
    input  logic                 [NrOperandQueues-1:0] operand_request_valid_i,
    output logic                 [NrOperandQueues-1:0] operand_request_ready_o,
    // Support for store exception flush
    input  logic                                       lsu_ex_flush_i,
    output logic                                       lsu_ex_flush_o,
    // Interface with the VRF
    output logic                 [NrBanks-1:0]         vrf_req_o,
    output vaddr_t               [NrBanks-1:0]         vrf_addr_o,
    output logic                 [NrBanks-1:0]         vrf_wen_o,
    output elen_t                [NrBanks-1:0]         vrf_wdata_o,
    output strb_t                [NrBanks-1:0]         vrf_be_o,
    output opqueue_e             [NrBanks-1:0]         vrf_tgt_opqueue_o,
    // Interface with the operand queues
    input  logic                 [NrOperandQueues-1:0] operand_queue_ready_i,
    output logic                 [NrOperandQueues-1:0] operand_issued_o,
    output operand_queue_cmd_t   [NrOperandQueues-1:0] operand_queue_cmd_o,
    output logic                 [NrOperandQueues-1:0] operand_queue_cmd_valid_o,
    // Interface with the VFUs
    // ALU
    input  logic                                       alu_result_req_i,
    input  vid_t                                       alu_result_id_i,
    input  vaddr_t                                     alu_result_addr_i,
    input  elen_t                                      alu_result_wdata_i,
    input  strb_t                                      alu_result_be_i,
    output logic                                       alu_result_gnt_o,
    // Multiplier/FPU
    input  logic                                       mfpu_result_req_i,
    input  vid_t                                       mfpu_result_id_i,
    input  vaddr_t                                     mfpu_result_addr_i,
    input  elen_t                                      mfpu_result_wdata_i,
    input  strb_t                                      mfpu_result_be_i,
    output logic                                       mfpu_result_gnt_o,
    // Mask unit
    input  logic                                       masku_result_req_i,
    input  vid_t                                       masku_result_id_i,
    input  vaddr_t                                     masku_result_addr_i,
    input  elen_t                                      masku_result_wdata_i,
    input  strb_t                                      masku_result_be_i,
    output logic                                       masku_result_gnt_o,
    output logic                                       masku_result_final_gnt_o,
    // Slide unit
    input  logic                                       sldu_result_req_i,
    input  vid_t                                       sldu_result_id_i,
    input  vaddr_t                                     sldu_result_addr_i,
    input  elen_t                                      sldu_result_wdata_i,
    input  strb_t                                      sldu_result_be_i,
    output logic                                       sldu_result_gnt_o,
    output logic                                       sldu_result_final_gnt_o,
    // Load unit (NrVRFWordsPerBeat independent result queues)
    input  logic               [NrVRFWordsPerBeat-1:0] ldu_result_req_i,
    input  vid_t               [NrVRFWordsPerBeat-1:0] ldu_result_id_i,
    input  vaddr_t             [NrVRFWordsPerBeat-1:0] ldu_result_addr_i,
    input  elen_t              [NrVRFWordsPerBeat-1:0] ldu_result_wdata_i,
    input  strb_t              [NrVRFWordsPerBeat-1:0] ldu_result_be_i,
    output logic               [NrVRFWordsPerBeat-1:0] ldu_result_gnt_o,
    output logic               [NrVRFWordsPerBeat-1:0] ldu_result_final_gnt_o,
    // Load completion signal (from VLDU, active for one cycle when a load instruction finishes)
    input  logic                                       load_complete_i
  );

  import cf_math_pkg::idx_width;

  ////////////////////////
  //  Stream registers  //
  ////////////////////////

  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } stream_register_payload_t;

  // Load unit — NrVRFWordsPerBeat independent stream registers (one per VRF word segment)
  vid_t   [NrVRFWordsPerBeat-1:0] ldu_result_id;
  vaddr_t [NrVRFWordsPerBeat-1:0] ldu_result_addr;
  elen_t  [NrVRFWordsPerBeat-1:0] ldu_result_wdata;
  strb_t  [NrVRFWordsPerBeat-1:0] ldu_result_be;
  logic   [NrVRFWordsPerBeat-1:0] ldu_result_req;
  logic   [NrVRFWordsPerBeat-1:0] ldu_result_gnt;

  for (genvar w = 0; w < NrVRFWordsPerBeat; w++) begin: gen_ldu_stream_registers
    stream_register #(.T(stream_register_payload_t)) i_ldu_stream_register (
      .clk_i     (clk_i                                                                         ),
      .rst_ni    (rst_ni                                                                        ),
      .clr_i     (1'b0                                                                          ),
      .testmode_i(1'b0                                                                          ),
      .data_i    ({ldu_result_id_i[w], ldu_result_addr_i[w], ldu_result_wdata_i[w], ldu_result_be_i[w]}),
      .valid_i   (ldu_result_req_i[w]                                                           ),
      .ready_o   (ldu_result_gnt_o[w]                                                           ),
      .data_o    ({ldu_result_id[w], ldu_result_addr[w], ldu_result_wdata[w], ldu_result_be[w]}),
      .valid_o   (ldu_result_req[w]                                                             ),
      .ready_i   (ldu_result_gnt[w]                                                             )
    );
  end: gen_ldu_stream_registers

  // Slide unit
  vid_t   sldu_result_id;
  vaddr_t sldu_result_addr;
  elen_t  sldu_result_wdata;
  strb_t  sldu_result_be;
  logic   sldu_result_req;
  logic   sldu_result_gnt;
  stream_register #(.T(stream_register_payload_t)) i_sldu_stream_register (
    .clk_i     (clk_i                                                                        ),
    .rst_ni    (rst_ni                                                                       ),
    .clr_i     (1'b0                                                                         ),
    .testmode_i(1'b0                                                                         ),
    .data_i    ({sldu_result_id_i, sldu_result_addr_i, sldu_result_wdata_i, sldu_result_be_i}),
    .valid_i   (sldu_result_req_i                                                            ),
    .ready_o   (sldu_result_gnt_o                                                            ),
    .data_o    ({sldu_result_id, sldu_result_addr, sldu_result_wdata, sldu_result_be}        ),
    .valid_o   (sldu_result_req                                                              ),
    .ready_i   (sldu_result_gnt                                                              )
  );

  // Mask unit
  vid_t   masku_result_id;
  vaddr_t masku_result_addr;
  elen_t  masku_result_wdata;
  strb_t  masku_result_be;
  logic   masku_result_req;
  logic   masku_result_gnt;
  stream_register #(.T(stream_register_payload_t)) i_masku_stream_register (
    .clk_i     (clk_i                                                                            ),
    .rst_ni    (rst_ni                                                                           ),
    .clr_i     (1'b0                                                                             ),
    .testmode_i(1'b0                                                                             ),
    .data_i    ({masku_result_id_i, masku_result_addr_i, masku_result_wdata_i, masku_result_be_i}),
    .valid_i   (masku_result_req_i                                                               ),
    .ready_o   (masku_result_gnt_o                                                               ),
    .data_o    ({masku_result_id, masku_result_addr, masku_result_wdata, masku_result_be}        ),
    .valid_o   (masku_result_req                                                                 ),
    .ready_i   (masku_result_gnt                                                                 )
  );

  // The very last grant must happen when the instruction actually write in the VRF
  // Otherwise the dependency is freed in advance
  always_ff @(posedge clk_i or negedge rst_ni) begin : p_final_gnts
    if (!rst_ni) begin
      ldu_result_final_gnt_o   <= '0;
      sldu_result_final_gnt_o  <= 1'b0;
      masku_result_final_gnt_o <= 1'b0;
    end else begin
      ldu_result_final_gnt_o   <= ldu_result_gnt;
      sldu_result_final_gnt_o  <= sldu_result_gnt;
      masku_result_final_gnt_o <= masku_result_gnt;
    end
  end

  ///////////////////////
  //  Stall mechanism  //
  ///////////////////////

  // To handle any type of stall between vector instructions, we ensure
  // that operands of a second instruction that has a hazard on a first
  // instruction are read at the same rate the results of the second
  // instruction are written. Therefore, the second instruction can never
  // overtake the first one.

  // Instruction wrote a result
  logic [NrVInsn-1:0] vinsn_result_written_d, vinsn_result_written_q;

  // Fine-grained element-level tracking for load-compute chaining.
  // 16 bits track NrVRFWordsPerBeat queues x NrVRFWordsPerBeat beats.
  // Bit layout: bit[beat * NrVRFWordsPerBeat + queue].
  //   Queue 0 owns bits {0, 4, 8, 12}; Queue 1 owns {1, 5, 9, 13}; etc.
  // Each per-requester block maintains its own copy of this register.
  // The module-level set mask is broadcast to all requesters simultaneously.
  //
  // IMPORTANT: The element tracking only works for the *active* load (ldu_active_id_q).
  // For other concurrent loads, the coarse ldu_beat_seg_granted / vinsn_result_written
  // mechanism is kept as a fallback. Element tracking adds finer granularity on top.
  localparam int unsigned NrLduTrackBits = NrVRFWordsPerBeat * NrVRFWordsPerBeat;

  // Per-VLDU-queue write counter: which beat (0..NrVRFWordsPerBeat-1) the next grant belongs to.
  logic [$clog2(NrVRFWordsPerBeat)-1:0] ldu_queue_wr_cnt_d [NrVRFWordsPerBeat];
  logic [$clog2(NrVRFWordsPerBeat)-1:0] ldu_queue_wr_cnt_q [NrVRFWordsPerBeat];
  // Active load instruction ID (updated on every VLDU grant)
  vid_t ldu_active_id_d, ldu_active_id_q;
  // Combinational mask: which bits of the 16-bit tracking register to set this cycle
  logic [NrLduTrackBits-1:0] ldu_queue_set_mask;

  always_comb begin
    vinsn_result_written_d  = '0;
    ldu_active_id_d         = ldu_active_id_q;
    ldu_queue_set_mask      = '0;
    for (int w = 0; w < NrVRFWordsPerBeat; w++)
      ldu_queue_wr_cnt_d[w] = ldu_queue_wr_cnt_q[w];

    // Which vector instructions are writing something?
    vinsn_result_written_d[alu_result_id_i]  |= alu_result_gnt_o;
    vinsn_result_written_d[mfpu_result_id_i] |= mfpu_result_gnt_o;
    vinsn_result_written_d[masku_result_id]  |= masku_result_gnt;
    vinsn_result_written_d[sldu_result_id]   |= sldu_result_gnt;

    // Per-segment load pacing: each individual segment grant fires vinsn_result_written.
    // This avoids deadlock where HP operand reads starve LP load writes —
    // if one segment is granted, the dependent compute can make progress immediately.
    for (int w = 0; w < NrVRFWordsPerBeat; w++)
      vinsn_result_written_d[ldu_result_id[w]] |= ldu_result_gnt[w];

    // Reset write counters when a load instruction completes or on exception flush
    if (load_complete_i || lsu_ex_flush_i) begin
      for (int w = 0; w < NrVRFWordsPerBeat; w++)
        ldu_queue_wr_cnt_d[w] = '0;
    end

    // VLDU: compute the fine-grained set mask from queue grants
    for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
      if (ldu_result_gnt[w]) begin
        ldu_queue_set_mask[ldu_queue_wr_cnt_d[w] * NrVRFWordsPerBeat + w] = 1'b1;
        ldu_queue_wr_cnt_d[w] = ldu_queue_wr_cnt_d[w] + 1;
        ldu_active_id_d = ldu_result_id[w];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_vinsn_result_written_ff
    if (!rst_ni) begin
      vinsn_result_written_q <= '0;
      ldu_active_id_q        <= '0;
      for (int w = 0; w < NrVRFWordsPerBeat; w++)
        ldu_queue_wr_cnt_q[w] <= '0;
      lsu_ex_flush_o         <= 1'b0;
    end else begin
      vinsn_result_written_q <= vinsn_result_written_d;
      ldu_active_id_q        <= ldu_active_id_d;
      for (int w = 0; w < NrVRFWordsPerBeat; w++)
        ldu_queue_wr_cnt_q[w] <= ldu_queue_wr_cnt_d[w];
      lsu_ex_flush_o         <= lsu_ex_flush_i;
    end
  end

  ///////////////////////
  //  Operand request  //
  ///////////////////////

  // There is an operand requester_index for each operand queue. Each one
  // can be in one of the following two states.
  typedef enum logic {
    IDLE,
    REQUESTING
  } state_t;

  // A set bit indicates that the the master q is requesting access to the bank b
  // Masters 0 to NrOperandQueues-1 correspond to the operand queues.
  // The remaining masters correspond to the ALU, the MFPU, the SLDU, the MASKU,
  // and NrVRFWordsPerBeat independent load-unit result queues.
  localparam int unsigned NrGlobalMasters = 4 + NrVRFWordsPerBeat;
  localparam int unsigned NrMasters = NrOperandQueues + NrGlobalMasters;

  typedef struct packed {
    vaddr_t addr;
    logic wen;
    elen_t wdata;
    strb_t be;
    opqueue_e opqueue;
  } payload_t;

  logic     [NrBanks-1:0][NrOperandQueues-1:0] lane_operand_req;
  logic     [NrOperandQueues-1:0][NrBanks-1:0] lane_operand_req_transposed;
  logic     [NrBanks-1:0][NrGlobalMasters-1:0] ext_operand_req;
  logic     [NrBanks-1:0][NrMasters-1:0] operand_gnt;
  payload_t [NrMasters-1:0]              operand_payload;

  // Metadata required to request all elements of this vector operand
  typedef struct packed {
    // ID of the instruction for this requester_index
    vid_t id;
    // Address of the next element to be read
    vaddr_t addr;
    // How many elements remain to be read
    vlen_t len;
    // Element width
    vew_e vew;

    // Hazards between vector instructions
    logic [NrVInsn-1:0] hazard;

    // Widening instructions produces two writes of every read
    // In case of a WAW with a previous instruction,
    // read once every two writes of the previous instruction
    logic is_widening;
    // One-bit counters
    logic [NrVInsn-1:0] waw_hazard_counter;
  } requester_metadata_t;

  for (genvar b = 0; b < NrBanks; b++) begin
    for (genvar r = 0; r < NrOperandQueues; r++) begin
      assign lane_operand_req[b][r] = lane_operand_req_transposed[r][b];
    end
  end

  for (genvar requester_index = 0; requester_index < NrOperandQueues; requester_index++) begin : gen_operand_requester
    // StA_0..StA_{NrVRFWordsPerBeat-1} are driven by the shared block below.
    if (requester_index < int'(StA_0) || requester_index >= int'(StA_0) + NrVRFWordsPerBeat) begin : gen_independent
    // State of this operand requester_index
    state_t state_d, state_q;

    requester_metadata_t requester_metadata_d, requester_metadata_q;

    // Per-requester element-level tracking register and read pointer
    logic [NrLduTrackBits-1:0]          ldu_elem_written_d, ldu_elem_written_q;
    logic [$clog2(NrLduTrackBits)-1:0]  ldu_rd_pnt_d, ldu_rd_pnt_q;

    // Augment vinsn_result_written with per-element load tracking.
    // Element tracking provides finer granularity for the active load BETWEEN
    // coarse per-segment pulses. When the coarse mechanism fires for the active
    // load, it already handles pacing — element tracking is not applied to avoid
    // double-advancing.
    logic [NrVInsn-1:0] effective_result_written;
    always_comb begin
      effective_result_written = vinsn_result_written_q;
      if (!vinsn_result_written_q[ldu_active_id_q])
        effective_result_written[ldu_active_id_q] =
          effective_result_written[ldu_active_id_q] | ldu_elem_written_q[ldu_rd_pnt_q];
    end

    // Is there a hazard during this cycle?
    logic stall;
    assign stall = |(requester_metadata_q.hazard & ~(effective_result_written &
                   (~{NrVInsn{requester_metadata_q.is_widening}} | requester_metadata_q.waw_hazard_counter)));

    // Did we get a grant?
    logic [NrBanks-1:0] operand_requester_gnt;
    for (genvar bank = 0; bank < NrBanks; bank++) begin: gen_operand_requester_gnt
      assign operand_requester_gnt[bank] = operand_gnt[bank][requester_index];
    end

    // Did we issue a word to this operand queue?
    assign operand_issued_o[requester_index] = |(operand_requester_gnt);

    always_comb begin: operand_requester
      // Helper local variables
      automatic operand_queue_cmd_t  operand_queue_cmd_tmp;
      automatic requester_metadata_t requester_metadata_tmp;
      automatic vlen_t               effective_vector_body_length;
      automatic vaddr_t              vrf_addr;

      automatic elen_t vl_byte;
      automatic elen_t vstart_byte;
      automatic elen_t vector_body_len_byte;
      automatic elen_t scaled_vector_len_elements;

      // Bank we are currently requesting
      automatic int bank = requester_metadata_q.addr[idx_width(NrBanks)-1:0];

      // Maintain state
      state_d     = state_q;
      requester_metadata_d = requester_metadata_q;

      // Per-requester element tracking: apply set mask from VLDU writes
      ldu_elem_written_d = ldu_elem_written_q | ldu_queue_set_mask;
      ldu_rd_pnt_d       = ldu_rd_pnt_q;

      // Reset element tracking when load completes
      if (load_complete_i) begin
        ldu_elem_written_d = ldu_queue_set_mask;
        ldu_rd_pnt_d       = '0;
      end

      // Make no requests to the VRF
      operand_payload[requester_index] = '0;
      for (int b = 0; b < NrBanks; b++) lane_operand_req_transposed[requester_index][b] = 1'b0;

      // Do not acknowledge any operand requester_index commands
      operand_request_ready_o[requester_index] = 1'b0;

      // Do not send any operand conversion commands
      operand_queue_cmd_o[requester_index]       = '0;
      operand_queue_cmd_valid_o[requester_index] = 1'b0;

      // Count the number of packets to fetch if we need to deshuffle.
      // Slide operations use the vstart signal, which does NOT correspond to the architectural
      // vstart, only when computing the fetch address. Ara supports architectural vstart > 0
      // only for memory operations.
      vl_byte     = operand_request_i[requester_index].vl     << operand_request_i[requester_index].vtype.vsew;
      vstart_byte = operand_request_i[requester_index].is_slide
                  ? 0
                  : operand_request_i[requester_index].vstart << operand_request_i[requester_index].vtype.vsew;
      vector_body_len_byte = vl_byte - vstart_byte + (vstart_byte % 8);
      scaled_vector_len_elements = vector_body_len_byte >> operand_request_i[requester_index].eew;
      if (scaled_vector_len_elements << operand_request_i[requester_index].eew < vector_body_len_byte)
        scaled_vector_len_elements += 1;

      // Final computed length
      effective_vector_body_length = (operand_request_i[requester_index].scale_vl)
                                   ? scaled_vector_len_elements
                                   : operand_request_i[requester_index].vl;

      // Address of the vstart element of the vector in the VRF
      // This vstart is NOT the architectural one and was modified in the lane
      // sequencer to provide the correct start address
      vrf_addr = vaddr(operand_request_i[requester_index].vs, NrLanes, VLEN)
               + (operand_request_i[requester_index].vstart >>
                   (unsigned'(EW64) - unsigned'(operand_request_i[requester_index].eew)));
      // Init helper variables
      requester_metadata_tmp = '{
        id          : operand_request_i[requester_index].id,
        addr        : vrf_addr,
        len         : effective_vector_body_length,
        vew         : operand_request_i[requester_index].eew,
        hazard      : operand_request_i[requester_index].hazard,
        is_widening : operand_request_i[requester_index].cvt_resize == CVT_WIDE,
        default: '0
      };
      operand_queue_cmd_tmp = '{
        eew       : operand_request_i[requester_index].eew,
        elem_count: effective_vector_body_length,
        conv      : operand_request_i[requester_index].conv,
        ntr_red   : operand_request_i[requester_index].cvt_resize,
        target_fu : operand_request_i[requester_index].target_fu,
        is_reduct : operand_request_i[requester_index].is_reduct
      };

      case (state_q)
        IDLE: begin : state_q_IDLE
          // Accept a new instruction
          if (operand_request_valid_i[requester_index]) begin : op_req_valid
            state_d                            = REQUESTING;
            // Acknowledge the request
            operand_request_ready_o[requester_index] = 1'b1;

            // Reset element tracking for the new instruction
            ldu_elem_written_d = ldu_queue_set_mask;
            ldu_rd_pnt_d       = '0;

            // Send a command to the operand queue
            operand_queue_cmd_o[requester_index] = operand_queue_cmd_tmp;
            operand_queue_cmd_valid_o[requester_index] = 1'b1;

            // The length should be at least one after the rescaling
            if (operand_queue_cmd_o[requester_index].elem_count == '0) begin : cmd_zero_rescaled_vl
              operand_queue_cmd_o[requester_index].elem_count = 1;
            end : cmd_zero_rescaled_vl

            // Store the request
            requester_metadata_d = requester_metadata_tmp;

            // The length should be at least one after the rescaling
            if (requester_metadata_d.len == '0) begin : req_zero_rescaled_vl
              requester_metadata_d.len = 1;
            end : req_zero_rescaled_vl


            // Mute the requisition if the vl is zero
            if (operand_request_i[requester_index].vl == '0) begin : zero_vl
              state_d                              = IDLE;
              operand_queue_cmd_valid_o[requester_index] = 1'b0;
            end : zero_vl
          end : op_req_valid
        end : state_q_IDLE

        REQUESTING: begin
          // Update waw counters
          for (int b = 0; b < NrVInsn; b++) begin : waw_counters_update
            if ( vinsn_result_written_d[b] ) begin : result_valid
              requester_metadata_d.waw_hazard_counter[b] = ~requester_metadata_q.waw_hazard_counter[b];
            end : result_valid
          end : waw_counters_update

          if (operand_queue_ready_i[requester_index]) begin
            automatic vlen_t num_elements;

            // Operand request
            lane_operand_req_transposed[requester_index][bank] = !stall;
            operand_payload[requester_index]   = '{
              addr   : requester_metadata_q.addr >> $clog2(NrBanks),
              opqueue: opqueue_e'(requester_index),
              default: '0 // this is a read operation
            };

            // Received a grant.
            if (|operand_requester_gnt) begin : op_req_grant
              // Bump the address pointer
              requester_metadata_d.addr = requester_metadata_q.addr + 1'b1;

              // We read less than 64 bits worth of elements
              num_elements = ( 1 << ( unsigned'(EW64) - unsigned'(requester_metadata_q.vew) ) );
              if (requester_metadata_q.len < num_elements) begin
                requester_metadata_d.len    = 0;
              end
              else begin
                requester_metadata_d.len = requester_metadata_q.len - num_elements;
              end

              // Advance element tracking pointer when element tracking was the
              // sole enabler (coarse didn't fire for the active load this cycle).
              if (requester_metadata_q.hazard[ldu_active_id_q] &&
                  !vinsn_result_written_q[ldu_active_id_q]) begin
                ldu_elem_written_d[ldu_rd_pnt_q] = 1'b0;
                ldu_rd_pnt_d = ldu_rd_pnt_q + 1;
              end
            end : op_req_grant

            // Finished requesting all the elements
            if (requester_metadata_d.len == '0) begin
              state_d = IDLE;

              // Accept a new instruction
              if (operand_request_valid_i[requester_index]) begin
                state_d                            = REQUESTING;
                // Acknowledge the request
                operand_request_ready_o[requester_index] = 1'b1;

                // Reset element tracking for the new instruction
                ldu_elem_written_d = ldu_queue_set_mask;
                ldu_rd_pnt_d       = '0;

                // Send a command to the operand queue
                operand_queue_cmd_o[requester_index] = operand_queue_cmd_tmp;
                operand_queue_cmd_valid_o[requester_index] = 1'b1;

                // The length should be at least one after the rescaling
                if (operand_queue_cmd_o[requester_index].elem_count == '0) begin : cmd_zero_rescaled_vl
                  operand_queue_cmd_o[requester_index].elem_count = 1;
                end : cmd_zero_rescaled_vl

                // Store the request
                requester_metadata_d = requester_metadata_tmp;

                // The length should be at least one after the rescaling
                if (requester_metadata_d.len == '0) begin : req_zero_rescaled_vl
                  requester_metadata_d.len = 1;
                end : req_zero_rescaled_vl

                // Mute the requisition if the vl is zero
                if (operand_request_i[requester_index].vl == '0) begin
                  state_d                              = IDLE;
                  operand_queue_cmd_valid_o[requester_index] = 1'b0;
                end
              end
            end
          end
        end
      endcase
      // Always keep the hazard bits up to date with the global hazard table
      requester_metadata_d.hazard &= global_hazard_table_i[requester_metadata_d.id];

      // Kill all store-unit, idx, and mem-masked requests in case of exceptions
      if (lsu_ex_flush_o && (requester_index == SlideAddrGenA || requester_index == MaskM)) begin : vlsu_exception_idle
        // Reset state
        state_d = IDLE;
        // Don't wake up the store queue (redundant, as it will be flushed anyway)
        operand_queue_cmd_valid_o[requester_index] = 1'b0;
        // Clear metadata
        requester_metadata_d = '0;
        // Flush this request
        lane_operand_req_transposed[requester_index][bank] = '0;
        // Reset element tracking
        ldu_elem_written_d = '0;
        ldu_rd_pnt_d       = '0;
      end : vlsu_exception_idle
    end : operand_requester

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        state_q              <= IDLE;
        requester_metadata_q <= '0;
        ldu_elem_written_q   <= '0;
        ldu_rd_pnt_q         <= '0;
      end else begin
        state_q              <= state_d;
        requester_metadata_q <= requester_metadata_d;
        ldu_elem_written_q   <= ldu_elem_written_d;
        ldu_rd_pnt_q         <= ldu_rd_pnt_d;
      end
    end
    end : gen_independent
  end : gen_operand_requester

  // Continuous assignment for StA operand_issued_o (must not mix assign/procedural)
  for (genvar w = 0; w < NrVRFWordsPerBeat; w++) begin : gen_sta_issued
    logic [NrBanks-1:0] sta_requester_gnt;
    for (genvar b = 0; b < NrBanks; b++) begin : gen_sta_gnt
      assign sta_requester_gnt[b] = operand_gnt[b][int'(StA_0)+w];
    end
    assign operand_issued_o[int'(StA_0)+w] = |sta_requester_gnt;
  end

  ///////////////////////////////
  //  Shared StA state machine  //
  ///////////////////////////////
  //
  // One shared address counter distributes per-lane VRF elements to all
  // NrVRFWordsPerBeat StA queues in parallel. Each batch, StA_w reads from
  // VRF address (base+w); the counter then advances by NrVRFWordsPerBeat.
  // Consecutive per-lane elements live in consecutive banks, so all
  // NrVRFWordsPerBeat reads can be granted simultaneously by independent
  // bank arbiters. A per-queue grant flag handles the rare case where an
  // HP write preempts one bank: the affected queue is retried the next cycle
  // while the already-granted queues do not re-request.

  typedef struct packed {
    vid_t   id;
    vaddr_t addr;    // base VRF address of the current batch
    vlen_t  len;     // remaining batches = ceil(vl / NrVRFWordsPerBeat)
    vew_e   vew;
    logic [NrVInsn-1:0] hazard;
  } sta_meta_t;

  state_t    sta_state_d, sta_state_q;
  sta_meta_t sta_meta_d,  sta_meta_q;
  // Tracks which StA queues have received their data in the current batch
  logic [NrVRFWordsPerBeat-1:0] sta_batch_granted_d, sta_batch_granted_q;

  // Stall when a hazardous instruction has not yet committed enough results.
  // The StA reads NrVRFWordsPerBeat words per batch, so we must wait until
  // the hazardous instruction has written NrVRFWordsPerBeat words before
  // releasing. We reuse the same pacing signal (vinsn_result_written_q) that
  // independent operand requesters use, but count NrVRFWordsPerBeat pulses.
  logic sta_stall;
  logic [$clog2(NrVRFWordsPerBeat):0] sta_wr_cnt_d, sta_wr_cnt_q;

  always_comb begin
    sta_wr_cnt_d = sta_wr_cnt_q;

    // Count pacing pulses from hazardous instructions
    if (|(sta_meta_q.hazard & vinsn_result_written_q))
      sta_wr_cnt_d = sta_wr_cnt_q + 1;

    // Reset when no hazard (instruction completed)
    if (!(|(sta_meta_q.hazard)))
      sta_wr_cnt_d = '0;

    // Stall until NrVRFWordsPerBeat writes have been observed for this batch
    sta_stall = (|(sta_meta_q.hazard)) && (sta_wr_cnt_d < NrVRFWordsPerBeat);

    // When threshold reached, consume NrVRFWordsPerBeat for the next batch
    if (sta_wr_cnt_d >= NrVRFWordsPerBeat)
      sta_wr_cnt_d = sta_wr_cnt_d - NrVRFWordsPerBeat;
  end

  always_comb begin : sta_shared_operand_requester
    automatic vaddr_t vrf_addr_base;
    automatic vlen_t  per_queue_len;


    // Defaults
    sta_state_d         = sta_state_q;
    sta_meta_d          = sta_meta_q;
    sta_batch_granted_d = sta_batch_granted_q;

    for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
      operand_payload[int'(StA_0)+w]           = '0;
      for (int b = 0; b < NrBanks; b++)
        lane_operand_req_transposed[int'(StA_0)+w][b] = 1'b0;
      operand_request_ready_o[int'(StA_0)+w]   = 1'b0;
      operand_queue_cmd_o[int'(StA_0)+w]        = '0;
      operand_queue_cmd_valid_o[int'(StA_0)+w]  = 1'b0;
    end

    // Helper: VRF base address for the incoming request
    vrf_addr_base = vaddr(operand_request_i[StA_0].vs, NrLanes, VLEN)
                  + (operand_request_i[StA_0].vstart >>
                     (unsigned'(EW64) - unsigned'(operand_request_i[StA_0].eew)));
    // Per-queue element count: ceil(vl / NrVRFWordsPerBeat), minimum 1
    per_queue_len = (operand_request_i[StA_0].vl + NrVRFWordsPerBeat - 1)
                    / NrVRFWordsPerBeat;
    if (per_queue_len == '0) per_queue_len = 1;

    case (sta_state_q)
      IDLE: begin : sta_idle
        if (operand_request_valid_i[StA_0]) begin : sta_accept_new
          // Acknowledge all NrVRFWordsPerBeat StA requests simultaneously
          for (int w = 0; w < NrVRFWordsPerBeat; w++)
            operand_request_ready_o[int'(StA_0)+w] = 1'b1;
          // Send identical command to every StA queue
          for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
            operand_queue_cmd_o[int'(StA_0)+w] = '{
              eew       : operand_request_i[StA_0].eew,
              elem_count: per_queue_len,
              conv      : operand_request_i[StA_0].conv,
              ntr_red   : operand_request_i[StA_0].cvt_resize,
              target_fu : operand_request_i[StA_0].target_fu,
              is_reduct : operand_request_i[StA_0].is_reduct
            };
            operand_queue_cmd_valid_o[int'(StA_0)+w] = 1'b1;
          end
          sta_meta_d = '{
            id    : operand_request_i[StA_0].id,
            addr  : vrf_addr_base,
            len   : per_queue_len,
            vew   : operand_request_i[StA_0].eew,
            hazard: operand_request_i[StA_0].hazard
          };
          sta_state_d         = REQUESTING;
          sta_batch_granted_d = '0;
          // Nothing to fetch when vl == 0
          if (operand_request_i[StA_0].vl == '0) begin
            sta_state_d = IDLE;
            for (int w = 0; w < NrVRFWordsPerBeat; w++)
              operand_queue_cmd_valid_o[int'(StA_0)+w] = 1'b0;
          end
        end : sta_accept_new
      end : sta_idle

      REQUESTING: begin : sta_requesting
        automatic logic sta_queues_rdy;
        sta_queues_rdy = 1'b1;
        for (int w = 0; w < NrVRFWordsPerBeat; w++)
          sta_queues_rdy &= operand_queue_ready_i[int'(StA_0)+w];

        if (sta_queues_rdy) begin : sta_queues_ready
          // Issue read to each StA_w that hasn't received its data this batch
          for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
            if (!sta_batch_granted_q[w]) begin
              automatic vaddr_t addr_w;
              automatic int     bank_w;
              addr_w = sta_meta_q.addr + vaddr_t'(w);
              bank_w = int'(addr_w[idx_width(NrBanks)-1:0]);
              lane_operand_req_transposed[int'(StA_0)+w][bank_w] = !sta_stall;
              operand_payload[int'(StA_0)+w] = '{
                addr   : addr_w >> $clog2(NrBanks),
                opqueue: opqueue_e'(int'(StA_0) + w),
                default: '0
              };
            end
          end

          // Accumulate grants across cycles within the current batch
          for (int w = 0; w < NrVRFWordsPerBeat; w++)
            for (int b = 0; b < NrBanks; b++)
              if (operand_gnt[b][int'(StA_0)+w])
                sta_batch_granted_d[w] = 1'b1;

          // When all queues have their data, advance to the next batch
          if (&sta_batch_granted_d) begin : sta_batch_complete
            sta_meta_d.addr     = sta_meta_q.addr + vaddr_t'(NrVRFWordsPerBeat);
            sta_meta_d.len      = sta_meta_q.len - 1;
            sta_batch_granted_d = '0;

            if (sta_meta_d.len == '0) begin : sta_insn_done
              sta_state_d = IDLE;
              // Immediately accept the next instruction if already waiting
              if (operand_request_valid_i[StA_0]) begin : sta_accept_next
                for (int w = 0; w < NrVRFWordsPerBeat; w++)
                  operand_request_ready_o[int'(StA_0)+w] = 1'b1;
                for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
                  operand_queue_cmd_o[int'(StA_0)+w] = '{
                    eew       : operand_request_i[StA_0].eew,
                    elem_count: per_queue_len,
                    conv      : operand_request_i[StA_0].conv,
                    ntr_red   : operand_request_i[StA_0].cvt_resize,
                    target_fu : operand_request_i[StA_0].target_fu,
                    is_reduct : operand_request_i[StA_0].is_reduct
                  };
                  operand_queue_cmd_valid_o[int'(StA_0)+w] = 1'b1;
                end
                sta_meta_d = '{
                  id    : operand_request_i[StA_0].id,
                  addr  : vrf_addr_base,
                  len   : per_queue_len,
                  vew   : operand_request_i[StA_0].eew,
                  hazard: operand_request_i[StA_0].hazard
                };
                sta_state_d = REQUESTING;
                if (operand_request_i[StA_0].vl == '0) begin
                  sta_state_d = IDLE;
                  for (int w = 0; w < NrVRFWordsPerBeat; w++)
                    operand_queue_cmd_valid_o[int'(StA_0)+w] = 1'b0;
                end
              end : sta_accept_next
            end : sta_insn_done
          end : sta_batch_complete
        end : sta_queues_ready
      end : sta_requesting
    endcase

    // Keep hazard bits current with the global hazard table
    sta_meta_d.hazard &= global_hazard_table_i[sta_meta_d.id];

    // Kill StA requests on LSU exceptions (flush handled by operand_queues_stage)
    if (lsu_ex_flush_o) begin : sta_exception_flush
      sta_state_d         = IDLE;
      sta_meta_d          = '0;
      sta_batch_granted_d = '0;
      for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
        operand_queue_cmd_valid_o[int'(StA_0)+w] = 1'b0;
        for (int b = 0; b < NrBanks; b++)
          lane_operand_req_transposed[int'(StA_0)+w][b] = 1'b0;
      end
    end : sta_exception_flush
  end : sta_shared_operand_requester

  always_ff @(posedge clk_i or negedge rst_ni) begin : sta_shared_ff
    if (!rst_ni) begin
      sta_state_q         <= IDLE;
      sta_meta_q          <= '0;
      sta_batch_granted_q <= '0;
      sta_wr_cnt_q        <= '0;
    end else begin
      sta_state_q         <= sta_state_d;
      sta_meta_q          <= sta_meta_d;
      sta_batch_granted_q <= sta_batch_granted_d;
      sta_wr_cnt_q        <= sta_wr_cnt_d;
    end
  end : sta_shared_ff

  ////////////////
  //  Arbiters  //
  ////////////////

  // Remember whether the VFUs are trying to write something to the VRF
  always_comb begin
    // Default assignment
    for (int bank = 0; bank < NrBanks; bank++) begin
      ext_operand_req[bank][VFU_Alu]       = 1'b0;
      ext_operand_req[bank][VFU_MFpu]      = 1'b0;
      ext_operand_req[bank][VFU_MaskUnit]  = 1'b0;
      ext_operand_req[bank][VFU_SlideUnit] = 1'b0;
      for (int w = 0; w < NrVRFWordsPerBeat; w++)
        ext_operand_req[bank][int'(VFU_LoadUnit) + w] = 1'b0;
    end

    // Generate the payloads for write back operations
    operand_payload[NrOperandQueues + VFU_Alu] = '{
      addr   : alu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : alu_result_wdata_i,
      be     : alu_result_be_i,
      opqueue: AluA,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MFpu] = '{
      addr   : mfpu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : mfpu_result_wdata_i,
      be     : mfpu_result_be_i,
      opqueue: AluA,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MaskUnit] = '{
      addr   : masku_result_addr >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : masku_result_wdata,
      be     : masku_result_be,
      opqueue: AluA,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_SlideUnit] = '{
      addr   : sldu_result_addr >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : sldu_result_wdata,
      be     : sldu_result_be,
      opqueue: AluA,
      default: '0
    };
    // NrVRFWordsPerBeat independent load-unit result queues.
    // Each occupies slot VFU_LoadUnit+w in the global masters array.
    for (int w = 0; w < NrVRFWordsPerBeat; w++) begin
      operand_payload[NrOperandQueues + int'(VFU_LoadUnit) + w] = '{
        addr   : ldu_result_addr[w] >> $clog2(NrBanks),
        wen    : 1'b1,
        wdata  : ldu_result_wdata[w],
        be     : ldu_result_be[w],
        opqueue: AluA,
        default: '0
      };
    end

    // Store their request value
    ext_operand_req[alu_result_addr_i[idx_width(NrBanks)-1:0]][VFU_Alu] =
    alu_result_req_i;
    ext_operand_req[mfpu_result_addr_i[idx_width(NrBanks)-1:0]][VFU_MFpu] =
    mfpu_result_req_i;
    ext_operand_req[masku_result_addr[idx_width(NrBanks)-1:0]][VFU_MaskUnit] =
    masku_result_req;
    ext_operand_req[sldu_result_addr[idx_width(NrBanks)-1:0]][VFU_SlideUnit] =
    sldu_result_req;
    for (int w = 0; w < NrVRFWordsPerBeat; w++)
      ext_operand_req[ldu_result_addr[w][idx_width(NrBanks)-1:0]][int'(VFU_LoadUnit) + w] =
      ldu_result_req[w];

    // Generate the grant signals
    alu_result_gnt_o  = 1'b0;
    mfpu_result_gnt_o = 1'b0;
    masku_result_gnt  = 1'b0;
    sldu_result_gnt   = 1'b0;
    ldu_result_gnt    = '0;
    for (int bank = 0; bank < NrBanks; bank++) begin
      alu_result_gnt_o  = alu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_Alu];
      mfpu_result_gnt_o = mfpu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_MFpu];
      masku_result_gnt  = masku_result_gnt | operand_gnt[bank][NrOperandQueues + VFU_MaskUnit];
      sldu_result_gnt   = sldu_result_gnt | operand_gnt[bank][NrOperandQueues + VFU_SlideUnit];
      for (int w = 0; w < NrVRFWordsPerBeat; w++)
        ldu_result_gnt[w] = ldu_result_gnt[w] |
          operand_gnt[bank][NrOperandQueues + int'(VFU_LoadUnit) + w];
    end
    // Note: individual segment grants are allowed — the stream registers advance
    // independently. Each segment grant immediately fires vinsn_result_written
    // (per-segment pacing) to avoid deadlock from HP/LP arbiter starvation.
    // Per-requester 16-bit element tracking registers provide additional
    // fine-grained load-compute chaining on top of this.
  end

  // Instantiate a RR arbiter per bank
  for (genvar bank = 0; bank < NrBanks; bank++) begin: gen_vrf_arbiters
    // High-priority requests
    payload_t payload_hp;
    logic payload_hp_req;
    logic payload_hp_gnt;
    rr_arb_tree #(
      .NumIn    (unsigned'(MulFPUC) - unsigned'(AluA) + 1 + unsigned'(VFU_MFpu) - unsigned'(VFU_Alu) + 1),
      .DataWidth($bits(payload_t)                                                   ),
      .AxiVldRdy(1'b0                                                               )
    ) i_hp_vrf_arbiter (
      .clk_i  (clk_i ),
      .rst_ni (rst_ni),
      .flush_i(1'b0  ),
      .rr_i   ('0    ),
      .data_i ({operand_payload[MulFPUC:AluA],
          operand_payload[NrOperandQueues + VFU_MFpu:NrOperandQueues + VFU_Alu]} ),
      .req_i ({lane_operand_req[bank][MulFPUC:AluA],
          ext_operand_req[bank][VFU_MFpu:VFU_Alu]}),
      .gnt_o ({operand_gnt[bank][MulFPUC:AluA],
          operand_gnt[bank][NrOperandQueues + VFU_MFpu:NrOperandQueues + VFU_Alu]}),
      .data_o (payload_hp    ),
      .idx_o  (/* Unused */  ),
      .req_o  (payload_hp_req),
      .gnt_i  (payload_hp_gnt)
    );

    // Low-priority requests
    payload_t payload_lp;
    logic payload_lp_req;
    logic payload_lp_gnt;
    rr_arb_tree #(
      .NumIn(unsigned'(SlideAddrGenA) - unsigned'(MaskB) + 1 +
             unsigned'(VFU_LoadUnit) + NrVRFWordsPerBeat - unsigned'(VFU_SlideUnit)),
      .DataWidth($bits(payload_t)),
      .AxiVldRdy(1'b0            )
    ) i_lp_vrf_arbiter (
      .clk_i  (clk_i ),
      .rst_ni (rst_ni),
      .flush_i(1'b0  ),
      .rr_i   ('0    ),
      .data_i ({operand_payload[SlideAddrGenA:MaskB],
          operand_payload[NrOperandQueues + int'(VFU_LoadUnit) + NrVRFWordsPerBeat - 1:
                          NrOperandQueues + int'(VFU_SlideUnit)]} ),
      .req_i ({lane_operand_req[bank][SlideAddrGenA:MaskB],
          ext_operand_req[bank][int'(VFU_LoadUnit) + NrVRFWordsPerBeat - 1:int'(VFU_SlideUnit)]}),
      .gnt_o ({operand_gnt[bank][SlideAddrGenA:MaskB],
          operand_gnt[bank][NrOperandQueues + int'(VFU_LoadUnit) + NrVRFWordsPerBeat - 1:
                            NrOperandQueues + int'(VFU_SlideUnit)]}),
      .data_o (payload_lp    ),
      .idx_o  (/* Unused */  ),
      .req_o  (payload_lp_req),
      .gnt_i  (payload_lp_gnt)
    );

    // High-priority requests always mask low-priority requests
    rr_arb_tree #(
      .NumIn    (2               ),
      .DataWidth($bits(payload_t)),
      .AxiVldRdy(1'b0            ),
      .ExtPrio  (1'b1            )
    ) i_vrf_arbiter (
      .clk_i  (clk_i                            ),
      .rst_ni (rst_ni                           ),
      .flush_i(1'b0                             ),
      .rr_i   (1'b0                             ),
      .data_i ({payload_lp, payload_hp}         ),
      .req_i  ({payload_lp_req, payload_hp_req} ),
      .gnt_o  ({payload_lp_gnt, payload_hp_gnt} ),
      .data_o ({vrf_addr_o[bank], vrf_wen_o[bank], vrf_wdata_o[bank], vrf_be_o[bank],
          vrf_tgt_opqueue_o[bank]}),
      .idx_o (/* Unused */    ),
      .req_o (vrf_req_o[bank] ),
      .gnt_i (vrf_req_o[bank] ) // Acknowledge it directly
    );
  end : gen_vrf_arbiters

endmodule : operand_requester
