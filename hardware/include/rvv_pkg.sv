// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Common RISC-V definitions for RVV.

package rvv_pkg;

  // This package depends on CVA6's riscv package
  import riscv::*;

  //////////////////////////////
  //  Common RVV definitions  //
  //////////////////////////////

  // Element width
  typedef enum logic [2:0] {
    EW8    = 3'b000,
    EW16   = 3'b001,
    EW32   = 3'b010,
    EW64   = 3'b011,
    EW128  = 3'b100,
    EW256  = 3'b101,
    EW512  = 3'b110,
    EW1024 = 3'b111
  } vew_e;

  // Length multiplier
  typedef enum logic [2:0] {
    LMUL_1,
    LMUL_2,
    LMUL_4,
    LMUL_8,
    LMUL_RSVD,
    LMUL_1_8,
    LMUL_1_4,
    LMUL_1_2
  } vlmul_e;

  // Vector type register
  typedef struct packed {
    logic vill;
    logic vma;
    logic vta;
    vew_e vsew;
    vlmul_e vlmul;
  } vtype_t;

  // Func3 values for vector arithmetics instructions under OpcodeV
  typedef enum logic [2:0] {
    OPIVV = 3'b000,
    OPFVV = 3'b001,
    OPMVV = 3'b010,
    OPIVI = 3'b011,
    OPIVX = 3'b100,
    OPFVF = 3'b101,
    OPMVX = 3'b110,
    OPCFG = 3'b111
  } opcodev_func3_e;

  ///////////////////
  //  Vector CSRs  //
  ///////////////////

  function automatic logic is_vector_csr (riscv::csr_reg_t csr);
    case (csr)
      riscv::CSR_VSTART,
      riscv::CSR_VXSAT,
      riscv::CSR_VXRM,
      riscv::CSR_VCSR,
      riscv::CSR_VL,
      riscv::CSR_VTYPE,
      riscv::CSR_VLENB: begin
        return 1'b1;
      end
      default: return 1'b0;
    endcase
  endfunction : is_vector_csr

  ////////////////////////////////
  //  Vector instruction types  //
  ////////////////////////////////

  typedef struct packed {
    logic [31:29] nf;
    logic mew;
    logic [27:26] mop;
    logic vm;
    logic [24:20] rs2;
    logic [19:15] rs1;
    logic [14:12] width;
    logic [11:7] rd;
    logic [6:0] opcode;
  } vmem_type_t;

  typedef struct packed {
    logic [31:27] amoop;
    logic wd;
    logic vm;
    logic [24:20] rs2;
    logic [19:15] rs1;
    logic [14:12] width;
    logic [11:7] rd;
    logic [6:0] opcode;
  } vamo_type_t;

  typedef struct packed {
    logic [31:26] func6;
    logic vm;
    logic [24:20] rs2;
    logic [19:15] rs1;
    opcodev_func3_e func3;
    logic [11:7] rd;
    logic [6:0] opcode;
  } varith_type_t;

  typedef struct packed {
    logic func1;
    logic [30:20] zimm10;
    logic [19:15] rs1;
    opcodev_func3_e func3;
    logic [11:7] rd;
    logic [6:0] opcode;
  } vsetvli_type_t;

  typedef struct packed {
    logic [31:25] func7;
    logic [24:20] rs2;
    logic [19:15] rs1;
    opcodev_func3_e func3;
    logic [11:7] rd;
    logic [6:0] opcode;
  } vsetvl_type_t;

  typedef union packed {
    logic [31:0] instr ;
    riscv::itype_t i_type; // For CSR instructions
    vmem_type_t vmem_type;
    vamo_type_t vamo_type;
    varith_type_t varith_type;
    vsetvli_type_t vsetvli_type;
    vsetvl_type_t vsetvl_type;
  } rvv_instruction_t;

  ////////////////////////////
  //  Vector mask register  //
  ////////////////////////////

  // The mask register is always vreg[0]
  localparam VMASK = 5'b00000;

endpackage : rvv_pkg
