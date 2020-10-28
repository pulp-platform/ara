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
// File          : vconv_stage.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 27.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This pipeline stage enqueues the operands and converts them to the appropriate
// type.

import ariane_pkg::*;
import ara_pkg::*   ;

module vconv_stage (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    // Interface with VLOOP stage
    input  opqueue_cmd_t [NR_OPQUEUE-1:0] opqueue_cmd_i,
    output logic         [NR_OPQUEUE-1:0] opqueue_ready_o,
    // Interface with VACCESS stage
    input  word_t        [NR_OPQUEUE-1:0] word_i,
    input  logic         [NR_OPQUEUE-1:0] word_issued_i,
    // Interface with VEX stage
    output word_t        [ 2:0]           alu_operand_o,
    output word_t        [ 3:0]           mfpu_operand_o,
    output word_t        [ 1:0]           sld_operand_o,
    output word_t                         ld_operand_o,
    output word_t        [ 1:0]           st_operand_o,
    output word_t                         addrgen_operand_o,
    input  logic                          alu_operand_ready_i,
    input  logic                          mfpu_operand_ready_i,
    input  logic                          red_operand_ready_i,
    input  logic                          ld_operand_ready_i,
    input  logic                          st_operand_ready_i,
    input  logic                          addrgen_operand_ready_i
  );

  /***********************
   *  INTERNAL OPERANDS  *
   ***********************/
  word_t [NR_OPQUEUE-1:0] word_int;

  assign alu_operand_o     = word_int[ALU_B:ALU_SLD_MASK]    ;
  assign mfpu_operand_o    = word_int[MFPU_C:MFPU_MASK]      ;
  assign sld_operand_o     = word_int[ALU_SLD_A:ALU_SLD_MASK];
  assign ld_operand_o      = word_int[LD_ST_MASK]            ;
  assign st_operand_o      = word_int[ST_A:LD_ST_MASK]       ;
  assign addrgen_operand_o = word_int[ADDRGEN_A]             ;

  /**********
   *  MFPU  *
   **********/

  opqueue #(
    .IBUF_DEPTH(5)
  ) i_opqueue_mfpu_m (
    .clk_i        (clk_i                     ) ,
    .rst_ni       (rst_ni                    ),
    .word_i       (word_i[MFPU_MASK]         ),
    .word_o       (word_int[MFPU_MASK]       ),
    .opqueue_cmd_i(opqueue_cmd_i[MFPU_MASK]  ),
    .word_issued_i(word_issued_i[MFPU_MASK]  ),
    .ready_i      (mfpu_operand_ready_i      ),
    .ready_o      (opqueue_ready_o[MFPU_MASK])
  );

  opqueue #(
    .IBUF_DEPTH(5)
  ) i_opqueue_mfpu_a (
    .clk_i        (clk_i                  ) ,
    .rst_ni       (rst_ni                 ),
    .word_i       (word_i[MFPU_A]         ),
    .word_o       (word_int[MFPU_A]       ),
    .opqueue_cmd_i(opqueue_cmd_i[MFPU_A]  ),
    .word_issued_i(word_issued_i[MFPU_A]  ),
    .ready_i      (mfpu_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[MFPU_A])
  );

  opqueue #(
    .IBUF_DEPTH(5)
  ) i_opqueue_mfpu_b (
    .clk_i        (clk_i                  ) ,
    .rst_ni       (rst_ni                 ),
    .word_i       (word_i[MFPU_B]         ),
    .word_o       (word_int[MFPU_B]       ),
    .opqueue_cmd_i(opqueue_cmd_i[MFPU_B]  ),
    .word_issued_i(word_issued_i[MFPU_B]  ),
    .ready_i      (mfpu_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[MFPU_B])
  );

  opqueue #(
    .IBUF_DEPTH(5)
  ) i_opqueue_mfpu_c (
    .clk_i        (clk_i                  ) ,
    .rst_ni       (rst_ni                 ),
    .word_i       (word_i[MFPU_C]         ),
    .word_o       (word_int[MFPU_C]       ),
    .opqueue_cmd_i(opqueue_cmd_i[MFPU_C]  ),
    .word_issued_i(word_issued_i[MFPU_C]  ),
    .ready_i      (mfpu_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[MFPU_C])
  );

  /*********
   *  ALU  *
   *********/

  opqueue #(
    .IBUF_DEPTH(5),
    .NR_SLAVES (2)
  ) i_opqueue_alu_sld_m (
    .clk_i        (clk_i                                     ),
    .rst_ni       (rst_ni                                    ),
    .word_i       (word_i[ALU_SLD_MASK]                      ),
    .word_o       (word_int[ALU_SLD_MASK]                    ),
    .opqueue_cmd_i(opqueue_cmd_i[ALU_SLD_MASK]               ),
    .word_issued_i(word_issued_i[ALU_SLD_MASK]               ),
    .ready_i      ({red_operand_ready_i, alu_operand_ready_i}),
    .ready_o      (opqueue_ready_o[ALU_SLD_MASK]             )
  );

  opqueue #(
    .IBUF_DEPTH(5),
    .NR_SLAVES (2)
  ) i_opqueue_alu_sld_a (
    .clk_i        (clk_i                                     ),
    .rst_ni       (rst_ni                                    ),
    .word_i       (word_i[ALU_SLD_A]                         ),
    .word_o       (word_int[ALU_SLD_A]                       ),
    .opqueue_cmd_i(opqueue_cmd_i[ALU_SLD_A]                  ),
    .word_issued_i(word_issued_i[ALU_SLD_A]                  ),
    .ready_i      ({red_operand_ready_i, alu_operand_ready_i}),
    .ready_o      (opqueue_ready_o[ALU_SLD_A]                )
  );

  opqueue #(
    .IBUF_DEPTH(5)
  ) i_opqueue_alu_b (
    .clk_i        (clk_i                 ) ,
    .rst_ni       (rst_ni                ),
    .word_i       (word_i[ALU_B]         ),
    .word_o       (word_int[ALU_B]       ),
    .opqueue_cmd_i(opqueue_cmd_i[ALU_B]  ),
    .word_issued_i(word_issued_i[ALU_B]  ),
    .ready_i      (alu_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[ALU_B])
  );

  /**********
   *  VLSU  *
   **********/

  opqueue #(
    .IBUF_DEPTH(2),
    .NR_SLAVES (2)
  ) i_opqueue_vlsu_m (
    .clk_i        (clk_i                                   ),
    .rst_ni       (rst_ni                                  ),
    .word_i       (word_i[LD_ST_MASK]                      ),
    .word_o       (word_int[LD_ST_MASK]                    ),
    .opqueue_cmd_i(opqueue_cmd_i[LD_ST_MASK]               ),
    .word_issued_i(word_issued_i[LD_ST_MASK]               ),
    .ready_i      ({ld_operand_ready_i, st_operand_ready_i}),
    .ready_o      (opqueue_ready_o[LD_ST_MASK]             )
  );

  opqueue #(
    .IBUF_DEPTH(2)
  ) i_opqueue_vstu_a (
    .clk_i        (clk_i                ),
    .rst_ni       (rst_ni               ),
    .word_i       (word_i[ST_A]         ),
    .word_o       (word_int[ST_A]       ),
    .opqueue_cmd_i(opqueue_cmd_i[ST_A]  ),
    .word_issued_i(word_issued_i[ST_A]  ),
    .ready_i      (st_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[ST_A])
  );

  opqueue #(
    .IBUF_DEPTH(2)
  ) i_opqueue_addrgen_a (
    .clk_i        (clk_i                     ) ,
    .rst_ni       (rst_ni                    ),
    .word_i       (word_i[ADDRGEN_A]         ),
    .word_o       (word_int[ADDRGEN_A]       ),
    .opqueue_cmd_i(opqueue_cmd_i[ADDRGEN_A]  ),
    .word_issued_i(word_issued_i[ADDRGEN_A]  ),
    .ready_i      (addrgen_operand_ready_i   ),
    .ready_o      (opqueue_ready_o[ADDRGEN_A])
  );

endmodule : vconv_stage
