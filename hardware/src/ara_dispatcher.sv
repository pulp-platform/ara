// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File:   ara_dispatcher.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's dispatcher interfaces Ariane's requests with the vector lanes.
// It also acknowledges instructions back to Ariane, perhaps with a
// response or an error message.

module ara_dispatcher import ara_pkg::*; import rvv_pkg::*; (
    // Clock and reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Interfaces with Ariane
    input  accelerator_req_t  acc_req_i,
    input  logic              acc_req_valid_i,
    output logic              acc_req_ready_o,
    output accelerator_resp_t acc_resp_o,
    output logic              acc_resp_valid_o,
    input  logic              acc_resp_ready_i,
    // Interface with Ara's backend
    output ara_req_t          ara_req_o,
    output logic              ara_req_valid_o,
    input  logic              ara_req_ready_i,
    input  ara_resp_t         ara_resp_i,
    input  logic              ara_resp_valid_i,
    input  logic              ara_idle_i,
    // Interface with the Vector Store Unit
    input  logic              store_pending_i
  );

  `include "common_cells/registers.svh"

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= NORMAL_OPERATION;
    end else begin
      state_q <= state_d;
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

    acc_req_ready_o  = 1'b0;
    acc_resp_valid_o = 1'b0;
    acc_resp_o       = '{
      trans_id     : acc_req_i.trans_id,
      store_pending: store_pending_i,
      default      : '0
    };

    ara_req_d = '{
      vl     : vl_q,
      vstart : vstart_q,
      vtype  : vtype_q,
      emul   : vtype_q.vlmul,
      eew    : vtype_q.vsew,
      default: '0
    };
    ara_req_valid_d = 1'b0;

    // Is Ara idle?
    if (state_q == WAIT_IDLE && ara_idle_i)
      state_d = NORMAL_OPERATION;

    if (acc_req_valid_i && acc_resp_ready_i && state_d == NORMAL_OPERATION) begin
      // Acknowledge the request
      acc_req_ready_o = ara_req_ready_i;

      // Decode the instructions based on their opcode
      case (acc_req_i.insn.itype.opcode)
        /************************************
         *  Vector Arithmetic instructions  *
         ************************************/

        riscv::OpcodeVec: begin
          // Instruction is of one of the RVV types
          automatic rvv_instruction_t insn = rvv_instruction_t'(acc_req_i.insn.instr);

          // These always respond at the same cycle
          acc_resp_valid_o = 1'b1;

          // Decode based on their func3 field
          case (insn.varith_type.func3)
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
                case (vtype_d.vlmul)
                  LMUL_1  : vlmax <<= 0;
                  LMUL_2  : vlmax <<= 1;
                  LMUL_4  : vlmax <<= 2;
                  LMUL_8  : vlmax <<= 3;
                  // Fractional LMUL
                  LMUL_1_2: vlmax >>= 1;
                  LMUL_1_4: vlmax >>= 2;
                  LMUL_1_8: vlmax >>= 3;
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
              case (insn.varith_type.func6)
                6'b000000: ara_req_d.op = ara_pkg::VADD;
                6'b000010: ara_req_d.op = ara_pkg::VSUB;
                6'b000100: ara_req_d.op = ara_pkg::VMINU;
                6'b000101: ara_req_d.op = ara_pkg::VMIN;
                6'b000110: ara_req_d.op = ara_pkg::VMAXU;
                6'b000111: ara_req_d.op = ara_pkg::VMAX;
                6'b001001: ara_req_d.op = ara_pkg::VAND;
                6'b001010: ara_req_d.op = ara_pkg::VOR;
                6'b001011: ara_req_d.op = ara_pkg::VXOR;
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.v does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              case (ara_req_d.emul)
                LMUL_2:
                  if (insn.varith_type.rs1 & 5'b00001 != 5'b00000 || insn.varith_type.rs2 & 5'b00001 != 5'b00000 || insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if (insn.varith_type.rs1 & 5'b00011 != 5'b00000 || insn.varith_type.rs2 & 5'b00011 != 5'b00000 || insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if (insn.varith_type.rs1 & 5'b00111 != 5'b00000 || insn.varith_type.rs2 & 5'b00111 != 5'b00000 || insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
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
              case (insn.varith_type.func6)
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
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.x does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              case (ara_req_d.emul)
                LMUL_2:
                  if (insn.varith_type.rs2 & 5'b00001 != 5'b00000 || insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if (insn.varith_type.rs2 & 5'b00011 != 5'b00000 || insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if (insn.varith_type.rs2 & 5'b00111 != 5'b00000 || insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
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
              case (insn.varith_type.func6)
                6'b000000: ara_req_d.op = ara_pkg::VADD;
                6'b000011: ara_req_d.op = ara_pkg::VRSUB;
                6'b001001: ara_req_d.op = ara_pkg::VAND;
                6'b001010: ara_req_d.op = ara_pkg::VOR;
                6'b001011: ara_req_d.op = ara_pkg::VXOR;
                6'b010111: begin
                  ara_req_d.op      = ara_pkg::VMERGE;
                  ara_req_d.use_vs2 = !insn.varith_type.vm; // vmv.v.i does not use vs2
                end
                6'b100101: ara_req_d.op = ara_pkg::VSLL;
                6'b101000: ara_req_d.op = ara_pkg::VSRL;
                6'b101001: ara_req_d.op = ara_pkg::VSRA;
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              case (ara_req_d.emul)
                LMUL_2:
                  if (insn.varith_type.rs2 & 5'b00001 != 5'b00000 || insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if (insn.varith_type.rs2 & 5'b00011 != 5'b00000 || insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if (insn.varith_type.rs2 & 5'b00111 != 5'b00000 || insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
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
              case (insn.varith_type.func6)
                6'b011000: ara_req_d.op = ara_pkg::VMANDNOT;
                6'b011001: ara_req_d.op = ara_pkg::VMAND;
                6'b011010: ara_req_d.op = ara_pkg::VMOR;
                6'b011011: ara_req_d.op = ara_pkg::VMXOR;
                6'b011100: ara_req_d.op = ara_pkg::VMORNOT;
                6'b011101: ara_req_d.op = ara_pkg::VMNAND;
                6'b011110: ara_req_d.op = ara_pkg::VMNOR;
                6'b011111: ara_req_d.op = ara_pkg::VMXNOR;
                // Widening instructions
                6'b110000: begin // VWADDU
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110001: begin // VWADD
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110010: begin // VWSUBU
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110011: begin // VWSUB
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110100: begin // VWADDU.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110101: begin // VWADD.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110110: begin // VWSUBU.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110111: begin // VWSUB.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Ara can only support this kind of operation if vl mod 8 == 0.
              // Otherwise, we would either need to have a 'bit enable' signal to leave
              // individual bits untouched, or we would need to read back the destination
              // register before writing the result back to the VRF.
              if (ara_req_d.op inside {VMANDNOT, VMAND, VMOR, VMXOR, VMORNOT, VMNAND, VMNOR, VMXNOR}) begin
                if (vl_q % 8 != '0) begin
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              end

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              case (ara_req_d.emul)
                LMUL_2:
                  if (insn.varith_type.rs1 & 5'b00001 != 5'b00000 || insn.varith_type.rs2 & 5'b00001 != 5'b00000 || insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if (insn.varith_type.rs1 & 5'b00011 != 5'b00000 || insn.varith_type.rs2 & 5'b00011 != 5'b00000 || insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if (insn.varith_type.rs1 & 5'b00111 != 5'b00000 || insn.varith_type.rs2 & 5'b00111 != 5'b00000 || insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
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
              case (insn.varith_type.func6)
                // Widening instructions
                6'b110000: begin // VWADDU
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110001: begin // VWADD
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110010: begin // VWSUBU
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionZExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110011: begin // VWSUB
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs1 = OpQueueConversionSExt;
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110100: begin // VWADDU.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110101: begin // VWADD.W
                  ara_req_d.op             = ara_pkg::VADD;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                6'b110110: begin // VWSUBU.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionZExt;
                end
                6'b110111: begin // VWSUB.W
                  ara_req_d.op             = ara_pkg::VSUB;
                  ara_req_d.emul           = next_lmul(vtype_q.vlmul);
                  ara_req_d.vtype.vsew     = vtype_q.vsew.next();
                  ara_req_d.conversion_vs2 = OpQueueConversionSExt;
                end
                default: begin
                  // Trigger an error
                  acc_resp_o.error = 1'b1;
                  ara_req_valid_d  = 1'b0;
                end
              endcase

              // Instructions with an integer LMUL have extra constraints on the registers they can access.
              case (ara_req_d.emul)
                LMUL_2:
                  if (insn.varith_type.rs2 & 5'b00001 != 5'b00000 || insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_4:
                  if (insn.varith_type.rs2 & 5'b00011 != 5'b00000 || insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
                LMUL_8:
                  if (insn.varith_type.rs2 & 5'b00111 != 5'b00000 || insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                    acc_resp_o.error = 1'b1;
                    ara_req_valid_d  = 1'b0;
                  end
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
          case (insn.vmem_type.mop)
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
          endcase

          // Decode the effective element width
          case ({insn.vmem_type.mew, insn.vmem_type.width})
            4'b0000: ara_req_d.eew = EW8;
            4'b0101: ara_req_d.eew = EW16;
            4'b0110: ara_req_d.eew = EW32;
            4'b0111: ara_req_d.eew = EW64;
            default: begin // Invalid. Element is too wide, or encoding is non-existant.
              acc_req_ready_o  = 1'b1;
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
              ara_req_valid_d  = 1'b0;
            end
          endcase

          // Instructions with an integer LMUL have extra constraints on the registers they can access.
          case (ara_req_d.emul)
            LMUL_2:
              if (insn.varith_type.rd & 5'b00001 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_4:
              if (insn.varith_type.rd & 5'b00011 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_8:
              if (insn.varith_type.rd & 5'b00111 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
          endcase

          // Vector register register loads are encoded as loads of length VLENB, length multiplier
          // LMUL_1 and element width EW8. They overwrite all this decoding.
          if (ara_req_d.op == VLE && insn.vmem_type.rs2 == 5'b01000) begin
            ara_req_d.eew  = EW8;
            ara_req_d.emul = LMUL_1;
            ara_req_d.vl   = VLENB;

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
          ara_req_d.vm        = insn.vmem_type.vm;
          ara_req_d.scalar_op = acc_req_i.rs1;
          ara_req_valid_d     = 1'b1;

          // Decode the addressing mode
          case (insn.vmem_type.mop)
            2'b00: begin
              ara_req_d.op = VSE;

              // Decode the sumop field
              case (insn.vmem_type.rs2)
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
          endcase

          // Decode the element width
          case ({insn.vmem_type.mew, insn.vmem_type.width})
            4'b0000: ara_req_d.eew = EW8;
            4'b0101: ara_req_d.eew = EW16;
            4'b0110: ara_req_d.eew = EW32;
            4'b0111: ara_req_d.eew = EW64;
            default: begin // Invalid. Element is too wide, or encoding is non-existant.
              acc_req_ready_o  = 1'b1;
              acc_resp_o.error = 1'b1;
              acc_resp_valid_o = 1'b1;
              ara_req_valid_d  = 1'b0;
            end
          endcase

          // Instructions with an integer LMUL have extra constraints on the registers they can access.
          case (ara_req_d.emul)
            LMUL_2:
              if (insn.varith_type.rs1 & 5'b00001 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_4:
              if (insn.varith_type.rs1 & 5'b00011 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
            LMUL_8:
              if (insn.varith_type.rs1 & 5'b00111 != 5'b00000) begin
                acc_resp_o.error = 1'b1;
                ara_req_valid_d  = 1'b0;
              end
          endcase

          // Vector register register stores are encoded as stores of length VLENB, length multiplier
          // LMUL_1 and element width EW8. They overwrite all this decoding.
          if (ara_req_d.op == VSE && insn.vmem_type.rs2 == 5'b01000) begin
            ara_req_d.eew  = EW8;
            ara_req_d.emul = LMUL_1;
            ara_req_d.vl   = VLENB;

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

          case (acc_req_i.insn.itype.funct3)
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
              case (riscv::csr_addr_t'(acc_req_i.insn.itype.imm))
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
  end: p_decoder

endmodule : ara_dispatcher
