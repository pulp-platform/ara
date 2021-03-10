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
    parameter int unsigned NrLanes = 0
  ) (
    // Clock and reset
    input  logic                                 clk_i,
    input  logic                                 rst_ni,
    // Interfaces with Ariane
    input  accelerator_req_t                     acc_req_i,
    input  logic                                 acc_req_valid_i,
    output logic                                 acc_req_ready_o,
    output accelerator_resp_t                    acc_resp_o,
    output logic                                 acc_resp_valid_o,
    input  logic                                 acc_resp_ready_i,
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
    // Interface with the Vector Store Unit
    output logic                                 core_st_pending_o,
    input  logic                                 load_complete_i,
    input  logic                                 store_complete_i,
    input  logic                                 store_pending_i
  );

  `include "common_cells/registers.svh"

  assign core_st_pending_o = acc_req_i.store_pending;

  /**********
   *  CSRs  *
   **********/

  vlen_t  vstart_d, vstart_q;
  vlen_t  vl_d, vl_q;
  vtype_t vtype_d, vtype_q;

  `FF(vstart_q, vstart_d, '0)
  `FF(vl_q, vl_d, '0)
  `FF(vtype_q, vtype_d, '{vill: 1'b1, default: '0})

  // Converts between the internal representation of `vtype_t` and the full XLEN-bit CSR.
  function automatic riscv::xlen_t xlen_vtype(vtype_t vtype);
    xlen_vtype = {vtype.vill, {riscv::XLEN-9{1'b0}}, vtype.vma, vtype.vta, vtype.vlmul[2], vtype.vsew, vtype.vlmul[1:0]};
  endfunction: xlen_vtype

  // Converts between the XLEN-bit vtype CSR and its internal representation
  function automatic vtype_t vtype_xlen(riscv::xlen_t xlen);
    vtype_xlen = '{
      vill  : xlen[riscv::XLEN-1],
      vma   : xlen[7],
      vta   : xlen[6],
      vsew  : vew_e'(xlen[4:2]),
      vlmul : vlmul_e'({xlen[5], xlen[1:0]})
    };
  endfunction: vtype_xlen

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
  endfunction: next_lmul

  // Calculates prev(prev(ew))
  function automatic vew_e prev_prev_ew(vew_e ew);
    unique case (ew)
      EW64: prev_prev_ew    = EW16;
      EW32: prev_prev_ew    = EW8;
      default: prev_prev_ew = EW1024;
    endcase
  endfunction: prev_prev_ew

  /***********************
   *  Backend interface  *
   ***********************/

  ara_req_t ara_req_d;
  logic     ara_req_valid_d;

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

  /***********
   *  State  *
   ***********/

  // The backend can either be in normal operation, or waiting for Ara to be idle before issuing new operations.
  // This can happen, for example, once the vlmul has changed.
  typedef enum logic {
    NORMAL_OPERATION,
    WAIT_IDLE
  } state_e;
  state_e state_d, state_q;

  // We need to memorize the element width used to store each vector on the lanes, so that we are able to
  // deshuffle it when needed.
  rvv_pkg::vew_e [31:0] eew_d, eew_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= NORMAL_OPERATION;
      eew_q   <= '{default: rvv_pkg::EW8};
    end else begin
      state_q <= state_d;
      eew_q   <= eew_d;
    end
  end

  /*************
   *  Decoder  *
   *************/

  always_comb begin: p_decoder
    // Default values
    vstart_d = vstart_q;
    vl_d     = vl_q;
    vtype_d  = vtype_q;
    state_d  = state_q;
    eew_d    = eew_q;

    acc_req_ready_o  = 1'b0;
    acc_resp_valid_o = 1'b0;
    acc_resp_o       = '{
      trans_id      : acc_req_i.trans_id,
      load_complete : load_complete_i,
      store_complete: store_complete_i,
      store_pending : store_pending_i,
      fflags_valid  : |fflags_ex_valid_i,
      default       : '0
    };

    // fflags
    for (int lane = 0; lane < NrLanes; lane++)
      acc_resp_o.fflags |= fflags_ex_i[lane];

    ara_req_d = '{
      vl       : vl_q,
      vstart   : vstart_q,
      vtype    : vtype_q,
      emul     : vtype_q.vlmul,
      eew_vs1  : vtype_q.vsew,
      eew_vs2  : vtype_q.vsew,
      eew_vd_op: vtype_q.vsew,
      eew_vmask: eew_q[VMASK],
      default  : '0
    };
    ara_req_valid_d = 1'b0;

    // Is Ara idle?
    if (state_q == WAIT_IDLE && ara_idle_i)
      state_d = NORMAL_OPERATION;

    if (acc_req_valid_i && ara_req_ready_i && acc_resp_ready_i && state_d == NORMAL_OPERATION) begin
      // Acknowledge the request
      acc_req_ready_o = ara_req_ready_i;

      // Decode the instructions based on their opcode
      unique case (acc_req_i.insn.itype.opcode)
        /************************************
         *  Vector Arithmetic instructions  *
         ************************************/

        riscv::OpcodeVec: begin
          // Instruction is of one of the RVV types
          automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

          // These always respond at the same cycle
          acc_resp_valid_o = 1'b1;

          // Decode based on their func3 field
          unique case (insn.varith_type.func3)
            // Configuration instructions
            OPCFG: begin: opcfg
              // These can be acknowledged regardless of the state of Ara
              acc_req_ready_o = 1'b1;

              // Update vtype
              if (insn.vsetvli_type.func1 == 1'b0) begin // vsetvli
                vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetvli_type.zimm10));
              end else if (insn.vsetvl_type.func7 == 7'b100_0000) begin // vsetvl
                vtype_d = vtype_xlen(acc_req_i.rs2[7:0]);
              end else
                acc_resp_o.error = 1'b1;

              // Check whether the updated vtype makes sense
              if ((vtype_d.vsew > rvv_pkg::vew_e'($clog2(ELENB))) || // SEW <= ELEN
                  (vtype_d.vlmul == LMUL_RSVD) ||                    // reserved value
                  (signed'($clog2(ELENB)) + signed'(vtype_d.vlmul) < signed'(vtype_d.vsew))) begin // LMUL >= SEW/ELEN
                vtype_d = '{ vill: 1'b1, default: '0 };
                vl_d    = '0;
              end

              // Update the vector length
              else begin
                // Maximum vector length. VLMAX = LMUL * VLEN / SEW.
                automatic int unsigned vlmax = VLENB >> vtype_d.vsew;
                unique case (vtype_d.vlmul)
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

                if (insn.vsetvl_type.rs1 == '0 && insn.vsetvl_type.rd == '0) begin
                  // Do not update the vector length
                  vl_d = vl_q;
                end else if (insn.vsetvl_type.rs1 == '0 && insn.vsetvl_type.rd != '0) begin
                  // Set the vector length to vlmax
                  vl_d = vlmax;
                end else begin
                  // Normal stripmining
                  vl_d = (vlen_t'(acc_req_i.rs1) > vlmax) ? vlmax : vlen_t'(acc_req_i.rs1);
                end
              end

              // Return the new vl
              acc_resp_o.result = vl_d;

              // If the vtype has changed, wait for the backend before issuing any new instructions.
              if (vtype_d != vtype_q)
                state_d = WAIT_IDLE;
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
                  if (insn.varith_type.vm) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // An illegal instruction is raised if the destination vector is v0
                  if (insn.varith_type.rd == 5'b0) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                end
                6'b010001: begin
                  ara_req_d.op        = ara_pkg::VMADC;
                  ara_req_d.use_vd_op = 1'b1;

                  // Check whether we can access vs1 and vs2
                  unique case (ara_req_d.emul)
                    LMUL_2:
                      if (((insn.varith_type.rs1 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) ||
                          ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if (((insn.varith_type.rs1 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) ||
                          ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if (((insn.varith_type.rs1 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) ||
                          ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    default:
                      if ((insn.varith_type.rs1 == insn.varith_type.rd) ||
                          (insn.varith_type.rs2 == insn.varith_type.rd)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                  endcase
                end
                6'b010010: begin
                  ara_req_d.op = ara_pkg::VSBC;

                  // Encoding corresponding to unmasked operations are reserved
                  if (insn.varith_type.vm) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // An illegal instruction is raised if the destination vector is v0
                  if (insn.varith_type.rd == 5'b0) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                end
                6'b010011: begin
                  ara_req_d.op        = ara_pkg::VMSBC;
                  ara_req_d.use_vd_op = 1'b1;

                  // Check whether we can access vs1 and vs2
                  unique case (ara_req_d.emul)
                    LMUL_2:
                      if (((insn.varith_type.rs1 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) ||
                          ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if (((insn.varith_type.rs1 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) ||
                          ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if (((insn.varith_type.rs1 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) ||
                          ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111))) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    default:
                      if ((insn.varith_type.rs1 == insn.varith_type.rd) ||
                          (insn.varith_type.rs2 == insn.varith_type.rd)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                  endcase
                end
                6'b011000: begin
                  ara_req_d.op        = VMSEQ;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011001: begin
                  ara_req_d.op        = VMSNE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011010: begin
                  ara_req_d.op        = VMSLTU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011011: begin
                  ara_req_d.op        = VMSLT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011100: begin
                  ara_req_d.op        = VMSLEU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011101: begin
                  ara_req_d.op        = VMSLE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.v does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                6'b101100: begin
                  ara_req_d.op             = ara_pkg::VNSRL;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                6'b101101: begin
                  ara_req_d.op             = ara_pkg::VNSRA;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000 || (insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000 || (insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000 || (insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                default:;
              endcase

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end

            OPIVX: begin: opivx
              // These generate a request to Ara's backend
              ara_req_d.scalar_op     = acc_req_i.rs1;
              ara_req_d.use_scalar_op = 1'b1;
              ara_req_d.vs2           = insn.varith_type.rs2;
              ara_req_d.use_vs2       = 1'b1;
              ara_req_d.vd            = insn.varith_type.rd;
              ara_req_d.use_vd        = 1'b1;
              ara_req_d.vm            = insn.varith_type.vm;
              ara_req_valid_d         = 1'b1;

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
                6'b010000: begin
                  ara_req_d.op = ara_pkg::VADC;

                  // Encoding corresponding to unmasked operations are reserved
                  if (insn.varith_type.vm) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // An illegal instruction is raised if the destination vector is v0
                  if (insn.varith_type.rd == 5'b0) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                end
                6'b010001: begin
                  ara_req_d.op        = ara_pkg::VMADC;
                  ara_req_d.use_vd_op = 1'b1;

                  // Check whether we can access vs1 and vs2
                  unique case (ara_req_d.emul)
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    default:
                      if (insn.varith_type.rs2 == insn.varith_type.rd) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                  endcase
                end
                6'b010010: begin
                  ara_req_d.op = ara_pkg::VSBC;

                  // Encoding corresponding to unmasked operations are reserved
                  if (insn.varith_type.vm) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // An illegal instruction is raised if the destination vector is v0
                  if (insn.varith_type.rd == 5'b0) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                end
                6'b010011: begin
                  ara_req_d.op        = ara_pkg::VMSBC;
                  ara_req_d.use_vd_op = 1'b1;

                  // Check whether we can access vs1 and vs2
                  unique case (ara_req_d.emul)
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    default:
                      if (insn.varith_type.rs2 == insn.varith_type.rd) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                  endcase
                end
                6'b011000: begin
                  ara_req_d.op        = VMSEQ;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011001: begin
                  ara_req_d.op        = VMSNE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011010: begin
                  ara_req_d.op        = VMSLTU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011011: begin
                  ara_req_d.op        = VMSLT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011100: begin
                  ara_req_d.op        = VMSLEU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011101: begin
                  ara_req_d.op        = VMSLE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011110: begin
                  ara_req_d.op        = VMSGTU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011111: begin
                  ara_req_d.op        = VMSGT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.x does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                6'b101100: begin
                  ara_req_d.op             = ara_pkg::VNSRL;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                6'b101101: begin
                  ara_req_d.op             = ara_pkg::VNSRA;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                default:;
              endcase

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
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
              ara_req_valid_d         = 1'b1;

              // Decode based on the func6 field
              unique case (insn.varith_type.func6)
                6'b000000: ara_req_d.op = ara_pkg::VADD;
                6'b000011: ara_req_d.op = ara_pkg::VRSUB;
                6'b001001: ara_req_d.op = ara_pkg::VAND;
                6'b001010: ara_req_d.op = ara_pkg::VOR;
                6'b001011: ara_req_d.op = ara_pkg::VXOR;
                6'b010000: begin
                  ara_req_d.op = ara_pkg::VADC;

                  // Encoding corresponding to unmasked operations are reserved
                  if (insn.varith_type.vm) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // An illegal instruction is raised if the destination vector is v0
                  if (insn.varith_type.rd == 5'b0) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                end
                6'b010001: begin
                  ara_req_d.op        = ara_pkg::VMADC;
                  ara_req_d.use_vd_op = 1'b1;

                  // Check whether we can access vs1 and vs2
                  unique case (ara_req_d.emul)
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) == (insn.varith_type.rd & 5'b00001)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) == (insn.varith_type.rd & 5'b00011)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) == (insn.varith_type.rd & 5'b00111)) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    default:
                      if (insn.varith_type.rs2 == insn.varith_type.rd) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                  endcase
                end
                6'b011000: begin
                  ara_req_d.op        = VMSEQ;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011001: begin
                  ara_req_d.op        = VMSNE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011100: begin
                  ara_req_d.op        = VMSLEU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011101: begin
                  ara_req_d.op        = VMSLE;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011110: begin
                  ara_req_d.op        = VMSGTU;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011111: begin
                  ara_req_d.op        = VMSGT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.i does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                6'b101100: begin
                  ara_req_d.op             = ara_pkg::VNSRL;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                6'b101101: begin
                  ara_req_d.op             = ara_pkg::VNSRA;
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();

                  // Check whether the EEW is not too wide.
                  if (int'(vtype_q.vsew) > int'(EW32)) begin
                    // Trigger an error
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end

                  // Check whether we can access vs2
                  unique case (ara_req_d.emul.next())
                    LMUL_2:
                      if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_4:
                      if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_8:
                      if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000) begin
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    LMUL_RSVD: begin
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
                    default:;
                  endcase
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                default:;
              endcase

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end

            OPMVV: begin: opmvv
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
                6'b011000: begin
                  ara_req_d.op        = ara_pkg::VMANDNOT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011001: begin
                  ara_req_d.op        = ara_pkg::VMAND;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011010: begin
                  ara_req_d.op        = ara_pkg::VMOR;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011011: begin
                  ara_req_d.op        = ara_pkg::VMXOR;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011100: begin
                  ara_req_d.op        = ara_pkg::VMORNOT;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011101: begin
                  ara_req_d.op        = ara_pkg::VMNAND;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011110: begin
                  ara_req_d.op        = ara_pkg::VMNOR;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b011111: begin
                  ara_req_d.op        = ara_pkg::VMXNOR;
                  ara_req_d.use_vd_op = 1'b1;
                end
                6'b010010: begin // VXUNARY0
                  // These instructions do not use vs1
                  ara_req_d.use_vs1       = 1'b0;
                  // They are always encoded as ADDs with zero.
                  ara_req_d.op            = VADD;
                  ara_req_d.use_scalar_op = 1'b1;
                  ara_req_d.scalar_op     = '0;

                  case (insn.varith_type.rs1)
                    5'b00010: begin // VZEXT.VF8
                      ara_req_d.conversion_vs2 = OpQueueConversionZExt8;
                      ara_req_d.eew_vs2        = eew_q[insn.varith_type.rs2];

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW64) || int'(vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    5'b00011: begin // VSEXT.VF8
                      ara_req_d.conversion_vs2 = OpQueueConversionSExt8;
                      ara_req_d.eew_vs2        = eew_q[insn.varith_type.rs2];

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW64) || int'(vtype_q.vlmul) inside {LMUL_1_2, LMUL_1_4, LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    5'b00100: begin // VZEXT.VF4
                      ara_req_d.conversion_vs2 = OpQueueConversionZExt4;
                      ara_req_d.eew_vs2        = prev_prev_ew(vtype_q.vsew);

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW32) || int'(vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    5'b00101: begin // VSEXT.VF4
                      ara_req_d.conversion_vs2 = OpQueueConversionSExt4;
                      ara_req_d.eew_vs2        = prev_prev_ew(vtype_q.vsew);

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW32) || int'(vtype_q.vlmul) inside {LMUL_1_4, LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    5'b00110: begin // VZEXT.VF2
                      ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                      ara_req_d.eew_vs2        = vtype_q.vsew.prev();

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW16) || int'(vtype_q.vlmul) inside {LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    5'b00111: begin // VSEXT.VF2
                      ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                      ara_req_d.eew_vs2        = vtype_q.vsew.prev();

                      // Invalid conversion
                      if (int'(vtype_q.vsew) < int'(EW16) || int'(vtype_q.vlmul) inside {LMUL_1_8}) begin
                        // Trigger an error
                        acc_resp_o.error = 1'b1;
                        ara_req_valid_d  = 1'b0;
                      end
                    end
                    default: begin
                      // Trigger an error
                      acc_resp_o.error = 1'b1;
                      ara_req_valid_d  = 1'b0;
                    end
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
                end
                6'b110001: begin // VWADD
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b110010: begin // VWSUBU
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                end
                6'b110011: begin // VWSUB
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b110100: begin // VWADDU.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110101: begin // VWADD.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110110: begin // VWSUBU.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110111: begin // VWSUB.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b111000: begin // VWMULU
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                end
                6'b111010: begin // VWMULSU
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b111011: begin // VWMUL
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b111100: begin // VWMACCU
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                6'b111101: begin // VWMACC
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                6'b111111: begin // VWMACCSU
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000 || (insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000 || (insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000 || (insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                default:;
              endcase

              // Ara cannot support instructions who operates on more than 64 bits.
              if (int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end

            OPMVX: begin: opmvx
              // These generate a request to Ara's backend
              ara_req_d.scalar_op     = acc_req_i.rs1;
              ara_req_d.use_scalar_op = 1'b1;
              ara_req_d.vs2           = insn.varith_type.rs2;
              ara_req_d.use_vs2       = 1'b1;
              ara_req_d.vd            = insn.varith_type.rd;
              ara_req_d.use_vd        = 1'b1;
              ara_req_d.vm            = insn.varith_type.vm;
              ara_req_valid_d         = 1'b1;

              // Decode based on the func6 field
              unique case (insn.varith_type.func6)
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
                end
                6'b110001: begin // VWADD
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b110010: begin // VWSUBU
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                end
                6'b110011: begin // VWSUB
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b110100: begin // VWADDU.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110101: begin // VWADD.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110110: begin // VWSUBU.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b110111: begin // VWSUB.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.eew_vs2        = vtype_q.vsew.next();
                end
                6'b111000: begin // VWMULU
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                end
                6'b111010: begin // VWMULSU
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b111011: begin // VWMUL
                  ara_req_d.op             = ara_pkg::VMUL;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                end
                6'b111100: begin // VWMACCU
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                6'b111101: begin // VWMACC
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                6'b111110: begin // VWMACCUS
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                6'b111111: begin // VWMACCSU
                  ara_req_d.op             = ara_pkg::VMACC;
                  ara_req_d.use_vd_op      = 1'b1;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt2;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt2;
                  ara_req_d.eew_vd_op      = vtype_q.vsew.next();
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                default:;
              endcase

              // Ara cannot support instructions who operates on more than 64 bits.
              if (int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end

            OPFVV: begin: opfvv
              // These generate a request to Ara's backend
              ara_req_d.vs1     = insn.varith_type.rs1;
              ara_req_d.use_vs1 = 1'b1;
              ara_req_d.vs2     = insn.varith_type.rs2;
              ara_req_d.use_vs2 = 1'b1;
              ara_req_d.vd      = insn.varith_type.rd;
              ara_req_d.use_vd  = 1'b1;
              ara_req_d.vm      = insn.varith_type.vm;
              ara_req_d.fp_rm   = acc_req_i.frm;
              ara_req_valid_d   = 1'b1;

              // Decode based on the func6 field
              unique case (insn.varith_type.func6)
                // VFP Addition
                6'b000000: begin
                  ara_req_d.op             = ara_pkg::VFADD;
                  // When performing a floating-point add/sub, fpnew adds the second and the third operand
                  // So, send the first operand (vs2) to the third result queue
                  ara_req_d.swap_vs2_vd_op = 1'b1;
                end
                6'b000010: begin
                  ara_req_d.op             = ara_pkg::VFSUB;
                  ara_req_d.swap_vs2_vd_op = 1'b1;
                end
                6'b000100: ara_req_d.op = ara_pkg::VFMIN;
                6'b000110: ara_req_d.op = ara_pkg::VFMAX;
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
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs1 & 5'b00001) != 5'b00000 || (insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs1 & 5'b00011) != 5'b00000 || (insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs1 & 5'b00111) != 5'b00000 || (insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_RSVD: begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
                default:;
              endcase

              // Ara supports 16-bit float, 32-bit float, 64-bit float.
              // Ara cannot support instructions who operates on more than 64 bits.
              // Ara cannot support 16-bit float if the scalar core (CVA6) does not support them
              if (ariane_pkg::XF16) begin
                if (int'(ara_req_d.vtype.vsew) < int'(EW16) || int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              end else begin
                if (int'(ara_req_d.vtype.vsew) < int'(EW32) || int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              end

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end

            OPFVF: begin: opfvf
              // These generate a request to Ara's backend
              ara_req_d.scalar_op     = acc_req_i.rs1;
              ara_req_d.use_scalar_op = 1'b1;
              ara_req_d.vs2           = insn.varith_type.rs2;
              ara_req_d.use_vs2       = 1'b1;
              ara_req_d.vd            = insn.varith_type.rd;
              ara_req_d.use_vd        = 1'b1;
              ara_req_d.vm            = insn.varith_type.vm;
              ara_req_d.fp_rm         = acc_req_i.frm;
              ara_req_valid_d         = 1'b1;

              // Decode based on the func6 field
              unique case (insn.varith_type.func6)
                // VFP Addition
                6'b000000: begin
                  ara_req_d.op             = ara_pkg::VFADD;
                  // When performing a floating-point add/sub, fpnew adds the second and the third operand
                  // So, send the first operand (vs2) to the third result queue
                  ara_req_d.swap_vs2_vd_op = 1'b1;
                end
                6'b000010: begin
                  ara_req_d.op             = ara_pkg::VFSUB;
                  ara_req_d.swap_vs2_vd_op = 1'b1;
                end
                6'b000100: ara_req_d.op = ara_pkg::VFMIN;
                6'b000110: ara_req_d.op = ara_pkg::VFMAX;
                6'b100100: ara_req_d.op = ara_pkg::VFMUL;
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
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              unique case (ara_req_d.emul)
                LMUL_2:
                  if ((insn.varith_type.rs2 & 5'b00001) != 5'b00000 || (insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if ((insn.varith_type.rs2 & 5'b00011) != 5'b00000 || (insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if ((insn.varith_type.rs2 & 5'b00111) != 5'b00000 || (insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_RSVD: begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
                default:;
              endcase

              // Ara supports 16-bit float, 32-bit float, 64-bit float.
              // Ara cannot support instructions who operates on more than 64 bits.
              // Ara cannot support 16-bit float if the scalar core (CVA6) does not support them
              if (ariane_pkg::XF16) begin
                if (int'(ara_req_d.vtype.vsew) < int'(EW16) || int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              end else begin
                if (int'(ara_req_d.vtype.vsew) < int'(EW32) || int'(ara_req_d.vtype.vsew) > int'(EW64)) begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              end

              // Instruction is invalid if the vtype is invalid
              if (vtype_q.vill) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            end
          endcase
        end

        /******************
         *  Vector Loads  *
         ******************/

        riscv::OpcodeLoadFp: begin
          // Instruction is of one of the RVV types
          automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

          // Wait before acknowledging this instruction
          acc_req_ready_o = 1'b0;

          // These generate a request to Ara's backend
          ara_req_d.vd        = insn.vmem_type.rd;
          ara_req_d.use_vd    = 1'b1;
          ara_req_d.vm        = insn.vmem_type.vm;
          ara_req_d.scalar_op = acc_req_i.rs1;
          ara_req_valid_d     = 1'b1;

          // Decode the addressing mode
          unique case (insn.vmem_type.mop)
            2'b00: begin
              ara_req_d.op = VLE;

              // Decode the lumop field
              case (insn.vmem_type.rs2)
                5'b00000:;      // Unit-strided
                5'b01000:;      // Unit-strided, whole registers
                5'b10000: begin // Unit-strided, fault-only first
                  // TODO: Not implemented
                  acc_req_ready_o  = 1'b1;
                  acc_resp_o.error = 1'b1;
                  acc_resp_valid_o = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
                default: begin // Reserved
                  acc_req_ready_o  = 1'b1;
                  acc_resp_o.error = 1'b1;
                  acc_resp_valid_o = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase
            end
            2'b01: begin // Invalid
              acc_req_ready_o  = 1'b1;
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
              ara_req_valid_d  = 1'b0;
            end
            2'b10: begin
              ara_req_d.op     = VLSE;
              ara_req_d.stride = acc_req_i.rs2;
            end
            2'b11: begin
              ara_req_d.op      = VLXE;
              // These also read vs2
              ara_req_d.vs2     = insn.vmem_type.rs2;
              ara_req_d.use_vs2 = 1'b1;
            end
            default:;
          endcase

          // Decode the element width
          unique case ({insn.vmem_type.mew, insn.vmem_type.width})
            4'b0000: ara_req_d.vtype.vsew = EW8;
            4'b0101: ara_req_d.vtype.vsew = EW16;
            4'b0110: ara_req_d.vtype.vsew = EW32;
            4'b0111: ara_req_d.vtype.vsew = EW64;
            default: begin // Invalid. Element is too wide, or encoding is non-existant.
              acc_req_ready_o  = 1'b1;
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
              ara_req_valid_d  = 1'b0;
            end
          endcase

          // Instructions with an integer LMUL have extra constraints on the registers they can access.
          unique case (ara_req_d.emul)
            LMUL_2:
              if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_4:
              if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_8:
              if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            default:;
          endcase

          // Vector register register loads are encoded as loads of length VLENB, length multiplier
          // LMUL_1 and element width EW8. They overwrite all this decoding.
          if (ara_req_d.op == VLE && insn.vmem_type.rs2 == 5'b01000) begin
            ara_req_d.eew_vs1 = EW8;
            ara_req_d.emul    = LMUL_1;
            ara_req_d.vl      = VLENB;

            acc_req_ready_o  = 1'b1;
            acc_resp_o.error = 1'b0;
            acc_resp_valid_o = 1'b0;
            ara_req_valid_d  = 1'b0;
          end

          // Wait until the back-end answers to acknowledge those instructions
          if (ara_resp_valid_i) begin
            acc_req_ready_o  = 1'b1;
            acc_resp_o.error = ara_resp_i.error;
            acc_resp_valid_o = 1'b1;
            ara_req_valid_d  = 1'b0;
          end
        end

        /*******************
         *  Vector Stores  *
         *******************/

        riscv::OpcodeStoreFp: begin
          // Instruction is of one of the RVV types
          automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

          // Wait before acknowledging this instruction
          acc_req_ready_o = 1'b0;

          // These generate a request to Ara's backend
          ara_req_d.vs1       = insn.vmem_type.rd; // vs3 is encoded in the same position as rd
          ara_req_d.use_vs1   = 1'b1;
          ara_req_d.eew_vs1   = eew_q[insn.vmem_type.rd];
          ara_req_d.vm        = insn.vmem_type.vm;
          ara_req_d.scalar_op = acc_req_i.rs1;
          ara_req_valid_d     = 1'b1;

          // Decode the addressing mode
          unique case (insn.vmem_type.mop)
            2'b00: begin
              ara_req_d.op = VSE;

              // Decode the sumop field
              unique case (insn.vmem_type.rs2)
                5'b00000:;     // Unit-strided
                5'b01000:;     // Unit-strided, whole registers
                default: begin // Reserved
                  acc_req_ready_o  = 1'b1;
                  acc_resp_o.error = 1'b1;
                  acc_resp_valid_o = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase
            end
            2'b10: begin
              ara_req_d.op     = VSSE;
              ara_req_d.stride = acc_req_i.rs2;
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

          // Decode the element width
          unique case ({insn.vmem_type.mew, insn.vmem_type.width})
            4'b0000: ara_req_d.vtype.vsew = EW8;
            4'b0101: ara_req_d.vtype.vsew = EW16;
            4'b0110: ara_req_d.vtype.vsew = EW32;
            4'b0111: ara_req_d.vtype.vsew = EW64;
            default: begin // Invalid. Element is too wide, or encoding is non-existant.
              acc_req_ready_o  = 1'b1;
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
              ara_req_valid_d  = 1'b0;
            end
          endcase

          // Instructions with an integer LMUL have extra constraints on the registers they can access.
          unique case (ara_req_d.emul)
            LMUL_2:
              if ((insn.varith_type.rd & 5'b00001) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_4:
              if ((insn.varith_type.rd & 5'b00011) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_8:
              if ((insn.varith_type.rd & 5'b00111) != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                acc_resp_valid_o = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            default:;
          endcase

          // Vector register register stores are encoded as stores of length VLENB, length multiplier
          // LMUL_1 and element width EW8. They overwrite all this decoding.
          if (ara_req_d.op == VSE && insn.vmem_type.rs2 == 5'b01000) begin
            ara_req_d.eew_vs1 = EW8;
            ara_req_d.emul    = LMUL_1;
            ara_req_d.vl      = VLENB;

            acc_req_ready_o  = 1'b1;
            acc_resp_o.error = 1'b0;
            acc_resp_valid_o = 1'b0;
            ara_req_valid_d  = 1'b0;
          end

          // Wait until the back-end answers to acknowledge those instructions
          if (ara_resp_valid_i) begin
            acc_req_ready_o  = 1'b1;
            acc_resp_o.error = ara_resp_i.error;
            acc_resp_valid_o = 1'b1;
            ara_req_valid_d  = 1'b0;
          end
        end

        /**************************
         *  CSR Reads and Writes  *
         **************************/

        riscv::OpcodeSystem: begin
          // These always respond at the same cycle
          acc_resp_valid_o = 1'b1;

          unique case (acc_req_i.insn.itype.funct3)
            3'b001: begin // csrrw
              // Decode the CSR.
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                // Only vstart can be written with CSR instructions.
                riscv::CSR_VSTART: begin
                  vstart_d          = acc_req_i.rs1;
                  acc_resp_o.result = vstart_q;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            3'b010: begin // csrrs
              // Decode the CSR.
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                riscv::CSR_VSTART: begin
                  vstart_d          = vstart_q | vlen_t'(acc_req_i.rs1);
                  acc_resp_o.result = vstart_q;
                end
                riscv::CSR_VTYPE: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = xlen_vtype(vtype_q);
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VL: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = vl_q;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VLENB: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = VLENB;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            3'b011: begin // csrrc
              // Decode the CSR.
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                riscv::CSR_VSTART: begin
                  vstart_d          = vstart_q & ~vlen_t'(acc_req_i.rs1);
                  acc_resp_o.result = vstart_q;
                end
                riscv::CSR_VTYPE: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = xlen_vtype(vtype_q);
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VL: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = vl_q;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VLENB: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = VLENB;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            3'b101: begin // csrrwi
              // Decode the CSR.
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                // Only vstart can be written with CSR instructions.
                riscv::CSR_VSTART: begin
                  vstart_d          = vlen_t'(acc_req_i.insn.itype.rs1);
                  acc_resp_o.result = vstart_q;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            3'b110: begin // csrrsi
              // Decode the CSR.
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                riscv::CSR_VSTART: begin
                  vstart_d          = vstart_q | vlen_t'(acc_req_i.insn.itype.rs1);
                  acc_resp_o.result = vstart_q;
                end
                riscv::CSR_VTYPE: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = xlen_vtype(vtype_q);
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VL: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = vl_q;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VLENB: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = VLENB;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            3'b111: begin // csrrci
              // Decode the CSR.
              unique case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
                riscv::CSR_VSTART: begin
                  vstart_d          = vstart_q & ~vlen_t'(acc_req_i.insn.itype.rs1);
                  acc_resp_o.result = vstart_q;
                end
                riscv::CSR_VTYPE: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = xlen_vtype(vtype_q);
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VL: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = vl_q;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                riscv::CSR_VLENB: begin
                  // Only reads are allowed
                  if (acc_req_i.insn.itype.rs1 == '0) begin
                    acc_resp_o.result = VLENB;
                  end else
                    acc_resp_o.error = 1'b1;
                end
                default: acc_resp_o.error = 1'b1;
              endcase
            end
            default: begin
              // Trigger an illegal instruction
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
            end
          endcase
        end

        default: begin
          // Trigger an illegal instruction
          acc_resp_o.error = 1'b1;
          acc_resp_valid_o = 1'b1;
        end
      endcase
    end

    // Update the EEW
    if (ara_req_valid_d && ara_req_d.use_vd) begin
      eew_d[ara_req_d.vd] = ara_req_d.vtype.vsew;
    end
  end: p_decoder

endmodule : ara_dispatcher
