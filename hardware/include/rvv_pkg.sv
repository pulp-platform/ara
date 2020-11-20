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
// File:   rvv_pkg.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   26.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description: Common RISC-V definitions for RVV.

package rvv_pkg;

  // This package depends on CVA6's riscv package
  import riscv::*;

  /****************************
   *  Common RVV definitions  *
   ****************************/

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

  // Vector type register
  typedef struct packed {
    logic vill            ;
    logic [XLEN-2:8] wpri0;
    logic vma             ;
    logic vta             ;
    logic vlmul2          ;
    vew_e vsew            ;
    logic [1:0] vlmul     ;
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

  /*****************
   *  Vector CSRs  *
   *****************/

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
  endfunction


  /******************************
   *  Vector instruction types  *
   ******************************/

  typedef struct packed {
    logic [31:29] nf   ;
    logic mew          ;
    logic [27:26] mop  ;
    logic vm           ;
    logic [24:20] rs2  ;
    logic [19:15] rs1  ;
    logic [14:12] width;
    logic [11:7] rd    ;
    logic [6:0] opcode ;
  } vmem_type_t;

  typedef struct packed {
    logic [31:27] amoop;
    logic wd           ;
    logic vm           ;
    logic [24:20] rs2  ;
    logic [19:15] rs1  ;
    logic [14:12] width;
    logic [11:7] rd    ;
    logic [6:0] opcode ;
  } vamo_type_t;

  typedef struct packed {
    logic [31:26] func6  ;
    logic vm             ;
    logic [24:20] rs2    ;
    logic [19:15] rs1    ;
    opcodev_func3_e func3;
    logic [11:7] rd      ;
    logic [6:0] opcode   ;
  } varith_type_t;

  typedef struct packed {
    logic func1          ;
    logic [30:20] zimm10 ;
    logic [19:15] rs1    ;
    opcodev_func3_e func3;
    logic [11:7] rd      ;
    logic [6:0] opcode   ;
  } vsetvli_type_t;

  typedef struct packed {
    logic [31:25] func7  ;
    logic [24:20] rs2    ;
    logic [19:15] rs1    ;
    opcodev_func3_e func3;
    logic [11:7] rd      ;
    logic [6:0] opcode   ;
  } vsetvl_type_t;

  typedef union packed {
    logic [31:0] instr         ;
    riscv::itype_t i_type      ; // For CSR instructions
    vmem_type_t vmem_type      ;
    vamo_type_t vamo_type      ;
    varith_type_t varith_type  ;
    vsetvli_type_t vsetvli_type;
    vsetvl_type_t vsetvl_type  ;
  } rvv_instruction_t;

endpackage : rvv_pkg
