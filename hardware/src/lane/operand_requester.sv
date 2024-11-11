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
    parameter  type          vaddr_t               = logic, // Type used to address vector register file elements
    parameter  type          operand_request_cmd_t = logic,
    parameter  type          operand_queue_cmd_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
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
    // Load unit
    input  logic                                       ldu_result_req_i,
    input  vid_t                                       ldu_result_id_i,
    input  vaddr_t                                     ldu_result_addr_i,
    input  elen_t                                      ldu_result_wdata_i,
    input  strb_t                                      ldu_result_be_i,
    output logic                                       ldu_result_gnt_o,
    output logic                                       ldu_result_final_gnt_o,
    // Store Unit
    input  logic                                       stu_exception_i
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

  // Load unit
  vid_t   ldu_result_id;
  vaddr_t ldu_result_addr;
  elen_t  ldu_result_wdata;
  strb_t  ldu_result_be;
  logic   ldu_result_req;
  logic   ldu_result_gnt;
  stream_register #(.T(stream_register_payload_t)) i_ldu_stream_register (
    .clk_i     (clk_i                                                                    ),
    .rst_ni    (rst_ni                                                                   ),
    .clr_i     (1'b0                                                                     ),
    .testmode_i(1'b0                                                                     ),
    .data_i    ({ldu_result_id_i, ldu_result_addr_i, ldu_result_wdata_i, ldu_result_be_i}),
    .valid_i   (ldu_result_req_i                                                         ),
    .ready_o   (ldu_result_gnt_o                                                         ),
    .data_o    ({ldu_result_id, ldu_result_addr, ldu_result_wdata, ldu_result_be}        ),
    .valid_o   (ldu_result_req                                                           ),
    .ready_i   (ldu_result_gnt                                                           )
  );

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
      ldu_result_final_gnt_o   <= 1'b0;
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

  always_comb begin
    vinsn_result_written_d = '0;

    // Which vector instructions are writing something?
    vinsn_result_written_d[alu_result_id_i] |= alu_result_gnt_o;
    vinsn_result_written_d[mfpu_result_id_i] |= mfpu_result_gnt_o;
    vinsn_result_written_d[masku_result_id] |= masku_result_gnt;
    vinsn_result_written_d[ldu_result_id] |= ldu_result_gnt;
    vinsn_result_written_d[sldu_result_id] |= sldu_result_gnt;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_vinsn_result_written_ff
    if (!rst_ni) begin
      vinsn_result_written_q <= '0;
    end else begin
      vinsn_result_written_q <= vinsn_result_written_d;
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
  // The remaining four masters correspond to the ALU, the MFPU, the MASKU, the VLDU, and the SLDU.
  localparam NrGlobalMasters = 5;
  localparam NrMasters = NrOperandQueues + NrGlobalMasters;

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
    // State of this operand requester_index
    state_t state_d, state_q;

    requester_metadata_t requester_metadata_d, requester_metadata_q;

    // Is there a hazard during this cycle?
    logic stall;
    assign stall = |(requester_metadata_q.hazard & ~(vinsn_result_written_q &
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
      automatic vlen_t               vector_body_length;
      automatic vlen_t               effective_vector_body_length;
      automatic vaddr_t              vrf_addr;

      automatic elen_t vl_byte;
      automatic elen_t vstart_byte;
      automatic elen_t vector_body_len_byte;
      automatic elen_t vector_body_len_packets;

      // Bank we are currently requesting
      automatic int bank = requester_metadata_q.addr[idx_width(NrBanks)-1:0];

      // Maintain state
      state_d     = state_q;
      requester_metadata_d = requester_metadata_q;

      // Make no requests to the VRF
      operand_payload[requester_index] = '0;
      for (int b = 0; b < NrBanks; b++) lane_operand_req_transposed[requester_index][b] = 1'b0;

      // Do not acknowledge any operand requester_index commands
      operand_request_ready_o[requester_index] = 1'b0;

      // Do not send any operand conversion commands
      operand_queue_cmd_o[requester_index]       = '0;
      operand_queue_cmd_valid_o[requester_index] = 1'b0;

      // Prepare metadata upfront
      // Length of vector body in elements, i.e., vl - vstart
      vector_body_length = operand_request_i[requester_index].vl - operand_request_i[requester_index].vstart;

      // Count the number of packets to fetch if we need to deshuffle.
      // Slide operations use the vstart signal, which does NOT correspond to the architectural
      // vstart, only when computing the fetch address. Ara supports architectural vstart > 0
      // only for memory operations.
      vl_byte     = operand_request_i[requester_index].vl     << operand_request_i[requester_index].vtype.vsew;
      vstart_byte = operand_request_i[requester_index].is_slide
                  ? 0
                  : operand_request_i[requester_index].vstart << operand_request_i[requester_index].vtype.vsew;
      vector_body_len_byte = vl_byte - vstart_byte + (vstart_byte % 8);
      vector_body_len_packets = vector_body_len_byte >> operand_request_i[requester_index].eew;
      if (vector_body_len_packets << operand_request_i[requester_index].eew < vector_body_len_byte)
        vector_body_len_packets += 1;

      // Final computed length
      effective_vector_body_length = (operand_request_i[requester_index].scale_vl)
                                   ? vector_body_len_packets
                                   : vector_body_length;

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
            automatic vlen_t num_bytes;

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
              num_bytes = ( 1 << ( unsigned'(EW64) - unsigned'(requester_metadata_q.vew) ) );
              if (requester_metadata_q.len < num_bytes) begin
                requester_metadata_d.len    = 0;
              end
              else begin
                requester_metadata_d.len = requester_metadata_q.len - num_bytes;
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

      // Kill all store-unit requests in case of exceptions
      if (stu_exception_i && (requester_index == StA)) begin : vstu_exception_idle
        // Reset state
        state_d = IDLE;
        // Don't wake up the store queue (redundant, as it will be flushed anyway)
        operand_queue_cmd_valid_o[requester_index] = 1'b0;
        // Clear metadata
        requester_metadata_d = '0;
        // Flush this request
        lane_operand_req_transposed[requester_index][bank] = '0;
      end : vstu_exception_idle
    end : operand_requester

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        state_q     <= IDLE;
        requester_metadata_q <= '0;
      end else begin
        state_q     <= state_d;
        requester_metadata_q <= requester_metadata_d;
      end
    end
  end : gen_operand_requester

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
      ext_operand_req[bank][VFU_LoadUnit]  = 1'b0;
    end

    // Generate the payloads for write back operations
    operand_payload[NrOperandQueues + VFU_Alu] = '{
      addr   : alu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : alu_result_wdata_i,
      be     : alu_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MFpu] = '{
      addr   : mfpu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : mfpu_result_wdata_i,
      be     : mfpu_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MaskUnit] = '{
      addr   : masku_result_addr >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : masku_result_wdata,
      be     : masku_result_be,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_SlideUnit] = '{
      addr   : sldu_result_addr >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : sldu_result_wdata,
      be     : sldu_result_be,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_LoadUnit] = '{
      addr   : ldu_result_addr >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : ldu_result_wdata,
      be     : ldu_result_be,
      default: '0
    };

    // Store their request value
    ext_operand_req[alu_result_addr_i[idx_width(NrBanks)-1:0]][VFU_Alu] =
    alu_result_req_i;
    ext_operand_req[mfpu_result_addr_i[idx_width(NrBanks)-1:0]][VFU_MFpu] =
    mfpu_result_req_i;
    ext_operand_req[masku_result_addr[idx_width(NrBanks)-1:0]][VFU_MaskUnit] =
    masku_result_req;
    ext_operand_req[sldu_result_addr[idx_width(NrBanks)-1:0]][VFU_SlideUnit] =
    sldu_result_req;
    ext_operand_req[ldu_result_addr[idx_width(NrBanks)-1:0]][VFU_LoadUnit] =
    ldu_result_req;

    // Generate the grant signals
    alu_result_gnt_o  = 1'b0;
    mfpu_result_gnt_o = 1'b0;
    masku_result_gnt  = 1'b0;
    sldu_result_gnt   = 1'b0;
    ldu_result_gnt    = 1'b0;
    for (int bank = 0; bank < NrBanks; bank++) begin
      alu_result_gnt_o  = alu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_Alu];
      mfpu_result_gnt_o = mfpu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_MFpu];
      masku_result_gnt  = masku_result_gnt | operand_gnt[bank][NrOperandQueues + VFU_MaskUnit];
      sldu_result_gnt   = sldu_result_gnt | operand_gnt[bank][NrOperandQueues + VFU_SlideUnit];
      ldu_result_gnt    = ldu_result_gnt | operand_gnt[bank][NrOperandQueues + VFU_LoadUnit];
    end
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
      .NumIn(unsigned'(SlideAddrGenA)- unsigned'(MaskB) + 1 + unsigned'(VFU_LoadUnit) - unsigned'(VFU_SlideUnit) + 1),
      .DataWidth($bits(payload_t)                                                               ),
      .AxiVldRdy(1'b0                                                                           )
    ) i_lp_vrf_arbiter (
      .clk_i  (clk_i ),
      .rst_ni (rst_ni),
      .flush_i(1'b0  ),
      .rr_i   ('0    ),
      .data_i ({operand_payload[SlideAddrGenA:MaskB],
          operand_payload[NrOperandQueues + VFU_LoadUnit:NrOperandQueues + VFU_SlideUnit]} ),
      .req_i ({lane_operand_req[bank][SlideAddrGenA:MaskB],
          ext_operand_req[bank][VFU_LoadUnit:VFU_SlideUnit]}),
      .gnt_o ({operand_gnt[bank][SlideAddrGenA:MaskB],
          operand_gnt[bank][NrOperandQueues + VFU_LoadUnit:NrOperandQueues + VFU_SlideUnit]}),
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
