// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Frederic zur Bonsen <fzurbonsen@student.ethz.ch>
// Description:
// Ara's predecoder to detect legality: this module needs to be slimmed and has unused functionality.

module ara_pre_decoder import ara_pkg::*; import rvv_pkg::*; #(
    parameter int           unsigned NrLanes      = 0,
    // Support for floating-point data types
    parameter fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter fpext_support_e        FPExtSupport = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter fixpt_support_e        FixPtSupport = FixedPointEnable,

    parameter type x_req_t = core_v_xif_pkg::x_req_t,
    parameter type x_resp_t = core_v_xif_pkg::x_resp_t,
    parameter type x_issue_req_t = core_v_xif_pkg::x_issue_req_t,
    parameter type x_issue_resp_t = core_v_xif_pkg::x_issue_resp_t,
    parameter type x_acc_resp_t = core_v_xif_pkg::x_acc_resp_t,
    parameter type csr_sync_t = logic
  ) (
    // Clock and reset
    input  logic                                 clk_i,
    input  logic                                 rst_ni,
    // X issue interface
    input  x_issue_req_t                         cvxif_issue_req_i,
    input  logic                                 cvxif_issue_req_valid_i,
    output x_issue_resp_t                        cvxif_issue_resp_o,
    // Update the speculative CSRs
    input  logic                                 csr_sync_valid_i,
    input  csr_sync_t                            csr_sync_i,
    // The current insn is modifying a speculative CSR
    output logic                                 csr_spec_mod_o,
    output logic                                 csr_spec_mod_reg_o
  );

  ara_resp_t  ara_resp;
  assign ara_resp = '0;


  import cf_math_pkg::idx_width;

  `include "common_cells/registers.svh"

  ///////////////////////
  // Speculative CSRs  //
  ///////////////////////

  vlen_t  vstart_d, vstart_q;
  vtype_t vtype_d, vtype_q;

  `FF(vstart_q, vstart_d, '0)
  `FF(vtype_q, vtype_d, '{vill: 1'b1, default: '0})

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

  ara_req_t ara_req_d;
  logic     ara_req_valid_d;

  /////////////
  //  State  //
  /////////////

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vs_buffer_q         <= '0;
      reshuffle_req_q     <= '0;
      rs_lmul_cnt_q       <= '0;
      rs_lmul_cnt_limit_q <= '0;
      rs_mask_request_q   <= 1'b0;
    end else begin
      vs_buffer_q         <= vs_buffer_d;
      reshuffle_req_q     <= reshuffle_req_d;
      rs_lmul_cnt_q       <= rs_lmul_cnt_d;
      rs_lmul_cnt_limit_q <= rs_lmul_cnt_limit_d;
      rs_mask_request_q   <= rs_mask_request_d;
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
  // A memory operation can be completed both when it is over and when vl_q == 0. In the latter case,
  // Ara's decoder answers immediately, and this can cause a collision with an answer from Ara's VLSU.
  // To avoid collisions, we give precedence to the VLSU, and we delay the vl_q == 0 memory op
  // completion signal if a collision occurs
  logic load_zero_vl, store_zero_vl;
  // Do not checks vregs validity against current LMUL
  logic skip_lmul_checks;
  logic skip_vs1_lmul_checks;
  // Are we decoding?
  logic is_decoding;
  // Is this an in-lane operation?
  logic in_lane_op;
  // If the vslideup offset is greater than vl_q, the vslideup has no effects
  logic null_vslideup;

  // NP2 Slide support
  logic is_stride_np2;

  assign is_stride_np2 = '0;

  ///////////////
  //  Decoder  //
  ///////////////

  logic illegal_insn;
  logic insn_error;

  logic is_rs1;
  logic is_rs2;
  logic is_rd;
  logic is_fs1;
  logic is_fs2;
  logic is_fd;
  logic is_vfp;

  logic inv_accept;

  assign cvxif_issue_resp_o.accept           = is_decoding & ~insn_error;
  assign cvxif_issue_resp_o.writeback        = (is_rd || is_fd);
  assign cvxif_issue_resp_o.register_read[0] = (is_rs1 || is_fs1);
  assign cvxif_issue_resp_o.register_read[1] = (is_rs2 || is_fs2);
  assign cvxif_issue_resp_o.is_vfp           = is_vfp;

  always_comb begin: p_decoder
    // Default values
    vstart_d     = vstart_q;
    vtype_d      = vtype_q;
    lmul_vs2     = vtype_q.vlmul;
    lmul_vs1     = vtype_q.vlmul;

    reshuffle_req_d  = reshuffle_req_q;
    eew_old_buffer_d = eew_old_buffer_q;
    eew_new_buffer_d = eew_new_buffer_q;
    vs_buffer_d      = vs_buffer_q;

    rs_lmul_cnt_d       = '0;
    rs_lmul_cnt_limit_d = '0;
    rs_mask_request_d   = 1'b0;

    illegal_insn = 1'b0;

    is_vload      = 1'b0;
    is_vstore     = 1'b0;
    load_zero_vl  = 1'b0;
    store_zero_vl = 1'b0;

    skip_lmul_checks     = 1'b0;
    skip_vs1_lmul_checks = 1'b0;

    null_vslideup = 1'b0;

    is_decoding = 1'b0;
    in_lane_op  = 1'b0;


    inv_accept = 1'b1;

    insn_error    = 1'b0;
    csr_spec_mod_o   = '0;
    csr_spec_mod_reg_o   = '0;

    is_rs1 = 1'b0;
    is_rs2 = 1'b0;
    is_rd  = 1'b0;
    is_fs1 = 1'b0;
    is_fs2 = 1'b0;
    is_fd  = 1'b0;
    is_vfp = 1'b0;

    ara_req_d = '{
      vl           : '0,
      vstart       : vstart_q,
      vtype        : vtype_q,
      emul         : vtype_q.vlmul,
      eew_vs1      : vtype_q.vsew,
      eew_vs2      : vtype_q.vsew,
      eew_vd_op    : vtype_q.vsew,
      eew_vmask    : EW8,
      cvt_resize   : CVT_SAME,
      default      : '0
    };
    ara_req_valid_d = 1'b0;

    is_config            = 1'b0;
    ignore_zero_vl_check = 1'b0;

    if (1'b1) begin
      if (cvxif_issue_req_valid_i) begin
        // Decoding
        is_decoding = 1'b1;

        // Decode the instructions based on their opcode
        unique case (cvxif_issue_req_i.instr.itype.opcode)
          //////////////////////////////////////
          //  Vector Arithmetic instructions  //
          //////////////////////////////////////

          riscv::OpcodeVec: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(cvxif_issue_req_i.instr.instr);
            // Decode based on their func3 field
            unique case (insn.varith_type.func3)
              // Configuration instructions
              OPCFG: begin: opcfg
                // These can be acknowledged regardless of the state of Ara
                is_config       = 1'b1;

                // Issue if info
                is_rs1  = insn.vsetivli_type.func2 != 2'b11;
                is_rs2  = insn.vsetvl_type.func7 == 7'b100_0000;
                is_rd   = 1'b1;

                // Update vtype
                if (insn.vsetvli_type.func1 == 1'b0) begin // vsetvli
                  vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetvli_type.zimm11));
                  csr_spec_mod_o     = 1'b1;
                end else if (insn.vsetivli_type.func2 == 2'b11) begin // vsetivli
                  vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetivli_type.zimm10));
                  csr_spec_mod_o     = 1'b1;
                end else if (insn.vsetvl_type.func7 == 7'b100_0000) begin // vsetvl
                  // vtype_d = vtype_xlen(riscv::xlen_t'(register_rs[1][7:0]));
                  csr_spec_mod_o     = 1'b1;
                  csr_spec_mod_reg_o = 1'b1;
                end else begin
                  illegal_insn = 1'b1;
                end

                // Check whether the updated vtype makes sense
                if ((vtype_d.vsew > rvv_pkg::vew_e'($clog2(ELENB))) || // SEW <= ELEN
                    (vtype_d.vlmul == LMUL_RSVD) ||                    // reserved value
                    // LMUL >= SEW/ELEN
                    (signed'($clog2(ELENB)) + signed'(vtype_d.vlmul) < signed'(vtype_d.vsew))) begin
                  vtype_d = '{vill: 1'b1, default: '0};
                  csr_spec_mod_o = 1'b1;
                end
              end

              OPIVV: begin: opivv
                // These generate a request to Ara's backend
                ara_req_d.vs1     = insn.varith_type.rs1;
                ara_req_d.use_vs1 = 1'b1;
                ara_req_d.vs2     = insn.varith_type.rs2;
                ara_req_d.use_vs2 = 1'b1;
                ara_req_d.vd      = insn.varith_type.rd;
                ara_req_d.use_vd  = 1'b1;
                ara_req_d.vm      = insn.varith_type.vm;
                ara_req_valid_d   = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req_d.op = ara_pkg::VADD;
                  6'b000010: ara_req_d.op = ara_pkg::VSUB;
                  6'b000100: ara_req_d.op = ara_pkg::VMINU;
                  6'b000101: ara_req_d.op = ara_pkg::VMIN;
                  6'b000110: ara_req_d.op = ara_pkg::VMAXU;
                  6'b000111: ara_req_d.op = ara_pkg::VMAX;
                  6'b001001: ara_req_d.op = ara_pkg::VAND;
                  6'b001010: ara_req_d.op = ara_pkg::VOR;
                  6'b001011: ara_req_d.op = ara_pkg::VXOR;
                  6'b010000: begin
                    ara_req_d.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req_d.op        = ara_pkg::VMADC;
                    ara_req_d.use_vd_op = 1'b1;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req_d.emul)
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
                    ara_req_d.op = ara_pkg::VSBC;
                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn         = 1'b1;
                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010011: begin
                    ara_req_d.op        = ara_pkg::VMSBC;
                    ara_req_d.use_vd_op = 1'b1;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req_d.emul)
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
                    ara_req_d.op        = ara_pkg::VMSEQ;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011001: begin
                    ara_req_d.op        = ara_pkg::VMSNE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011010: begin
                    ara_req_d.op        = ara_pkg::VMSLTU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011011: begin
                    ara_req_d.op        = ara_pkg::VMSLT;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011100: begin
                    ara_req_d.op        = ara_pkg::VMSLEU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011101: begin
                    ara_req_d.op        = ara_pkg::VMSLE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b010111: begin
                    ara_req_d.op      = ara_pkg::VMERGE;
                    ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.v does not use vs2
                  end
                  6'b100000: ara_req_d.op = ara_pkg::VSADDU;
                  6'b100001: ara_req_d.op = ara_pkg::VSADD;
                  6'b100010: ara_req_d.op = ara_pkg::VSSUBU;
                  6'b100011: ara_req_d.op = ara_pkg::VSSUB;
                  6'b100101: ara_req_d.op = ara_pkg::VSLL;
                  6'b100111: ara_req_d.op = ara_pkg::VSMUL;
                  6'b101000: ara_req_d.op = ara_pkg::VSRL;
                  6'b101010: ara_req_d.op = ara_pkg::VSSRL;
                  6'b101011: ara_req_d.op = ara_pkg::VSSRA;
                  6'b101001: ara_req_d.op = ara_pkg::VSRA;
                  6'b101100: begin
                    ara_req_d.op             = ara_pkg::VNSRL;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req_d.op             = ara_pkg::VNSRA;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req_d.op = ara_pkg::VNCLIPU;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req_d.op = ara_pkg::VNCLIP;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  // Reductions encode in cvt_resize the neutral value bits
                  // CVT_WIDE is 2'b00 (hack to save wires)
                  6'b110000: begin
                    ara_req_d.op = ara_pkg::VWREDSUMU;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.eew_vs1        = vtype_q.vsew.next();
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin
                    ara_req_d.op = ara_pkg::VWREDSUM;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.eew_vs1        = vtype_q.vsew.next();
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req_d.emul)
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
                if (vtype_q.vill) illegal_insn = 1'b1;
              end

              OPIVX: begin: opivx
                // These generate a request to Ara's backend
                ara_req_d.use_scalar_op = 1'b1;
                ara_req_d.vs2           = insn.varith_type.rs2;
                ara_req_d.use_vs2       = 1'b1;
                ara_req_d.vd            = insn.varith_type.rd;
                ara_req_d.use_vd        = 1'b1;
                ara_req_d.vm            = insn.varith_type.vm;
                ara_req_d.is_stride_np2 = is_stride_np2;
                ara_req_valid_d         = 1'b1;

                // Issue if information
                is_rs1 = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req_d.op = ara_pkg::VADD;
                  6'b000010: ara_req_d.op = ara_pkg::VSUB;
                  6'b000011: ara_req_d.op = ara_pkg::VRSUB;
                  6'b000100: ara_req_d.op = ara_pkg::VMINU;
                  6'b000101: ara_req_d.op = ara_pkg::VMIN;
                  6'b000110: ara_req_d.op = ara_pkg::VMAXU;
                  6'b000111: ara_req_d.op = ara_pkg::VMAX;
                  6'b001001: ara_req_d.op = ara_pkg::VAND;
                  6'b001010: ara_req_d.op = ara_pkg::VOR;
                  6'b001011: ara_req_d.op = ara_pkg::VXOR;
                  6'b001110: begin
                    ara_req_d.op            = ara_pkg::VSLIDEUP;
                    ara_req_d.eew_vs2       = vtype_q.vsew;
                    // Encode vslideup/vslide1up on the use_scalar_op field
                    ara_req_d.use_scalar_op = 1'b0;
                    // Vl refers to current system vsew, but operand requesters
                    // will fetch bytes from a vreg with a different eew
                    // i.e., request will need reshuffling
                    ara_req_d.scale_vl      = 1'b1;
                  end
                  6'b001111: begin
                    ara_req_d.op            = ara_pkg::VSLIDEDOWN;
                    ara_req_d.eew_vs2       = vtype_q.vsew;
                    // Encode vslidedown/vslide1down on the use_scalar_op field
                    ara_req_d.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req_d.scale_vl      = 1'b1;
                  end
                  6'b010000: begin
                    ara_req_d.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req_d.op        = ara_pkg::VMADC;
                    ara_req_d.use_vd_op = 1'b1;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req_d.emul)
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
                    ara_req_d.op = ara_pkg::VSBC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010011: begin
                    ara_req_d.op        = ara_pkg::VMSBC;
                    ara_req_d.use_vd_op = 1'b1;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req_d.emul)
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
                    ara_req_d.op        = ara_pkg::VMSEQ;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011001: begin
                    ara_req_d.op        = ara_pkg::VMSNE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011010: begin
                    ara_req_d.op        = ara_pkg::VMSLTU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011011: begin
                    ara_req_d.op        = ara_pkg::VMSLT;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011100: begin
                    ara_req_d.op        = ara_pkg::VMSLEU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011101: begin
                    ara_req_d.op        = ara_pkg::VMSLE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011110: begin
                    ara_req_d.op        = ara_pkg::VMSGTU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011111: begin
                    ara_req_d.op        = ara_pkg::VMSGT;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b010111: begin
                    ara_req_d.op      = ara_pkg::VMERGE;
                    ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.x does not use vs2
                  end
                  6'b100000: ara_req_d.op = ara_pkg::VSADDU;
                  6'b100001: ara_req_d.op = ara_pkg::VSADD;
                  6'b100010: ara_req_d.op = ara_pkg::VSSUBU;
                  6'b100011: ara_req_d.op = ara_pkg::VSSUB;
                  6'b100101: ara_req_d.op = ara_pkg::VSLL;
                  6'b100111: ara_req_d.op = ara_pkg::VSMUL;
                  6'b101000: ara_req_d.op = ara_pkg::VSRL;
                  6'b101010: ara_req_d.op = ara_pkg::VSSRL;
                  6'b101011: ara_req_d.op = ara_pkg::VSSRA;
                  6'b101001: ara_req_d.op = ara_pkg::VSRA;
                  6'b101100: begin
                    ara_req_d.op             = ara_pkg::VNSRL;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req_d.op             = ara_pkg::VNSRA;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req_d.op = ara_pkg::VNCLIPU;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req_d.op = ara_pkg::VNCLIP;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req_d.emul)
                  LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                  default:;
                endcase

                // Instruction is invalid if the vtype is invalid
                if (vtype_q.vill) illegal_insn = 1'b1;
              end

              OPIVI: begin: opivi
                // These generate a request to Ara's backend
                // Sign-extend this by default.
                // Instructions that need the immediate to be zero-extended
                // (vrgather, shifts, clips, slides) should do overwrite this.
                ara_req_d.scalar_op     = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                ara_req_d.use_scalar_op = 1'b1;
                ara_req_d.vs2           = insn.varith_type.rs2;
                ara_req_d.use_vs2       = 1'b1;
                ara_req_d.vd            = insn.varith_type.rd;
                ara_req_d.use_vd        = 1'b1;
                ara_req_d.vm            = insn.varith_type.vm;
                ara_req_d.is_stride_np2 = is_stride_np2;
                ara_req_valid_d         = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b000000: ara_req_d.op = ara_pkg::VADD;
                  6'b000011: ara_req_d.op = ara_pkg::VRSUB;
                  6'b001001: ara_req_d.op = ara_pkg::VAND;
                  6'b001010: ara_req_d.op = ara_pkg::VOR;
                  6'b001011: ara_req_d.op = ara_pkg::VXOR;
                  6'b001110: begin
                    ara_req_d.op            = ara_pkg::VSLIDEUP;
                    ara_req_d.stride        = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                    ara_req_d.eew_vs2       = vtype_q.vsew;
                    // Encode vslideup/vslide1up on the use_scalar_op field
                    ara_req_d.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req_d.scale_vl      = 1'b1;
                  end
                  6'b001111: begin
                    ara_req_d.op            = ara_pkg::VSLIDEDOWN;
                    ara_req_d.stride        = {{ELEN{insn.varith_type.rs1[19]}}, insn.varith_type.rs1};
                    ara_req_d.eew_vs2       = vtype_q.vsew;
                    // Encode vslidedown/vslide1down on the use_scalar_op field
                    ara_req_d.use_scalar_op = 1'b0;
                    // Request will need reshuffling
                    ara_req_d.scale_vl      = 1'b1;
                  end
                  6'b010000: begin
                    ara_req_d.op = ara_pkg::VADC;

                    // Encoding corresponding to unmasked operations are reserved
                    if (insn.varith_type.vm) illegal_insn = 1'b1;

                    // An illegal instruction is raised if the destination vector is v0
                    if (insn.varith_type.rd == 5'b0) illegal_insn = 1'b1;
                  end
                  6'b010001: begin
                    ara_req_d.op        = ara_pkg::VMADC;
                    ara_req_d.use_vd_op = 1'b1;

                    // Check whether we can access vs1 and vs2
                    unique case (ara_req_d.emul)
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
                    ara_req_d.op        = ara_pkg::VMSEQ;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011001: begin
                    ara_req_d.op        = ara_pkg::VMSNE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011100: begin
                    ara_req_d.op        = ara_pkg::VMSLEU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011101: begin
                    ara_req_d.op        = ara_pkg::VMSLE;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011110: begin
                    ara_req_d.op        = ara_pkg::VMSGTU;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b011111: begin
                    ara_req_d.op        = ara_pkg::VMSGT;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b010111: begin
                    ara_req_d.op      = ara_pkg::VMERGE;
                    ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.i does not use vs2
                  end
                  6'b100000: ara_req_d.op = ara_pkg::VSADDU;
                  6'b100001: ara_req_d.op = ara_pkg::VSADD;
                  6'b100101: ara_req_d.op = ara_pkg::VSLL;
                  6'b100111: begin // vmv<nr>r.v
                    // From here on, the only difference with a vmv.v.v is that the vector reg index
                    // is in rs2. For the rest,, pretend to be a vmv.v.v
                    ara_req_d.op            = ara_pkg::VMERGE;
                    ara_req_d.use_scalar_op = 1'b0;
                    ara_req_d.use_vs1       = 1'b1;
                    ara_req_d.use_vs2       = 1'b0;
                    ara_req_d.vs1           = insn.varith_type.rs2;
                    unique case (insn.varith_type.rs1[17:15])
                      3'd0 : begin
                        ara_req_d.emul = LMUL_1;
                      end
                      3'd1 : begin
                        ara_req_d.emul = LMUL_2;
                      end
                      3'd3 : begin
                        ara_req_d.emul = LMUL_4;
                      end
                      3'd7 : begin
                        ara_req_d.emul = LMUL_8;
                      end
                      default: begin
                        // Trigger an error for the reserved simm values
                        illegal_insn = 1'b1;
                      end
                    endcase
                  end
                  6'b101000: ara_req_d.op = ara_pkg::VSRL;
                  6'b101001: ara_req_d.op = ara_pkg::VSRA;
                  6'b101010: ara_req_d.op = ara_pkg::VSSRL;
                  6'b101011: ara_req_d.op = ara_pkg::VSSRA;
                  6'b101100: begin
                    ara_req_d.op             = ara_pkg::VNSRL;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101101: begin
                    ara_req_d.op             = ara_pkg::VNSRA;
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);

                    // Check whether the EEW is not too wide.
                    if (int'(vtype_q.vsew) > int'(EW32)) illegal_insn = 1'b1;

                    // Check whether we can access vs2
                    unique case (ara_req_d.emul.next())
                      LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                      LMUL_RSVD: illegal_insn = 1'b1;
                      default:;
                    endcase
                  end
                  6'b101110: begin
                    ara_req_d.op = ara_pkg::VNCLIPU;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  6'b101111: begin
                    ara_req_d.op = ara_pkg::VNCLIP;
                    ara_req_d.eew_vs2 = vtype_q.vsew.next();
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access.
                unique case (ara_req_d.emul)
                  LMUL_2: if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00001) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_4: if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00011) != 5'b00000) illegal_insn = 1'b1;
                  LMUL_8: if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 ||
                        (insn.varith_type.rd & 5'b00111) != 5'b00000) illegal_insn = 1'b1;
                  default:;
                endcase

                // Instruction is invalid if the vtype is invalid
                if (vtype_q.vill) illegal_insn = 1'b1;
              end

              OPMVV: begin: opmvv
                // Issue if information
                is_rd = insn.varith_type.func6 == 6'b010_000;

                // These generate a request to Ara's backend
                ara_req_d.vs1     = insn.varith_type.rs1;
                ara_req_d.use_vs1 = 1'b1;
                ara_req_d.vs2     = insn.varith_type.rs2;
                ara_req_d.use_vs2 = 1'b1;
                ara_req_d.vd      = insn.varith_type.rd;
                ara_req_d.use_vd  = 1'b1;
                ara_req_d.vm      = insn.varith_type.vm;
                ara_req_valid_d   = 1'b1;

                // Assume an effective EMUL = LMUL1 by default (for the mask operations)
                ara_req_d.emul = LMUL_1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  // Encode, for each reduction, the bits of the neutral
                  // value of each operation
                  6'b000000: begin
                    ara_req_d.op             = ara_pkg::VREDSUM;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000001: begin
                    ara_req_d.op             = ara_pkg::VREDAND;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b11);
                  end
                  6'b000010: begin
                    ara_req_d.op             = ara_pkg::VREDOR;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000011: begin
                    ara_req_d.op             = ara_pkg::VREDXOR;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000100: begin
                    ara_req_d.op             = ara_pkg::VREDMINU;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b11);
                  end
                  6'b000101: begin
                    ara_req_d.op             = ara_pkg::VREDMIN;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b01);
                  end
                  6'b000110: begin
                    ara_req_d.op             = ara_pkg::VREDMAXU;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b00);
                  end
                  6'b000111: begin
                    ara_req_d.op             = ara_pkg::VREDMAX;
                    ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                    ara_req_d.cvt_resize     = resize_e'(2'b10);
                  end
                  6'b010000: begin // VWXUNARY0
                    // vmv.x.s
                    case (insn.varith_type.rs1)
                      5'b00000: begin
                        ara_req_d.op      = ara_pkg::VMVXS;
                        ara_req_d.vl      = 1;
                      end
                      5'b10000: begin
                        ara_req_d.op      = ara_pkg::VCPOP;
                        ara_req_d.use_vs1 = 1'b0;
                      end
                      5'b10001: begin
                        ara_req_d.op      = ara_pkg::VFIRST;
                        ara_req_d.use_vs1 = 1'b0;
                      end
                      default :;
                    endcase

                    ara_req_d.use_vd     = 1'b0;
                    ara_req_d.vstart     = '0;
                    skip_lmul_checks     = 1'b1;

                    // Sign extend operands
                    unique case (vtype_q.vsew)
                      EW8: begin
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt8;
                      end
                      EW16: begin
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt4;
                      end
                      EW32: begin
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                      end
                      default:;
                    endcase
                  end
                  6'b010100: begin
                    ara_req_d.use_vd_op = 1'b1;
                    ara_req_d.use_vs1   = 1'b0;
                    case (insn.varith_type.rs1)
                      5'b00001: ara_req_d.op = ara_pkg::VMSBF;
                      5'b00010: ara_req_d.op = ara_pkg::VMSOF;
                      5'b00011: ara_req_d.op = ara_pkg::VMSIF;
                      5'b10000: ara_req_d.op = ara_pkg::VIOTA;
                      5'b10001: ara_req_d.op = ara_pkg::VID;
                    endcase
                  end
                  6'b001000: ara_req_d.op = ara_pkg::VAADDU;
                  6'b001001: ara_req_d.op = ara_pkg::VAADD;
                  6'b001010: ara_req_d.op = ara_pkg::VASUBU;
                  6'b001011: ara_req_d.op = ara_pkg::VASUB;
                  6'b011000: begin
                    ara_req_d.op        = ara_pkg::VMANDNOT;
                    // Prefer mask operation on EW8 encoding
                    // In mask operations, vs1, vs2, vd should
                    // have the same encoding.
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011001: begin
                    ara_req_d.op         = ara_pkg::VMAND;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011010: begin
                    ara_req_d.op         = ara_pkg::VMOR;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011011: begin
                    ara_req_d.op         = ara_pkg::VMXOR;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011100: begin
                    ara_req_d.op         = ara_pkg::VMORNOT;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011101: begin
                    ara_req_d.op         = ara_pkg::VMNAND;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011110: begin
                    ara_req_d.op         = ara_pkg::VMNOR;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b011111: begin
                    ara_req_d.op         = ara_pkg::VMXNOR;
                    ara_req_d.eew_vs1    = EW8;
                    ara_req_d.eew_vs2    = EW8;
                    ara_req_d.eew_vd_op  = EW8;
                    ara_req_d.vtype.vsew = EW8;
                    ara_req_d.use_vd_op  = 1'b1;
                  end
                  6'b010010: begin // VXUNARY0
                    // These instructions do not use vs1
                    ara_req_d.use_vs1    = 1'b0;
                    skip_vs1_lmul_checks = 1'b1;
                    // They are always encoded as ADDs with zero.
                    ara_req_d.op            = ara_pkg::VADD;
                    ara_req_d.use_scalar_op = 1'b1;
                    ara_req_d.scalar_op     = '0;

                    case (insn.varith_type.rs1)
                      5'b00010: begin // VZEXT.VF8
                        ara_req_d.conversion_vs2 = OpQueueConversionZExt8;
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW64) ||
                            int'(vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00011: begin // VSEXT.VF8
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt8;
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW64) ||
                            int'(vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00100: begin // VZEXT.VF4
                        ara_req_d.conversion_vs2 = OpQueueConversionZExt4;
                        ara_req_d.eew_vs2        = prev_prev_ew(vtype_q.vsew);
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW32) ||
                            int'(vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) illegal_insn = 1'b1;
                      end
                      5'b00101: begin // VSEXT.VF4
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt4;
                        ara_req_d.eew_vs2        = prev_prev_ew(vtype_q.vsew);
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW32) ||
                            int'(vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) illegal_insn = 1'b1;
                      end
                      5'b00110: begin // VZEXT.VF2
                        ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                        ara_req_d.eew_vs2        = vtype_q.vsew.prev();
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW16) || int'(vtype_q.vlmul) inside {LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      5'b00111: begin // VSEXT.VF2
                        ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                        ara_req_d.eew_vs2        = vtype_q.vsew.prev();
                        ara_req_d.cvt_resize     = CVT_WIDE;

                        // Invalid conversion
                        if (int'(vtype_q.vsew) < int'(EW16) || int'(vtype_q.vlmul) inside {LMUL_1_8})
                          illegal_insn = 1'b1;
                      end
                      default: illegal_insn = 1'b1;
                    endcase
                  end
                  // Divide instructions
                  6'b100000: ara_req_d.op = ara_pkg::VDIVU;
                  6'b100001: ara_req_d.op = ara_pkg::VDIV;
                  6'b100010: ara_req_d.op = ara_pkg::VREMU;
                  6'b100011: ara_req_d.op = ara_pkg::VREM;
                  // Multiply instructions
                  6'b100100: ara_req_d.op = ara_pkg::VMULHU;
                  6'b100101: ara_req_d.op = ara_pkg::VMUL;
                  6'b100110: ara_req_d.op = ara_pkg::VMULHSU;
                  6'b100111: ara_req_d.op = ara_pkg::VMULH;
                  // Multiply-Add instructions
                  // vd is also used as a source operand
                  6'b101001: begin
                    ara_req_d.op             = ara_pkg::VMADD;
                    ara_req_d.use_vd_op      = 1'b1;
                    // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                    ara_req_d.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101011: begin
                    ara_req_d.op             = ara_pkg::VNMSUB;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101101: begin
                    ara_req_d.op        = ara_pkg::VMACC;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b101111: begin
                    ara_req_d.op        = ara_pkg::VNMSAC;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  // Widening instructions
                  6'b110000: begin // VWADDU
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin // VWADD
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110010: begin // VWSUBU
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110011: begin // VWSUB
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110100: begin // VWADDU.W
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110101: begin // VWADD.W
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110110: begin // VWSUBU.W
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110111: begin // VWSUB.W
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111000: begin // VWMULU
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111010: begin // VWMULSU
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111011: begin // VWMUL
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111100: begin // VWMACCU
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111101: begin // VWMACC
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111111: begin // VWMACCSU
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access. These constraints can be different for the two source operands and the
                // destination register.
                if (!skip_lmul_checks) begin
                  unique case (ara_req_d.emul)
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
                if (int'(ara_req_d.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;

                // Instruction is invalid if the vtype is invalid
                if (vtype_q.vill) illegal_insn = 1'b1;
              end

              OPMVX: begin: opmvx
                // Issue if information
                is_rs1 = 1'b1;

                // These generate a request to Ara's backend
                ara_req_d.use_scalar_op = 1'b1;
                ara_req_d.vs2           = insn.varith_type.rs2;
                ara_req_d.use_vs2       = 1'b1;
                ara_req_d.vd            = insn.varith_type.rd;
                ara_req_d.use_vd        = 1'b1;
                ara_req_d.vm            = insn.varith_type.vm;
                ara_req_d.is_stride_np2 = is_stride_np2;
                ara_req_valid_d         = 1'b1;

                // Decode based on the func6 field
                unique case (insn.varith_type.func6)
                  6'b001000: ara_req_d.op = ara_pkg::VAADDU;
                  6'b001001: ara_req_d.op = ara_pkg::VAADD;
                  6'b001010: ara_req_d.op = ara_pkg::VASUBU;
                  6'b001011: ara_req_d.op = ara_pkg::VASUB;
                  // Slides
                  6'b001110: begin // vslide1up
                    ara_req_d.op      = ara_pkg::VSLIDEUP;
                    ara_req_d.stride  = 1;
                    ara_req_d.eew_vs2 = vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req_d.scale_vl = 1'b1;
                  end
                  6'b001111: begin // vslide1down
                    ara_req_d.op      = ara_pkg::VSLIDEDOWN;
                    ara_req_d.stride  = 1;
                    ara_req_d.eew_vs2 = vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req_d.scale_vl = 1'b1;
                  end
                  6'b010000: begin // VRXUNARY0
                    // vmv.s.x
                    ara_req_d.op      = ara_pkg::VMVSX;
                    ara_req_d.use_vs2 = 1'b0;
                    // This instruction ignores LMUL checks
                    skip_lmul_checks  = 1'b1;
                  end
                  // Divide instructions
                  6'b100000: ara_req_d.op = ara_pkg::VDIVU;
                  6'b100001: ara_req_d.op = ara_pkg::VDIV;
                  6'b100010: ara_req_d.op = ara_pkg::VREMU;
                  6'b100011: ara_req_d.op = ara_pkg::VREM;
                  // Multiply instructions
                  6'b100100: ara_req_d.op = ara_pkg::VMULHU;
                  6'b100101: ara_req_d.op = ara_pkg::VMUL;
                  6'b100110: ara_req_d.op = ara_pkg::VMULHSU;
                  6'b100111: ara_req_d.op = ara_pkg::VMULH;
                  // Multiply-Add instructions
                  // vd is also used as a source operand
                  6'b101001: begin
                    ara_req_d.op             = ara_pkg::VMADD;
                    ara_req_d.use_vd_op      = 1'b1;
                    // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                    ara_req_d.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101011: begin
                    ara_req_d.op             = ara_pkg::VNMSUB;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.swap_vs2_vd_op = 1'b1;
                  end
                  6'b101101: begin
                    ara_req_d.op        = ara_pkg::VMACC;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  6'b101111: begin
                    ara_req_d.op        = ara_pkg::VNMSAC;
                    ara_req_d.use_vd_op = 1'b1;
                  end
                  // Widening instructions
                  6'b110000: begin // VWADDU
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110001: begin // VWADD
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110010: begin // VWSUBU
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110011: begin // VWSUB
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110100: begin // VWADDU.W
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110101: begin // VWADD.W
                    ara_req_d.op             = ara_pkg::VADD;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110110: begin // VWSUBU.W
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b110111: begin // VWSUB.W
                    ara_req_d.op             = ara_pkg::VSUB;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    lmul_vs2                 = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.eew_vs2        = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111000: begin // VWMULU
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111010: begin // VWMULSU
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111011: begin // VWMUL
                    ara_req_d.op             = ara_pkg::VMUL;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111100: begin // VWMACCU
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111101: begin // VWMACC
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111110: begin // VWMACCUS
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  6'b111111: begin // VWMACCSU
                    ara_req_d.op             = ara_pkg::VMACC;
                    ara_req_d.use_vd_op      = 1'b1;
                    ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                    ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                    ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                    ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                    ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    ara_req_d.cvt_resize     = CVT_WIDE;
                  end
                  default: illegal_insn = 1'b1;
                endcase

                // Instructions with an integer LMUL have extra constraints on the registers they can
                // access. The constraints can be different for the two source operands and the
                // destination register.
                if (!skip_lmul_checks) begin
                  unique case (ara_req_d.emul)
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
                if (int'(ara_req_d.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;

                // Instruction is invalid if the vtype is invalid
                if (vtype_q.vill) illegal_insn = 1'b1;
              end

              OPFVV: begin: opfvv
                // Issue if information
                is_fd = insn.varith_type.func6 == 6'b010_000;
                is_vfp = 1'b1;

                if (FPUSupport != FPUSupportNone) begin
                  // These generate a request to Ara's backend
                  ara_req_d.vs1     = insn.varith_type.rs1;
                  ara_req_d.use_vs1 = 1'b1;
                  ara_req_d.vs2     = insn.varith_type.rs2;
                  ara_req_d.use_vs2 = 1'b1;
                  ara_req_d.vd      = insn.varith_type.rd;
                  ara_req_d.use_vd  = 1'b1;
                  ara_req_d.vm      = insn.varith_type.vm;
                  ara_req_valid_d   = 1'b1;

                  // Decode based on the func6 field
                  unique case (insn.varith_type.func6)
                    // VFP Addition
                    6'b000000: begin
                      ara_req_d.op             = ara_pkg::VFADD;
                      // When performing a floating-point add/sub, fpnew adds the second and the third
                      // operand. Send the first operand (vs2) to the third result queue.
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000001: begin
                      ara_req_d.op             = ara_pkg::VFREDUSUM;
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b000010: begin
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000011: begin
                      ara_req_d.op             = ara_pkg::VFREDOSUM;
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b000100: ara_req_d.op = ara_pkg::VFMIN;
                    6'b000101: begin
                      ara_req_d.op             = ara_pkg::VFREDMIN;
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.cvt_resize     = resize_e'(2'b01);
                    end
                    6'b000110: ara_req_d.op = ara_pkg::VFMAX;
                    6'b000111: begin
                      ara_req_d.op             = ara_pkg::VFREDMAX;
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.cvt_resize     = resize_e'(2'b10);
                    end
                    6'b001000: ara_req_d.op = ara_pkg::VFSGNJ;
                    6'b001001: ara_req_d.op = ara_pkg::VFSGNJN;
                    6'b001010: ara_req_d.op = ara_pkg::VFSGNJX;
                    6'b010000: begin // VWFUNARY0
                      // vmv.f.s
                      ara_req_d.op         = ara_pkg::VFMVFS;
                      ara_req_d.use_vd     = 1'b0;
                      ara_req_d.vl         = 1;
                      ara_req_d.vstart     = '0;
                      skip_lmul_checks     = 1'b1;

                      // Zero-extend operands
                      unique case (vtype_q.vsew)
                        EW16: begin
                          ara_req_d.conversion_vs2 = OpQueueConversionZExt4;
                        end
                        EW32: begin
                          ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                        end
                        default:;
                      endcase
                    end
                    6'b011000: ara_req_d.op = ara_pkg::VMFEQ;
                    6'b011001: ara_req_d.op = ara_pkg::VMFLE;
                    6'b011011: ara_req_d.op = ara_pkg::VMFLT;
                    6'b011100: ara_req_d.op = ara_pkg::VMFNE;
                    6'b010010: begin // VFUNARY0
                      // These instructions do not use vs1
                      ara_req_d.use_vs1    = 1'b0;
                      skip_vs1_lmul_checks = 1'b1;

                      case (insn.varith_type.rs1)
                        5'b00000: ara_req_d.op = VFCVTXUF;
                        5'b00001: ara_req_d.op = VFCVTXF;
                        5'b00010: ara_req_d.op = VFCVTFXU;
                        5'b00011: ara_req_d.op = VFCVTFX;
                        5'b00110: ara_req_d.op = VFCVTRTZXUF;
                        5'b00111: ara_req_d.op = VFCVTRTZXF;
                        5'b01000: begin // Widening VFCVTXUF
                          ara_req_d.op             = VFCVTXUF;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01001: begin // Widening VFCVTXF
                          ara_req_d.op             = VFCVTXF;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01010: begin // Widening VFCVTFXU
                          ara_req_d.op             = VFCVTFXU;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01011: begin // Widening VFCVTFX
                          ara_req_d.op             = VFCVTFX;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01100: begin // Widening VFCVTFF
                          ara_req_d.op             = VFCVTFF;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01110: begin // Widening VFCVTRTZXUF
                          ara_req_d.op             = VFCVTRTZXUF;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b01111: begin // Widening VFCVTRTZXF
                          ara_req_d.op             = VFCVTRTZXF;
                          ara_req_d.cvt_resize     = CVT_WIDE;
                          ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                          ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                          ara_req_d.conversion_vs2 = OpQueueAdjustFPCvt;
                        end
                        5'b10000: begin // Narrowing VFCVTXUF
                          ara_req_d.op             = VFCVTXUF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10001: begin // Narrowing VFCVTXF
                          ara_req_d.op             = VFCVTXF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10010: begin // Narrowing VFCVTFXU
                          ara_req_d.op             = VFCVTFXU;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10011: begin // Narrowing VFCVTFX
                          ara_req_d.op             = VFCVTFX;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10100: begin // Narrowing VFCVTFF
                          ara_req_d.op             = VFCVTFF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10101: begin // Narrowing VFNCVTRODFF
                          ara_req_d.op             = VFNCVTRODFF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10110: begin // Narrowing VFCVTRTZXUF
                          ara_req_d.op             = VFCVTRTZXUF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        5'b10111: begin // Narrowing VFCVTRTZXF
                          ara_req_d.op             = VFCVTRTZXF;
                          ara_req_d.cvt_resize     = CVT_NARROW;
                          ara_req_d.eew_vs2        = vtype_q.vsew.next();
                        end
                        default: begin
                          // Trigger an error
                          illegal_insn = 1'b1;
                        end
                      endcase
                    end
                    6'b010011: begin // VFUNARY1
                    // These instructions do not use vs1
                    ara_req_d.use_vs1    = 1'b0;
                    skip_vs1_lmul_checks = 1'b1;

                    unique case (insn.varith_type.rs1)
                      5'b00000: ara_req_d.op = ara_pkg::VFSQRT;
                      5'b00100: ara_req_d.op = ara_pkg::VFRSQRT7;
                      5'b00101: ara_req_d.op = ara_pkg::VFREC7;
                      5'b10000: ara_req_d.op = ara_pkg::VFCLASS;
                      default : illegal_insn = 1'b1;
                    endcase

                    end
                    6'b100000: ara_req_d.op = ara_pkg::VFDIV;
                    6'b100100: ara_req_d.op = ara_pkg::VFMUL;
                    6'b101000: begin
                      ara_req_d.op             = ara_pkg::VFMADD;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101001: begin
                      ara_req_d.op             = ara_pkg::VFNMADD;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101010: begin
                      ara_req_d.op             = ara_pkg::VFMSUB;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101011: begin
                      ara_req_d.op             = ara_pkg::VFNMSUB;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101100: begin
                      ara_req_d.op        = ara_pkg::VFMACC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101101: begin
                      ara_req_d.op        = ara_pkg::VFNMACC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101110: begin
                      ara_req_d.op        = ara_pkg::VFMSAC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101111: begin
                      ara_req_d.op        = ara_pkg::VFNMSAC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b110000: begin // VFWADD
                      ara_req_d.op             = ara_pkg::VFADD;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b110001: begin // VFWREDUSUM
                      ara_req_d.op             = ara_pkg::VFWREDUSUM;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vs1        = vtype_q.vsew.next();
                      ara_req_d.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b110010: begin // VFWSUB
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b110011: begin // VFWREDOSUM
                      ara_req_d.op             = ara_pkg::VFWREDOSUM;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueReductionZExt;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vs1        = vtype_q.vsew.next();
                      ara_req_d.cvt_resize     = resize_e'(2'b00);
                    end
                    6'b110100: begin // VFWADD.W
                      ara_req_d.op             = ara_pkg::VFADD;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.eew_vs2        = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                    end
                    6'b110110: begin // VFWSUB.W
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.eew_vs2        = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                    end
                    6'b111000: begin // VFWMUL
                      ara_req_d.op             = ara_pkg::VFMUL;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                    end
                    6'b111100: begin // VFWMACC
                      ara_req_d.op             = ara_pkg::VFMACC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111101: begin // VFWNMACC
                      ara_req_d.op             = ara_pkg::VFNMACC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111110: begin // VFWMSAC
                      ara_req_d.op             = ara_pkg::VFMSAC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111111: begin // VFWNMSAC
                      ara_req_d.op             = ara_pkg::VFNMSAC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs1 = OpQueueConversionWideFP2;
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    default: illegal_insn = 1'b1;
                  endcase

                  // Instructions with an integer LMUL have extra constraints on the registers they
                  // can access. The constraints can be different for the two source operands and the
                  // destination register.
                  if (!skip_lmul_checks) begin
                    unique case (ara_req_d.emul)
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
                    FPUSupportHalfSingleDouble: if (int'(ara_req_d.vtype.vsew) < int'(EW16) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW64) || int'(ara_req_d.eew_vs2) > int'(EW64))
                          illegal_insn = 1'b1;
                    FPUSupportHalfSingle: if (int'(ara_req_d.vtype.vsew) < int'(EW16) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW32) || int'(ara_req_d.eew_vs2) > int'(EW32))
                          illegal_insn = 1'b1;
                    FPUSupportSingleDouble: if (int'(ara_req_d.vtype.vsew) < int'(EW32) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW64) || int'(ara_req_d.eew_vs2) > int'(EW64))
                          illegal_insn = 1'b1;
                    FPUSupportHalf: if (int'(ara_req_d.vtype.vsew) != int'(EW16) || int'(ara_req_d.eew_vs2) > int'(EW16))
                          illegal_insn = 1'b1;
                    FPUSupportSingle: if (int'(ara_req_d.vtype.vsew) != int'(EW32) || int'(ara_req_d.eew_vs2) > int'(EW32))
                        illegal_insn = 1'b1;
                    FPUSupportDouble: if (int'(ara_req_d.vtype.vsew) != int'(EW64) || int'(ara_req_d.eew_vs2) > int'(EW64))
                        illegal_insn = 1'b1;
                    default: illegal_insn = 1'b1; // Unsupported configuration
                  endcase

                  // Instruction is invalid if the vtype is invalid
                  if (vtype_q.vill) illegal_insn = 1'b1;
                end else illegal_insn = 1'b1; // Vector FP instructions are disabled
              end

              OPFVF: begin: opfvf
                // Issue if information
                is_fs1 = 1'b1;
                is_vfp = 1'b1;

                if (FPUSupport != FPUSupportNone) begin
                  // These generate a request to Ara's backend
                  ara_req_d.use_scalar_op = 1'b1;
                  ara_req_d.vs2           = insn.varith_type.rs2;
                  ara_req_d.use_vs2       = 1'b1;
                  ara_req_d.vd            = insn.varith_type.rd;
                  ara_req_d.use_vd        = 1'b1;
                  ara_req_d.vm            = insn.varith_type.vm;
                  ara_req_d.is_stride_np2 = is_stride_np2;
                  ara_req_valid_d         = 1'b1;

                  // Decode based on the func6 field
                  unique case (insn.varith_type.func6)
                    6'b000000: begin
                      ara_req_d.op             = ara_pkg::VFADD;
                      // When performing a floating-point add/sub, fpnew adds the second and the third
                      // operand
                      // So, send the first operand (vs2) to the third result queue
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000010: begin
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b000100: ara_req_d.op = ara_pkg::VFMIN;
                    6'b000110: ara_req_d.op = ara_pkg::VFMAX;
                    6'b001000: ara_req_d.op = ara_pkg::VFSGNJ;
                    6'b001001: ara_req_d.op = ara_pkg::VFSGNJN;
                    6'b001010: ara_req_d.op = ara_pkg::VFSGNJX;
                    6'b001110: begin // vfslide1up
                      ara_req_d.op     = ara_pkg::VSLIDEUP;
                      ara_req_d.stride = 1;
                      ara_req_d.eew_vs2  = vtype_q.vsew;
                      // Request will need reshuffling
                      ara_req_d.scale_vl = 1'b1;
                    end
                    6'b001111: begin // vfslide1down
                      ara_req_d.op     = ara_pkg::VSLIDEDOWN;
                      ara_req_d.stride = 1;
                    ara_req_d.eew_vs2  = vtype_q.vsew;
                    // Request will need reshuffling
                    ara_req_d.scale_vl = 1'b1;
                    end
                    6'b010000: begin // VRFUNARY0
                      // vmv.s.f
                      ara_req_d.op      = ara_pkg::VFMVSF;
                      ara_req_d.use_vs2 = 1'b0;
                      // This instruction ignores LMUL checks
                      skip_lmul_checks  = 1'b1;
                    end
                    6'b010111: ara_req_d.op = ara_pkg::VMERGE;
                    6'b011000: ara_req_d.op = ara_pkg::VMFEQ;
                    6'b011001: ara_req_d.op = ara_pkg::VMFLE;
                    6'b011011: ara_req_d.op = ara_pkg::VMFLT;
                    6'b011100: ara_req_d.op = ara_pkg::VMFNE;
                    6'b011101: ara_req_d.op = ara_pkg::VMFGT;
                    6'b011111: ara_req_d.op = ara_pkg::VMFGE;
                    6'b100100: ara_req_d.op = ara_pkg::VFMUL;
                    6'b100000: ara_req_d.op = ara_pkg::VFDIV;
                    6'b100001: ara_req_d.op = ara_pkg::VFRDIV;
                    6'b100111: begin
                      ara_req_d.op             = ara_pkg::VFRSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101000: begin
                      ara_req_d.op             = ara_pkg::VFMADD;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101001: begin
                      ara_req_d.op             = ara_pkg::VFNMADD;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101010: begin
                      ara_req_d.op             = ara_pkg::VFMSUB;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101011: begin
                      ara_req_d.op             = ara_pkg::VFNMSUB;
                      ara_req_d.use_vd_op      = 1'b1;
                      // Swap "vs2" and "vd" since "vs2" is the addend and "vd" is the multiplicand
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                    end
                    6'b101100: begin
                      ara_req_d.op        = ara_pkg::VFMACC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101101: begin
                      ara_req_d.op        = ara_pkg::VFNMACC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101110: begin
                      ara_req_d.op        = ara_pkg::VFMSAC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b101111: begin
                      ara_req_d.op        = ara_pkg::VFNMSAC;
                      ara_req_d.use_vd_op = 1'b1;
                    end
                    6'b110000: begin // VFWADD
                      ara_req_d.op             = ara_pkg::VFADD;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                    end
                    6'b110010: begin // VFWSUB
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                    end
                    6'b110100: begin // VFWADD.W
                      ara_req_d.op             = ara_pkg::VFADD;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.eew_vs2        = vtype_q.vsew.next();
                      ara_req_d.wide_fp_imm    = 1'b1;
                    end
                    6'b110110: begin // VFWSUB.W
                      ara_req_d.op             = ara_pkg::VFSUB;
                      ara_req_d.swap_vs2_vd_op = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      lmul_vs2                 = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.eew_vs2        = vtype_q.vsew.next();
                      ara_req_d.wide_fp_imm    = 1'b1;
                    end
                    6'b111000: begin // VFWMUL
                      ara_req_d.op             = ara_pkg::VFMUL;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                    end
                    6'b111100: begin // VFWMACC
                      ara_req_d.op             = ara_pkg::VFMACC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111101: begin // VFWNMACC
                      ara_req_d.op             = ara_pkg::VFNMACC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111110: begin // VFWMSAC
                      ara_req_d.op             = ara_pkg::VFMSAC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    6'b111111: begin // VFWNMSAC
                      ara_req_d.op             = ara_pkg::VFNMSAC;
                      ara_req_d.use_vd_op      = 1'b1;
                      ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                      ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                      ara_req_d.conversion_vs2 = OpQueueConversionWideFP2;
                      ara_req_d.wide_fp_imm    = 1'b1;
                      ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                    end
                    default: illegal_insn = 1'b1;
                  endcase

                  // Instructions with an integer LMUL have extra constraints on the registers they
                  // can access. The constraints can be different for the two source operands and the
                  // destination register.
                  if (!skip_lmul_checks) begin
                    unique case (ara_req_d.emul)
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
                    FPUSupportHalfSingleDouble: if (int'(ara_req_d.vtype.vsew) < int'(EW16) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;
                    FPUSupportHalfSingle: if (int'(ara_req_d.vtype.vsew) < int'(EW16) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW32)) illegal_insn = 1'b1;
                    FPUSupportSingleDouble: if (int'(ara_req_d.vtype.vsew) < int'(EW32) ||
                          int'(ara_req_d.vtype.vsew) > int'(EW64)) illegal_insn = 1'b1;
                    FPUSupportHalf: if (int'(ara_req_d.vtype.vsew) != int'(EW16)) illegal_insn = 1'b1;
                    FPUSupportSingle: if (int'(ara_req_d.vtype.vsew) != int'(EW32))
                        illegal_insn = 1'b1;
                    FPUSupportDouble: if (int'(ara_req_d.vtype.vsew) != int'(EW64))
                        illegal_insn = 1'b1;
                    default: illegal_insn = 1'b1; // Unsupported configuration
                  endcase

                  // Instruction is invalid if the vtype is invalid
                  if (vtype_q.vill) illegal_insn = 1'b1;
                end else illegal_insn = 1'b1; // Vector FP instructions are disabled
              end
            endcase
          end

          ////////////////////
          //  Vector Loads  //
          ////////////////////

          riscv::OpcodeLoadFp: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(cvxif_issue_req_i.instr.instr);
            // The instruction is a load
            is_vload = 1'b1;

            // These generate a request to Ara's backend
            ara_req_d.vd        = insn.vmem_type.rd;
            ara_req_d.use_vd    = 1'b1;
            ara_req_d.vm        = insn.vmem_type.vm;
            ara_req_valid_d     = 1'b1;

            // Decode the element width
            // Indexed memory operations follow a different rule
            unique case ({insn.vmem_type.mew, insn.vmem_type.width})
              4'b0000: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW8;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW8;
                  end
              end
              4'b0101: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW16;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW16;
                  end
              end
              4'b0110: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW32;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW32;
                  end
              end
              4'b0111: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW64;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW64;
                  end
              end
              4'b1000, //VLxE128/VSxE128
              4'b1101, //VLxE256/VSxE256
              4'b1110, //VLxE512/VSxE512
              4'b1111: begin //VLxE1024/VSxE1024
                  is_rs1   = 1'b1 ;
                  is_rs2   = insn.vmem_type.mop == 2'b10; // Strided operation
              end
              default: begin // Invalid. Element is too wide, or encoding is non-existant.
                illegal_insn = 1'b1;
              end
            endcase

            // Decode the addressing mode
            unique case (insn.vmem_type.mop)
              2'b00: begin
                ara_req_d.op = VLE;

                // Decode the lumop field
                case (insn.vmem_type.rs2)
                  5'b00000:;      // Unit-strided
                  5'b01000:;      // Unit-strided, whole registers
                  5'b01011: begin // Unit-strided, mask load, EEW=1
                    // We operate ceil(vl/8) bytes
                    ara_req_d.vtype.vsew = EW8;
                  end
                  5'b10000: begin // Unit-strided, fault-only first
                    // TODO: Not implemented
                    illegal_insn     = 1'b1;
                  end
                  default: begin // Reserved
                    illegal_insn     = 1'b1;
                  end
                endcase
              end
              2'b10: begin
                ara_req_d.op     = VLSE;
              end
              2'b01, // Indexed-unordered
              2'b11: begin // Indexed-ordered
                ara_req_d.op      = VLXE;
                // These also read vs2
                ara_req_d.vs2     = insn.vmem_type.rs2;
                ara_req_d.use_vs2 = 1'b1;
              end
              default:;
            endcase

            // For memory operations: EMUL = LMUL * (EEW / SEW)
            // EEW is encoded in the instruction
            ara_req_d.emul = vlmul_e'(vtype_q.vlmul + (ara_req_d.vtype.vsew - vtype_q.vsew));

            // Exception if EMUL > 8 or < 1/8
            unique case ({vtype_q.vlmul[2], ara_req_d.emul[2]})
              // The new emul is lower than the previous lmul
              2'b01: begin
                // But the new eew is greater than vsew
                if (signed'(ara_req_d.vtype.vsew - vtype_q.vsew) > 0) begin
                  illegal_insn     = 1'b1;
                end
              end
              // The new emul is greater than the previous lmul
              2'b10: begin
                // But the new eew is lower than vsew
                if (signed'(ara_req_d.vtype.vsew - vtype_q.vsew) < 0) begin
                  illegal_insn     = 1'b1;
                end
              end
              default:;
            endcase

            // Instructions with an integer LMUL have extra constraints on the registers they can
            // access.
            unique case (ara_req_d.emul)
              LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_RSVD: begin
                illegal_insn     = 1'b1;
              end
              default:;
            endcase

            // Vector whole register loads overwrite all the other decoding information.
            if (ara_req_d.op == VLE && insn.vmem_type.rs2 == 5'b01000) begin
              // The LMUL value is kept in the instruction itself
              illegal_insn     = 1'b0;
              ara_req_valid_d  = 1'b1;

              // Maximum vector length. VLMAX = nf * VLEN / EW8.
              ara_req_d.vtype.vsew = EW8;
              unique case (insn.vmem_type.nf)
                3'd0, 3'd1, 3'd3, 3'd7:  begin
                  /* Not illegal */
                end
                default: begin
                  // Trigger an error for the reserved simm values
                  illegal_insn     = 1'b1;
                end
              endcase
            end
          end

          /////////////////////
          //  Vector Stores  //
          /////////////////////

          // Vector stores encode:
          //  - The target EEW in ara_req_d.vtype.vsew
          //  - The EEW of the source register in ara_req_d.eew_vs1
          // The current vector length refers to the target EEW!
          // Vector stores never re-shuffle the source register!

          riscv::OpcodeStoreFp: begin
            // Instruction is of one of the RVV types
            automatic rvv_instruction_t insn = rvv_instruction_t'(cvxif_issue_req_i.instr.instr);
            // The instruction is a store
            is_vstore = 1'b1;

            // vl depends on the EEW encoded in the instruction.
            // Ara does not reshuffle source vregs upon vector stores,
            // thus the operand requesters will fetch Bytes referring
            // to the encoding of the source register
            ara_req_d.scale_vl = 1'b1;

            // These generate a request to Ara's backend
            ara_req_d.vs1       = insn.vmem_type.rd; // vs3 is encoded in the same position as rd
            ara_req_d.use_vs1   = 1'b1;
            ara_req_d.vm        = insn.vmem_type.vm;
            ara_req_valid_d     = 1'b1;

            // Decode the element width
            // Indexed memory operations follow a different rule
            unique case ({insn.vmem_type.mew, insn.vmem_type.width})
              4'b0000: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW8; // ara_req_d.vtype.vsew is the target EEW!
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW8;
                  end
              end
              4'b0101: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW16;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW16;
                  end
              end
              4'b0110: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW32;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW32;
                  end
              end
              4'b0111: begin
                  is_rs1 = 1'b1;
                  is_rs2 = insn.vmem_type.mop == 2'b10;
                  if (insn.vmem_type.mop != 2'b01 && insn.vmem_type.mop != 2'b11) begin
                    ara_req_d.vtype.vsew = EW64;
                  end else begin
                    ara_req_d.vtype.vsew = vtype_q.vsew;
                    ara_req_d.eew_vs2    = EW64;
                  end
              end
              4'b1000, //VLxE128/VSxE128
              4'b1101, //VLxE256/VSxE256
              4'b1110, //VLxE512/VSxE512
              4'b1111: begin //VLxE1024/VSxE1024
                  is_rs1   = 1'b1 ;
                  is_rs2   = insn.vmem_type.mop == 2'b10; // Strided operation
              end
              default: begin // Invalid. Element is too wide, or encoding is non-existant.
                illegal_insn = 1'b1;
              end
            endcase

            // Decode the addressing mode
            unique case (insn.vmem_type.mop)
              2'b00: begin
                ara_req_d.op = VSE;

                // Decode the sumop field
                unique case (insn.vmem_type.rs2)
                  5'b00000:;     // Unit-strided
                  5'b01000:;     // Unit-strided, whole registers
                  5'b01011: begin // Unit-strided, mask store, EEW=1
                    ara_req_d.vtype.vsew = EW8;
                  end
                  default: begin // Reserved
                    illegal_insn     = 1'b1;
                  end
                endcase
              end
              2'b10: begin
                ara_req_d.op     = VSSE;
              end
              2'b01, // Indexed-unordered
              2'b11: begin // Indexed-orderd
                ara_req_d.op      = VSXE;
                // These also read vs2
                ara_req_d.vs2     = insn.vmem_type.rs2;
                ara_req_d.use_vs2 = 1'b1;
              end
              default:;
            endcase

            // For memory operations: EMUL = LMUL * (EEW / SEW)
            // EEW is encoded in the instruction
            ara_req_d.emul = vlmul_e'(vtype_q.vlmul + (ara_req_d.vtype.vsew - vtype_q.vsew));

            // Exception if EMUL > 8 or < 1/8
            unique case ({vtype_q.vlmul[2], ara_req_d.emul[2]})
              // The new emul is lower than the previous lmul
              2'b01: begin
                // But the new eew is greater than vsew
                if (signed'(ara_req_d.vtype.vsew - vtype_q.vsew) > 0) begin
                  illegal_insn     = 1'b1;
                end
              end
              // The new emul is greater than the previous lmul
              2'b10: begin
                // But the new eew is lower than vsew
                if (signed'(ara_req_d.vtype.vsew - vtype_q.vsew) < 0) begin
                  illegal_insn     = 1'b1;
                end
              end
              default:;
            endcase

            // Instructions with an integer LMUL have extra constraints on the registers they can
            // access.
            unique case (ara_req_d.emul)
              LMUL_2: if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_4: if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_8: if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                illegal_insn     = 1'b1;
              end
              LMUL_RSVD: begin
                  illegal_insn     = 1'b1;
              end
              default:;
            endcase

            // Vector whole register stores are encoded as stores of length VLENB, length
            // multiplier LMUL_1 and element width EW8. They overwrite all this decoding.
            if (ara_req_d.op == VSE && insn.vmem_type.rs2 == 5'b01000) begin
              illegal_insn     = 1'b0;
              ara_req_valid_d  = 1'b1;

              unique case (insn.vmem_type.nf)
                3'd0, 3'd1,
                3'd3, 3'd7:  begin
                  /* Not illegal */
                end
                default: begin
                  // Trigger an error for the reserved simm values
                  illegal_insn = 1'b1;
                end
              endcase
            end
          end

          ////////////////////////////
          //  CSR Reads and Writes  //
          ////////////////////////////

          riscv::OpcodeSystem: begin
            automatic rvv_instruction_t insn = rvv_instruction_t'(cvxif_issue_req_i.instr.instr);
            // These always respond at the same cycle
            is_config        = 1'b1;

            unique case (cvxif_issue_req_i.instr.itype.funct3)
              3'b001: begin // csrrw
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  // Only vstart can be written with CSR instructions.
                  riscv::CSR_VSTART: begin
                    //vstart_d           = register_rs[0];
                    csr_spec_mod_o     = 1'b1;
                    csr_spec_mod_reg_o = 1'b1;
                  end
                  riscv::CSR_VXRM: begin
                    /* Not illegal */
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              3'b010: begin // csrrs
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  riscv::CSR_VSTART: begin
                    //vstart_d           = vstart_q | vlen_t'(register_rs[0]);
                    csr_spec_mod_o     = 1'b1;
                    csr_spec_mod_reg_o = 1'b1;
                  end
                  riscv::CSR_VTYPE: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VL: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VLENB: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VXRM: begin
                    /* Not illegal */
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              3'b011: begin // csrrc
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  riscv::CSR_VSTART: begin
                    //vstart_d           = vstart_q & ~vlen_t'(register_rs[0]);
                    csr_spec_mod_o     = 1'b1;
                    csr_spec_mod_reg_o = 1'b1;
                  end
                  riscv::CSR_VTYPE: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VL: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VLENB: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              3'b101: begin // csrrwi
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  // Only vstart can be written with CSR instructions.
                  riscv::CSR_VSTART: begin
                    vstart_d       = vlen_t'(cvxif_issue_req_i.instr.itype.rs1);
                    csr_spec_mod_o = 1'b1;
                  end
                  riscv::CSR_VXRM: begin
                    /* Not illegal */
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              3'b110: begin // csrrsi
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  riscv::CSR_VSTART: begin
                    vstart_d       = vstart_q | vlen_t'(cvxif_issue_req_i.instr.itype.rs1);
                    csr_spec_mod_o = 1'b1;
                  end
                  riscv::CSR_VTYPE: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VL: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VLENB: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              3'b111: begin // csrrci
                is_rs1   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rs2   = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                is_rd    = is_vector_csr(riscv::csr_reg_t'(insn.i_type.imm));
                // Decode the CSR.
                unique case (riscv::csr_addr_t'(cvxif_issue_req_i.instr.itype.imm))
                  riscv::CSR_VSTART: begin
                    vstart_d       = vstart_q & ~vlen_t'(cvxif_issue_req_i.instr.itype.rs1);
                    csr_spec_mod_o = 1'b1;
                  end
                  riscv::CSR_VTYPE: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VL: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VLENB: begin
                    // Only reads are allowed
                    if (!(cvxif_issue_req_i.instr.itype.rs1 == '0)) begin
                      illegal_insn = 1'b1;
                    end
                  end
                  riscv::CSR_VXSAT: begin
                    /* Not illegal */
                  end
                  default: begin
                    illegal_insn = 1'b1;
                  end
                endcase
              end
              default: begin
                // Trigger an illegal instruction
                illegal_insn = 1'b1;
              end
            endcase
          end

          riscv::OpcodeAmo: begin
            automatic rvv_instruction_t insn = rvv_instruction_t'(cvxif_issue_req_i.instr.instr);
            case (insn.vamo_type.width)
              3'b000, //VAMO*EI8.V
              3'b101, //VAMO*EI16.V
              3'b110, //VAMO*EI32.V
              3'b111: begin //VAMO*EI64.V
                is_rs1   = 1'b1;
              end
            endcase
          end

          default: begin
            // Trigger an illegal instruction
            illegal_insn = 1'b1;
          end
        endcase
      end

      // Check that we have fixed-point support if requested
      // vxsat and vxrm are always accessible anyway
      if (ara_req_valid_d && (ara_req_d.op inside {[VSADDU:VNCLIPU], VSMUL}) && (FixPtSupport == FixedPointDisable))
        illegal_insn = 1'b1;

      // Check that we have we have vfrec7, vfrsqrt7
      if (ara_req_valid_d && (ara_req_d.op inside {VFREC7, VFRSQRT7}) && (FPExtSupport == FPExtSupportDisable))
        illegal_insn = 1'b1;
    end

    // Raise an illegal instruction exception
    if (illegal_insn) begin
      ara_req_valid_d  = 1'b0;
      insn_error = 1'b1;
    end

    // Sync the speculative CSRs with their real values
    if (csr_sync_valid_i) begin
      vstart_d = csr_sync_i.vstart;
      vtype_d  = csr_sync_i.vtype;
    end
  end: p_decoder
endmodule : ara_pre_decoder
