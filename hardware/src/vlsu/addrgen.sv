// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This unit generates transactions on the AR/AW buses, upon receiving vector
// memory operations.

module addrgen import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes      = 0,
    // AXI Interface parameters
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_aw_t     = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter type          axi_addr_t   = logic [AxiAddrWidth-1:0]
  ) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Memory interface
    output axi_ar_t                        axi_ar_o,
    output logic                           axi_ar_valid_o,
    input  logic                           axi_ar_ready_i,
    output axi_aw_t                        axi_aw_o,
    output logic                           axi_aw_valid_o,
    input  logic                           axi_aw_ready_i,
    // Interace with the dispatcher
    input  logic                           core_st_pending_i,
    // Interface with the main sequencer
    input  pe_req_t                        pe_req_i,
    input  logic                           pe_req_valid_i,
    output logic                           addrgen_error_o,
    output logic                           addrgen_ack_o,
    // Interface with the load/store units
    output addrgen_axi_req_t               axi_addrgen_req_o,
    output logic                           axi_addrgen_req_valid_o,
    input  logic                           ldu_axi_addrgen_req_ready_i,
    input  logic                           stu_axi_addrgen_req_ready_i,
    // Interface with the lanes (for scatter/gather operations)
    input  elen_t            [NrLanes-1:0] addrgen_operand_i,
    input  logic             [NrLanes-1:0] addrgen_operand_valid_i,
    output logic                           addrgen_operand_ready_o,
    output logic                           addrgen_operand_ack_o
  );

  import cf_math_pkg::ceil_div;
  import cf_math_pkg::idx_width;
  import axi_pkg::aligned_addr;
  import axi_pkg::BURST_INCR;
  import axi_pkg::CACHE_MODIFIABLE;

  /////////////////////
  //  Address Queue  //
  /////////////////////

  // Address queue for the vector load/store units
  addrgen_axi_req_t axi_addrgen_queue;
  logic             axi_addrgen_queue_push;
  logic             axi_addrgen_queue_full;
  logic             axi_addrgen_queue_empty;

  fifo_v3 #(
    .DEPTH(2                ),
    .dtype(addrgen_axi_req_t)
  ) i_addrgen_req_queue (
    .clk_i     (clk_i                                                    ),
    .rst_ni    (rst_ni                                                   ),
    .flush_i   (1'b0                                                     ),
    .testmode_i(1'b0                                                     ),
    .data_i    (axi_addrgen_queue                                        ),
    .push_i    (axi_addrgen_queue_push                                   ),
    .full_o    (axi_addrgen_queue_full                                   ),
    .data_o    (axi_addrgen_req_o                                        ),
    .pop_i     (ldu_axi_addrgen_req_ready_i | stu_axi_addrgen_req_ready_i),
    .empty_o   (axi_addrgen_queue_empty                                  ),
    .usage_o   (/* Unused */                                             )
  );
  assign axi_addrgen_req_valid_o = !axi_addrgen_queue_empty;

  //////////////////////////
  //  Address generation  //
  //////////////////////////

  // Running vector instructions
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // The Address Generator can be in one of the following three states.
  // IDLE: Waiting for a vector load/store instruction.
  // ADDRGEN: Generates a series of AXI requests from a vector instruction.
  // ADDRGEN_SCATTER_GATHER: Generates a series of AXI requests from a
  //    vector instruction, but reading a vector of offsets from Ara's lanes.
  //    This is used for scatter and gather operations.
  enum logic [1:0] {
    IDLE,
    ADDRGEN,
    ADDRGEN_SCATTER_GATHER
  } state_q, state_d;

  // The address generation process interacts with another process, that
  // generates the AXI requests. They interact through the following signals.
  typedef struct packed {
    axi_addr_t addr;
    vlen_t len;
    elen_t stride;
    vew_e vew;
    logic is_load;
    logic is_burst; // Unit-strided instructions can be converted into AXI INCR bursts
  } addrgen_req_t;
  addrgen_req_t addrgen_req;
  logic         addrgen_req_valid;
  logic         addrgen_req_ready;

  // Support for Scatther/Gather
  axi_addr_t idx_final_addr;
  logic [$bits(elen_t)*NrLanes-1:0] shuffled_word;
  logic [$bits(elen_t)*NrLanes-1:0] deshuffled_word;
  elen_t               reduced_word;
  elen_t               index_address;
  // Pointer to point to the correct
  logic [NrLanes-1:0] word_lane_ptr_d, word_lane_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] elm_ptr_d, elm_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] last_elm_subw_d, last_elm_subw_q;

  always_comb begin: addr_generation
    // Maintain state
    state_d = state_q;

    // Running vector instructions
    vinsn_running_d = vinsn_running_q & pe_req_i.vinsn_running;

    // No request, by default
    addrgen_req       = '0;
    addrgen_req_valid = 1'b0;

    // Nothing to acknowledge
    addrgen_ack_o           = 1'b0;
    addrgen_error_o         = 1'b0;

    case (state_q)
      IDLE: begin
        // Received a new request
        if (pe_req_valid_i &&
            (is_load(pe_req_i.op) || is_store(pe_req_i.op)) && !vinsn_running_q[pe_req_i.id]) begin
          // Mark the instruction as running in this unit
          vinsn_running_d[pe_req_i.id] = 1'b1;

          case (pe_req_i.op)
            VLXE, VSXE: state_d = ADDRGEN_SCATTER_GATHER;
            default: begin
              state_d = ADDRGEN;

              // Request early
              addrgen_req = '{
                addr    : pe_req_i.scalar_op,
                len     : pe_req_i.vl,
                stride  : pe_req_i.stride,
                vew     : pe_req_i.vtype.vsew,
                is_load : is_load(pe_req_i.op),
                // Unit-strided loads/stores trigger incremental AXI bursts.
                is_burst: (pe_req_i.op inside {VLE, VSE})
              };
              addrgen_req_valid = 1'b1;
            end
          endcase
        end
      end
      ADDRGEN: begin
        // Ara does not support misaligned AXI requests
        if (|(pe_req_i.scalar_op & (elen_t'(1 << pe_req_i.vtype.vsew) - 1))) begin
          state_d         = IDLE;
          addrgen_ack_o   = 1'b1;
          addrgen_error_o = 1'b1;
        end else begin
          addrgen_req = '{
            addr    : pe_req_i.scalar_op,
            len     : pe_req_i.vl,
            stride  : pe_req_i.stride,
            vew     : pe_req_i.vtype.vsew,
            is_load : is_load(pe_req_i.op),
            // Unit-strided loads/stores trigger incremental AXI bursts.
            is_burst: (pe_req_i.op inside {VLE, VSE})
          };
          addrgen_req_valid = 1'b1;

          if (addrgen_req_ready) begin
            addrgen_req_valid = '0;
            addrgen_ack_o     = 1'b1;
            state_d           = IDLE;
          end
        end
      end
      ADDRGEN_SCATTER_GATHER : begin
        // Stall the interface until the operation is over
        // Wait until we have a valid data
        // Make a single request
        if (|addrgen_operand_valid_i) begin
          addrgen_req = '{
            addr    : pe_req_i.scalar_op,
            len     : pe_req_i.vl,
            stride  : pe_req_i.stride,
            vew     : pe_req_i.vtype.vsew,
            is_load : is_load(pe_req_i.op),
            // Unit-strided loads/stores trigger incremental AXI bursts.
            is_burst: 1'b0
          };
          addrgen_req_valid = 1'b1;

          if (addrgen_req_ready) begin
            addrgen_req_valid = '0;
            addrgen_ack_o     = 1'b1;
            state_d           = IDLE;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= IDLE;
      vinsn_running_q <= '0;
      word_lane_ptr_q <= '0;
      elm_ptr_q       <= '0;
      last_elm_subw_q <= '0;
    end else begin
      state_q         <= state_d;
      vinsn_running_q <= vinsn_running_d;
      word_lane_ptr_q <= word_lane_ptr_d;
      elm_ptr_q       <= elm_ptr_d;
      last_elm_subw_q <= last_elm_subw_d;
    end
  end

  /////////////////////////////////////
  //  Support for misaligned stores  //
  /////////////////////////////////////

  // Narrower AXI Data Byte-Width used for misaligned stores
  logic [$clog2(AxiDataWidth/8)-1:0] narrow_axi_data_bwidth;
  // Helper signal to calculate the narrow_axi_data_bwidth
  // It carries information about the misalignment of the start address w.r.t. the AxiDataWidth
  logic [$clog2(AxiDataWidth/8)-1:0] axi_addr_misalignment;
  // Number of trailing 0s of axi_addr_misalignment
  localparam int unsigned LZC_OUT_WIDTH = cf_math_pkg::idx_width($clog2(AxiDataWidth/8));
  logic [LZC_OUT_WIDTH-1:0] zeroes_cnt;

  // Get the misalignment information for this vector memory instruction
  assign axi_addr_misalignment = axi_addrgen_d.addr[$clog2(AxiDataWidth/8)-1:0];

  // Calculate the maximum number of Bytes we can send in a store-misaligned beat.
  // This number must be a power of 2 not to get misaligned wrt the pack of data that the
  // store unit receives from the lanes
  lzc #(
    .WIDTH($clog2(AxiDataWidth/8)),
    .MODE (1'b0                  )
  ) i_lzc (
    .in_i   (axi_addr_misalignment  ),
    .cnt_o  (zeroes_cnt             ),
    .empty_o(/* Unconnected */      )
  );

  // Effective AXI data width for misaligned stores
  assign narrow_axi_data_bwidth = (AxiDataWidth/8) >> ($clog2(AxiDataWidth/8) - zeroes_cnt);

  //////////////////////////////
  //  AXI Request Generation  //
  //////////////////////////////

  addrgen_req_t axi_addrgen_d, axi_addrgen_q;
  enum logic [1:0] {
    AXI_ADDRGEN_IDLE, AXI_ADDRGEN_WAITING, AXI_ADDRGEN_REQUESTING
  } axi_addrgen_state_d, axi_addrgen_state_q;

  axi_addr_t aligned_start_addr_d, aligned_start_addr_q;
  axi_addr_t aligned_end_addr_d, aligned_end_addr_q;

  logic [$clog2(AxiDataWidth/8):0] eff_axi_data_bwidth_d, eff_axi_data_bwidth_q;
  logic [LZC_OUT_WIDTH:0] eff_axi_data_bwidth_log_d, eff_axi_data_bwidth_log_q;

  always_comb begin: axi_addrgen
    // Maintain state
    axi_addrgen_state_d = axi_addrgen_state_q;
    axi_addrgen_d       = axi_addrgen_q;

    aligned_start_addr_d = aligned_start_addr_q;
    aligned_end_addr_d   = aligned_end_addr_q;

    eff_axi_data_bwidth_d     = eff_axi_data_bwidth_q;
    eff_axi_data_bwidth_log_d = eff_axi_data_bwidth_log_q;

    idx_final_addr = axi_addrgen_q.addr;
    addrgen_operand_ack_o = 1'b0;
    shuffled_word = '0;
    deshuffled_word = '0;
    index_address   = '0;
    reduced_word    = '0;
    addrgen_operand_ready_o = 1'b0;
    word_lane_ptr_d = word_lane_ptr_q;
    elm_ptr_d = elm_ptr_q;
    last_elm_subw_d = last_elm_subw_q;

    // No addrgen request to acknowledge
    addrgen_req_ready = 1'b0;

    // No addrgen command to the load/store units
    axi_addrgen_queue      = '0;
    axi_addrgen_queue_push = 1'b0;

    // No AXI request
    axi_ar_o       = '0;
    axi_ar_valid_o = 1'b0;
    axi_aw_o       = '0;
    axi_aw_valid_o = 1'b0;

    case (axi_addrgen_state_q)
      AXI_ADDRGEN_IDLE: begin
        if (addrgen_req_valid) begin
          axi_addrgen_d       = addrgen_req;
          axi_addrgen_state_d = core_st_pending_i ? AXI_ADDRGEN_WAITING : AXI_ADDRGEN_REQUESTING;

          // In case of a misaligned store, reduce the effective AXI Data-Byte-Width since
          // the store unit does not support misalignments between the Axi Bus and the
          // data received from the lanes
          eff_axi_data_bwidth_d =
            ((axi_addrgen_d.addr[$clog2(AxiDataWidth/8)-1:0] != '0) && !axi_addrgen_d.is_load) ?
            {1'b0, narrow_axi_data_bwidth} :
            AxiDataWidth/8;
          // In case of a misaligned store, eff_axi_data_bwidth_d == narrow_axi_data_bwidth
          // In this situation, $clog2(narrow_axi_data_bwidth) == zeroes_cnt
          eff_axi_data_bwidth_log_d =
            ((axi_addrgen_d.addr[$clog2(AxiDataWidth/8)-1:0] != '0) && !axi_addrgen_d.is_load) ?
            zeroes_cnt :
            $clog2(AxiDataWidth/8);

          // The start address is found by aligning the original request address by the width of
          // the memory interface.
          aligned_start_addr_d = aligned_addr(axi_addrgen_d.addr, eff_axi_data_bwidth_log_d);
          // The final address can be found similarly...
          if (axi_addrgen_d.len << int'(axi_addrgen_d.vew) > (256 << eff_axi_data_bwidth_log_d)) begin
            aligned_end_addr_d =
              aligned_addr(axi_addrgen_d.addr + (256 << eff_axi_data_bwidth_log_d) - 1,
              eff_axi_data_bwidth_log_d) + ((eff_axi_data_bwidth_d) - 1);
          end else begin
            aligned_end_addr_d =
                  aligned_addr(axi_addrgen_d.addr + (axi_addrgen_d.len << int'(axi_addrgen_d.vew)) - 1,
                  eff_axi_data_bwidth_log_d) + ((eff_axi_data_bwidth_d) - 1);
          end
          // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
          // same page as aligned_start_addr
          if (aligned_start_addr_d[AxiAddrWidth-1:12] != aligned_end_addr_d[AxiAddrWidth-1:12])
            aligned_end_addr_d = {aligned_start_addr_d[AxiAddrWidth-1:12], 12'hFFF};

          // Load element pointers
          elm_ptr_d       = '0;
          word_lane_ptr_d = '0;
          case (axi_addrgen_d.vew)
            EW8:  last_elm_subw_d = 7;
            EW16: last_elm_subw_d = 3;
            EW32: last_elm_subw_d = 1;
            EW64: last_elm_subw_d = 0;
            default:
              last_elm_subw_d = 0;
          endcase
        end
      end
      AXI_ADDRGEN_WAITING: begin
        if (!core_st_pending_i)
          axi_addrgen_state_d = AXI_ADDRGEN_REQUESTING;
      end
      AXI_ADDRGEN_REQUESTING : begin
        automatic logic axi_ax_ready = (axi_addrgen_q.is_load && axi_ar_ready_i) || (!
          axi_addrgen_q.is_load && axi_aw_ready_i);

        // Before starting a transaction on a different channel, wait the formers to complete
        // Otherwise, the ordering of the responses is not guaranteed, and with the current
        // implementation we can incur in deadlocks
        if (axi_addrgen_queue_empty || (axi_addrgen_req_o.is_load && axi_addrgen_q.is_load) ||
             (~axi_addrgen_req_o.is_load && ~axi_addrgen_q.is_load)) begin
        if (!axi_addrgen_queue_full && axi_ax_ready) begin
          if (axi_addrgen_q.is_burst) begin

            /////////////////////////
            //  Unit-Stride access //
            /////////////////////////

            // AXI burst length
            automatic int unsigned burst_length;

            // 1 - AXI bursts are at most 256 beats long.
              burst_length = 256;
            // 2 - The AXI burst length cannot be longer than the number of beats required
            //     to access the memory regions between aligned_start_addr and
            //     aligned_end_addr
            if (burst_length > ((aligned_end_addr_q[11:0] - aligned_start_addr_q[11:0]) >>
                  eff_axi_data_bwidth_log_q) + 1)
              burst_length = ((aligned_end_addr_q[11:0] - aligned_start_addr_q[11:0]) >>
                eff_axi_data_bwidth_log_q) + 1;

            // AR Channel
            if (axi_addrgen_q.is_load) begin
              axi_ar_o = '{
                addr   : axi_addrgen_q.addr,
                len    : burst_length - 1,
                size   : eff_axi_data_bwidth_log_q,
                cache  : CACHE_MODIFIABLE,
                burst  : BURST_INCR,
                default: '0
              };
              axi_ar_valid_o = 1'b1;
            end
            // AW Channel
            else begin
              axi_aw_o = '{
                addr   : axi_addrgen_q.addr,
                len    : burst_length - 1,
                // If misaligned store access, reduce the effective AXI width
                // This hurts performance
                size   : eff_axi_data_bwidth_log_q,
                cache  : CACHE_MODIFIABLE,
                burst  : BURST_INCR,
                default: '0
              };
              axi_aw_valid_o = 1'b1;
            end

            // Send this request to the load/store units
            axi_addrgen_queue = '{
              addr   : axi_addrgen_q.addr,
              len    : burst_length - 1,
              size   : eff_axi_data_bwidth_log_q,
              is_load: axi_addrgen_q.is_load
            };
            axi_addrgen_queue_push = 1'b1;

            // Account for the requested operands
            axi_addrgen_d.len = axi_addrgen_q.len - ((aligned_end_addr_q[11:0] - axi_addrgen_q.addr[11:0] + 1) >> int'(axi_addrgen_q.vew));
            if (axi_addrgen_q.len < ((aligned_end_addr_q[11:0] - axi_addrgen_q.addr[11:0] + 1) >> int'(axi_addrgen_q.vew)))
              axi_addrgen_d.len = 0;
            axi_addrgen_d.addr = aligned_end_addr_q + 1;

            // Finished generating AXI requests
            if (axi_addrgen_d.len == 0) begin
              addrgen_req_ready   = 1'b1;
              axi_addrgen_state_d = AXI_ADDRGEN_IDLE;
            end

            // Calculate the addresses for the next iteration
            // The start address is found by aligning the original request address by the width of
            // the memory interface. In our case, we have it already.
            aligned_start_addr_d = axi_addrgen_d.addr;
            // The final address can be found similarly.
            // How many B we requested? No more than (256 << burst_size)
            if (axi_addrgen_d.len << int'(axi_addrgen_q.vew) > (256 << eff_axi_data_bwidth_log_q)) begin
              aligned_end_addr_d =
                aligned_addr(aligned_start_addr_d + (256 << eff_axi_data_bwidth_log_q) - 1,
                eff_axi_data_bwidth_log_q) + ((eff_axi_data_bwidth_q) - 1);
            end else begin
              aligned_end_addr_d =
                aligned_addr(aligned_start_addr_d + (axi_addrgen_d.len << int'(axi_addrgen_q.vew)) - 1,
                eff_axi_data_bwidth_log_q) + ((eff_axi_data_bwidth_q) - 1);
            end
            // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
            // same page as aligned_start_addr
            if (aligned_start_addr_d[AxiAddrWidth-1:12] != aligned_end_addr_d[AxiAddrWidth-1:12])
              aligned_end_addr_d = {aligned_start_addr_d[AxiAddrWidth-1:12], 12'hFFF};
          end else if (state_q != ADDRGEN_SCATTER_GATHER) begin

            /////////////////////
            //  Strided access //
            /////////////////////

            // AR Channel
            if (axi_addrgen_q.is_load) begin
              axi_ar_o = '{
                addr   : axi_addrgen_q.addr,
                len    : 0,
                size   : axi_addrgen_q.vew,
                cache  : CACHE_MODIFIABLE,
                burst  : BURST_INCR,
                default: '0
              };
              axi_ar_valid_o = 1'b1;
            end
            // AW Channel
            else begin
              axi_aw_o = '{
                addr   : axi_addrgen_q.addr,
                len    : 0,
                size   : axi_addrgen_q.vew,
                cache  : CACHE_MODIFIABLE,
                burst  : BURST_INCR,
                default: '0
              };
              axi_aw_valid_o = 1'b1;
            end

            // Send this request to the load/store units
            axi_addrgen_queue = '{
              addr   : axi_addrgen_q.addr,
              size   : axi_addrgen_q.vew,
              len    : 0,
              is_load: axi_addrgen_q.is_load
            };
            axi_addrgen_queue_push = 1'b1;

            // Account for the requested operands
            axi_addrgen_d.len = axi_addrgen_q.len - 1;
            // Calculate the addresses for the next iteration, adding the correct stride
            axi_addrgen_d.addr = axi_addrgen_q.addr + axi_addrgen_q.stride;

            // Finished generating AXI requests
            if (axi_addrgen_d.len == 0) begin
              addrgen_req_ready   = 1'b1;
              axi_addrgen_state_d = AXI_ADDRGEN_IDLE;
            end
          end else begin

            //////////////////////
            //  Indexed access  //
            //////////////////////

            if (&addrgen_operand_valid_i) begin

              shuffled_word = addrgen_operand_i;

              // Deshuffle the whole NrLanes * 8 Byte word
              for (int unsigned b = 0; b < 8*NrLanes; b++) begin
                automatic shortint unsigned b_shuffled = shuffle_index(b, NrLanes, axi_addrgen_q.vew);
                deshuffled_word[8*b +: 8] = shuffled_word[8*b_shuffled +: 8];
              end

              // Extract only 1/NrLanes of the word
              for (int unsigned lane = 0; lane < NrLanes; lane++)
                if (lane == word_lane_ptr_q)
                  reduced_word = deshuffled_word[word_lane_ptr_q*$bits(elen_t) +: $bits(elen_t)];

              // Select the correct element, and zero extend it depending on vsew
              case (axi_addrgen_q.vew)
                EW8: begin
                  for (int unsigned b = 0; b < 8; b++)
                    if (b == elm_ptr_q)
                      index_address[7:0] = reduced_word[b*8 +: 8];
                  index_address[$bits(elen_t)-1 : 8]  = '0;
                end
                EW16: begin
                  for (int unsigned h = 0; h < 4; h++)
                    if (h == elm_ptr_q)
                      index_address[15:0] = reduced_word[h*16 +: 16];
                  index_address[$bits(elen_t)-1 : 16]  = '0;
                end
                EW32: begin
                  for (int unsigned w = 0; w < 2; w++)
                    if (w == elm_ptr_q)
                      index_address[31:0] = reduced_word[w*32 +: 32];
                  index_address[$bits(elen_t)-1 : 32]  = '0;
                end
                default: begin
                  for (int unsigned b = 0; b < 8; b++)
                    if (b == elm_ptr_q)
                      index_address[7:0] = reduced_word[b*8 +: 8];
                  index_address[$bits(elen_t)-1 : 8]  = '0;
                end
              endcase

              // Compose the address
              idx_final_addr = axi_addrgen_q.addr + index_address;

              // AR Channel
              if (axi_addrgen_q.is_load) begin
                axi_ar_o = '{
                  addr   : idx_final_addr,
                  len    : 0,
                  size   : axi_addrgen_q.vew,
                  cache  : CACHE_MODIFIABLE,
                  burst  : BURST_INCR,
                  default: '0
                };
                axi_ar_valid_o = 1'b1;
              end
              // AW Channel
              else begin
                axi_aw_o = '{
                  addr   : idx_final_addr,
                  len    : 0,
                  size   : axi_addrgen_q.vew,
                  cache  : CACHE_MODIFIABLE,
                  burst  : BURST_INCR,
                  default: '0
                };
                axi_aw_valid_o = 1'b1;
              end

              // Bump lane pointer
              if (elm_ptr_q == last_elm_subw_q) begin
                elm_ptr_d       = '0;
                word_lane_ptr_d += 1;
              end else begin
                // Bump element pointer
                elm_ptr_d += 1;
              end

              // Account for the requested operands
              axi_addrgen_d.len = axi_addrgen_q.len - 1;

              // Send this request to the load/store units
              axi_addrgen_queue = '{
                addr   : idx_final_addr,
                size   : axi_addrgen_q.vew,
                len    : 0,
                is_load: axi_addrgen_q.is_load
              };
              axi_addrgen_queue_push = 1'b1;

              // Give the grant when the word is consumed
              if (elm_ptr_q == last_elm_subw_q && word_lane_ptr_q == (NrLanes-1))
                addrgen_operand_ready_o = 1'b1;

              // Finished generating AXI requests
              if (axi_addrgen_d.len == 0) begin
                addrgen_req_ready       = 1'b1;
                addrgen_operand_ready_o = 1'b1;
                addrgen_operand_ack_o   = 1'b1;
                axi_addrgen_state_d = AXI_ADDRGEN_IDLE;
              end
            end
          end
        end
        end
      end
    endcase
  end: axi_addrgen

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      axi_addrgen_state_q       <= AXI_ADDRGEN_IDLE;
      axi_addrgen_q             <= '0;
      aligned_start_addr_q      <= '0;
      aligned_end_addr_q        <= '0;
      eff_axi_data_bwidth_q     <= '0;
      eff_axi_data_bwidth_log_q <= '0;
    end else begin
      axi_addrgen_state_q       <= axi_addrgen_state_d;
      axi_addrgen_q             <= axi_addrgen_d;
      aligned_start_addr_q      <= aligned_start_addr_d;
      aligned_end_addr_q        <= aligned_end_addr_d;
      eff_axi_data_bwidth_q     <= eff_axi_data_bwidth_d;
      eff_axi_data_bwidth_log_q <= eff_axi_data_bwidth_log_d;
    end
  end

endmodule : addrgen
