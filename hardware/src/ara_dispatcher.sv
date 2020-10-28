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
    input  logic              acc_resp_ready_i
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

  // Converts between the interval representation of `vtype_t` and the full XLEN-bit CSR.
  function automatic riscv::xlen_t xlen_vtype(vtype_t vtype);
    xlen_vtype = {vtype.vill, {riscv::XLEN-9{1'b0}}, vtype.vma, vtype.vta, vtype.vlmul2, vtype.vsew, vtype.vlmul};
  endfunction: xlen_vtype

  // Converts between the XLEN-bit vtype CSR and its internal representation
  function automatic vtype_t vtype_xlen(riscv::xlen_t xlen);
    vtype_xlen = '{
      vill  : xlen[riscv::XLEN-1],
      vma   : xlen[7],
      vta   : xlen[6],
      vlmul2: xlen[5],
      vsew  : vew_e'(xlen[4:2]),
      vlmul : xlen[1:0]
    };
  endfunction: vtype_xlen

  /*************
   *  Decoder  *
   *************/

  always_comb begin: decoder
    // Default values
    vstart_d = vstart_q;
    vl_d     = vl_q;
    vtype_d  = vtype_q;

    acc_req_ready_o  = 1'b0;
    acc_resp_valid_o = 1'b0;
    acc_resp_o       = '{
      trans_id: acc_req_i.trans_id,
      default : '0
    };

    if (acc_req_valid_i && acc_resp_ready_i) begin
      // Acknowledge the request
      acc_req_ready_o = 1'b1;

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
            OPCFG: begin
              // Length multiplier
              automatic logic signed [2:0] lmul;

              // Update vtype
              if (insn.vsetvli_type.func1 == 1'b0) begin // vsetvli
                vtype_d = vtype_xlen(riscv::xlen_t'(insn.vsetvli_type.zimm10));
              end else if (insn.vsetvl_type.func7 == 7'b100_0000) begin // vsetvl
                vtype_d = vtype_xlen(acc_req_i.rs2[7:0]);
              end else
                acc_resp_o.error = 1'b1;

              // Calculate the length multiplier
              lmul = {vtype_d.vlmul2, vtype_d.vlmul};

              // Check whether the updated vtype makes sense
              if ((vtype_d.vsew > rvv_pkg::vew_e'($clog2(ELENB))) || // SEW <= ELEN
                  (lmul == 3'b100) ||                                // reserved value
                  (signed'($clog2(ELENB)) + signed'(lmul) < signed'(vtype_d.vsew))) begin // LMUL >= SEW/ELEN
                vtype_d = '{ vill: 1'b1, default: '0 };
                vl_d    = '0;
              end

              // Update the vector length
              else begin
                // Maximum vector length. VLMAX = LMUL * VLEN / SEW.
                automatic int unsigned vlmax = vtype_d.vlmul2 ? ((VLENB >> vtype_d.vsew) << vtype_d.vlmul) : ((VLENB >> vtype_d.vsew) >> -vtype_d.vlmul);

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
            end
          endcase
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
  end: decoder

endmodule : ara_dispatcher
