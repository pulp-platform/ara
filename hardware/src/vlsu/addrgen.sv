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
    parameter int  unsigned VLEN         = 0,
    // AXI Interface parameters
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_aw_t     = logic,
    parameter  type         pe_req_t     = logic,
    parameter  type         pe_resp_t    = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam type         axi_addr_t   = logic [AxiAddrWidth-1:0],
    localparam type         vlen_t       = logic[$clog2(VLEN+1)-1:0]
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
    // CSR input
    input  logic                           en_ld_st_translation_i,
    // Interface with CVA6's sv39 MMU
    // This is everything the MMU can provide, it might be overcomplete for Ara and some signals be useless
    output logic                           mmu_misaligned_ex_o,
    output logic                           mmu_req_o,        // request address translation
    output logic [riscv::VLEN-1:0]         mmu_vaddr_o,      // virtual address out
    output logic                           mmu_is_store_o,   // the translation is requested by a store
    // if we need to walk the page table we can't grant in the same cycle
    // Cycle 0
    input logic                            mmu_dtlb_hit_i,   // sent in the same cycle as the request if translation hits in the DTLB
    input logic [riscv::PPNW-1:0]          mmu_dtlb_ppn_i,   // ppn (send same cycle as hit)
    // Cycle 1
    input  logic                           mmu_valid_i,      // translation is valid
    input  logic [riscv::PLEN-1:0]         mmu_paddr_i,      // translated address
    input  ariane_pkg::exception_t         mmu_exception_i,  // address translation threw an exception
    // Interace with the dispatcher
    input  logic                           core_st_pending_i,
    // Interface with the main sequencer
    input  pe_req_t                        pe_req_i,
    input  logic                           pe_req_valid_i,
    input  logic     [NrVInsn-1:0]         pe_vinsn_running_i,
    output ariane_pkg::exception_t         addrgen_exception_o,
    output logic                           addrgen_ack_o,
    output vlen_t                          addrgen_exception_vstart_o,
    output logic                           addrgen_illegal_load_o,
    output logic                           addrgen_illegal_store_o,
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

  localparam unsigned DataWidth = $bits(elen_t);
  localparam unsigned DataWidthB = DataWidth / 8;

  // Ara reports misaligned exceptions on its own
  assign mmu_misaligned_ex_o  = '0;

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
    vlen_t vstart;
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
  logic             axi_addrgen_queue_pop;

  assign axi_addrgen_queue_pop = ldu_axi_addrgen_req_ready_i | stu_axi_addrgen_req_ready_i;

  fifo_v3 #(
    .DEPTH(VaddrgenInsnQueueDepth),
    .dtype(addrgen_axi_req_t     )
  ) i_addrgen_req_queue (
    .clk_i     (clk_i                                                    ),
    .rst_ni    (rst_ni                                                   ),
    .flush_i   (1'b0                                                     ),
    .testmode_i(1'b0                                                     ),
    .data_i    (axi_addrgen_queue                                        ),
    .push_i    (axi_addrgen_queue_push                                   ),
    .full_o    (axi_addrgen_queue_full                                   ),
    .data_o    (axi_addrgen_req_o                                        ),
    .pop_i     (axi_addrgen_queue_pop                                    ),
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
  axi_addr_t                        idx_final_vaddr_d, idx_final_vaddr_q;
  elen_t                            idx_vaddr;
  logic                             idx_op_error_d, idx_op_error_q;
  vlen_t                            addrgen_exception_vstart_d;

  // Pointer to point to the correct
  logic [$clog2(NrLanes)-1:0] word_lane_ptr_d, word_lane_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] elm_ptr_d, elm_ptr_q;
  logic [$clog2($bits(elen_t)/8)-1:0] last_elm_subw_d, last_elm_subw_q;
  vlen_t                              idx_op_cnt_d, idx_op_cnt_q;

  // Spill reg signals
  logic      idx_vaddr_valid_d, idx_vaddr_valid_q;
  logic      idx_vaddr_ready_d, idx_vaddr_ready_q;

  // Break the path from the VRF to the AXI request
  spill_register #(
    .T(axi_addr_t)
  ) i_addrgen_idx_op_spill_reg (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .valid_i(idx_vaddr_valid_d),
    .ready_o(idx_vaddr_ready_q),
    .data_i (idx_final_vaddr_d),
    .valid_o(idx_vaddr_valid_q),
    .ready_i(idx_vaddr_ready_d),
    .data_o (idx_final_vaddr_q)
  );

  //////////////////////////
  //  Address generation  //
  //////////////////////////
  ariane_pkg::exception_t mmu_exception_d, mmu_exception_q;
  logic last_translation_completed;

  // Running vector instructions
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // The Address Generator can be in one of the following three states.
  // IDLE: Waiting for a vector load/store instruction.
  // ADDRGEN: Generates a series of AXI requests from a vector instruction.
  // ADDRGEN_IDX_OP: Generates a series of AXI requests from a
  //    vector instruction, but reading a vector of offsets from Ara's lanes.
  //    This is used for scatter and gather operations.
  // WAIT_LAST_TRANSLATION: Wait for the last address translation to be acknowledged
  enum logic [2:0] {
    IDLE,
    ADDRGEN,
    ADDRGEN_IDX_OP,
    ADDRGEN_IDX_OP_END,
    WAIT_LAST_TRANSLATION
  } state_q, state_d;

  // TODO: Masked elements do not generate exceptions on:
  //      * EEW misalignment
  //      * page faults
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
    addrgen_exception_o.valid = 1'b0;
    addrgen_exception_o.tval  = '0;
    addrgen_exception_o.cause = '0;
    addrgen_illegal_load_o  = 1'b0;
    addrgen_illegal_store_o = 1'b0;

    // No valid words for the spill register
    idx_vaddr_valid_d       = 1'b0;
    addrgen_operand_ready_o = 1'b0;
    reduced_word            = '0;
    elm_ptr_d               = elm_ptr_q;
    idx_op_cnt_d            = idx_op_cnt_q;
    word_lane_ptr_d         = word_lane_ptr_q;
    idx_final_vaddr_d       = idx_final_vaddr_q;
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
    idx_vaddr = reduced_word;

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
              idx_op_cnt_d = pe_req_i.vl - pe_req_i.vstart;
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
          addrgen_exception_o.valid = 1'b1;
          addrgen_exception_o.cause = riscv::ILLEGAL_INSTR;
          addrgen_exception_o.tval  = '0;
        end
        else begin : address_valid
          // NOTE: indexed are not covered here
          automatic logic [riscv::VLEN-1:0] vaddr_start;

          case (pe_req_q.op)
            // Unit-stride: address = base + (vstart in elements)
            VLE,  VSE : vaddr_start = pe_req_q.scalar_op + (pe_req_q.vstart << unsigned'(pe_req_q.vtype.vsew));
            // Strided: address = base + (vstart * stride)
            // NOTE: this multiplier might cause some timing issues
            VLSE, VSSE: vaddr_start = pe_req_q.scalar_op + (pe_req_q.vstart * pe_req_q.stride);
            // Indexed: let the next stage take care of vstart
            VLXE, VSXE: vaddr_start = pe_req_q.scalar_op;
            default   : vaddr_start = '0;
          endcase // pe_req_q.op

          addrgen_req = '{
            addr    : vaddr_start,
            len     : pe_req_q.vl - pe_req_q.vstart,
            stride  : pe_req_q.stride,
            vew     : pe_req_q.vtype.vsew,
            is_load : is_load(pe_req_q.op),
            // Unit-strided loads/stores trigger incremental AXI bursts.
            is_burst: (pe_req_q.op inside {VLE, VSE}),
            vstart  : pe_req_q.vstart
          };
          addrgen_req_valid = 1'b1;

          if (addrgen_req_ready) begin : finished
            addrgen_req_valid = '0;
            addrgen_ack_o     = 1'b1;
            state_d           = IDLE;
          end : finished

          // If load/store translation is enabled
          if (en_ld_st_translation_i) begin : translation_enabled
            // We need to wait for the last translation to be over before acking back
            // addrgen_req_valid = '0; TODO: figure out if set/reset here
            addrgen_ack_o     = 1'b0;
            state_d           = WAIT_LAST_TRANSLATION;
          end : translation_enabled
        end : address_valid
      end

      ADDRGEN_IDX_OP: begin
        // NOTE: vstart is not supported for indexed operations
        //       the logic shuld be introduced:
        //       1. in the addrgen_operand_i operand read
        //       2. in idx_vaddr computation
        automatic logic [NrLanes-1:0] addrgen_operand_valid;

        // Stall the interface until the operation is over to catch possible exceptions

        // Every address can generate an exception
        addrgen_req = '{
          addr    : pe_req_q.scalar_op,
          len     : pe_req_q.vl - pe_req_q.vstart,
          stride  : pe_req_q.stride,
          vew     : pe_req_q.vtype.vsew,
          is_load : is_load(pe_req_q.op),
          // Unit-strided loads/stores trigger incremental AXI bursts.
          is_burst: 1'b0,
          vstart  : pe_req_q.vstart
        };
        addrgen_req_valid = 1'b1;

        // Adjust valid signals to the next block "operands_ready"
        addrgen_operand_valid = addrgen_operand_valid_i;
        for (int unsigned lane = 0; lane < NrLanes; lane++) begin : adjust_operand_valid
          // - We are left with less byte than the maximim to issue,
          //    this means that at least one lane is not going to push us any operand anymore
          // - For the lanes which index % NrLanes != 0
          if (((idx_op_cnt_q << pe_req_q.vtype.vsew) < (NrLanes * DataWidthB))
               && (lane < pe_req_q.vstart[idx_width(NrLanes)-1:0])) begin : vstart_lane_adjust
            addrgen_operand_valid[lane] |= 1'b1;
          end : vstart_lane_adjust
        end : adjust_operand_valid
        // TODO: apply the same vstart logic also to mask_valid_i

        // Handle handshake and data between VRF and spill register
        // We accept all the incoming data, without any checks
        // since Ara stalls on an indexed memory operation
        if (&addrgen_operand_valid & addrgen_operand_target_fu_i[0] == MFPU_ADDRGEN) begin

          // Valid data for the spill register
          idx_vaddr_valid_d = 1'b1;

          // Select the correct element, and zero extend it depending on vsew
          case (pe_req_q.eew_vs2)
            EW8: begin
              for (int unsigned b = 0; b < 8; b++)
                if (b == elm_ptr_q)
                  idx_vaddr = reduced_word[b*8 +: 8];
            end
            EW16: begin
              for (int unsigned h = 0; h < 4; h++)
                if (h == elm_ptr_q)
                  idx_vaddr = reduced_word[h*16 +: 16];
            end
            EW32: begin
              for (int unsigned w = 0; w < 2; w++)
                if (w == elm_ptr_q)
                  idx_vaddr = reduced_word[w*32 +: 32];
            end
            EW64: begin
              for (int unsigned d = 0; d < 1; d++)
                if (d == elm_ptr_q)
                  idx_vaddr = reduced_word[d*64 +: 64];
            end
            default: begin
              for (int unsigned b = 0; b < 8; b++)
                if (b == elm_ptr_q)
                  idx_vaddr = reduced_word[b*8 +: 8];
            end
          endcase

          // Compose the address
          idx_final_vaddr_d = pe_req_q.scalar_op + idx_vaddr;

          // When the data is accepted
          if (idx_vaddr_ready_q) begin
            // Consumed one element
            idx_op_cnt_d = idx_op_cnt_q - 1;
            // Have we finished a full NrLanes*64b word?
            // TODO: check for the need of vstart logic here
            if (elm_ptr_q == last_elm_subw_q) begin
              // Bump lane pointer
              elm_ptr_d       = '0;
              word_lane_ptr_d += 1;
              if (word_lane_ptr_q == NrLanes - 1) begin
                // Ready for the next full word
                addrgen_operand_ready_o = 1'b1;
              end
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

        if (idx_op_error_d || addrgen_req_ready || mmu_exception_d.valid) begin
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
          // In this case, we always get EEW-misaligned exceptions
          addrgen_exception_o.valid = 1'b1;
          addrgen_exception_o.cause = riscv::ILLEGAL_INSTR;
          addrgen_exception_o.tval  = '0;
        end
        // Propagate the exception from the MMU (if any)
        // NOTE: this would override idx_op_error_q
        if (mmu_exception_q.valid) begin
          addrgen_exception_o = mmu_exception_q;
        end
      end

      WAIT_LAST_TRANSLATION : begin
        if (last_translation_completed | mmu_exception_q.valid) begin
          // Acknowledge the indexed memory operation
          addrgen_ack_o     = 1'b1;
          addrgen_req_valid = '0;
          state_d           = IDLE;
          // Reset pointers
          elm_ptr_d       = '0;
          word_lane_ptr_d = '0;
          // Propagate the exception from the MMU (if any)
          addrgen_exception_o = mmu_exception_q;
        end
      end
    endcase

    // Immediately kill the load/store if the instruction was illegal
    if (addrgen_exception_o.valid && addrgen_ack_o) begin
      addrgen_illegal_load_o  =  is_load(pe_req_q.op) && (addrgen_exception_o.cause == riscv::ILLEGAL_INSTR);
      addrgen_illegal_store_o = !is_load(pe_req_q.op) && (addrgen_exception_o.cause == riscv::ILLEGAL_INSTR);
    end
  end : addr_generation

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
      addrgen_exception_vstart_o <= '0;
      mmu_exception_q    <= '0;
    end else begin
      state_q            <= state_d;
      pe_req_q           <= pe_req_d;
      vinsn_running_q    <= vinsn_running_d;
      word_lane_ptr_q    <= word_lane_ptr_d;
      elm_ptr_q          <= elm_ptr_d;
      idx_op_cnt_q       <= idx_op_cnt_d;
      last_elm_subw_q    <= last_elm_subw_d;
      idx_op_error_q     <= idx_op_error_d;
      addrgen_exception_vstart_o <= addrgen_exception_vstart_d;
      mmu_exception_q    <= mmu_exception_d;
    end
  end

  /////////////////////////////////////
  //  Support for misaligned stores  //
  /////////////////////////////////////

  localparam clog2_AxiStrobeWidth = $clog2(AxiDataWidth/8);

  // AXI Request Generation signals, declared here for convenience
  addrgen_req_t axi_addrgen_d, axi_addrgen_q;

  // Narrower AXI Data Byte-Width used for misaligned stores
  logic [clog2_AxiStrobeWidth-1:0]            narrow_axi_data_bwidth;
  // Helper signal to calculate the narrow_axi_data_bwidth
  // It carries information about the misalignment of the start address w.r.t. the AxiDataWidth
  logic [clog2_AxiStrobeWidth-1:0]            axi_addr_misalignment;
  // Number of trailing 0s of axi_addr_misalignment
  logic [idx_width(clog2_AxiStrobeWidth)-1:0] zeroes_cnt;

  // Get the misalignment information for this vector memory instruction
  assign axi_addr_misalignment = axi_addrgen_d.addr[clog2_AxiStrobeWidth-1:0];

  // Calculate the maximum number of Bytes we can send in a store-misaligned beat.
  // This number must be a power of 2 not to get misaligned wrt the pack of data that the
  // store unit receives from the lanes
  lzc #(
    .WIDTH(clog2_AxiStrobeWidth),
    .MODE (1'b0                  )
  ) i_lzc (
    .in_i   (axi_addr_misalignment),
    .cnt_o  (zeroes_cnt           ),
    .empty_o(/* Unconnected */    )
  );

  // Effective AXI data width for misaligned stores
  assign narrow_axi_data_bwidth = (AxiDataWidth/8) >> (clog2_AxiStrobeWidth - zeroes_cnt);

  //////////////////////////////
  //  AXI Request Generation  //
  //////////////////////////////

  enum logic [2:0] {
    AXI_ADDRGEN_IDLE,
    AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED,    // Misaligned vector store to AxiDataWidth/8, needs special treatement
    AXI_ADDRGEN_WAITING_CORE_STORE_PENDING, // Wait until (core_st_pending_i == 0)
    AXI_ADDRGEN_REQUESTING,                 // Perform AW/AR transactions and push addrgen_req to VSTU/VLDU
    AXI_ADDRGEN_WAIT_TRANSLATION            // Wait for MMU to ack back
  } axi_addrgen_state_d, axi_addrgen_state_q;

  axi_addr_t aligned_start_addr_d, aligned_start_addr_q;
  axi_addr_t aligned_next_start_addr_d, aligned_next_start_addr_q;
  axi_addr_t aligned_end_addr_d, aligned_end_addr_q;

  // MSb of the next-next page (page selector for page 2 positions after the current one)
  logic [($bits(aligned_start_addr_d) - 12)-1:0] next_2page_msb_d, next_2page_msb_q;

  logic [clog2_AxiStrobeWidth:0]            eff_axi_dw_d, eff_axi_dw_q;
  logic [idx_width(clog2_AxiStrobeWidth):0] eff_axi_dw_log_d, eff_axi_dw_log_q;

  function automatic void set_end_addr (
      input  logic [($bits(axi_addr_t) - 12)-1:0]       next_2page_msb,
      input  int unsigned                               num_bytes,
      input  axi_addr_t                                 addr,
      input  logic [clog2_AxiStrobeWidth:0]             eff_axi_dw,
      input  logic [idx_width(clog2_AxiStrobeWidth):0]  eff_axi_dw_log,
      input  axi_addr_t                                 aligned_start_addr,
      output axi_addr_t                                 aligned_end_addr,
      output axi_addr_t                                 aligned_next_start_addr
  );

    automatic int unsigned max_burst_bytes = 256 << eff_axi_dw_log;

    // The final address can be found similarly...
    if (num_bytes >= max_burst_bytes) begin
        aligned_next_start_addr = aligned_addr(addr + max_burst_bytes, eff_axi_dw_log);
    end else begin
        aligned_next_start_addr = aligned_addr(addr + num_bytes - 1, eff_axi_dw_log) + eff_axi_dw;
    end
    aligned_end_addr = aligned_next_start_addr - 1;

    // But since AXI requests are aligned in 4 KiB pages, aligned_end_addr must be in the
    // same page as aligned_start_addr
    if (aligned_start_addr[AxiAddrWidth-1:12] != aligned_end_addr[AxiAddrWidth-1:12]) begin
        aligned_end_addr        = {aligned_start_addr[AxiAddrWidth-1:12], 12'hFFF};
        aligned_next_start_addr = {                     next_2page_msb  , 12'h000};
    end
  endfunction

  always_comb begin: axi_addrgen
    // Maintain state
    axi_addrgen_state_d = axi_addrgen_state_q;
    axi_addrgen_d       = axi_addrgen_q;

    aligned_start_addr_d      = aligned_start_addr_q;
    aligned_next_start_addr_d = aligned_next_start_addr_q;
    aligned_end_addr_d        = aligned_end_addr_q;

    next_2page_msb_d = next_2page_msb_q;

    eff_axi_dw_d     = eff_axi_dw_q;
    eff_axi_dw_log_d = eff_axi_dw_log_q;

    idx_vaddr_ready_d    = 1'b0;
    addrgen_exception_vstart_d  = '0;

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

    // MMU
    mmu_exception_d = mmu_exception_q;
    mmu_req_o       = 1'b0;
    mmu_vaddr_o     = '0;
    mmu_is_store_o  = 1'b0;

    // For addrgen FSM
    last_translation_completed = 1'b0;

    case (axi_addrgen_state_q)
      AXI_ADDRGEN_IDLE: begin : axi_addrgen_state_AXI_ADDRGEN_IDLE
        // Clear exception buffer
        mmu_exception_d = '0;

        if (addrgen_req_valid) begin
          axi_addrgen_d       = addrgen_req;
          axi_addrgen_state_d = core_st_pending_i ? AXI_ADDRGEN_WAITING_CORE_STORE_PENDING : AXI_ADDRGEN_REQUESTING;

          // In case of a misaligned store, reduce the effective width of the AXI transaction,
          // since the store unit does not support misalignments between the AXI bus and the lanes
          if (axi_addrgen_d.vstart != 0 && !axi_addrgen_d.is_load) begin
            // vstart > 0 can create problems similar to the ones a misalignment would create.
            // Limit the effective AXI bus width to the element width to avoid problems.
            axi_addrgen_state_d = AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED;

            eff_axi_dw_d     = 1 << axi_addrgen_d.vew;
            eff_axi_dw_log_d = axi_addrgen_d.vew;
          end else if ((axi_addrgen_d.addr[clog2_AxiStrobeWidth-1:0] != '0) && !axi_addrgen_d.is_load) begin
            // Calculate the start and the end addresses in the AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED state
            axi_addrgen_state_d = AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED;

            eff_axi_dw_d     = {1'b0, narrow_axi_data_bwidth};
            eff_axi_dw_log_d = zeroes_cnt;
          end else begin
            eff_axi_dw_d     = AxiDataWidth/8;
            eff_axi_dw_log_d = clog2_AxiStrobeWidth;
          end

          // The start address is found by aligning the original request address by the width of
          // the memory interface.
          aligned_start_addr_d = aligned_addr(axi_addrgen_d.addr, clog2_AxiStrobeWidth);
          // Pre-calculate the next_2page_msb. This should not require much energy if the addr
          // has zeroes in the upper positions.
          // We can use this also for the misaligned address calculation, as the next 2 page msb
          // will be the same either way.
          next_2page_msb_d = aligned_start_addr_d[AxiAddrWidth-1:12] + 1;
          // The final address can be found similarly...
          set_end_addr (
            next_2page_msb_d,
            (axi_addrgen_d.len << unsigned'(axi_addrgen_d.vew)),
            axi_addrgen_d.addr,
            AxiDataWidth/8,
            clog2_AxiStrobeWidth,
            aligned_start_addr_d,
            aligned_end_addr_d,
            aligned_next_start_addr_d
          );
        end
      end : axi_addrgen_state_AXI_ADDRGEN_IDLE

      AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED: begin : axi_addrgen_state_AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED
        axi_addrgen_state_d = core_st_pending_i ? AXI_ADDRGEN_WAITING_CORE_STORE_PENDING : AXI_ADDRGEN_REQUESTING;

        // The start address is found by aligning the original request address by the width of
        // the memory interface.
        aligned_start_addr_d = aligned_addr(axi_addrgen_q.addr, eff_axi_dw_log_q);

        set_end_addr (
          next_2page_msb_q,
          (axi_addrgen_q.len << unsigned'(axi_addrgen_q.vew)),
          axi_addrgen_q.addr,
          eff_axi_dw_q,
          eff_axi_dw_log_q,
          aligned_start_addr_d,
          aligned_end_addr_d,
          aligned_next_start_addr_d
        );
      end : axi_addrgen_state_AXI_ADDRGEN_AXI_DW_STORE_MISALIGNED

      AXI_ADDRGEN_WAITING_CORE_STORE_PENDING: begin : axi_addrgen_state_AXI_ADDRGEN_WAITING_CORE_STORE_PENDING
        if (!core_st_pending_i) begin
          axi_addrgen_state_d = AXI_ADDRGEN_REQUESTING;
        end
      end : axi_addrgen_state_AXI_ADDRGEN_WAITING_CORE_STORE_PENDING

      AXI_ADDRGEN_REQUESTING : begin : axi_addrgen_state_AXI_ADDRGEN_REQUESTING
        automatic logic axi_ax_ready = (axi_addrgen_q.is_load && axi_ar_ready_i) || (!axi_addrgen_q.is_load && axi_aw_ready_i);

        // Pre-calculate the next_2page_msb. This should not require much energy if the addr
        // has zeroes in the upper positions.
        next_2page_msb_d = aligned_next_start_addr_q[AxiAddrWidth-1:12] + 1;

        // Before starting a transaction on a different channel, wait the formers to complete
        // Otherwise, the ordering of the responses is not guaranteed, and with the current
        // implementation we can incur in deadlocks
        // NOTE: this might be referring to an obsolete axi_cut implementation
        if (axi_addrgen_queue_empty || (axi_addrgen_req_o.is_load && axi_addrgen_q.is_load) ||
             (~axi_addrgen_req_o.is_load && ~axi_addrgen_q.is_load)) begin : axi_ax_idle
          if (!axi_addrgen_queue_full && axi_ax_ready) begin : start_req
            automatic logic [riscv::PLEN-1:0] paddr;

            // Mux target address
            paddr = (en_ld_st_translation_i) ? mmu_paddr_i : axi_addrgen_q.addr;

            // If we have a translation already, don't try to request another translation back to back
            if (en_ld_st_translation_i & !mmu_valid_i) begin : translation_req
              // Request an address translation
              mmu_req_o           = 1'b1;
              mmu_vaddr_o         = (state_q == ADDRGEN_IDX_OP) ? idx_final_vaddr_q : axi_addrgen_q.addr;
              mmu_is_store_o      = !axi_addrgen_q.is_load;
            end : translation_req
            // Either we got a valid address translation from the MMU
            // or virtual memory is disabled
            else if ((mmu_valid_i && !mmu_exception_i.valid) || !en_ld_st_translation_i) begin : paddr_valid
              if (axi_addrgen_q.is_burst) begin : unit_stride
                /////////////////////////
                //  Unit-Stride access //
                /////////////////////////

                // NOTE: all these variables could be narrowed to the minimum number of bits
                automatic int unsigned num_beats;
                automatic int unsigned num_bytes;
                automatic int unsigned burst_len_bytes;
                automatic int unsigned axi_addrgen_bytes;

                // AXI burst length
                automatic int unsigned burst_length;

                // 1 - AXI bursts are at most 256 beats long.
                burst_length = 256;
                // 2 - The AXI burst length cannot be longer than the number of beats required
                //     to access the memory regions between aligned_start_addr and
                //     aligned_end_addr
                num_beats = ((aligned_end_addr_q[11:0] - aligned_start_addr_q[11:0]) >> eff_axi_dw_log_q) + 1;
                if (burst_length > num_beats) begin
                  burst_length = num_beats;
                end

                // AR Channel
                if (axi_addrgen_q.is_load) begin
                  axi_ar_o = '{
                    addr   : paddr,
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
                    addr   : paddr,
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
                  addr         : paddr,
                  len          : burst_length - 1,
                  size         : eff_axi_dw_log_q,
                  is_load      : axi_addrgen_q.is_load,
                  is_exception : 1'b0
                };
                axi_addrgen_queue_push = 1'b1;

                // Account for the requested operands
                num_bytes = ((aligned_end_addr_q[11:0] - axi_addrgen_q.addr[11:0] + 1) >> unsigned'(axi_addrgen_q.vew));
                if (axi_addrgen_q.len >= num_bytes) begin
                  axi_addrgen_d.len = axi_addrgen_q.len - num_bytes;
                end
                else begin
                  axi_addrgen_d.len = 0;
                end
                axi_addrgen_d.addr = aligned_next_start_addr_q;

                // Calculate the addresses for the next iteration
                // TODO: test this for SEW!=64, otherwise this computation is never used
                // The start address is found by aligning the original request address by the width of
                // the memory interface. In our case, we have it already.
                aligned_start_addr_d = axi_addrgen_d.addr;
                // The final address can be found similarly.
                // How many B we requested? No more than (256 << burst_len_bytes)
                burst_len_bytes   = (256 << eff_axi_dw_log_q);
                axi_addrgen_bytes = (axi_addrgen_d.len << unsigned'(axi_addrgen_q.vew));
                set_end_addr (
                  next_2page_msb_d,
                  (axi_addrgen_d.len << unsigned'(axi_addrgen_d.vew)),
                  aligned_start_addr_d,
                  eff_axi_dw_q,
                  eff_axi_dw_log_q,
                  aligned_start_addr_d,
                  aligned_end_addr_d,
                  aligned_next_start_addr_d
                );
              end : unit_stride
              else if (state_q != ADDRGEN_IDX_OP) begin : strided
                /////////////////////
                //  Strided access //
                /////////////////////
                // AR Channel
                if (axi_addrgen_q.is_load) begin
                  axi_ar_o = '{
                    addr   : paddr,
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
                    addr   : paddr,
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
                  addr         : paddr,
                  size         : axi_addrgen_q.vew,
                  len          : 0,
                  is_load      : axi_addrgen_q.is_load,
                  is_exception : 1'b0
                };
                axi_addrgen_queue_push = 1'b1;

                // Account for the requested operands
                axi_addrgen_d.len  = axi_addrgen_q.len - 1;
                // Calculate the addresses for the next iteration, adding the correct stride
                axi_addrgen_d.addr = axi_addrgen_q.addr + axi_addrgen_q.stride;
              end : strided
              else begin : indexed
                // NOTE: address translation is not yet been implemented/tested for indexed

                automatic logic [riscv::PLEN-1:0] idx_final_paddr;
                //////////////////////
                //  Indexed access  //
                //////////////////////

                // TODO: check if idx_vaddr_valid_q is stable
                if (idx_vaddr_valid_q) begin : if_idx_vaddr_valid_q

                  // Check if the virtual address generates an exception
                  // NOTE: we can do this even before address translation, since the
                  //       page offset (2^12) is the same for both physical and virtual addresses
                  if (is_addr_error(idx_final_vaddr_q, axi_addrgen_q.vew)) begin : eew_misaligned_error
                    // Generate an error
                    idx_op_error_d          = 1'b1;
                    // Forward next vstart info to the dispatcher
                    addrgen_exception_vstart_d  = addrgen_req.len - axi_addrgen_q.len - 1;
                    addrgen_req_ready       = 1'b1;
                    axi_addrgen_state_d     = AXI_ADDRGEN_IDLE;
                  end : eew_misaligned_error
                  else begin : aligned_vaddress
                    // Mux target address
                    idx_final_paddr = (en_ld_st_translation_i) ? mmu_paddr_i : idx_final_vaddr_q;

                    // We consumed a word
                    idx_vaddr_ready_d = 1'b1;

                    // AR Channel
                    if (axi_addrgen_q.is_load) begin
                      axi_ar_o = '{
                        addr   : idx_final_paddr,
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
                        addr   : idx_final_paddr,
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
                      addr         : idx_final_paddr,
                      size         : axi_addrgen_q.vew,
                      len          : 0,
                      is_load      : axi_addrgen_q.is_load,
                      is_exception : 1'b0
                    };
                    axi_addrgen_queue_push = 1'b1;

                    // Account for the requested operands
                    axi_addrgen_d.len = axi_addrgen_q.len - 1;
                  end : aligned_vaddress
                end : if_idx_vaddr_valid_q
              end : indexed
            end : paddr_valid

            // Finished generating AXI requests
            if (axi_addrgen_d.len == 0) begin : finished
              addrgen_req_ready   = 1'b1;
              axi_addrgen_state_d = AXI_ADDRGEN_IDLE;
              if (en_ld_st_translation_i & !mmu_exception_i.valid) begin : has_last_translation_completed
                // Signal the other FSM
                last_translation_completed = 1'b1;
              end : has_last_translation_completed
            end : finished

            // Check for MMU exception
            if (mmu_exception_i.valid) begin : mmu_exception_valid
              // Sample the exception
              mmu_exception_d = mmu_exception_i;

              // Send the exception to the load or store unit
              axi_addrgen_queue = '{
                addr         : paddr,
                size         : axi_addrgen_q.vew,
                len          : 0,
                is_load      : axi_addrgen_q.is_load,
                is_exception : 1'b1
              };
              axi_addrgen_queue_push = 1'b1;

              // Set vstart: vl minus how many elements we have left
              // NOTE: this added complexity only comes from the fact that the beat counting
              //       implementation counts down from the expected length, instead that up from zero
              addrgen_exception_vstart_d  = pe_req_q.vl - axi_addrgen_q.len;

              // Mute new requests
              mmu_req_o = 1'b0;

              // End exection and clear instruction metadata
              axi_addrgen_d.len = 0;
              axi_addrgen_state_d = AXI_ADDRGEN_IDLE;
              // Signal the other FSM
              addrgen_req_ready   = 1'b1;
            end : mmu_exception_valid
          end : start_req
        end : axi_ax_idle
      end : axi_addrgen_state_AXI_ADDRGEN_REQUESTING

    endcase // axi_addrgen_state_q
  end: axi_addrgen

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      axi_addrgen_state_q       <= AXI_ADDRGEN_IDLE;
      axi_addrgen_q             <= '0;
      aligned_start_addr_q      <= '0;
      aligned_next_start_addr_q <= '0;
      aligned_end_addr_q        <= '0;
      eff_axi_dw_q              <= '0;
      eff_axi_dw_log_q          <= '0;
      next_2page_msb_q          <= '0;
    end else begin
      axi_addrgen_state_q       <= axi_addrgen_state_d;
      axi_addrgen_q             <= axi_addrgen_d;
      aligned_start_addr_q      <= aligned_start_addr_d;
      aligned_next_start_addr_q <= aligned_next_start_addr_d;
      aligned_end_addr_q        <= aligned_end_addr_d;
      eff_axi_dw_q              <= eff_axi_dw_d;
      eff_axi_dw_log_q          <= eff_axi_dw_log_d;
      next_2page_msb_q          <= next_2page_msb_d;
    end
  end

endmodule : addrgen
