// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description: Decides combinatorially whether an instruction is a vector
//              instruction, whether it reads scalar registers, and whether
//              it writes to a destination scalar register

module cva6_accel_first_pass_decoder import rvv_pkg::*; import ariane_pkg::*; (
    input  logic [31:0]       instruction_i,   // instruction from IF
    input  riscv::xs_t        fs_i,            // floating point extension status
    input  riscv::xs_t        vs_i,            // vector extension status
    output logic              is_accel_o,      // is a vector instruction
    output scoreboard_entry_t instruction_o,   // predecoded instruction
    output logic              illegal_instr_o, // is an illegal instruction
    output logic              is_control_flow_instr_o
  );

  logic        is_rs1;
  logic        is_rs2;
  logic        is_rd;
  logic        is_fs1;
  logic        is_fs2;
  logic        is_fd;
  logic        is_vfp;      // is a vector floating-point instruction
  logic        is_load;
  logic        is_store;

  // Cast instruction into the `rvv_instruction_t` struct
  rvv_instruction_t instr;
  assign instr = rvv_instruction_t'(instruction_i);

  // Cast instruction into scalar `instruction_t` struct
  riscv::instruction_t instr_scalar;
  assign instr_scalar = riscv::instruction_t'(instruction_i);

  // Vector instructions never change control flow
  assign is_control_flow_instr_o = 1'b0;

  always_comb begin
    // Default values
    is_accel_o = 1'b0;
    is_rs1   = 1'b0;
    is_rs2   = 1'b0;
    is_rd    = 1'b0;
    is_fs1   = 1'b0;
    is_fs2   = 1'b0;
    is_fd    = 1'b0;
    is_vfp   = 1'b0;
    is_load  = instr.i_type.opcode == riscv::OpcodeLoadFp;
    is_store = instr.i_type.opcode == riscv::OpcodeStoreFp;

    // Decode based on the opcode
    case (instr.i_type.opcode)

      // Arithmetic vector operations
      riscv::OpcodeVec: begin
        is_accel_o = 1'b1;
        case (instr.varith_type.func3)
          OPFVV: begin
            is_fd  = instr.varith_type.func6 == 6'b010_000; // VFWUNARY0
            is_vfp = 1'b1;
          end
          OPMVV: is_rd  = instr.varith_type.func6 == 6'b010_000; // VWXUNARY0
          OPIVX: is_rs1 = 1'b1 ;
          OPFVF: begin
            is_fs1 = 1'b1;
            is_vfp = 1'b1;
          end
          OPMVX: is_rs1 = 1'b1 ;
          OPCFG: begin
            is_rs1 = instr.vsetivli_type.func2 != 2'b11; // not vsetivli
            is_rs2 = instr.vsetvl_type.func7 == 7'b100_0000; // vsetvl
            is_rd  = 1'b1 ;
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
            is_accel_o = 1'b1 ;
            is_rs1   = 1'b1 ;
            is_rs2   = instr.vmem_type.mop == 2'b10; // Strided operation
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
            is_accel_o = 1'b1;
            is_rs1   = 1'b1;
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
            is_accel_o = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs1   = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs2   = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rd    = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
          end
        endcase
      end
    endcase
  end

  always_comb begin
    instruction_o   = '0;
    illegal_instr_o = 1'b1;

    if (is_accel_o && vs_i != riscv::Off) begin // trigger illegal instruction if the vector extension is turned off
      // TODO: Instruction going to other accelerators might need to distinguish whether the value of vs_i is needed or not.
      // Send accelerator instructions to the coprocessor
      instruction_o.fu  = ACCEL;
      instruction_o.vfp = is_vfp;
      instruction_o.rs1 = (is_rs1 || is_fs1) ? instr_scalar.rtype.rs1 : {REG_ADDR_SIZE{1'b0}};
      instruction_o.rs2 = (is_rs2 || is_fs2) ? instr_scalar.rtype.rs2 : {REG_ADDR_SIZE{1'b0}};
      instruction_o.rd  = (is_rd || is_fd) ? instr_scalar.rtype.rd : {REG_ADDR_SIZE{1'b0}};

      // Decode the vector operation
      unique case ({is_store, is_load, is_fs1, is_fs2, is_fd})
        5'b10000: instruction_o.op = ACCEL_OP_STORE;
        5'b01000: instruction_o.op = ACCEL_OP_LOAD;
        5'b00100: instruction_o.op = ACCEL_OP_FS1;
        5'b00001: instruction_o.op = ACCEL_OP_FD;
        5'b00000: instruction_o.op = ACCEL_OP;
      endcase

      // Check that mstatus.FS is not OFF if we have a FP instruction for the accelerator
      illegal_instr_o = (is_vfp && (fs_i == riscv::Off)) ? 1'b1 : 1'b0;

      // result holds the undecoded instruction
      instruction_o.result = { {riscv::XLEN-32{1'b0}}, instruction_i[31:0] };
      instruction_o.use_imm = 1'b0;
    end
  end

endmodule : cva6_accel_first_pass_decoder
