// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's dispatcher interfaces Ariane's requests with the vector lanes.
// It also acknowledges instructions back to Ariane, perhaps with a
// response or an error message.

module ara_dispatcher import ara_pkg::*; import rvv_pkg::*; #(
    parameter int           unsigned NrLanes      = 0,
    parameter int           unsigned VLEN         = 0,
    parameter type                   ara_req_t    = logic,
    parameter type                   ara_resp_t   = logic,
    // Support for floating-point data types
    parameter fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter fpext_support_e        FPExtSupport = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter fixpt_support_e        FixPtSupport = FixedPointEnable,
    // Support for segment memory operations
    parameter seg_support_e          SegSupport   = SegSupportEnable,
    // Dependent parameters: DO NOT CHANGE
    localparam type                  vlen_t       = logic[$clog2(VLEN+1)-1:0],
    localparam int          unsigned VLENB        = VLEN / 8
  ) (
    // Clock and reset
    input  logic                                 clk_i,
    input  logic                                 rst_ni,
    // Interfaces with Ariane
    input  accelerator_req_t                     acc_req_i,
    output accelerator_resp_t                    acc_resp_o,
    // Interface with Ara's backend
    output ara_req_t                             ara_req_o,
    output logic                                 ara_req_valid_o,
    input  logic                                 ara_req_ready_i,
    input  ara_resp_t                            ara_resp_i,
    input  logic                                 ara_resp_valid_i,
    input  logic                                 ara_idle_i,
    // Interface with the lanes
    input  logic              [NrLanes-1:0][4:0] fflags_ex_i,
    input  logic              [NrLanes-1:0]      fflags_ex_valid_i,
    // Rounding mode is shared between all lanes
    input  logic              [NrLanes-1:0]      vxsat_flag_i,
    output vxrm_t             [NrLanes-1:0]      alu_vxrm_o,
    // Interface with the Vector Store Unit
    output logic                                 core_st_pending_o,
    input  logic                                 load_complete_i,
    input  logic                                 store_complete_i,
    input  logic                                 store_pending_i
  );

  import cf_math_pkg::idx_width;

  `include "common_cells/registers.svh"

  assign core_st_pending_o = acc_req_i.store_pending;

  ////////////
  //  CSRs  //
  ////////////

  vlen_t  csr_vstart_d, csr_vstart_q;
  vlen_t  csr_vl_d, csr_vl_q;
  vtype_t csr_vtype_d, csr_vtype_q;
  vxsat_e csr_vxsat_d, csr_vxsat_q;
  vxrm_t  csr_vxrm_d, csr_vxrm_q;

  `FF(csr_vstart_q, csr_vstart_d, '0)
  `FF(csr_vl_q, csr_vl_d, '0)
  `FF(csr_vtype_q, csr_vtype_d, '{vill: 1'b1, default: '0})
  `FF(csr_vxsat_q, csr_vxsat_d, '0)
  `FF(csr_vxrm_q, csr_vxrm_d, '0)
  // Converts between the internal representation of `vtype_t` and the full XLEN-bit CSR.
  function automatic riscv::xlen_t xlen_vtype(vtype_t vtype);
    xlen_vtype = {vtype.vill, {riscv::XLEN-9{1'b0}}, vtype.vma, vtype.vta, vtype.vsew,
      vtype.vlmul[2:0]};
  endfunction: xlen_vtype

  // Converts between the XLEN-bit vtype CSR and its internal representation
  function automatic vtype_t vtype_xlen(riscv::xlen_t xlen);
    vtype_xlen = '{
      vill  : xlen[riscv::XLEN-1],
      vma   : xlen[7],
      vta   : xlen[6],
      vsew  : vew_e'(xlen[5:3]),
      vlmul : vlmul_e'(xlen[2:0])
    };
  endfunction : vtype_xlen

  // Calculates next(lmul)
  function automatic vlmul_e next_lmul(vlmul_e lmul);
    unique case (lmul)
      LMUL_1_8: next_lmul = LMUL_1_4;
      LMUL_1_4: next_lmul = LMUL_1_2;
      LMUL_1_2: next_lmul = LMUL_1;
      LMUL_1  : next_lmul = LMUL_2;
      LMUL_2  : next_lmul = LMUL_4;
      LMUL_4  : next_lmul = LMUL_8;
      default : next_lmul = LMUL_RSVD;
    endcase
  endfunction : next_lmul

  // Calculates prev(prev(ew))
  function automatic vew_e prev_prev_ew(vew_e ew);
    unique case (ew)
      EW64: prev_prev_ew    = EW16;
      EW32: prev_prev_ew    = EW8;
      default: prev_prev_ew = EW1024;
    endcase
  endfunction : prev_prev_ew

  /////////////////////////
  //  Backend interface  //
  /////////////////////////

  ara_req_t ara_req, ara_req_d;
  logic     ara_req_valid, ara_req_valid_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ara_req_o       <= '0;
      ara_req_valid_o <= 1'b0;
    end else begin
      if (ara_req_ready_i) begin
        ara_req_o       <= ara_req_d;
        ara_req_valid_o <= ara_req_valid_d;
      end
    end
  end

  /////////////
  //  State  //
  /////////////

  // The backend can either be in normal operation, waiting for Ara to be idle before issuing new
  // operations, or injecting a reshuffling uop.
  // IDLE can happen, for example, once the vlmul has changed.
  // RESHUFFLE can happen when an instruction writes a register with != EEW
  typedef enum logic [1:0] {
    NORMAL_OPERATION,
    WAIT_IDLE,
    RESHUFFLE
  } state_e;
  state_e state_d, state_q, state_qq;
  // state_qq is the previous state signal. Useful to know from which state we come from.

  // We need to memorize the element width used to store each vector on the lanes, so that we are
  // able to deshuffle it when needed.
  rvv_pkg::vew_e [31:0] eew_d, eew_q;
  // eew buffers for reshuffling
  rvv_pkg::vew_e reshuffle_eew_vs1_d, reshuffle_eew_vs1_q;
  rvv_pkg::vew_e reshuffle_eew_vs2_d, reshuffle_eew_vs2_q;
  rvv_pkg::vew_e reshuffle_eew_vd_d, reshuffle_eew_vd_q;
  // If the reg was not written, the content is unknown. No need to reshuffle
  // when writing with != EEW
  logic [31:0] eew_valid_d, eew_valid_q;
  // Save eew information before reshuffling
  rvv_pkg::vew_e eew_old_buffer_d, eew_old_buffer_q, eew_new_buffer_d, eew_new_buffer_q;
  // Helpers to handle reshuffling with LMUL > 1
  logic [2:0] rs_lmul_cnt_d, rs_lmul_cnt_q;
  logic [2:0] rs_lmul_cnt_limit_d, rs_lmul_cnt_limit_q;
  logic rs_mask_request_d, rs_mask_request_q;
  // Save vreg to be reshuffled before reshuffling
  logic [4:0] vs_buffer_d, vs_buffer_q;
  // Keep track of the registers to be reshuffled |vs1|vs2|vd|
  logic [2:0] reshuffle_req_d, reshuffle_req_q;
  // Segment memory operations end or ongoing?
  logic seg_mem_op_end, pending_seg_mem_op_d, pending_seg_mem_op_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q              <= NORMAL_OPERATION;
      state_qq             <= NORMAL_OPERATION;
      eew_q                <= '{default: rvv_pkg::EW8};
      eew_valid_q          <= '0;
      eew_old_buffer_q     <= rvv_pkg::EW8;
      eew_new_buffer_q     <= rvv_pkg::EW8;
      vs_buffer_q          <= '0;
      reshuffle_req_q      <= '0;
      rs_lmul_cnt_q        <= '0;
      rs_lmul_cnt_limit_q  <= '0;
      rs_mask_request_q    <= 1'b0;
      reshuffle_eew_vs1_q  <= rvv_pkg::EW8;
      reshuffle_eew_vs2_q  <= rvv_pkg::EW8;
      reshuffle_eew_vd_q   <= rvv_pkg::EW8;
      pending_seg_mem_op_q <= 1'b0;
    end else begin
      state_q              <= state_d;
      state_qq             <= state_q;
      eew_q                <= eew_d;
      eew_valid_q          <= eew_valid_d;
      eew_old_buffer_q     <= eew_old_buffer_d;
      eew_new_buffer_q     <= eew_new_buffer_d;
      vs_buffer_q          <= vs_buffer_d;
      reshuffle_req_q      <= reshuffle_req_d;
      rs_lmul_cnt_q        <= rs_lmul_cnt_d;
      rs_lmul_cnt_limit_q  <= rs_lmul_cnt_limit_d;
      rs_mask_request_q    <= rs_mask_request_d;
      reshuffle_eew_vs1_q  <= reshuffle_eew_vs1_d;
      reshuffle_eew_vs2_q  <= reshuffle_eew_vs2_d;
      reshuffle_eew_vd_q   <= reshuffle_eew_vd_d;
      pending_seg_mem_op_q <= pending_seg_mem_op_d;
    end
  end

  // We need to know if the source operands have a different LMUL constraint than the destination
  // register
  rvv_pkg::vlmul_e lmul_vs2, lmul_vs1;

  // Helper signals to discriminate between config/csr, load/store instructions and the others
  logic is_config, is_vload, is_vstore;
  // Whole-register memory-ops / move should be executed even when vl == 0
  logic ignore_zero_vl_check;
  // Helper signals to identify memory operations with vl == 0. They must acknoledge Ariane to update
  // its counters of pending memory operations
  // Ara should tell Ariane when a memory operation is completed, so that it can modify
  // its pending load/store counters.
  // A memory operation can be completed both when it is over and when csr_vl_q == 0. In the latter case,
  // Ara's decoder answers immediately, and this can cause a collision with an answer from Ara's VLSU.
  // To avoid collisions, we give precedence to the VLSU, and we delay the csr_vl_q == 0 memory op
  // completion signal if a collision occurs
  logic load_zero_vl, store_zero_vl;
  // Do not checks vregs validity against current LMUL
  logic skip_lmul_checks;
  logic skip_vs1_lmul_checks;
  // Are we decoding?
  logic is_decoding;
  // Is this an in-lane operation?
  logic in_lane_op;
  // If the vslideup offset is greater than csr_vl_q, the vslideup has no effects
  logic null_vslideup;

  // Pipeline the VLSU's load and store complete signals, for timing reasons
  logic load_complete, load_complete_q;
  logic store_complete, store_complete_q;
  logic illegal_insn_load, illegal_insn_store;
  `FF(load_complete_q, load_complete || illegal_insn_load, 1'b0)
  `FF(store_complete_q, store_complete || illegal_insn_store, 1'b0)

  // NP2 Slide support
  logic is_stride_np2;
  logic [idx_width(idx_width(VLENB << 3)):0] sldu_popc;

  // Is the stride power of two?
  popcount #(
    .INPUT_WIDTH (idx_width(VLENB << 3))
  ) i_np2_stride (
    .data_i    (ara_req.stride[idx_width(VLENB << 3)-1:0]  ),
    .popcount_o(sldu_popc                                  )
  );

  assign is_stride_np2 = sldu_popc > 1;

  // Segment-memory instruction sequencer
  // Decompose the segment memory operations into non-segment memory operations
  // This is a low-impact and low-performance implementation
  logic is_segment_mem_op;
  logic illegal_insn;

  // The handshake signals are just passed-through if the insn is non-segment
  ara_resp_t ara_resp;
  logic ara_resp_valid;

  segment_sequencer #(
    .SegSupport(SegSupport),
    .ara_req_t (ara_req_t ),
    .ara_resp_t(ara_resp_t)
  ) i_segment_sequencer (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ara_idle_i(ara_idle_i),
    .is_segment_mem_op_i(is_segment_mem_op),
    .illegal_insn_i(illegal_insn),
    .is_vload_i(is_vload),
    .seg_mem_op_end_o(seg_mem_op_end),
    .load_complete_i(load_complete_i),
    .load_complete_o(load_complete),
    .store_complete_i(store_complete_i),
    .store_complete_o(store_complete),
    .ara_req_i(ara_req),
    .ara_req_o(ara_req_d),
    .ara_req_valid_i(ara_req_valid),
    .ara_req_valid_o(ara_req_valid_d),
    .ara_req_ready_i(ara_req_ready_i),
    .ara_resp_i(ara_resp_i),
    .ara_resp_o(ara_resp),
    .ara_resp_valid_i(ara_resp_valid_i),
    .ara_resp_valid_o(ara_resp_valid)
  );

  ///////////////
  //  Decoder  //
  ///////////////

  elen_t vfmvfs_result;

  always_comb begin: p_decoder
    // Default values
    csr_vstart_d     = csr_vstart_q;
    csr_vl_d         = csr_vl_q;
    csr_vtype_d      = csr_vtype_q;
    state_d      = state_q;
    eew_d        = eew_q;
    eew_valid_d  = eew_valid_q;
    lmul_vs2     = csr_vtype_q.vlmul;
    lmul_vs1     = csr_vtype_q.vlmul;

    reshuffle_req_d     = reshuffle_req_q;
    eew_old_buffer_d    = eew_old_buffer_q;
    eew_new_buffer_d    = eew_new_buffer_q;
    vs_buffer_d         = vs_buffer_q;
    reshuffle_eew_vs1_d = reshuffle_eew_vs1_q;
    reshuffle_eew_vs2_d = reshuffle_eew_vs2_q;
    reshuffle_eew_vd_d  = reshuffle_eew_vd_q;

    pending_seg_mem_op_d = pending_seg_mem_op_q;

    rs_lmul_cnt_d       = '0;
    rs_lmul_cnt_limit_d = '0;
    rs_mask_request_d   = 1'b0;

    illegal_insn = 1'b0;
    illegal_insn_load  = 1'b0;
    illegal_insn_store = 1'b0;
    csr_vxsat_d      = csr_vxsat_q;
    csr_vxrm_d       = csr_vxrm_q;

    is_vload      = 1'b0;
    is_vstore     = 1'b0;
    load_zero_vl  = 1'b0;
    store_zero_vl = 1'b0;

    skip_lmul_checks     = 1'b0;
    skip_vs1_lmul_checks = 1'b0;

    null_vslideup = 1'b0;

    is_decoding     = 1'b0;
    in_lane_op      = 1'b0;

    is_segment_mem_op = 1'b0;

    acc_resp_o       = '{
      trans_id      : acc_req_i.trans_id,
      load_complete : load_zero_vl | load_complete_q,
      store_complete: store_zero_vl | store_complete_q,
      store_pending : store_pending_i,
      fflags_valid  : |fflags_ex_valid_i,
      default       : '0
    };
    acc_resp_o.req_ready  = 1'b0;
    acc_resp_o.resp_valid = 1'b0;

    // fflags
    for (int lane = 0; lane < NrLanes; lane++) acc_resp_o.fflags |= fflags_ex_i[lane];

    ara_req = '{
      vl           : csr_vl_q,
      vstart       : csr_vstart_q,
      vtype        : csr_vtype_q,
      emul         : csr_vtype_q.vlmul,
      eew_vs1      : csr_vtype_q.vsew,
      eew_vs2      : csr_vtype_q.vsew,
      eew_vd_op    : csr_vtype_q.vsew,
      eew_vmask    : eew_q[VMASK],
      cvt_resize   : CVT_SAME,
      default      : '0
    };
    ara_req_valid = 1'b0;

    is_config            = 1'b0;
    ignore_zero_vl_check = 1'b0;

    // Saturation in any lane will raise vxsat flag
    csr_vxsat_d |= |vxsat_flag_i;
    // Fixed-point rounding mode is applied to all lanes
    for (int lane = 0; lane < NrLanes; lane++) alu_vxrm_o[lane] = csr_vxrm_q;
    // Rounding mode is shared between all lanes
    for (int lane = 0; lane < NrLanes; lane++) acc_resp_o.fflags |= fflags_ex_i[lane];
    // Special states
    case (state_q)
      // Is Ara idle?
      WAIT_IDLE: begin
        if (ara_idle_i) state_d = NORMAL_OPERATION;
      end

      // Inject a reshuffle instruction
      RESHUFFLE: begin
        // Instruction is of one of the RVV types
        automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

        // Stall the interface, wait for the backend to accept the injected uop
        acc_resp_o.req_ready  = 1'b0;
        acc_resp_o.resp_valid = 1'b0;

        // Handle LMUL > 1
        rs_lmul_cnt_d       = rs_lmul_cnt_q;
        rs_lmul_cnt_limit_d = rs_lmul_cnt_limit_q;
        rs_mask_request_d   = 1'b0;

        // Every single reshuffle request refers to LMUL == 1
        ara_req.emul = LMUL_1;

        // vstart is always 0 for a reshuffle
        ara_req.vstart = '0;

        // These generate a reshuffle request to Ara's backend
        // When LMUL > 1, not all the regs that compose a large
        // register should always be reshuffled
        ara_req_valid         = ~rs_mask_request_q;
        ara_req.use_scalar_op = 1'b1;
        ara_req.vs2           = vs_buffer_q;
        ara_req.eew_vs2       = eew_old_buffer_q;
        ara_req.use_vs2       = 1'b1;
        ara_req.vd            = vs_buffer_q;
        ara_req.use_vd        = 1'b1;
        ara_req.op            = ara_pkg::VSLIDEDOWN;
        ara_req.stride        = '0;
        ara_req.use_scalar_op = 1'b0;
        // Unmasked: reshuffle everything
        ara_req.vm            = 1'b1;
        // Shuffle the whole reg (vl refers to current vsew)
        ara_req.vtype.vsew    = eew_new_buffer_q;
        // Always reshuffle one vreg at a time
        ara_req.vl            = VLENB >> ara_req.vtype.vsew;
        // Vl refers to current system vsew but operand requesters
        // will fetch from a register with a different eew
        ara_req.scale_vl      = 1'b1;

        // Backend ready - Decide what to do next
        if (ara_req_ready_i) begin
          // Register completely reshuffled
          if (rs_lmul_cnt_q == rs_lmul_cnt_limit_q) begin
            rs_lmul_cnt_d = 0;

            // Delete the already processed vector register from the notebook -> |vs1|vs2|vd|
            unique casez (reshuffle_req_q)
              3'b??1: reshuffle_req_d = {reshuffle_req_q[2:1], 1'b0};
              3'b?10: reshuffle_req_d = {reshuffle_req_q[2  ], 2'b0};
              3'b100: reshuffle_req_d =                        3'b0 ;
              default:;
            endcase

            // Prepare the information to reshuffle the vector registers during the next cycles
            // Reshuffle in the following order: vd, v2, v1. The order is arbitrary.
            // If we are here, vd has been already reshuffled.
            unique casez (reshuffle_req_d)
              3'b?10: begin
                eew_old_buffer_d = eew_q[insn.vmem_type.rs2];
                eew_new_buffer_d = reshuffle_eew_vs2_q;
                vs_buffer_d      = insn.varith_type.rs2;
              end
              3'b100: begin
                eew_old_buffer_d = eew_q[insn.vmem_type.rs1];
                eew_new_buffer_d = reshuffle_eew_vs1_q;
                vs_buffer_d      = insn.varith_type.rs1;
              end
              default:;
            endcase

            if (reshuffle_req_d == 3'b0) begin
              // If LMUL_X has X > 1, Ara can inject different reshuffle ops during RESHUFFLE,
              // one per LMUL_1-register that needs to be reshuffled. In mixed cases, we have
              // multiple instructions that reshuffle parts of the original LMUL_X-register
              // (e.g., LMUL_8, vd = v0, eew = 64, and only v1 and v5 have eew = 64). In this
              // case, the dependency of the next LMUL_8 instruction on v0 should be on all
              // the reshuffle micro operations. This is not possible with the current architecture.
              // Therefore, we either set the dependency on the very last instruction only, or
              // we just wait until the reshuffle is over.
              // The best optimization would be injecting contiguous reshuffles with X > 1 and
              // an extended vl. If we injected only one reshuffle, we can skip the wait idle.
              if (csr_vtype_q.vlmul != LMUL_1) state_d = WAIT_IDLE;
              else state_d = NORMAL_OPERATION;
            end
          // The register is not completely reshuffled (LMUL > 1)
          end else begin
            // Count up
            rs_lmul_cnt_d = rs_lmul_cnt_q + 1;

            // Prepare the information to reshuffle the vector registers during the next cycles
            // Since LMUL > 1, we should go on and check if the next register needs a reshuffle
            // at all.
            unique casez (reshuffle_req_d)
              3'b??1: begin
                vs_buffer_d      = vs_buffer_q + 1;
                eew_old_buffer_d = eew_q[vs_buffer_d];
                eew_new_buffer_d = reshuffle_eew_vd_q;
              end
              3'b?10: begin
                vs_buffer_d      = vs_buffer_q + 1;
                eew_old_buffer_d = eew_q[vs_buffer_d];
                eew_new_buffer_d = reshuffle_eew_vs2_q;
              end
              3'b100: begin
                vs_buffer_d      = vs_buffer_q + 1;
                eew_old_buffer_d = eew_q[vs_buffer_d];
                eew_new_buffer_d = reshuffle_eew_vs1_q;
              end
              default:;
            endcase

            // Mask the next request if we don't need to reshuffle the next reg
            if (eew_new_buffer_d == eew_old_buffer_d) rs_mask_request_d = 1'b1;
          end
        end
      end
    endcase

    if (state_d == NORMAL_OPERATION && state_q != RESHUFFLE) begin
      if (acc_req_i.req_valid && ara_req_ready_i && acc_req_i.resp_ready) begin
        // Decoding
        is_decoding = 1'b1;
        // Acknowledge the request
        acc_resp_o.req_ready = 1'b1;

        // Decode the instructions based on their opcode
        unique case (acc_req_i.insn.itype.opcode)
          //////////////////////////////////////
          //  Vector Arithmetic instructions  //
          //////////////////////////////////////

          riscv::OpcodeVec: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

            // These (mostly) always respond at the same cycle
            acc_resp_o.resp_valid = 1'b1;

            // Decode based on their func3 field
            unique case (insn.varith_type.func3)
              // Configuration instructions
              OPCFG: begin: opcfg
                // These can be acknowledged regardless of the state of Ara
                // NOTE: unless there is a pending fault-only first vector load
                is_config       = 1'b1;

                // Update vtype
                if (insn.vsetvli_type.func1 == 1'b0) begin // vsetvli
                  csr_vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetvli_type.zimm11));
                end else if (insn.vsetivli_type.func2 == 2'b11) begin // vsetivli
                  csr_vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetivli_type.zimm10));
                end else if (insn.vsetvl_type.func7 == 7'b100_0000) begin // vsetvl
                  csr_vtype_d = vtype_xlen(riscv::xlen_t'(acc_req_i.rs2[7:0]));
                end else
                  illegal_insn = 1'b1;

                // Check whether the updated vtype makes sense
                if ((csr_vtype_d.vsew > rvv_pkg::vew_e'($clog2(ELENB))) || // SEW <= ELEN
                    (csr_vtype_d.vlmul == LMUL_RSVD) ||                    // reserved value
                    // LMUL >= SEW/ELEN
                    (signed'($clog2(ELENB)) + signed'(csr_vtype_d.vlmul) < signed'(csr_vtype_d.vsew))) begin
                  csr_vtype_d = '{vill: 1'b1, default: '0};
                  csr_vl_d    = '0;
                end

                // Update the vector length
                else begin
                  // Maximum vector length. VLMAX = LMUL * VLEN / SEW.
                  automatic int unsigned vlmax = VLENB >> csr_vtype_d.vsew;
                  unique case (csr_vtype_d.vlmul)
                    LMUL_1  : vlmax <<= 0;
                    LMUL_2  : vlmax <<= 1;
                    LMUL_4  : vlmax <<= 2;
                    LMUL_8  : vlmax <<= 3;
                    // Fractional LMUL
                    LMUL_1_2: vlmax >>= 1;
                    LMUL_1_4: vlmax >>= 2;
                    LMUL_1_8: vlmax >>= 3;
                    default:;
                  endcase

                  if (insn.vsetivli_type.func2 == 2'b11) begin // vsetivli
                    csr_vl_d = vlen_t'(insn.vsetivli_type.uimm5);
                  end else begin // vsetvl || vsetvli
                    if (insn.vsetvl_type.rs1 == '0 && insn.vsetvl_type.rd == '0) begin
                      // Do not update the vector length
                      csr_vl_d = csr_vl_q;
                    end else if (insn.vsetvl_type.rs1 == '0 && insn.vsetvl_type.rd != '0) begin
                      // Set the vector length to vlmax
                      csr_vl_d = vlmax;
                    end else begin
                      // Normal stripmining
                      csr_vl_d = ((|acc_req_i.rs1[$bits(acc_req_i.rs1)-1:$bits(csr_vl_d)]) ||
                        (vlen_t'(acc_req_i.rs1) > vlmax)) ? vlmax : vlen_t'(acc_req_i.rs1);
                    end
                  end
                end

                // Return the new vl
                acc_resp_o.result = csr_vl_d;

                // If the vtype has changed, wait for the backend before issuing any new instructions.
                // This is to avoid hazards on implicit register labels when LMUL_old > LMUL_new
                // and both the LMULs are greater then LMUL_1 (i.e., lmul[2] == 1'b0)
                // Checking only lmul_q is a trick: we want to stall only if both lmuls have
                // zero MSB. If lmul_q has zero MSB, it's greater than lmul_d only if also
                // lmul_d has zero MSB since the slice comparison is intrinsically unsigned
                if (!csr_vtype_q.vlmul[2] && (csr_vtype_d.vlmul[2:0] < csr_vtype_q.vlmul[2:0]))
                  state_d = WAIT_IDLE;
              end

              OPIVV: begin: opivv
                // These generate a request to Ara's backend
                ara_req.vs1     = insn.varith_type.rs1;
                ara_req.use_vs1 = 1'b1;
                ara_req.vs2     = insn.varith_type.rs2;
                ara_req.use_vs2 = 1'b1;
                ara_req.vd      = insn.varith_type.rd;
                ara_req.use_vd  = 1'b1;
                ara_req.vm      = insn.varith_type.vm;
                ara_req_valid   = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req.op = ara_pkg::VADD;
                  6'b000010: ara_req.op = ara_pkg::VSUB;
                  6'b000100: ara_req.op = ara_pkg::VMINU;
                  6'b000101: ara_req.op = ara_pkg::VMIN;
                  6'b000110: ara_req.op = ara_pkg::VMAXU;
                  6'b000111: ara_req.op = ara_pkg::VMAX;
                  6'b001001: ara_req.op = ara_pkg::VAND;
                  6'b001010: ara_req.op = ara_pkg::VOR;
                  6'b001011: ara_req.op = ara_pkg::VXOR;
                  6'b010000: begin
                    ara_req.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req.op        = ara_pkg::VMADC;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req.emul)
                      LMUL_2:
                        if (((insn.varith_type.rs1 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) ||
                            ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001)))
                          illegal_insn = 1'b1;
                      LMUL_4:
                        if (((insn.varith_type.rs1 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) ||
                            ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011)))
                          illegal_insn = 1'b1;
                      LMUL_8:
                        if (((insn.varith_type.rs1 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) ||
                            ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111)))
                          illegal_insn = 1'b1;
                      default:
                        if ((insn.varith_type.rs1 == insn.varith_type.rd) ||
                            (insn.varith_type.rs2 == insn.varith_type.rd)) illegal_insn = 1'b1;
                    endcase
                  end
                  6'b010010: begin
                    ara_req.op = ara_pkg::VSBC;
                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn         = 1'b1;
                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010011: begin
                    ara_req.op        = ara_pkg::VMSBC;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req.emul)
                      LMUL_2:
                        if (((insn.varith_type.rs1 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) ||
                            ((insn.varith_type.rs2 & 5'b00001) == ( insn.varith_type.rd & 5'b00001)))
                          illegal_insn = 1'b1;
                      LMUL_4:
                        if (((insn.varith_type.rs1 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) ||
                            ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011)))
                          illegal_insn = 1'b1;
                      LMUL_8:
                        if (((insn.varith_type.rs1 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) ||
                            ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111)))
                          illegal_insn = 1'b1;
                      default:
                        if ((insn.varith_type.rs1 == insn.varith_type.rd) ||
                            (insn.varith_type.rs2 == insn.varith_type.rd)) illegal_insn = 1'b1;
                    endcase
                  end
                  6'b011000: begin
                    ara_req.op        = ara_pkg::VMSEQ;
                  end
                  6'b011001: begin
                    ara_req.op        = ara_pkg::VMSNE;
                  end
                  6'b011010: begin
                    ara_req.op        = ara_pkg::VMSLTU;
                  end
                  6'b011011: begin
                    ara_req.op        = ara_pkg::VMSLT;
                  end
                  6'b011100: begin
                    ara_req.op        = ara_pkg::VMSLEU;
                  end
                  6'b011101: begin
                    ara_req.op        = ara_pkg::VMSLE;
                  end
                  6'b010111: begin
                    ara_req.op      = ara_pkg::VMERGE;
                    ara_req.use_vs2 = !insn.varith_type.vm; // vmv.v.v does not use vs2
                    // With a normal vmv.v.v, copy input eew to output
                    // to avoid unnecessary reshuffles
                    if (insn.varith_type.vm) begin
                      ara_req.eew_vs1    = eew_q[ara_req.vs1];
                      ara_req.vtype.vsew = eew_q[ara_req.vs1];
                      ara_req.vl         = (csr_vl_q << csr_vtype_q.vsew[1:0]) >> ara_req.eew_vs1[1:0];
                    end
                  end
                  6'b100000: ara_req.op = ara_pkg::VSADDU;
                  6'b100001: ara_req.op = ara_pkg::VSADD;
                  6'b100010: ara_req.op = ara_pkg::VSSUBU;
                  6'b100011: ara_req.op = ara_pkg::VSSUB;
                  6'b100101: ara_req.op = ara_pkg::VSLL;
                  6'b100111: ara_req.op = ara_pkg::VSMUL;
                  6'b101000: ara_req.op = ara_pkg::VSRL;
                  6'b101010: ara_req.op = ara_pkg::VSSRL;
                  6'b101011: ara_req.op = ara_pkg::VSSRA;
                  6'b101001: ara_req.op = ara_pkg::VSRA;
                  6'b101100: begin
                    ara_req.op             = ara_pkg::VNSRL;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req.op             = ara_pkg::VNSRA;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req.op = ara_pkg::VNCLIPU;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req.op = ara_pkg::VNCLIP;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  // Reductions encode in cvt_resize the neutral value bits
                  // CVT_WIDE is 2'b00 (hack to save wires)
                  6'b110000: begin
                    ara_req.op = ara_pkg::VWREDSUMU;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.eew_vs1        = csr_vtype_q.vsew.next();
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin
                    ara_req.op = ara_pkg::VWREDSUM;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.eew_vs1        = csr_vtype_q.vsew.next();
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req.emul)
                  LMUL_2: if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rs2 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_4: if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rs2 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_8: if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rs2 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                  default:;
                endcase

                // Instruction is invalid if the vtype is invalid
                if (csr_vtype_q.vill) illegal_insn = 1'b1;
              end

              OPIVX: begin: opivx
                // These generate a request to Ara's backend
                ara_req.scalar_op     = acc_req_i.rs1;
                ara_req.use_scalar_op = 1'b1;
                ara_req.vs2           = insn.varith_type.rs2;
                ara_req.use_vs2       = 1'b1;
                ara_req.vd            = insn.varith_type.rd;
                ara_req.use_vd        = 1'b1;
                ara_req.vm            = insn.varith_type.vm;
                ara_req.is_stride_np2 = is_stride_np2;
                ara_req_valid         = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req.op = ara_pkg::VADD;
                  6'b000010: ara_req.op = ara_pkg::VSUB;
                  6'b000011: ara_req.op = ara_pkg::VRSUB;
                  6'b000100: ara_req.op = ara_pkg::VMINU;
                  6'b000101: ara_req.op = ara_pkg::VMIN;
                  6'b000110: ara_req.op = ara_pkg::VMAXU;
                  6'b000111: ara_req.op = ara_pkg::VMAX;
                  6'b001001: ara_req.op = ara_pkg::VAND;
                  6'b001010: ara_req.op = ara_pkg::VOR;
                  6'b001011: ara_req.op = ara_pkg::VXOR;
                  6'b001110: begin
                    ara_req.op            = ara_pkg::VSLIDEUP;
                    ara_req.stride        = acc_req_i.rs1;
                    ara_req.eew_vs2       = csr_vtype_q.vsew;
                    // Encode vslideup/vslide1up on the use_scalar_op field
                    ara_req.use_scalar_op = 1'b0;
                    // Vl refers to current system vsew, but operand requesters
                    // will fetch bytes from a vreg with a different eew
                    // i.e., request will need reshuffling
                    ara_req.scale_vl      = 1'b1;
                    // If stride > vl, the vslideup has no effects
                    if (|ara_req.stride[$bits(ara_req.stride)-1:$bits(csr_vl_q)] ||
                      (vlen_t'(ara_req.stride) >= csr_vl_q)) null_vslideup = 1'b1;
                  end
                  6'b001111: begin
                    ara_req.op            = ara_pkg::VSLIDEDOWN;
                    ara_req.stride        = acc_req_i.rs1;
                    ara_req.eew_vs2       = csr_vtype_q.vsew;
                    // Encode vslidedown/vslide1down on the use_scalar_op field
                    ara_req.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req.scale_vl      = 1'b1;
                  end
                  6'b010000: begin
                    ara_req.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req.op        = ara_pkg::VMADC;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req.emul)
                      LMUL_2:
                        if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001))
                          illegal_insn = 1'b1;
                      LMUL_4:
                        if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011))
                          illegal_insn = 1'b1;
                      LMUL_8:
                        if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111))
                          illegal_insn = 1'b1;
                      default: if (insn.varith_type.rs2 == insn.varith_type.rd) illegal_insn = 1'b1;
                    endcase
                  end
                  6'b010010: begin
                    ara_req.op = ara_pkg::VSBC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010011: begin
                    ara_req.op        = ara_pkg::VMSBC;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req.emul)
                      LMUL_2:
                        if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001))
                          illegal_insn = 1'b1;
                      LMUL_4:
                        if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011))
                          illegal_insn = 1'b1;
                      LMUL_8:
                        if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111))
                          illegal_insn = 1'b1;
                      default: if (insn.varith_type.rs2 == insn.varith_type.rd) illegal_insn = 1'b1;
                    endcase
                  end
                  6'b011000: begin
                    ara_req.op        = ara_pkg::VMSEQ;
                  end
                  6'b011001: begin
                    ara_req.op        = ara_pkg::VMSNE;
                  end
                  6'b011010: begin
                    ara_req.op        = ara_pkg::VMSLTU;
                  end
                  6'b011011: begin
                    ara_req.op        = ara_pkg::VMSLT;
                  end
                  6'b011100: begin
                    ara_req.op        = ara_pkg::VMSLEU;
                  end
                  6'b011101: begin
                    ara_req.op        = ara_pkg::VMSLE;
                  end
                  6'b011110: begin
                    ara_req.op        = ara_pkg::VMSGTU;
                  end
                  6'b011111: begin
                    ara_req.op        = ara_pkg::VMSGT;
                  end
                  6'b010111: begin
                    ara_req.op      = ara_pkg::VMERGE;
                    ara_req.use_vs2 = !insn.varith_type.vm; // vmv.v.x does not use vs2
                  end
                  6'b100000: ara_req.op = ara_pkg::VSADDU;
                  6'b100001: ara_req.op = ara_pkg::VSADD;
                  6'b100010: ara_req.op = ara_pkg::VSSUBU;
                  6'b100011: ara_req.op = ara_pkg::VSSUB;
                  6'b100101: ara_req.op = ara_pkg::VSLL;
                  6'b100111: ara_req.op = ara_pkg::VSMUL;
                  6'b101000: ara_req.op = ara_pkg::VSRL;
                  6'b101010: ara_req.op = ara_pkg::VSSRL;
                  6'b101011: ara_req.op = ara_pkg::VSSRA;
                  6'b101001: ara_req.op = ara_pkg::VSRA;
                  6'b101100: begin
                    ara_req.op             = ara_pkg::VNSRL;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req.op             = ara_pkg::VNSRA;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req.op = ara_pkg::VNCLIPU;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req.op = ara_pkg::VNCLIP;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req.emul)
                  LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                  default:;
                endcase

                // Instruction is invalid if the vtype is invalid
                if (csr_vtype_q.vill) illegal_insn = 1'b1;
              end

              OPIVI: begin: opivi
                // These generate a request to Ara's backend
                // Sign-extend this by default.
                // Instructions that need the immediate to be zero-extended
                // (vrgather, shifts, clips, slides) should do overwrite this.
                ara_req.scalar_op     = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                ara_req.use_scalar_op = 1'b1;
                ara_req.vs2           = insn.varith_type.rs2;
                ara_req.use_vs2       = 1'b1;
                ara_req.vd            = insn.varith_type.rd;
                ara_req.use_vd        = 1'b1;
                ara_req.vm            = insn.varith_type.vm;
                ara_req.is_stride_np2 = is_stride_np2;
                ara_req_valid         = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req.op = ara_pkg::VADD;
                  6'b000011: ara_req.op = ara_pkg::VRSUB;
                  6'b001001: ara_req.op = ara_pkg::VAND;
                  6'b001010: ara_req.op = ara_pkg::VOR;
                  6'b001011: ara_req.op = ara_pkg::VXOR;
                  6'b001110: begin
                    ara_req.op            = ara_pkg::VSLIDEUP;
                    ara_req.stride        = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                    ara_req.eew_vs2       = csr_vtype_q.vsew;
                    // Encode vslideup/vslide1up on the use_scalar_op field
                    ara_req.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req.scale_vl      = 1'b1;
                    // If stride > vl, the vslideup has no effects
                    if (|ara_req.stride[$bits(ara_req.stride)-1:$bits(csr_vl_q)] ||
                      (vlen_t'(ara_req.stride) >= csr_vl_q)) null_vslideup = 1'b1;
                  end
                  6'b001111: begin
                    ara_req.op            = ara_pkg::VSLIDEDOWN;
                    ara_req.stride        = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                    ara_req.eew_vs2       = csr_vtype_q.vsew;
                    // Encode vslidedown/vslide1down on the use_scalar_op field
                    ara_req.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req.scale_vl      = 1'b1;
                  end
                  6'b010000: begin
                    ara_req.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req.op        = ara_pkg::VMADC;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req.emul)
                      LMUL_2:
                        if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001))
                          illegal_insn = 1'b1;
                      LMUL_4:
                        if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011))
                          illegal_insn = 1'b1;
                      LMUL_8:
                        if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111))
                          illegal_insn = 1'b1;
                      default: if (insn.varith_type.rs2 == insn.varith_type.rd) illegal_insn = 1'b1;
                    endcase
                  end
                  6'b011000: begin
                    ara_req.op        = ara_pkg::VMSEQ;
                  end
                  6'b011001: begin
                    ara_req.op        = ara_pkg::VMSNE;
                  end
                  6'b011100: begin
                    ara_req.op        = ara_pkg::VMSLEU;
                  end
                  6'b011101: begin
                    ara_req.op        = ara_pkg::VMSLE;
                  end
                  6'b011110: begin
                    ara_req.op        = ara_pkg::VMSGTU;
                  end
                  6'b011111: begin
                    ara_req.op        = ara_pkg::VMSGT;
                  end
                  6'b010111: begin
                    ara_req.op      = ara_pkg::VMERGE;
                    ara_req.use_vs2 = !insn.varith_type.vm; // vmv.v.i does not use vs2
                  end
                  6'b100000: ara_req.op = ara_pkg::VSADDU;
                  6'b100001: ara_req.op = ara_pkg::VSADD;
                  6'b100101: ara_req.op = ara_pkg::VSLL;
                  6'b100111: begin // vmv<nr>r.v
                    automatic int unsigned vlmax;
                    // Execute also if vl == 0
                    ignore_zero_vl_check = 1'b1;
                    // The number of elements depends on the EEW we will consider
                    vlmax = VLENB >> eew_q[insn.varith_type.rs2];
                    // Rescale the maximum vector length depending on how many
                    // registers we should copy (VLMAX = simm[2:0] * VLEN / SEW).
                    unique case (insn.varith_type.rs1[17:15])
                      3'd0 : begin
                        vlmax <<= 0;
                        ara_req.emul = LMUL_1;
                      end
                      3'd1 : begin
                        vlmax <<= 1;
                        ara_req.emul = LMUL_2;
                      end
                      3'd3 : begin
                        vlmax <<= 2;
                        ara_req.emul = LMUL_4;
                      end
                      3'd7 : begin
                        vlmax <<= 3;
                        ara_req.emul = LMUL_8;
                      end
                      default: begin
                        // Trigger an error for the reserved simm values
                        illegal_insn = 1'b1;
                      end
                    endcase
                    // From here on, the only difference with a vmv.v.v is that the vector reg index
                    // is in rs2. For the rest,, pretend to be a vmv.v.v
                    ara_req.op            = ara_pkg::VMERGE;
                    ara_req.use_scalar_op = 1'b0;
                    ara_req.use_vs1       = 1'b1;
                    ara_req.use_vs2       = 1'b0;
                    ara_req.vs1           = insn.varith_type.rs2;
                    ara_req.eew_vs1       = eew_q[insn.varith_type.rs2];
                    // Copy the encoding information to the new register
                    ara_req.vtype.vsew    = eew_q[insn.varith_type.rs2];
                    ara_req.vl            = vlmax; // whole register move
                  end
                  6'b101000: ara_req.op = ara_pkg::VSRL;
                  6'b101001: ara_req.op = ara_pkg::VSRA;
                  6'b101010: ara_req.op = ara_pkg::VSSRL;
                  6'b101011: ara_req.op = ara_pkg::VSSRA;
                  6'b101100: begin
                    ara_req.op             = ara_pkg::VNSRL;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req.op             = ara_pkg::VNSRA;
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(csr_vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req.op = ara_pkg::VNCLIPU;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req.op = ara_pkg::VNCLIP;
                    ara_req.eew_vs2 = csr_vtype_q.vsew.next();
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req.emul)
                  LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                  default:;
                endcase

                // Instruction is invalid if the vtype is invalid
                if (csr_vtype_q.vill) illegal_insn = 1'b1;
              end

              OPMVV: begin: opmvv
                // These generate a request to Ara's backend
                ara_req.vs1     = insn.varith_type.rs1;
                ara_req.use_vs1 = 1'b1;
                ara_req.vs2     = insn.varith_type.rs2;
                ara_req.use_vs2 = 1'b1;
                ara_req.vd      = insn.varith_type.rd;
                ara_req.use_vd  = 1'b1;
                ara_req.vm      = insn.varith_type.vm;
                ara_req_valid   = 1'b1;

                // Assume an effective EMUL = LMUL1 by default (for the mask operations)
                ara_req.emul = LMUL_1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  // Encode, for each reduction, the bits of the neutral
                  // value of each operation
                  6'b000000: begin
                    ara_req.op             = ara_pkg::VREDSUM;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000001: begin
                    ara_req.op             = ara_pkg::VREDAND;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b11);
                  end
                  6'b000010: begin
                    ara_req.op             = ara_pkg::VREDOR;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000011: begin
                    ara_req.op             = ara_pkg::VREDXOR;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000100: begin
                    ara_req.op             = ara_pkg::VREDMINU;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b11);
                  end
                  6'b000101: begin
                    ara_req.op             = ara_pkg::VREDMIN;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b01);
                  end
                  6'b000110: begin
                    ara_req.op             = ara_pkg::VREDMAXU;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000111: begin
                    ara_req.op             = ara_pkg::VREDMAX;
                    ara_req.conversion_vs1 = OpQueueReductionZExt;
                    ara_req.cvt_resize     = resize_e'(2'b10);
                  end
                  6'b010000: begin // VWXUNARY0
                    // vmv.x.s
                    // Stall the interface until we get the result
                    acc_resp_o.req_ready  = 1'b0;
                    acc_resp_o.resp_valid = 1'b0;

                    case (insn.varith_type.rs1)
                      5'b00000: begin
                        ara_req.op      = ara_pkg::VMVXS;
                        ara_req.vl      = 1;
                      end
                      5'b10000: begin
                        ara_req.op      = ara_pkg::VCPOP;
                        ara_req.use_vs1 = 1'b0;
                      end
                      5'b10001: begin
                        ara_req.op      = ara_pkg::VFIRST;
                        ara_req.use_vs1 = 1'b0;
                      end
                      default :;
                    endcase

                    ara_req.use_vd     = 1'b0;
                    ara_req.vstart     = '0;
                    skip_lmul_checks     = 1'b1;
                    ignore_zero_vl_check = 1'b1;

                    // Sign extend operands
                    unique case (csr_vtype_q.vsew)
                      EW8: begin
                        ara_req.conversion_vs2 = OpQueueConversionSExt8;
                      end
                      EW16: begin
                        ara_req.conversion_vs2 = OpQueueConversionSExt4;
                      end
                      EW32: begin
                        ara_req.conversion_vs2 = OpQueueConversionSExt2;
                      end
                      default:;
                    endcase

                    // Wait until the back-end answers to acknowledge those instructions
                    if ( ara_resp_valid ) begin
                      acc_resp_o.req_ready  = 1'b1;
                      acc_resp_o.resp_valid = 1'b1;
                      acc_resp_o.result     = ara_resp.resp;
                      acc_resp_o.exception  = ara_resp.exception;
                      ara_req_valid       = 1'b0;
                    end
                  end
                  6'b010100: begin
                    ara_req.use_vd_op = 1'b1;
                    ara_req.use_vs1   = 1'b0;
                    case (insn.varith_type.rs1)
                      5'b00001: ara_req.op = ara_pkg::VMSBF;
                      5'b00010: ara_req.op = ara_pkg::VMSOF;
                      5'b00011: ara_req.op = ara_pkg::VMSIF;
                      5'b10000: ara_req.op = ara_pkg::VIOTA;
                      5'b10001: ara_req.op = ara_pkg::VID;
                    endcase
                  end
                  6'b001000: ara_req.op = ara_pkg::VAADDU;
                  6'b001001: ara_req.op = ara_pkg::VAADD;
                  6'b001010: ara_req.op = ara_pkg::VASUBU;
                  6'b001011: ara_req.op = ara_pkg::VASUB;
                  6'b011000: begin
                    ara_req.op        = ara_pkg::VMANDNOT;
                    // Prefer mask operation on EW8 encoding
                    // In mask operations, vs1, vs2, vd should
                    // have the same encoding.
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011001: begin
                    ara_req.op         = ara_pkg::VMAND;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011010: begin
                    ara_req.op         = ara_pkg::VMOR;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011011: begin
                    ara_req.op         = ara_pkg::VMXOR;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011100: begin
                    ara_req.op         = ara_pkg::VMORNOT;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011101: begin
                    ara_req.op         = ara_pkg::VMNAND;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011110: begin
                    ara_req.op         = ara_pkg::VMNOR;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b011111: begin
                    ara_req.op         = ara_pkg::VMXNOR;
                    ara_req.eew_vs1    = EW8;
                    ara_req.eew_vs2    = EW8;
                    ara_req.eew_vd_op  = EW8;
                    ara_req.vtype.vsew = EW8;
                  end
                  6'b010010: begin // VXUNARY0
                    // These instructions do not use vs1
                    ara_req.use_vs1    = 1'b0;
                    skip_vs1_lmul_checks = 1'b1;
                    // They are always encoded as ADDs with zero.
                    ara_req.op            = ara_pkg::VADD;
                    ara_req.use_scalar_op = 1'b1;
                    ara_req.scalar_op     = '0;

                    case (insn.varith_type.rs1)
                      5'b00010: begin // VZEXT.VF8
                        ara_req.conversion_vs2 = OpQueueConversionZExt8;
                        ara_req.eew_vs2        = eew_q[insn.varith_type.rs2];
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW64) ||
                            int'(csr_vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00011: begin // VSEXT.VF8
                        ara_req.conversion_vs2 = OpQueueConversionSExt8;
                        ara_req.eew_vs2        = eew_q[insn.varith_type.rs2];
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW64) ||
                            int'(csr_vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00100: begin // VZEXT.VF4
                        ara_req.conversion_vs2 = OpQueueConversionZExt4;
                        ara_req.eew_vs2        = prev_prev_ew(csr_vtype_q.vsew);
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW32) ||
                            int'(csr_vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) illegal_insn = 1'b1;
                      end
                      5'b00101: begin // VSEXT.VF4
                        ara_req.conversion_vs2 = OpQueueConversionSExt4;
                        ara_req.eew_vs2        = prev_prev_ew(csr_vtype_q.vsew);
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW32) ||
                            int'(csr_vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) illegal_insn = 1'b1;
                      end
                      5'b00110: begin // VZEXT.VF2
                        ara_req.conversion_vs2 = OpQueueConversionZExt2;
                        ara_req.eew_vs2        = csr_vtype_q.vsew.prev();
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW16) || int'(csr_vtype_q.vlmul) inside {LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00111: begin // VSEXT.VF2
                        ara_req.conversion_vs2 = OpQueueConversionSExt2;
                        ara_req.eew_vs2        = csr_vtype_q.vsew.prev();
                        ara_req.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(csr_vtype_q.vsew) < int'(EW16) || int'(csr_vtype_q.vlmul) inside {LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      default: illegal_insn = 1'b1;
                    endcase
                  end
                  // Divide instructions
                  6'b100000: ara_req.op = ara_pkg::VDIVU;
                  6'b100001: ara_req.op = ara_pkg::VDIV;
                  6'b100010: ara_req.op = ara_pkg::VREMU;
                  6'b100011: ara_req.op = ara_pkg::VREM;
                  // Multiply instructions
                  6'b100100: ara_req.op = ara_pkg::VMULHU;
                  6'b100101: ara_req.op = ara_pkg::VMUL;
                  6'b100110: ara_req.op = ara_pkg::VMULHSU;
                  6'b100111: ara_req.op = ara_pkg::VMULH;
                  // Multiply-Add instructions
                  // vd is also used as a source operand
                  6'b101001: begin
                    ara_req.op             = ara_pkg::VMADD;
                    ara_req.use_vd_op      = 1'b1;
                    // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                    ara_req.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101011: begin
                    ara_req.op             = ara_pkg::VNMSUB;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101101: begin
                    ara_req.op        = ara_pkg::VMACC;
                    ara_req.use_vd_op = 1'b1;
                  end
                  6'b101111: begin
                    ara_req.op        = ara_pkg::VNMSAC;
                    ara_req.use_vd_op = 1'b1;
                  end
                  // Widening instructions
                  6'b110000: begin // VWADDU
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin // VWADD
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110010: begin // VWSUBU
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110011: begin // VWSUB
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110100: begin // VWADDU.W
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110101: begin // VWADD.W
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110110: begin // VWSUBU.W
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110111: begin // VWSUB.W
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111000: begin // VWMULU
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111010: begin // VWMULSU
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111011: begin // VWMUL
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111100: begin // VWMACCU
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111101: begin // VWMACC
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111111: begin // VWMACCSU
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access. These constraints can be different for the two source operands and the
                // destination register.
                if (!skip_lmul_checks) begin
                  unique case (ara_req.emul)
                    LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                    default:;
                  endcase
                  unique case (lmul_vs2)
                    LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                    default:;
                  endcase
                  unique case (lmul_vs1)
                    LMUL_2: if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_4: if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_8: if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                    default:;
                  endcase
                end

                // Ara cannot support instructions who operates on more than 64 bits.
                if (int'(ara_req.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;

                // Instruction is invalid if the vtype is invalid
                if (csr_vtype_q.vill) illegal_insn = 1'b1;
              end

              OPMVX: begin: opmvx
                // These generate a request to Ara's backend
                ara_req.scalar_op     = acc_req_i.rs1;
                ara_req.use_scalar_op = 1'b1;
                ara_req.vs2           = insn.varith_type.rs2;
                ara_req.use_vs2       = 1'b1;
                ara_req.vd            = insn.varith_type.rd;
                ara_req.use_vd        = 1'b1;
                ara_req.vm            = insn.varith_type.vm;
                ara_req.is_stride_np2 = is_stride_np2;
                ara_req_valid         = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b001000: ara_req.op = ara_pkg::VAADDU;
                  6'b001001: ara_req.op = ara_pkg::VAADD;
                  6'b001010: ara_req.op = ara_pkg::VASUBU;
                  6'b001011: ara_req.op = ara_pkg::VASUB;
                  // Slides
                  6'b001110: begin // vslide1up
                    ara_req.op      = ara_pkg::VSLIDEUP;
                    ara_req.stride  = 1;
                    ara_req.eew_vs2 = csr_vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req.scale_vl = 1'b1;
                    // If stride > vl, the vslideup has no effects
                    if (|ara_req.stride[$bits(ara_req.stride)-1:$bits(csr_vl_q)] ||
                      (vlen_t'(ara_req.stride) >= csr_vl_q)) null_vslideup = 1'b1;
                  end
                  6'b001111: begin // vslide1down
                    ara_req.op      = ara_pkg::VSLIDEDOWN;
                    ara_req.stride  = 1;
                    ara_req.eew_vs2 = csr_vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req.scale_vl = 1'b1;
                  end
                  6'b010000: begin // VRXUNARY0
                    // vmv.s.x
                    ara_req.op      = ara_pkg::VMVSX;
                    ara_req.use_vs2 = 1'b0;
                    ara_req.vl      = |csr_vl_q ? 1 : '0;
                    // This instruction ignores LMUL checks
                    skip_lmul_checks  = 1'b1;
                  end
                  // Divide instructions
                  6'b100000: ara_req.op = ara_pkg::VDIVU;
                  6'b100001: ara_req.op = ara_pkg::VDIV;
                  6'b100010: ara_req.op = ara_pkg::VREMU;
                  6'b100011: ara_req.op = ara_pkg::VREM;
                  // Multiply instructions
                  6'b100100: ara_req.op = ara_pkg::VMULHU;
                  6'b100101: ara_req.op = ara_pkg::VMUL;
                  6'b100110: ara_req.op = ara_pkg::VMULHSU;
                  6'b100111: ara_req.op = ara_pkg::VMULH;
                  // Multiply-Add instructions
                  // vd is also used as a source operand
                  6'b101001: begin
                    ara_req.op             = ara_pkg::VMADD;
                    ara_req.use_vd_op      = 1'b1;
                    // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                    ara_req.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101011: begin
                    ara_req.op             = ara_pkg::VNMSUB;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101101: begin
                    ara_req.op        = ara_pkg::VMACC;
                    ara_req.use_vd_op = 1'b1;
                  end
                  6'b101111: begin
                    ara_req.op        = ara_pkg::VNMSAC;
                    ara_req.use_vd_op = 1'b1;
                  end
                  // Widening instructions
                  6'b110000: begin // VWADDU
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin // VWADD
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110010: begin // VWSUBU
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110011: begin // VWSUB
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110100: begin // VWADDU.W
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110101: begin // VWADD.W
                    ara_req.op             = ara_pkg::VADD;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110110: begin // VWSUBU.W
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b110111: begin // VWSUB.W
                    ara_req.op             = ara_pkg::VSUB;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111000: begin // VWMULU
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111010: begin // VWMULSU
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111011: begin // VWMUL
                    ara_req.op             = ara_pkg::VMUL;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111100: begin // VWMACCU
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111101: begin // VWMACC
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111110: begin // VWMACCUS
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  6'b111111: begin // VWMACCSU
                    ara_req.op             = ara_pkg::VMACC;
                    ara_req.use_vd_op      = 1'b1;
                    ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                    ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                    ara_req.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    ara_req.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access. The constraints can be different for the two source operands and the
                // destination register.
                if (!skip_lmul_checks) begin
                  unique case (ara_req.emul)
                    LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                    default:;
                  endcase
                  unique case (lmul_vs2)
                    LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                    LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                    default:;
                  endcase
                end

                // Ara cannot support instructions who operates on more than 64 bits.
                if (int'(ara_req.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;

                // Instruction is invalid if the vtype is invalid
                if (csr_vtype_q.vill) illegal_insn = 1'b1;
              end

              OPFVV: begin: opfvv
                if (FPUSupport != FPUSupportNone) begin
                  // These generate a request to Ara's backend
                  ara_req.vs1     = insn.varith_type.rs1;
                  ara_req.use_vs1 = 1'b1;
                  ara_req.vs2     = insn.varith_type.rs2;
                  ara_req.use_vs2 = 1'b1;
                  ara_req.vd      = insn.varith_type.rd;
                  ara_req.use_vd  = 1'b1;
                  ara_req.vm      = insn.varith_type.vm;
                  ara_req.fp_rm   = acc_req_i.frm;
                  ara_req_valid   = 1'b1;

                  // Decode based on the func6 field
                  unique case (insn.varith_type.func6)
                    // VFP Addition
                    6'b000000: begin
                      ara_req.op             = ara_pkg::VFADD;
                      // When performing a floating-point add/sub, fpnew adds the second and the third
                      // operand. Send the first operand (vs2) to the third result queue.
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000001: begin
                      ara_req.op             = ara_pkg::VFREDUSUM;
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b000010: begin
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000011: begin
                      ara_req.op             = ara_pkg::VFREDOSUM;
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b000100: ara_req.op = ara_pkg::VFMIN;
                    6'b000101: begin
                      ara_req.op             = ara_pkg::VFREDMIN;
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.cvt_resize     = resize_e'(2'b01);
                    end
                    6'b000110: ara_req.op = ara_pkg::VFMAX;
                    6'b000111: begin
                      ara_req.op             = ara_pkg::VFREDMAX;
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.cvt_resize     = resize_e'(2'b10);
                    end
                    6'b001000: ara_req.op = ara_pkg::VFSGNJ;
                    6'b001001: ara_req.op = ara_pkg::VFSGNJN;
                    6'b001010: ara_req.op = ara_pkg::VFSGNJX;
                    6'b010000: begin // VWFUNARY0
                      // vmv.f.s
                      // Stall the interface until we get the result
                      acc_resp_o.req_ready  = 1'b0;
                      acc_resp_o.resp_valid = 1'b0;

                      ara_req.op         = ara_pkg::VFMVFS;
                      ara_req.use_vd     = 1'b0;
                      ara_req.vl         = 1;
                      ara_req.vstart     = '0;
                      skip_lmul_checks     = 1'b1;
                      ignore_zero_vl_check = 1'b1;

                      // Zero-extend operands
                      unique case (csr_vtype_q.vsew)
                        EW16: begin
                          ara_req.conversion_vs2 = OpQueueConversionZExt4;
                        end
                        EW32: begin
                          ara_req.conversion_vs2 = OpQueueConversionZExt2;
                        end
                        default:;
                      endcase

                      // NaN-box the result if needed
                      unique case (csr_vtype_q.vsew)
                        EW16: begin
                          vfmvfs_result[63:16] = '1;
                          vfmvfs_result[15:0]  = ara_resp.resp[15:0];
                        end
                        EW32: begin
                          vfmvfs_result[63:32] = '1;
                          vfmvfs_result[31:0]  = ara_resp.resp[31:0];
                        end
                        default: vfmvfs_result = ara_resp.resp;
                      endcase

                      // Wait until the back-end answers to acknowledge those instructions
                      if (ara_resp_valid) begin
                        acc_resp_o.req_ready  = 1'b1;
                        acc_resp_o.resp_valid = 1'b1;
                        acc_resp_o.result     = vfmvfs_result;
                        acc_resp_o.exception  = ara_resp.exception;
                        ara_req_valid       = 1'b0;
                      end
                    end
                    6'b011000: ara_req.op = ara_pkg::VMFEQ;
                    6'b011001: ara_req.op = ara_pkg::VMFLE;
                    6'b011011: ara_req.op = ara_pkg::VMFLT;
                    6'b011100: ara_req.op = ara_pkg::VMFNE;
                    6'b010010: begin // VFUNARY0
                      // These instructions do not use vs1
                      ara_req.use_vs1    = 1'b0;
                      skip_vs1_lmul_checks = 1'b1;

                      case (insn.varith_type.rs1)
                        5'b00000: ara_req.op = VFCVTXUF;
                        5'b00001: ara_req.op = VFCVTXF;
                        5'b00010: ara_req.op = VFCVTFXU;
                        5'b00011: ara_req.op = VFCVTFX;
                        5'b00110: ara_req.op = VFCVTRTZXUF;
                        5'b00111: ara_req.op = VFCVTRTZXF;
                        5'b01000: begin // Widening VFCVTXUF
                          ara_req.op             = VFCVTXUF;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01001: begin // Widening VFCVTXF
                          ara_req.op             = VFCVTXF;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01010: begin // Widening VFCVTFXU
                          ara_req.op             = VFCVTFXU;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01011: begin // Widening VFCVTFX
                          ara_req.op             = VFCVTFX;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01100: begin // Widening VFCVTFF
                          ara_req.op             = VFCVTFF;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01110: begin // Widening VFCVTRTZXUF
                          ara_req.op             = VFCVTRTZXUF;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01111: begin // Widening VFCVTRTZXF
                          ara_req.op             = VFCVTRTZXF;
                          ara_req.cvt_resize     = CVT_WIDE;
                          ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                          ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                          ara_req.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b10000: begin // Narrowing VFCVTXUF
                          ara_req.op             = VFCVTXUF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10001: begin // Narrowing VFCVTXF
                          ara_req.op             = VFCVTXF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10010: begin // Narrowing VFCVTFXU
                          ara_req.op             = VFCVTFXU;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10011: begin // Narrowing VFCVTFX
                          ara_req.op             = VFCVTFX;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10100: begin // Narrowing VFCVTFF
                          ara_req.op             = VFCVTFF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10101: begin // Narrowing VFNCVTRODFF
                          ara_req.op             = VFNCVTRODFF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10110: begin // Narrowing VFCVTRTZXUF
                          ara_req.op             = VFCVTRTZXUF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        5'b10111: begin // Narrowing VFCVTRTZXF
                          ara_req.op             = VFCVTRTZXF;
                          ara_req.cvt_resize     = CVT_NARROW;
                          ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                        end
                        default: begin
                          // Trigger an error
                          illegal_insn = 1'b1;
                        end
                      endcase
                    end
                    6'b010011: begin // VFUNARY1
                    // These instructions do not use vs1
                    ara_req.use_vs1    = 1'b0;
                    skip_vs1_lmul_checks = 1'b1;

                    unique case (insn.varith_type.rs1)
                      5'b00000: ara_req.op = ara_pkg::VFSQRT;
                      5'b00100: ara_req.op = ara_pkg::VFRSQRT7;
                      5'b00101: ara_req.op = ara_pkg::VFREC7;
                      5'b10000: ara_req.op = ara_pkg::VFCLASS;
                      default : illegal_insn = 1'b1;
                    endcase

                    end
                    6'b100000: ara_req.op = ara_pkg::VFDIV;
                    6'b100100: ara_req.op = ara_pkg::VFMUL;
                    6'b101000: begin
                      ara_req.op             = ara_pkg::VFMADD;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101001: begin
                      ara_req.op             = ara_pkg::VFNMADD;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101010: begin
                      ara_req.op             = ara_pkg::VFMSUB;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101011: begin
                      ara_req.op             = ara_pkg::VFNMSUB;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101100: begin
                      ara_req.op        = ara_pkg::VFMACC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101101: begin
                      ara_req.op        = ara_pkg::VFNMACC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101110: begin
                      ara_req.op        = ara_pkg::VFMSAC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101111: begin
                      ara_req.op        = ara_pkg::VFNMSAC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b110000: begin // VFWADD
                      ara_req.op             = ara_pkg::VFADD;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b110001: begin // VFWREDUSUM
                      ara_req.op             = ara_pkg::VFWREDUSUM;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vs1        = csr_vtype_q.vsew.next();
                      ara_req.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b110010: begin // VFWSUB
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b110011: begin // VFWREDOSUM
                      ara_req.op             = ara_pkg::VFWREDOSUM;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueReductionZExt;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vs1        = csr_vtype_q.vsew.next();
                      ara_req.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b110100: begin // VFWADD.W
                      ara_req.op             = ara_pkg::VFADD;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                    end
                    6'b110110: begin // VFWSUB.W
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                    end
                    6'b111000: begin // VFWMUL
                      ara_req.op             = ara_pkg::VFMUL;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b111100: begin // VFWMACC
                      ara_req.op             = ara_pkg::VFMACC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111101: begin // VFWNMACC
                      ara_req.op             = ara_pkg::VFNMACC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111110: begin // VFWMSAC
                      ara_req.op             = ara_pkg::VFMSAC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111111: begin // VFWNMSAC
                      ara_req.op             = ara_pkg::VFNMSAC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    default: illegal_insn = 1'b1;
                  endcase

                  // Instructions with an integer LMUL have extra constraints on the registers they
                  // can access. The constraints can be different for the two source operands and the
                  // destination register.
                  if (!skip_lmul_checks) begin
                    unique case (ara_req.emul)
                      LMUL_2   : if ((insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4   : if ((insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8   : if ((insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                    unique case (lmul_vs2)
                      LMUL_2   : if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4   : if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8   : if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                    if (!skip_vs1_lmul_checks) begin
                      unique case (lmul_vs1)
                        LMUL_2   : if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                        LMUL_4   : if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                        LMUL_8   : if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                        LMUL_RSVD: illegal_insn = 1'b1;
                        default:;
                      endcase
                    end
                  end

                  // Ara can support 16-bit float, 32-bit float, 64-bit float.
                  // Ara cannot support instructions who operates on more than 64 bits.
                  unique case (FPUSupport)
                    FPUSupportHalfSingleDouble: if (int'(ara_req.vtype.vsew) < int'(EW16) ||
                          int'(ara_req.vtype.vsew) > int'(EW64) || int'(ara_req.eew_vs2) > int'(EW64))
                          illegal_insn = 1'b1;
                    FPUSupportHalfSingle: if (int'(ara_req.vtype.vsew) < int'(EW16) ||
                          int'(ara_req.vtype.vsew) > int'(EW32) || int'(ara_req.eew_vs2) > int'(EW32))
                          illegal_insn = 1'b1;
                    FPUSupportSingleDouble: if (int'(ara_req.vtype.vsew) < int'(EW32) ||
                          int'(ara_req.vtype.vsew) > int'(EW64) || int'(ara_req.eew_vs2) > int'(EW64))
                          illegal_insn = 1'b1;
                    FPUSupportHalf: if (int'(ara_req.vtype.vsew) != int'(EW16) || int'(ara_req.eew_vs2) > int'(EW16))
                          illegal_insn = 1'b1;
                    FPUSupportSingle: if (int'(ara_req.vtype.vsew) != int'(EW32) || int'(ara_req.eew_vs2) > int'(EW32))
                        illegal_insn = 1'b1;
                    FPUSupportDouble: if (int'(ara_req.vtype.vsew) != int'(EW64) || int'(ara_req.eew_vs2) > int'(EW64))
                        illegal_insn = 1'b1;
                    default: illegal_insn = 1'b1; // Unsupported configuration
                  endcase

                  // Instruction is invalid if the vtype is invalid
                  if (csr_vtype_q.vill) illegal_insn = 1'b1;
                end else illegal_insn = 1'b1; // Vector FP instructions are disabled
              end

              OPFVF: begin: opfvf
                if (FPUSupport != FPUSupportNone) begin
                  // These generate a request to Ara's backend
                  ara_req.scalar_op     = acc_req_i.rs1;
                  ara_req.use_scalar_op = 1'b1;
                  ara_req.vs2           = insn.varith_type.rs2;
                  ara_req.use_vs2       = 1'b1;
                  ara_req.vd            = insn.varith_type.rd;
                  ara_req.use_vd        = 1'b1;
                  ara_req.vm            = insn.varith_type.vm;
                  ara_req.is_stride_np2 = is_stride_np2;
                  ara_req.fp_rm         = acc_req_i.frm;
                  ara_req_valid         = 1'b1;

                  // Decode based on the func6 field
                  unique case (insn.varith_type.func6)
                    6'b000000: begin
                      ara_req.op             = ara_pkg::VFADD;
                      // When performing a floating-point add/sub, fpnew adds the second and the third
                      // operand
                      // So, send the first operand (vs2) to the third result queue
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000010: begin
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000100: ara_req.op = ara_pkg::VFMIN;
                    6'b000110: ara_req.op = ara_pkg::VFMAX;
                    6'b001000: ara_req.op = ara_pkg::VFSGNJ;
                    6'b001001: ara_req.op = ara_pkg::VFSGNJN;
                    6'b001010: ara_req.op = ara_pkg::VFSGNJX;
                    6'b001110: begin // vfslide1up
                      ara_req.op     = ara_pkg::VSLIDEUP;
                      ara_req.stride = 1;
                    ara_req.eew_vs2  = csr_vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req.scale_vl = 1'b1;
                    // If stride > vl, the vslideup has no effects
                    if (|ara_req.stride[$bits(ara_req.stride)-1:$bits(csr_vl_q)] ||
                      (vlen_t'(ara_req.stride) >= csr_vl_q)) null_vslideup = 1'b1;
                    end
                    6'b001111: begin // vfslide1down
                      ara_req.op     = ara_pkg::VSLIDEDOWN;
                      ara_req.stride = 1;
                    ara_req.eew_vs2  = csr_vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req.scale_vl = 1'b1;
                    end
                    6'b010000: begin // VRFUNARY0
                      // vmv.s.f
                      ara_req.op      = ara_pkg::VFMVSF;
                      ara_req.use_vs2 = 1'b0;
                      ara_req.vl      = |csr_vl_q ? 1 : '0;
                      // This instruction ignores LMUL checks
                      skip_lmul_checks  = 1'b1;
                    end
                    6'b010111: ara_req.op = ara_pkg::VMERGE;
                    6'b011000: ara_req.op = ara_pkg::VMFEQ;
                    6'b011001: ara_req.op = ara_pkg::VMFLE;
                    6'b011011: ara_req.op = ara_pkg::VMFLT;
                    6'b011100: ara_req.op = ara_pkg::VMFNE;
                    6'b011101: ara_req.op = ara_pkg::VMFGT;
                    6'b011111: ara_req.op = ara_pkg::VMFGE;
                    6'b100100: ara_req.op = ara_pkg::VFMUL;
                    6'b100000: ara_req.op = ara_pkg::VFDIV;
                    6'b100001: ara_req.op = ara_pkg::VFRDIV;
                    6'b100111: begin
                      ara_req.op             = ara_pkg::VFRSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101000: begin
                      ara_req.op             = ara_pkg::VFMADD;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101001: begin
                      ara_req.op             = ara_pkg::VFNMADD;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101010: begin
                      ara_req.op             = ara_pkg::VFMSUB;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101011: begin
                      ara_req.op             = ara_pkg::VFNMSUB;
                      ara_req.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101100: begin
                      ara_req.op        = ara_pkg::VFMACC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101101: begin
                      ara_req.op        = ara_pkg::VFNMACC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101110: begin
                      ara_req.op        = ara_pkg::VFMSAC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b101111: begin
                      ara_req.op        = ara_pkg::VFNMSAC;
                      ara_req.use_vd_op = 1'b1;
                    end
                    6'b110000: begin // VFWADD
                      ara_req.op             = ara_pkg::VFADD;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                    end
                    6'b110010: begin // VFWSUB
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                    end
                    6'b110100: begin // VFWADD.W
                      ara_req.op             = ara_pkg::VFADD;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                      ara_req.wide_fp_imm    = 1'b1;
                    end
                    6'b110110: begin // VFWSUB.W
                      ara_req.op             = ara_pkg::VFSUB;
                      ara_req.swap_vs2_vd_op = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.eew_vs2        = csr_vtype_q.vsew.next();
                      ara_req.wide_fp_imm    = 1'b1;
                    end
                    6'b111000: begin // VFWMUL
                      ara_req.op             = ara_pkg::VFMUL;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                    end
                    6'b111100: begin // VFWMACC
                      ara_req.op             = ara_pkg::VFMACC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111101: begin // VFWNMACC
                      ara_req.op             = ara_pkg::VFNMACC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111110: begin // VFWMSAC
                      ara_req.op             = ara_pkg::VFMSAC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    6'b111111: begin // VFWNMSAC
                      ara_req.op             = ara_pkg::VFNMSAC;
                      ara_req.use_vd_op      = 1'b1;
                      ara_req.emul           = next_lmul(csr_vtype_q.vlmul);
                      ara_req.vtype.vsew     = csr_vtype_q.vsew.next();
                      ara_req.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req.wide_fp_imm    = 1'b1;
                      ara_req.eew_vd_op      = csr_vtype_q.vsew.next();
                    end
                    default: illegal_insn = 1'b1;
                  endcase

                  // Check if the FP scalar operand is NaN-boxed. If not, replace it with a NaN.
                  case (csr_vtype_q.vsew)
                    EW16: if (~(&acc_req_i.rs1[63:16])) ara_req.scalar_op = 64'h0000000000007e00;
                    EW32: if (~(&acc_req_i.rs1[63:32])) ara_req.scalar_op = 64'h000000007fc00000;
                  endcase

                  // Instructions with an integer LMUL have extra constraints on the registers they
                  // can access. The constraints can be different for the two source operands and the
                  // destination register.
                  if (!skip_lmul_checks) begin
                    unique case (ara_req.emul)
                      LMUL_2   : if ((insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4   : if ((insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8   : if ((insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                    unique case (lmul_vs2)
                      LMUL_2   : if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4   : if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8   : if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end

                  // Ara can support 16-bit float, 32-bit float, 64-bit float.
                  // Ara cannot support instructions who operates on more than 64 bits.
                  unique case (FPUSupport)
                    FPUSupportHalfSingleDouble: if (int'(ara_req.vtype.vsew) < int'(EW16) ||
                          int'(ara_req.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;
                    FPUSupportHalfSingle: if (int'(ara_req.vtype.vsew) < int'(EW16) ||
                          int'(ara_req.vtype.vsew) > int'(EW32)) illegal_insn = 1'b1;
                    FPUSupportSingleDouble: if (int'(ara_req.vtype.vsew) < int'(EW32) ||
                          int'(ara_req.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;
                    FPUSupportHalf: if (int'(ara_req.vtype.vsew) != int'(EW16)) illegal_insn = 1'b1;
                    FPUSupportSingle: if (int'(ara_req.vtype.vsew) != int'(EW32))
                        illegal_insn = 1'b1;
                    FPUSupportDouble: if (int'(ara_req.vtype.vsew) != int'(EW64))
                        illegal_insn = 1'b1;
                    default: illegal_insn = 1'b1; // Unsupported configuration
                  endcase

                  // Instruction is invalid if the vtype is invalid
                  if (csr_vtype_q.vill) illegal_insn = 1'b1;
                end else illegal_insn = 1'b1; // Vector FP instructions are disabled
              end
            endcase
          end

          ////////////////////
          //  Vector Loads  //
          ////////////////////

          riscv::OpcodeLoadFp: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

            // The instruction is a load
            is_vload = 1'b1;

            // Wait before acknowledging this instruction
            acc_resp_o.req_ready = 1'b0;

            // These generate a request to Ara's backend
            ara_req.vd        = insn.vmem_type.rd;
            ara_req.use_vd    = 1'b1;
            ara_req.vm        = insn.vmem_type.vm;
            ara_req.scalar_op = acc_req_i.rs1;
            ara_req.nf        = insn.vmem_type.nf;
            ara_req_valid     = 1'b1;

            // Decode the element width
            // Indexed memory operations follow a different rule
            unique case ({insn.vmem_type.mew, insn.vmem_type.width})
              4'b0000: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW8;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW8;
                  end
              end
              4'b0101: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW16;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW16;
                  end
              end
              4'b0110: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW32;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW32;
                  end
              end
              4'b0111: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW64;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW64;
                  end
              end
              default: begin // Invalid. Element is too wide, or encoding is non-existant.
                acc_resp_o.req_ready  = 1'b1;
                acc_resp_o.resp_valid = 1'b1;
                illegal_insn          = 1'b1;
                ara_req_valid       = 1'b0;
              end
            endcase

            // Decode the addressing mode
            unique case (insn.vmem_type.mop)
              2'b00: begin
                ara_req.op = VLE;

                // Decode the lumop field
                case (insn.vmem_type.rs2)
                  5'b00000:;      // Unit-strided
                  5'b01000:;      // Unit-strided, whole registers
                  5'b01011: begin // Unit-strided, mask load, EEW=1
                    // We operate ceil(vl/8) bytes
                    ara_req.vl         = (csr_vl_q >> 3) + |csr_vl_q[2:0];
                    ara_req.vtype.vsew = EW8;
                  end
                  5'b10000: begin // Unit-strided, fault-only first
                    // TODO: Not implemented
                    illegal_insn_load     = 1'b1;
                  end
                  default: begin // Reserved
                    illegal_insn_load     = 1'b1;
                  end
                endcase
              end
              2'b10: begin
                ara_req.op     = VLSE;
                ara_req.stride = acc_req_i.rs2;
              end
              2'b01, // Indexed-unordered
              2'b11: begin // Indexed-ordered
                ara_req.op      = VLXE;
                // These also read vs2
                ara_req.vs2     = insn.vmem_type.rs2;
                ara_req.use_vs2 = 1'b1;
              end
              default:;
            endcase

            // For memory operations: EMUL = LMUL * (EEW / SEW)
            // EEW is encoded in the instruction
            ara_req.emul = vlmul_e'(csr_vtype_q.vlmul + (ara_req.vtype.vsew - csr_vtype_q.vsew));

            // Exception if EMUL > 8 or < 1/8
            unique case ({csr_vtype_q.vlmul[2], ara_req.emul[2]})
              // The new emul is lower than the previous lmul
              2'b01: begin
                // But the new eew is greater than vsew
                if (signed'(ara_req.vtype.vsew - csr_vtype_q.vsew) > 0) begin
                  illegal_insn_load     = 1'b1;
                end
              end
              // The new emul is greater than the previous lmul
              2'b10: begin
                // But the new eew is lower than vsew
                if (signed'(ara_req.vtype.vsew - csr_vtype_q.vsew) < 0) begin
                  illegal_insn_load     = 1'b1;
                end
              end
              default:;
            endcase

            // Instructions with an integer LMUL have extra constraints on the registers they can
            // access.
            unique case (ara_req.emul)
              LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                illegal_insn_load     = 1'b1;
              end
              LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                illegal_insn_load     = 1'b1;
              end
              LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                illegal_insn_load     = 1'b1;
              end
              LMUL_RSVD: begin
                illegal_insn_load     = 1'b1;
              end
              default:;
            endcase

            // Check for segment loads
            if (ara_req.nf != 3'b000 && insn.vmem_type.rs2 != 5'b01000) begin
              if (pending_seg_mem_op_q) begin
                // This is a segment load instruction
                is_segment_mem_op = 1'b1;
                // Remove pending segment mem op when over
                if (seg_mem_op_end) pending_seg_mem_op_d = 1'b0;
              end else begin
                // Wait for idle not to mess with load/store_complete_i
                // since the segment sequencer filters these signals
                ara_req_valid = 1'b0;
                pending_seg_mem_op_d = 1'b1;
                state_d = WAIT_IDLE;
              end
              // Check that EMUL * NFIELDS <= 8
              if (!ara_req.emul[2]) begin
                // emul >= 1
                if ((ara_req.nf << ara_req.emul[1:0]) > 8)
                  illegal_insn = 1'b1;
              end else begin
                // emul < 1
                if ((ara_req.nf >> ara_req.emul[1:0]) > 8)
                  illegal_insn = 1'b1;
              end
              // Check if we will not access vector regs past 31
              if (!ara_req.emul[2]) begin
                if ((ara_req.vd + (ara_req.nf << ara_req.emul[1:0])) > 5'b11111)
                  illegal_insn = 1'b1;
              end else begin
                if ((ara_req.vd + ara_req.nf) > 5'b11111)
                  illegal_insn = 1'b1;
              end
            end

            // Vector whole register loads overwrite all the other decoding information.
            if (ara_req.op == VLE && insn.vmem_type.rs2 == 5'b01000) begin
              // Execute also if vl == 0
              ignore_zero_vl_check = 1'b1;
              // The LMUL value is kept in the instruction itself
              illegal_insn_load     = 1'b0;
              ara_req_valid  = 1'b1;

              // Maximum vector length. VLMAX = nf * VLEN / EW8.
              ara_req.vtype.vsew = EW8;
              unique case (insn.vmem_type.nf)
                3'd0: begin
                  ara_req.vl = VLENB << 0;
                  ara_req.emul = LMUL_1;
                end
                3'd1: begin
                  ara_req.vl = VLENB << 1;
                  ara_req.emul = LMUL_2;
                end
                3'd3:  begin
                  ara_req.vl = VLENB << 2;
                  ara_req.emul = LMUL_4;
                end
                3'd7:  begin
                  ara_req.vl = VLENB << 3;
                  ara_req.emul = LMUL_8;
                end
                default: begin
                  // Trigger an error for the reserved simm values
                  illegal_insn_load = 1'b1;
                end
              endcase
            end

            // Wait until the back-end answers to acknowledge those instructions
            if ( ara_resp_valid ) begin
              acc_resp_o.req_ready  = 1'b1;
              acc_resp_o.resp_valid = 1'b1;
              acc_resp_o.exception  = ara_resp.exception;
              ara_req_valid       = 1'b0;
              // In case of exception, modify vstart
              if ( ara_resp.exception.valid ) begin
                csr_vstart_d = ara_resp.exception_vstart;
              end
            end
          end

          /////////////////////
          //  Vector Stores  //
          /////////////////////

          // Vector stores encode:
          //  - The target EEW in ara_req.vtype.vsew
          //  - The EEW of the source register in ara_req.eew_vs1
          // The current vector length refers to the target EEW!
          // Vector stores never re-shuffle the source register!

          riscv::OpcodeStoreFp: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

            // The instruction is a store
            is_vstore = 1'b1;

            // Wait before acknowledging this instruction
            acc_resp_o.req_ready = 1'b0;

            // vl depends on the EEW encoded in the instruction.
            // Ara does not reshuffle source vregs upon vector stores,
            // thus the operand requesters will fetch Bytes referring
            // to the encoding of the source register
            ara_req.scale_vl = 1'b1;

            // These generate a request to Ara's backend
            ara_req.vs1       = insn.vmem_type.rd; // vs3 is encoded in the same position as rd
            ara_req.use_vs1   = 1'b1;
            ara_req.old_eew_vs1 = eew_q[insn.vmem_type.rd]; // This is the old vs1 EEW;
            ara_req.vm        = insn.vmem_type.vm;
            ara_req.scalar_op = acc_req_i.rs1;
            ara_req.nf        = insn.vmem_type.nf;
            ara_req_valid     = 1'b1;

            // Decode the element width
            // Indexed memory operations follow a different rule
            unique case ({insn.vmem_type.mew, insn.vmem_type.width})
              4'b0000: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW8; // ara_req.vtype.vsew is the target EEW!
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW8;
                  end
              end
              4'b0101: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW16;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW16;
                  end
              end
              4'b0110: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW32;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW32;
                  end
              end
              4'b0111: begin
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req.vtype.vsew = EW64;
                  end else begin
                    ara_req.vtype.vsew = csr_vtype_q.vsew;
                    ara_req.eew_vs2    = EW64;
                  end
              end
              default: begin // Invalid. Element is too wide, or encoding is non-existant.
                illegal_insn  = 1'b1;
              end
            endcase

            // Decode the addressing mode
            unique case (insn.vmem_type.mop)
              2'b00: begin
                ara_req.op = VSE;

                // Decode the sumop field
                unique case (insn.vmem_type.rs2)
                  5'b00000:;     // Unit-strided
                  5'b01000:;     // Unit-strided, whole registers
                  5'b01011: begin // Unit-strided, mask store, EEW=1
                    // We operate ceil(vl/8) bytes
                    ara_req.vl         = (csr_vl_q >> 3) + |csr_vl_q[2:0];
                    ara_req.vtype.vsew = EW8;
                  end
                  default: begin // Reserved
                    illegal_insn_store    = 1'b1;
                  end
                endcase
              end
              2'b10: begin
                ara_req.op     = VSSE;
                ara_req.stride = acc_req_i.rs2;
              end
              2'b01, // Indexed-unordered
              2'b11: begin // Indexed-orderd
                ara_req.op      = VSXE;
                // These also read vs2
                ara_req.vs2     = insn.vmem_type.rs2;
                ara_req.use_vs2 = 1'b1;
              end
              default:;
            endcase

            // For memory operations: EMUL = LMUL * (EEW / SEW)
            // EEW is encoded in the instruction
            ara_req.emul = vlmul_e'(csr_vtype_q.vlmul + (ara_req.vtype.vsew - csr_vtype_q.vsew));

            // Exception if EMUL > 8 or < 1/8
            unique case ({csr_vtype_q.vlmul[2], ara_req.emul[2]})
              // The new emul is lower than the previous lmul
              2'b01: begin
                // But the new eew is greater than vsew
                if (signed'(ara_req.vtype.vsew - csr_vtype_q.vsew) > 0) begin
                  illegal_insn_store    = 1'b1;
                end
              end
              // The new emul is greater than the previous lmul
              2'b10: begin
                // But the new eew is lower than vsew
                if (signed'(ara_req.vtype.vsew - csr_vtype_q.vsew) < 0) begin
                  illegal_insn_store    = 1'b1;
                end
              end
              default:;
            endcase

            // Instructions with an integer LMUL have extra constraints on the registers they can
            // access.
            unique case (ara_req.emul)
              LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                illegal_insn_store     = 1'b1;
              end
              LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                illegal_insn_store    = 1'b1;
              end
              LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                illegal_insn_store    = 1'b1;
              end
              LMUL_RSVD: begin
                illegal_insn_store    = 1'b1;
              end
              default:;
            endcase

            // Check for segment stores
            if (ara_req.nf != 3'b000 && insn.vmem_type.rs2 != 5'b01000) begin
              if (pending_seg_mem_op_q) begin
                // This is a segment store instruction
                is_segment_mem_op = 1'b1;
                // Remove pending segment mem op when over
                if (seg_mem_op_end) pending_seg_mem_op_d = 1'b0;
              end else begin
                // Wait for idle not to mess with load/store_complete_i
                // since the segment sequencer filters these signals
                ara_req_valid = 1'b0;
                pending_seg_mem_op_d = 1'b1;
                state_d = WAIT_IDLE;
              end
              // Check that EMUL * NFIELDS <= 8
              if (!ara_req.emul[2]) begin
                // emul >= 1
                if ((ara_req.nf << ara_req.emul[1:0]) > 8)
                  illegal_insn = 1'b1;
              end else begin
                // emul < 1
                if ((ara_req.nf >> ara_req.emul[1:0]) > 8)
                  illegal_insn = 1'b1;
              end
              // Check if we will not access vector regs past 31
              if (!ara_req.emul[2]) begin
                if ((ara_req.vd + (ara_req.nf << ara_req.emul[1:0])) > 5'b11111)
                  illegal_insn = 1'b1;
              end else begin
                if ((ara_req.vd + ara_req.nf) > 5'b11111)
                  illegal_insn = 1'b1;
              end
            end

            // Vector whole register stores are encoded as stores of length VLENB, length
            // multiplier LMUL_1 and element width EW8. They overwrite all this decoding.
            if (ara_req.op == VSE && insn.vmem_type.rs2 == 5'b01000) begin
              // Execute also if vl == 0
              ignore_zero_vl_check = 1'b1;
              illegal_insn_store    = 1'b0;

              // Maximum vector length. VLMAX = nf * VLEN / EW8.
              ara_req.vtype.vsew = EW8;
              unique case (insn.vmem_type.nf)
                3'd0: begin
                  ara_req.vl = VLENB << 0;
                  ara_req.emul = LMUL_1;
                end
                3'd1: begin
                  ara_req.vl = VLENB << 1;
                  ara_req.emul = LMUL_2;
                end
                3'd3:  begin
                  ara_req.vl = VLENB << 2;
                  ara_req.emul = LMUL_4;
                end
                3'd7:  begin
                  ara_req.vl = VLENB << 3;
                  ara_req.emul = LMUL_8;
                end
                default: begin
                  // Trigger an error for the reserved simm values
                  illegal_insn_store = 1'b1;
                end
              endcase

              acc_resp_o.req_ready  = 1'b0;
              acc_resp_o.resp_valid = 1'b0;
              ara_req_valid  = 1'b1;
            end

            // Wait until the back-end answers to acknowledge those instructions
            if ( ara_resp_valid ) begin
              acc_resp_o.req_ready  = 1'b1;
              acc_resp_o.resp_valid = 1'b1;
              acc_resp_o.exception  = ara_resp.exception;
              ara_req_valid       = 1'b0;
              // In case of exception, modify vstart and wait until the previous
              // operations are over
              if ( ara_resp.exception.valid ) begin
                csr_vstart_d = ara_resp.exception_vstart;
                state_d = WAIT_IDLE;
              end
            end
            ara_req.eew_vs1 = ara_req.vtype.vsew; // This is the new vs1 EEW
          end

          ////////////////////////////
          //  CSR Reads and Writes  //
          ////////////////////////////

          riscv::OpcodeSystem: begin
            // CSR ops have semantic dependency from vector instrucitons.
            // Therefore, Ara must be idle before performing any CSR operation.
            // Stall if there is any pending vector instruction
            // NOTE: This is overconstraining. Not all CSR ops actually need to stall if a vector instruction is pending.
            //       E.g., CSR vl is never updated by instructions past ara_dispatcher, except for "unit-stride fault-only-first loads". Reading vl would be safe otherwise.
            //       E.g., CSR vlenb is a design-constant parameter, reading is always safe.
            //       E.g., CSRs vxrm and vxsat have no influence on-non fixed-point instructions, it could be read and written safely when no fixed-point operation is running.
            //       By better analyzing the spec, more of optimizations of such can be made. For the sake of simplicity, the current implementation treats CSR ops as one block.
            // Just always go to WAIT_IDLE for at least one cycle (if there is a vinsn before the CSR one, it can be that ara_idle_i is still deasserted when the CSR is here).
            if (!state_qq != WAIT_IDLE) begin
              state_d = WAIT_IDLE;
              acc_resp_o.req_ready = 1'b0;
            end else begin
              // These always respond at the same cycle
              acc_resp_o.resp_valid = 1'b1;
              is_config        = 1'b1;

              unique case (acc_req_i.insn.itype.funct3)
                3'b001: begin // csrrw
                  // Decode the CSR.
                  case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    // Only vstart can be written with CSR instructions.
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = acc_req_i.rs1;
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VXRM: begin
                      csr_vxrm_d            = vxrm_t'(acc_req_i.rs1[16:15]);
                      acc_resp_o.result = vlen_t'(csr_vxrm_q);
                    end
                    riscv::CSR_VXSAT: begin
                      csr_vxsat_d           = vxsat_e'(acc_req_i.rs1[15]);
                      acc_resp_o.result = vlen_t'(csr_vxsat_q);
                    end
                    riscv::CSR_VCSR: begin
                      csr_vxrm_d            = vxrm_t'(  acc_req_i.rs1[17:16]  );
                      csr_vxsat_d           = vxsat_e'( acc_req_i.rs1[15]    );
                      acc_resp_o.result = vlen_t'(  { csr_vxrm_q, csr_vxsat_q } );
                    end
                    default: illegal_insn = 1'b1;
                  endcase
                end
                3'b010: begin // csrrs
                  // Decode the CSR.
                  case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = csr_vstart_q | vlen_t'(acc_req_i.rs1);
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VTYPE: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = xlen_vtype(csr_vtype_q);
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VL: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = csr_vl_q;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VLENB: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = VLENB;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VXRM: begin
                      csr_vxrm_d            = csr_vxrm_q | vxrm_t'(acc_req_i.rs1[16:15]);
                      acc_resp_o.result = vlen_t'(csr_vxrm_q);
                    end
                    riscv::CSR_VXSAT: begin
                      csr_vxsat_d           = csr_vxsat_q | vxsat_e'(acc_req_i.rs1[15]);
                      acc_resp_o.result = vlen_t'(csr_vxsat_q);
                    end
                    riscv::CSR_VCSR: begin
                      csr_vxrm_d            = csr_vxrm_q  | vxrm_t'(acc_req_i.rs1[17:16]);
                      csr_vxsat_d           = csr_vxsat_q | vxsat_e'(acc_req_i.rs1[15]);
                      acc_resp_o.result = vlen_t'(  { csr_vxrm_q, csr_vxsat_q } );
                    end
                    default: illegal_insn = 1'b1;
                  endcase
                end
                3'b011: begin // csrrc
                  // Decode the CSR.
                  case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = csr_vstart_q & ~vlen_t'(acc_req_i.rs1);
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VTYPE: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = xlen_vtype(csr_vtype_q);
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VL: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = csr_vl_q;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VLENB: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = VLENB;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VXSAT: begin
                      csr_vxsat_d           = csr_vxsat_q & ~vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = csr_vxsat_q;
                    end
                    riscv::CSR_VXRM: begin
                      csr_vxrm_d           = csr_vxrm_q & ~vxsat_e'(acc_req_i.rs1[1:0]);
                      acc_resp_o.result = csr_vxrm_q;
                    end
                    riscv::CSR_VCSR: begin
                      csr_vxrm_d            = csr_vxrm_q  & ~vxsat_e'(acc_req_i.rs1[2:1]);
                      csr_vxsat_d           = csr_vxsat_q & ~vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = vlen_t'(  { csr_vxrm_q, csr_vxsat_q } );
                    end
                    default: illegal_insn = 1'b1;
                  endcase
                end
                3'b101: begin // csrrwi
                  // Decode the CSR.
                  case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    // Only vstart can be written with CSR instructions.
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = vlen_t'(acc_req_i.rs1);
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VXRM: begin
                      csr_vxrm_d            = vxrm_t'(acc_req_i.rs1[1:0]);
                      acc_resp_o.result = vlen_t'(csr_vxrm_q);
                    end
                    riscv::CSR_VXSAT: begin
                      csr_vxsat_d           = acc_req_i.rs1[0];
                      acc_resp_o.result = csr_vxsat_q;
                    end
                    riscv::CSR_VCSR: begin
                      // logic [19:15] rs1; So, LSB is [15]
                      csr_vxrm_d            = vxrm_t'(acc_req_i.rs1[2:1]);
                      csr_vxsat_d           = vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = csr_vxsat_q;
                    end
                    default: illegal_insn = 1'b1;
                  endcase
                end
                3'b110: begin // csrrsi
                  // Decode the CSR.
                  case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = csr_vstart_q | vlen_t'(acc_req_i.rs1);
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VTYPE: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = xlen_vtype(csr_vtype_q);
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VL: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = csr_vl_q;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VLENB: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = VLENB;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VXSAT: begin
                      // logic [19:15] rs1; So, LSB is [15]
                      csr_vxsat_d           = csr_vxsat_q | vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = csr_vxsat_q;
                    end
                    riscv::CSR_VXRM: begin
                      // logic [19:15] rs1; So, LSB is [15]
                      csr_vxrm_d           = csr_vxrm_q | vxrm_t'(acc_req_i.rs1[1:0]);
                      acc_resp_o.result = csr_vxrm_q;
                    end
                    riscv::CSR_VCSR: begin
                      // logic [19:15] rs1; So, LSB is [15]
                      csr_vxrm_d            = csr_vxrm_q  |  vxrm_t'(acc_req_i.rs1[2:1]);
                      csr_vxsat_d           = csr_vxsat_q | vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = { csr_vxrm_q,  csr_vxsat_q };
                    end
                    default: illegal_insn = 1'b1;
                  endcase
                end
                3'b111: begin // csrrci
                  // Decode the CSR.
                  unique case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                    riscv::CSR_VSTART: begin
                      csr_vstart_d          = csr_vstart_q & ~vlen_t'(acc_req_i.rs1);
                      acc_resp_o.result = csr_vstart_q;
                    end
                    riscv::CSR_VTYPE: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = xlen_vtype(csr_vtype_q);
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VL: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = csr_vl_q;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VLENB: begin
                      // Only reads are allowed
                      if (acc_req_i.insn.itype.rs1 == '0) acc_resp_o.result = VLENB;
                      else illegal_insn = 1'b1;
                    end
                    riscv::CSR_VXSAT: begin
                      csr_vxsat_d           = csr_vxsat_q & ~vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = csr_vxsat_q;
                    end
                    riscv::CSR_VXRM: begin
                      csr_vxrm_d           = csr_vxrm_q & ~vxsat_e'(acc_req_i.rs1[1:0]);
                      acc_resp_o.result = csr_vxrm_q;
                    end
                    riscv::CSR_VCSR: begin
                      // logic [19:15] rs1; So, LSB is [15]
                      csr_vxrm_d           = csr_vxrm_q  &  ~vxrm_t'(acc_req_i.rs1[2:1]);
                      csr_vxsat_d          = csr_vxsat_q & ~vxsat_e'(acc_req_i.rs1[0]);
                      acc_resp_o.result = { csr_vxrm_q,  csr_vxsat_q };
                    end
                    default: illegal_insn= 1'b1;
                  endcase
                end
                default: begin
                  // Trigger an illegal instruction
                  illegal_insn = 1'b1;
                end
              endcase // acc_req_i.insn.itype.funct3
            end
          end

          default: begin
            // Trigger an illegal instruction
            illegal_insn = 1'b1;
          end
        endcase
      end

      // Check that we have fixed-point support if requested
      // vxsat and vxrm are always accessible anyway
      if (ara_req_valid && (ara_req.op inside {[VSADDU:VNCLIPU], VSMUL}) && (FixPtSupport == FixedPointDisable))
        illegal_insn = 1'b1;

      // Check that we have we have vfrec7, vfrsqrt7
      if (ara_req_valid && (ara_req.op inside {VFREC7, VFRSQRT7}) && (FPExtSupport == FPExtSupportDisable))
        illegal_insn = 1'b1;

      // Raise an illegal instruction exception
      if ( illegal_insn || illegal_insn_load || illegal_insn_store ) begin
        ara_req_valid            = 1'b0;
        acc_resp_o.req_ready       = 1'b1;
        acc_resp_o.resp_valid      = 1'b1;
        acc_resp_o.exception.valid = 1'b1;
        acc_resp_o.exception.cause = riscv::ILLEGAL_INSTR;
        acc_resp_o.exception.tval  = acc_req_i.insn;
      end

      // Check if we need to reshuffle our vector registers involved in the operation
      // This operation is costly when occurs, so avoid it if possible
      if ( ara_req_valid && !acc_resp_o.exception.valid ) begin
        automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

        // Is the instruction an in-lane one and could it be subject to reshuffling?
        in_lane_op = ara_req.op inside {[VADD:VMERGE]} || ara_req.op inside {[VREDSUM:VMSBC]} ||
                     ara_req.op inside {[VMANDNOT:VMXNOR]} || ara_req.op inside {VSLIDEUP, VSLIDEDOWN};
        // Annotate which registers need a reshuffle -> |vs1|vs2|vd|
        // Optimization: reshuffle vs1 and vs2 only if the operation is strictly in-lane
        // Optimization: reshuffle vd only if we are not overwriting the whole vector register!
        // During a vstore, if vstart > 0, reshuffle immediately not to complicate operand fetch stage
        reshuffle_req_d = {ara_req.use_vs1 && (ara_req.eew_vs1    != eew_q[ara_req.vs1]) && eew_valid_q[ara_req.vs1] && (in_lane_op || (is_vstore && (csr_vstart_q != '0))),
                           ara_req.use_vs2 && (ara_req.eew_vs2    != eew_q[ara_req.vs2]) && eew_valid_q[ara_req.vs2] && in_lane_op,
                           ara_req.use_vd  && (ara_req.vtype.vsew != eew_q[ara_req.vd ]) && eew_valid_q[ara_req.vd ] && csr_vl_q != ((VLENB << ara_req.emul[1:0]) >> ara_req.vtype.vsew)};
        // Mask out requests if they refer to the same register!
        reshuffle_req_d &= {
          (insn.varith_type.rs1 != insn.varith_type.rs2) && (insn.varith_type.rs1 != insn.varith_type.rd),
          (insn.varith_type.rs2 != insn.varith_type.rd),
          1'b1};

        // Prepare the information to reshuffle the vector registers during the next cycles
        // Reshuffle in the following order: vd, v2, v1. The order is arbitrary.
        unique casez (reshuffle_req_d)
          3'b??1: begin
            eew_old_buffer_d = eew_q[insn.vmem_type.rd];
            eew_new_buffer_d = ara_req.vtype.vsew;
            vs_buffer_d      = insn.varith_type.rd;
          end
          3'b?10: begin
            eew_old_buffer_d = eew_q[insn.vmem_type.rs2];
            eew_new_buffer_d = ara_req.eew_vs2;
            vs_buffer_d      = insn.varith_type.rs2;
          end
          3'b100: begin
            eew_old_buffer_d = is_vstore ? eew_q[insn.vmem_type.rd] : eew_q[insn.vmem_type.rs1];
            eew_new_buffer_d = ara_req.eew_vs1;
            vs_buffer_d      = is_vstore ? insn.vmem_type.rd : insn.varith_type.rs1;
          end
          default:;
        endcase
      end

      // Reshuffle if at least one of the three registers needs a reshuffle
      if (|reshuffle_req_d) begin
        // Instruction is of one of the RVV types
        automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

        // Stall the interface, and inject a reshuffling instruction
        acc_resp_o.req_ready  = 1'b0;
        acc_resp_o.resp_valid = 1'b0;
        ara_req_valid  = 1'b0;

        // Initialize the reshuffle counter limit to handle LMUL > 1
        unique case (ara_req.emul)
          LMUL_2:  rs_lmul_cnt_limit_d = 1;
          LMUL_4:  rs_lmul_cnt_limit_d = 3;
          LMUL_8:  rs_lmul_cnt_limit_d = 7;
          default: rs_lmul_cnt_limit_d = 0;
        endcase

        // Save info for next reshuffles
        reshuffle_eew_vs1_d = ara_req.eew_vs1;
        reshuffle_eew_vs2_d = ara_req.eew_vs2;
        reshuffle_eew_vd_d  = ara_req.vtype.vsew;

        // Reshuffle
        state_d = RESHUFFLE;
      end
    end

    // Update the EEW
    if (ara_req_valid_d && ara_req.use_vd && ara_req_ready_i) begin
      unique case (ara_req.emul)
        LMUL_1: begin
          for (int i = 0; i < 1; i++) begin
            eew_d[ara_req.vd + i]       = ara_req.vtype.vsew;
            eew_valid_d[ara_req.vd + i] = 1'b1;
          end
        end
        LMUL_2: begin
          for (int i = 0; i < 2; i++) begin
            eew_d[ara_req.vd + i]       = ara_req.vtype.vsew;
            eew_valid_d[ara_req.vd + i] = 1'b1;
          end
        end
        LMUL_4: begin
          for (int i = 0; i < 4; i++) begin
            eew_d[ara_req.vd + i]       = ara_req.vtype.vsew;
            eew_valid_d[ara_req.vd + i] = 1'b1;
          end
        end
        LMUL_8: begin
          for (int i = 0; i < 8; i++) begin
            eew_d[ara_req.vd + i]       = ara_req.vtype.vsew;
            eew_valid_d[ara_req.vd + i] = 1'b1;
          end
        end
        default: begin // EMUL < 1
          for (int i = 0; i < 1; i++) begin
            eew_d[ara_req.vd + i]       = ara_req.vtype.vsew;
            eew_valid_d[ara_req.vd + i] = 1'b1;
          end
        end
      endcase
    end

    // Any valid non-config instruction is a NOP if vl == 0, with some exceptions,
    // e.g. whole vector memory operations / whole vector register move
    if (is_decoding && (csr_vstart_q >= csr_vl_q || null_vslideup) && !is_config &&
      !ignore_zero_vl_check && !acc_resp_o.exception.valid) begin
      // If we are acknowledging a memory operation, we must tell Ariane that the memory
      // operation was resolved (to decrement its pending load/store counter)
      // This can collide with the same signal from the vector load/store unit, so we must
      // delay the zero_vl acknowledge by 1 cycle
      acc_resp_o.req_ready  = ~((is_vload & load_complete_q) | (is_vstore & store_complete_q));
      acc_resp_o.resp_valid = ~((is_vload & load_complete_q) | (is_vstore & store_complete_q));
      ara_req_valid  = 1'b0;
      load_zero_vl     = is_vload;
      store_zero_vl    = is_vstore;
    end

    // Reset vstart to zero for successful vector instructions
    // Corner cases:
    // * vstart exception reporting, e.g., VLSU, is handled above
    // * CSR operations are not considered vector instructions
    if ( acc_resp_o.resp_valid
          & !acc_resp_o.exception.valid
          & (acc_req_i.insn.itype.opcode != riscv::OpcodeSystem)
        ) begin
      csr_vstart_d = '0;
    end

    acc_resp_o.load_complete  = load_zero_vl  | load_complete_q;
    acc_resp_o.store_complete = store_zero_vl | store_complete_q;

    // The token must change at every new instruction
    ara_req.token = (ara_req_valid_o && ara_req_ready_i) ? ~ara_req_o.token : ara_req_o.token;
  end: p_decoder

endmodule : ara_dispatcher
