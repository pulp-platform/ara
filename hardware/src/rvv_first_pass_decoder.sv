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
// File:   rvv_first_pass_decoder.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   23.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description: Decides combinatorially whether an instruction is a vector
//              instruction, whether it reads scalar registers, and whether
//              it writes to a destination scalar register

module rvv_first_pass_decoder import rvv_pkg::*; (
    input  logic [31:0] instruction_i, // instruction from IF
    output logic        is_rvv_o,      // is a vector extension
    output logic        is_rs1_o,
    output logic        is_rs2_o,
    output logic        is_rd_o,
    output logic        is_fs1_o,
    output logic        is_fs2_o,
    output logic        is_fd_o
  );

  // Cast instruction into the `rvv_instruction_t` struct
  rvv_instruction_t instr;
  assign instr = rvv_instruction_t'(instruction_i);

  always_comb begin
    // Default values
    is_rvv_o = 1'b0;
    is_rs1_o = 1'b0;
    is_rs2_o = 1'b0;
    is_rd_o  = 1'b0;
    is_fs1_o = 1'b0;
    is_fs2_o = 1'b0;
    is_fd_o  = 1'b0;

    // Decode based on the opcode
    case (instr.i_type.opcode)

      // Arithmetic vector operations
      riscv::OpcodeVec: begin
        is_rvv_o = 1'b1;
        case (instr.varith_type.func3)
          OPFVV: is_fd_o  = instr.varith_type.func6 == 6'b010_000; // VFWUNARY0
          OPMVV: is_rd_o  = instr.varith_type.func6 == 6'b010_000; // VWXUNARY0
          OPIVX: is_rs1_o = 1'b1                                 ;
          OPFVF: is_fs1_o = 1'b1                                 ;
          OPMVX: is_rs1_o = 1'b1                                 ;
          OPCFG: begin
            is_rs1_o = 1'b1                                  ;
            is_rs2_o = instr.vsetvl_type.func7 == 7'b100_0000; // vsetvl
            is_rd_o  = 1'b1                                  ;
          end
        endcase
      end

      // Memory vector operations
      riscv::OpcodeLoadFp,
      riscv::OpcodeStoreFp: begin
        case ({instr.vmem_type.mew, instr.vmem_type.width})
          4'b0000, //VLxE8/VSxE8
          4'b0101, //VLxE16/VSxE16
          4'b0110, //VLxE32/VSxE32
          4'b0111, //VLxE64/VSxE64
          4'b1000, //VLxE128/VSxE128
          4'b1101, //VLxE256/VSxE256
          4'b1110, //VLxE512/VSxE512
          4'b1111: begin //VLxE1024/VSxE1024
            is_rvv_o = 1'b1                        ;
            is_rs1_o = 1'b1                        ;
            is_rs2_o = instr.vmem_type.mop == 2'b10; // Strided operation
          end
        endcase
      end

      // Atomic vector operations
      riscv::OpcodeAmo: begin
        case (instr.vamo_type.width)
          3'b000, //VAMO*EI8.V
          3'b101, //VAMO*EI16.V
          3'b110, //VAMO*EI32.V
          3'b111: begin //VAMO*EI64.V
            is_rvv_o = 1'b1;
            is_rs1_o = 1'b1;
          end
        endcase
      end

      // CSRR/W instructions into vector CSRs
      riscv::OpcodeSystem: begin
        case (instr.i_type.funct3)
          3'b001, //CSRRW
          3'b010, //CSRRS,
          3'b011, //CSRRC,
          3'b101, //CSRRWI
          3'b110, //CSRRSI
          3'b111: begin //CSRRCI
            is_rvv_o = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs1_o = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs2_o = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rd_o  = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
          end
        endcase

      end
    endcase
  end

endmodule : rvv_first_pass_decoder
