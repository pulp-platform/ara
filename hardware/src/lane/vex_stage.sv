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
// File          : vex_stage.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 27.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Vector Execution stage.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module vex_stage (
    input  logic                      clk_i,
    input  logic                      rst_ni,
    // Operation
    input  operation_t                operation_i,
    output vfu_status_t  [NR_VFU-1:0] vfu_status_o,
    // Operands
    input  word_t        [ 2:0]       alu_operand_i,
    input  word_t        [ 3:0]       mfpu_operand_i,
    output logic                      alu_operand_ready_o,
    output logic                      mfpu_operand_ready_o,
    // Results
    output arb_request_t              alu_result_o,
    output arb_request_t              mfpu_result_o,
    input  logic                      alu_result_gnt_i,
    input  logic                      mfpu_result_gnt_i
  );

  valu i_valu (
    .clk_i              (clk_i                ),
    .rst_ni             (rst_ni               ),
    .operation_i        (operation_i          ),
    .alu_operand_i      (alu_operand_i        ),
    .alu_operand_ready_o(alu_operand_ready_o  ),
    .alu_result_o       (alu_result_o         ),
    .alu_result_gnt_i   (alu_result_gnt_i     ),
    .vfu_status_o       (vfu_status_o[VFU_ALU])
  );

  vmfpu i_vmfpu (
    .clk_i               (clk_i                 ),
    .rst_ni              (rst_ni                ),
    .operation_i         (operation_i           ),
    .mfpu_operand_i      (mfpu_operand_i        ),
    .mfpu_operand_ready_o(mfpu_operand_ready_o  ),
    .mfpu_result_o       (mfpu_result_o         ),
    .mfpu_result_gnt_i   (mfpu_result_gnt_i     ),
    .vfu_status_o        (vfu_status_o[VFU_MFPU])
  );

  // Unused channels
  always_comb begin
    vfu_status_o[VFU_SLD]       = '0  ;
    vfu_status_o[VFU_SLD].ready = 1'b1;

    vfu_status_o[VFU_LD]       = '0  ;
    vfu_status_o[VFU_LD].ready = 1'b1;

    vfu_status_o[VFU_ST]       = '0  ;
    vfu_status_o[VFU_ST].ready = 1'b1;
  end

endmodule : vex_stage
