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
    input  logic     [NrVInsn-1:0]         pe_vinsn_running_i,
    output logic                           addrgen_error_o,
    output logic                           addrgen_ack_o,
    output vlen_t                          addrgen_error_vl_o,
    // Interface with the load/store units
    output addrgen_axi_req_t               axi_addrgen_req_o,
    output logic                           axi_addrgen_req_valid_o,
    input  logic                           ldu_axi_addrgen_req_ready_i,
    input  logic                           stu_axi_addrgen_req_ready_i,
    // Interface with the lanes (for scatter/gather operations)
    input  elen_t            [NrLanes-1:0] addrgen_operand_i,
    input  target_fu_e       [NrLanes-1:0] addrgen_operand_target_fu_i,
    input  logic             [NrLanes-1:0] addrgen_operand_valid_i,
    output logic                           addrgen_operand_ready_o
  );

  import cf_math_pkg::idx_width;
  import axi_pkg::aligned_addr;
  import axi_pkg::BURST_INCR;
  import axi_pkg::CACHE_MODIFIABLE;

  // Check if the address is aligned to a particular width
  function automatic logic is_addr_error(axi_addr_t addr, vew_e vew);
    is_addr_error = |(addr & (elen_t'(1 << vew) - 1));
  endfunction // is_addr_error

  ////////////////////
  //  PE Req Queue  //
  ////////////////////

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

  // Pipeline the PE requests
  pe_req_t pe_req_d, pe_req_q;

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
  //  Indexed Memory Ops  //
  //////////////////////////

  // Support for indexed memory operations (scatter/gather)
  logic [$bits(elen_t)*NrLanes-1:0] shuffled_word;
  logic [$bits(elen_t)*NrLanes-1:0] deshuffled_word;
  elen_t                            reduced_word;
  axi_addr_t                        idx_final_addr_d, idx_final_addr_q;
  elen_t                            idx_addr;
  logic                             idx_op_error_d, idx_op_error_q;
  vlen_t                            addrgen_error_vl_d;

  // Pointer to point to the correct
  logic [$clog2(NrLanes)-1:0] word_lane_ptr_d, word_lane_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] elm_ptr_d, elm_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] last_elm_subw_d, last_elm_subw_q;
  vlen_t                              idx_op_cnt_d, idx_op_cnt_q;

  // Spill reg signals
  logic      idx_addr_valid_d, idx_addr_valid_q;
  logic      idx_addr_ready_d, idx_addr_ready_q;

  // Break the path from the VRF to the AXI request
  spill_register #(
    .T(elen_t)
  ) i_addrgen_idx_op_spill_reg (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .valid_i(idx_addr_valid_d),
    .ready_o(idx_addr_ready_q),
    .data_i (idx_final_addr_d),
    .valid_o(idx_addr_valid_q),
    .ready_i(idx_addr_ready_d),
    .data_o (idx_final_addr_q)
  );

  //////////////////////////
  //  Address generation  //
  //////////////////////////

  // Running vector instructions
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // The Address Generator can be in one of the following three states.
  // IDLE: Waiting for a vector load/store instruction.
  // ADDRGEN: Generates a series of AXI requests from a vector instruction.
  // ADDRGEN_IDX_OP: Generates a series of AXI requests from a
  //    vector instruction, but reading a vector of offsets from Ara's lanes.
  //    This is used for scatter and gather operations.
  enum logic [1:0] {
    IDLE,
    ADDRGEN,
    ADDRGEN_IDX_OP,
    ADDRGEN_IDX_OP_END
  } state_q, state_d;

  always_comb begin: addr_generation
    // Maintain state
    state_d  = state_q;
    pe_req_d = pe_req_q;

    // Running vector instructions
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // No request, by default
    addrgen_req       = '0;
    addrgen_req_valid = 1'b0;

    // Nothing to acknowledge
    addrgen_ack_o           = 1'b0;
    addrgen_error_o         = 1'b0;

    // No valid words for the spill register
    idx_addr_valid_d        = 1'b0;
    addrgen_operand_ready_o = 1'b0;
    reduced_word            = '0;
    elm_ptr_d               = elm_ptr_q;
    idx_op_cnt_d            = idx_op_cnt_q;
    word_lane_ptr_d         = word_lane_ptr_q;
    idx_final_addr_d        = idx_final_addr_q;
    last_elm_subw_d         = last_elm_subw_q;

    // Support for indexed operations
    shuffled_word = addrgen_operand_i;
    // Deshuffle the whole NrLanes * 8 Byte word
    for (int unsigned b = 0; b < 8*NrLanes; b++) begin
      automatic shortint unsigned b_shuffled = shuffle_index(b, NrLanes, pe_req_q.eew_vs2);
      deshuffled_word[8*b +: 8] = shuffled_word[8*b_shuffled +: 8];
    end

    // Extract only 1/NrLanes of the word
    for (int unsigned lane = 0; lane < NrLanes; lane++)
      if (lane == word_lane_ptr_q)
        reduced_word = deshuffled_word[word_lane_ptr_q*$bits(elen_t) +: $bits(elen_t)];
    idx_addr = reduced_word;

    case (state_q)
      IDLE: begin
        // Received a new request
        if (pe_req_valid_i &&
            (is_load(pe_req_i.op) || is_store(pe_req_i.op)) && !vinsn_running_q[pe_req_i.id]) begin
          // Mark the instruction as running in this unit
          vinsn_running_d[pe_req_i.id] = 1'b1;

          // Store the PE request
          pe_req_d = pe_req_i;

          case (pe_req_i.op)
            VLXE, VSXE: begin
              state_d = ADDRGEN_IDX_OP;

              // Load element pointers
              case (pe_req_i.eew_vs2)
                EW8:  last_elm_subw_d = 7;
                EW16: last_elm_subw_d = 3;
                EW32: last_elm_subw_d = 1;
                EW64: last_elm_subw_d = 0;
                default:
                  last_elm_subw_d = 0;
              endcase

              // Load element counter
              idx_op_cnt_d = pe_req_i.vl;
            end
            default: state_d = ADDRGEN;
          endcase
        end
      end
      ADDRGEN: begin
        // Ara does not support misaligned AXI requests
        if (is_addr_error(pe_req_q.scalar_op, pe_req_q.vtype.vsew)) begin
          state_d         = IDLE;
          addrgen_ack_o   = 1'b1;
          addrgen_error_o = 1'b1;
        end else begin
          addrgen_req = '{
            addr    : pe_req_q.scalar_op,
            len     : pe_req_q.vl,
            stride  : pe_req_q.stride,
            vew     : pe_req_q.vtype.vsew,
            is_load : is_load(pe_req_q.op),
            // Unit-strided loads/stores trigger incremental AXI bursts.
            is_burst: (pe_req_q.op inside {VLE, VSE})
          };
          addrgen_req_valid = 1'b1;

          if (addrgen_req_ready) begin
            addrgen_req_valid = '0;
            addrgen_ack_o     = 1'b1;
            state_d           = IDLE;
          end
        end
      end
      ADDRGEN_IDX_OP: begin
        // Stall the interface until the operation is over to catch possible exceptions

        // Every address can generate an exception
        addrgen_req = '{
          addr    : pe_req_q.scalar_op,
          len     : pe_req_q.vl,
          stride  : pe_req_q.stride,
          vew     : pe_req_q.vtype.vsew,
          is_load : is_load(pe_req_q.op),
          // Unit-strided loads/stores trigger incremental AXI bursts.
          is_burst: 1'b0
        };
        addrgen_req_valid = 1'b1;

        // Handle handshake and data between VRF and spill register
        // We accept all the incoming data, without any checks
        // since Ara stalls on an indexed memory operation
        if (&addrgen_operand_valid_i & addrgen_operand_target_fu_i[0] == ADDRGEN) begin

          // Valid data for the spill register
          idx_addr_valid_d = 1'b1;

          // Select the correct element, and zero extend it depending on vsew
          case (pe_req_q.eew_vs2)
            EW8: begin
              for (int unsigned b = 0; b < 8; b++)
                if (b == elm_ptr_q)
                  idx_addr = reduced_word[b*8 +: 8];
            end
            EW16: begin
              for (int unsigned h = 0; h < 4; h++)
                if (h == elm_ptr_q)
                  idx_addr = reduced_word[h*16 +: 16];
            end
            EW32: begin
              for (int unsigned w = 0; w < 2; w++)
                if (w == elm_ptr_q)
                  idx_addr = reduced_word[w*32 +: 32];
            end
            EW64: begin
              for (int unsigned d = 0; d < 1; d++)
                if (d == elm_ptr_q)
                  idx_addr = reduced_word[d*64 +: 64];
            end
            default: begin
              for (int unsigned b = 0; b < 8; b++)
                if (b == elm_ptr_q)
                  idx_addr = reduced_word[b*8 +: 8];
            end
          endcase

          // Compose the address
          idx_final_addr_d = pe_req_q.scalar_op + idx_addr;

          // When the data is accepted
          if (idx_addr_ready_q) begin
            // Consumed one element
            idx_op_cnt_d = idx_op_cnt_q - 1;
            // Have we finished a full NrLanes*64b word?
            if (elm_ptr_q == last_elm_subw_q) begin
              // Bump lane pointer
              elm_ptr_d       = '0;
              word_lane_ptr_d += 1;
              if (word_lane_ptr_q == NrLanes - 1)
              // Ready for the next full word
              addrgen_operand_ready_o = 1'b1;
            end else begin
              // Bump element pointer
              elm_ptr_d += 1;
            end
          end

          if (idx_op_cnt_d == '0) begin
            // Give a ready to the lanes if this was not done before
            addrgen_operand_ready_o = 1'b1;
          end
        end

        if (idx_op_error_d || addrgen_req_ready) begin
          state_d = ADDRGEN_IDX_OP_END;
        end
      end

      // This state exists not to create combinatorial paths on the interface
      ADDRGEN_IDX_OP_END : begin
        // Acknowledge the indexed memory operation
        addrgen_ack_o     = 1'b1;
        addrgen_req_valid = '0;
        state_d           = IDLE;
        // Reset pointers
        elm_ptr_d       = '0;
        word_lane_ptr_d = '0;
        // Raise an error if necessary
        if (idx_op_error_q) begin
          addrgen_error_o = 1'b1;
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q            <= IDLE;
      pe_req_q           <= '0;
      vinsn_running_q    <= '0;
      word_lane_ptr_q    <= '0;
      elm_ptr_q          <= '0;
      idx_op_cnt_q       <= '0;
      last_elm_subw_q    <= '0;
      idx_op_error_q     <= '0;
      addrgen_error_vl_o <= '0;
    end else begin
      state_q            <= state_d;
      pe_req_q           <= pe_req_d;
      vinsn_running_q    <= vinsn_running_d;
      word_lane_ptr_q    <= word_lane_ptr_d;
      elm_ptr_q          <= elm_ptr_d;
      idx_op_cnt_q       <= idx_op_cnt_d;
      last_elm_subw_q    <= last_elm_subw_d;
      idx_op_error_q     <= idx_op_error_d;
      addrgen_error_vl_o <= addrgen_error_vl_d;
    end
  end

  /////////////////////////////////////
  //  Support for misaligned stores  //
  /////////////////////////////////////

  // AXI Request Generation signals, declared here for convenience
  addrgen_req_t axi_addrgen_d, axi_addrgen_q;

  // Narrower AXI Data Byte-Width used for misaligned stores
  logic [$clog2(AxiDataWidth/8)-1:0]            narrow_axi_data_bwidth;
  // Helper signal to calculate the narrow_axi_data_bwidth
  // It carries information about the misalignment of the start address w.r.t. the AxiDataWidth
  logic [$clog2(AxiDataWidth/8)-1:0]            axi_addr_misalignment;
  // Number of trailing 0s of axi_addr_misalignment
  logic [idx_width($clog2(AxiDataWidth/8))-1:0] zeroes_cnt;

  // Get the misalignment information for this vector memory instruction
  assign axi_addr_misalignment = axi_addrgen_d.addr[$clog2(AxiDataWidth/8)-1:0];

  // Calculate the maximum number of Bytes we can send in a store-misaligned beat.
  // This number must be a power of 2 not to get misaligned wrt the pack of data that the
  // store unit receives from the lanes
  lzc #(
    .WIDTH($clog2(AxiDataWidth/8)),
    .MODE (1'b0                  )
  ) i_lzc (
    .in_i   (axi_addr_misalignment),
    .cnt_o  (zeroes_cnt           ),
    .empty_o(/* Unconnected */    )
  );

  // Effective AXI data width for misaligned stores
  assign narrow_axi_data_bwidth = (AxiDataWidth/8) >> ($clog2(AxiDataWidth/8) - zeroes_cnt);

  //////////////////////////////
  //  AXI Request Generation  //
  //////////////////////////////

  enum logic [1:0] {
    AXI_ADDRGEN_IDLE, AXI_ADDRGEN_MISALIGNED, AXI_ADDRGEN_WAITING, AXI_ADDRGEN_REQUESTING
  } axi_addrgen_state_d, axi_addrgen_state_q;

  axi_addr_t aligned_start_addr_d, aligned_start_addr_q;
  axi_addr_t aligned_end_addr_d, aligned_end_addr_q;

  logic [$clog2(AxiDataWidth/8):0]            eff_axi_dw_d, eff_axi_dw_q;
  logic [idx_width($clog2(AxiDataWidth/8)):0] eff_axi_dw_log_d, eff_axi_dw_log_q;

  always_comb begin: axi_addrgen
    // Maintain state
    axi_addrgen_state_d = axi_addrgen_state_q;
    axi_addrgen_d       = axi_addrgen_q;

    aligned_start_addr_d = aligned_start_addr_q;
    aligned_end_addr_d   = aligned_end_addr_q;

    eff_axi_dw_d     = eff_axi_dw_q;
    eff_axi_dw_log_d = eff_axi_dw_log_q;

    idx_addr_ready_d    = 1'b0;
    addrgen_error_vl_d  = '0;

    // No error by default
    idx_op_error_d = 1'b0;

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

          // In case of a misaligned store, reduce the effective width of the AXI transaction,
          // since the store unit does not support misalignments between the AXI bus and the lanes
          if ((axi_addrgen_d.addr[$clog2(AxiDataWidth/8)-1:0] != '0) && !axi_addrgen_d.is_load)
          begin
            // Calculate the start and the end addresses in the AXI_ADDRGEN_MISALIGNED state
            axi_addrgen_state_d = AXI_ADDRGEN_MISALIGNED;

            eff_axi_dw_d     = {1'b0, narrow_axi_data_bwidth};
            eff_axi_dw_log_d = zeroes_cnt;
          end else begin
            eff_axi_dw_d     = AxiDataWidth/8;
            eff_axi_dw_log_d = $clog2(AxiDataWidth/8);
          end

          // The start address is found by aligning the original request address by the width of
          // the memory interface.
          aligned_start_addr_d = aligned_addr(axi_addrgen_d.addr, $clog2(AxiDataWidth/8));
          // The final address can be found similarly...
          if (axi_addrgen_d.len << int'(axi_addrgen_d.vew) > (256 << $clog2(AxiDataWidth/8))) begin
            aligned_end_addr_d =
            aligned_addr(axi_addrgen_d.addr + (256 << $clog2(AxiDataWidth/8)) - 1,
              $clog2(AxiDataWidth/8)) + AxiDataWidth/8 - 1;
          end else begin
            aligned_end_addr_d =
            aligned_addr(axi_addrgen_d.addr + (axi_addrgen_d.len << int'(axi_addrgen_d.vew)) - 1,
              $clog2(AxiDataWidth/8)) + AxiDataWidth/8 - 1;
          end
          // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
          // same page as aligned_start_addr
          if (aligned_start_addr_d[AxiAddrWidth-1:12] != aligned_end_addr_d[AxiAddrWidth-1:12])
            aligned_end_addr_d = {aligned_start_addr_d[AxiAddrWidth-1:12], 12'hFFF};
        end
      end
      AXI_ADDRGEN_MISALIGNED: begin
        axi_addrgen_state_d = core_st_pending_i ? AXI_ADDRGEN_WAITING : AXI_ADDRGEN_REQUESTING;

        // The start address is found by aligning the original request address by the width of
        // the memory interface.
        aligned_start_addr_d = aligned_addr(axi_addrgen_q.addr, eff_axi_dw_log_q);
        // The final address can be found similarly...
        if (axi_addrgen_q.len << int'(axi_addrgen_q.vew) > (256 << eff_axi_dw_log_q)) begin
          aligned_end_addr_d =
            aligned_addr(axi_addrgen_q.addr + (256 << eff_axi_dw_log_q) - 1, eff_axi_dw_log_q)
            + eff_axi_dw_q - 1;
        end else begin
          aligned_end_addr_d =
            aligned_addr(axi_addrgen_q.addr + (axi_addrgen_q.len << int'(axi_addrgen_q.vew)) - 1,
            eff_axi_dw_log_q) + eff_axi_dw_q - 1;
        end
        // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
        // same page as aligned_start_addr
        if (aligned_start_addr_d[AxiAddrWidth-1:12] != aligned_end_addr_d[AxiAddrWidth-1:12])
          aligned_end_addr_d = {aligned_start_addr_d[AxiAddrWidth-1:12], 12'hFFF};
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
                    eff_axi_dw_log_q) + 1)
                burst_length = ((aligned_end_addr_q[11:0] - aligned_start_addr_q[11:0]) >>
                  eff_axi_dw_log_q) + 1;

              // AR Channel
              if (axi_addrgen_q.is_load) begin
                axi_ar_o = '{
                  addr   : axi_addrgen_q.addr,
                  len    : burst_length - 1,
                  size   : eff_axi_dw_log_q,
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
                  size   : eff_axi_dw_log_q,
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
                size   : eff_axi_dw_log_q,
                is_load: axi_addrgen_q.is_load
              };
              axi_addrgen_queue_push = 1'b1;

              // Account for the requested operands
              axi_addrgen_d.len = axi_addrgen_q.len -
                ((aligned_end_addr_q[11:0] - axi_addrgen_q.addr[11:0] + 1)
                  >> int'(axi_addrgen_q.vew));
              if (axi_addrgen_q.len <
                ((aligned_end_addr_q[11:0] - axi_addrgen_q.addr[11:0] + 1)
                  >> int'(axi_addrgen_q.vew)))
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
              if (axi_addrgen_d.len << int'(axi_addrgen_q.vew) > (256 << eff_axi_dw_log_q))
              begin
                aligned_end_addr_d =
                  aligned_addr(aligned_start_addr_d + (256 << eff_axi_dw_log_q) - 1,
                    eff_axi_dw_log_q) + eff_axi_dw_q - 1;
              end else begin
                aligned_end_addr_d =
                  aligned_addr(aligned_start_addr_d + (axi_addrgen_d.len << int'(axi_addrgen_q.vew))
                  - 1, eff_axi_dw_log_q) + eff_axi_dw_q - 1;
              end
              // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
              // same page as aligned_start_addr
              if (aligned_start_addr_d[AxiAddrWidth-1:12] != aligned_end_addr_d[AxiAddrWidth-1:12])
                aligned_end_addr_d = {aligned_start_addr_d[AxiAddrWidth-1:12], 12'hFFF};
            end else if (state_q != ADDRGEN_IDX_OP) begin

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
              axi_addrgen_d.len  = axi_addrgen_q.len - 1;
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

              if (idx_addr_valid_q) begin
                // We consumed a word
                idx_addr_ready_d = 1'b1;

                // AR Channel
                if (axi_addrgen_q.is_load) begin
                  axi_ar_o = '{
                    addr   : idx_final_addr_q,
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
                    addr   : idx_final_addr_q,
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
                  addr   : idx_final_addr_q,
                  size   : axi_addrgen_q.vew,
                  len    : 0,
                  is_load: axi_addrgen_q.is_load
                };
                axi_addrgen_queue_push = 1'b1;

                // Account for the requested operands
                axi_addrgen_d.len = axi_addrgen_q.len - 1;

                // Check if the address does generate an exception
                if (is_addr_error(idx_final_addr_q, axi_addrgen_q.vew)) begin
                  // Generate an error
                  idx_op_error_d          = 1'b1;
                  // Forward next vstart info to the dispatcher
                  addrgen_error_vl_d      = addrgen_req.len - axi_addrgen_q.len - 1;
                  addrgen_req_ready       = 1'b1;
                  axi_addrgen_state_d     = AXI_ADDRGEN_IDLE;
                end

                // Finished generating AXI requests
                if (axi_addrgen_d.len == 0) begin
                  addrgen_req_ready   = 1'b1;
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
      axi_addrgen_state_q  <= AXI_ADDRGEN_IDLE;
      axi_addrgen_q        <= '0;
      aligned_start_addr_q <= '0;
      aligned_end_addr_q   <= '0;
      eff_axi_dw_q         <= '0;
      eff_axi_dw_log_q     <= '0;
    end else begin
      axi_addrgen_state_q  <= axi_addrgen_state_d;
      axi_addrgen_q        <= axi_addrgen_d;
      aligned_start_addr_q <= aligned_start_addr_d;
      aligned_end_addr_q   <= aligned_end_addr_d;
      eff_axi_dw_q         <= eff_axi_dw_d;
      eff_axi_dw_log_q     <= eff_axi_dw_log_d;
    end
  end

endmodule : addrgen
