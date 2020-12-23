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
// File:    vector_fus_stage.sv
// Author:  Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created: 27.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is Ara's vector execution stage. This contains the functional units
// of each lane, namely the ALU and the Multiplier/FPU.

module vector_fus_stage import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes   = 0,
    // Type used to address vector register file elements
    parameter type          vaddr_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter type          strb_t    = logic [DataWidth/8-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Interface with the lane sequencer
    input  vfu_operation_t               vfu_operation_i,
    input  logic                         vfu_operation_valid_i,
    output logic                         alu_ready_o,
    output logic           [NrVInsn-1:0] alu_vinsn_done_o,
    output logic                         mfpu_ready_o,
    output logic           [NrVInsn-1:0] mfpu_vinsn_done_o,
    // Interface with the operand queues
    input  elen_t          [1:0]         alu_operand_i,
    input  logic           [1:0]         alu_operand_valid_i,
    output logic           [1:0]         alu_operand_ready_o,
    input  elen_t          [2:0]         mfpu_operand_i,
    input  logic           [2:0]         mfpu_operand_valid_i,
    output logic           [2:0]         mfpu_operand_ready_o,
    // Interface with the vector register file
    output logic                         alu_result_req_o,
    output vid_t                         alu_result_id_o,
    output vaddr_t                       alu_result_addr_o,
    output elen_t                        alu_result_wdata_o,
    output strb_t                        alu_result_be_o,
    input  logic                         alu_result_gnt_i,
    // Multiplier/FPU
    output logic                         mfpu_result_req_o,
    output vid_t                         mfpu_result_id_o,
    output vaddr_t                       mfpu_result_addr_o,
    output elen_t                        mfpu_result_wdata_o,
    output strb_t                        mfpu_result_be_o,
    input  logic                         mfpu_result_gnt_i,
    // Interface with the Mask unit
    input  strb_t                        mask_i,
    input  logic                         mask_valid_i,
    output logic                         mask_ready_o
  );

  /*************
   *  Signals  *
   *************/

  logic alu_mask_ready;
  assign mask_ready_o = alu_mask_ready;


  /****************
   *  Vector ALU  *
   ****************/

  valu #(
    .NrLanes(NrLanes),
    .vaddr_t(vaddr_t)
  ) i_valu (
    .clk_i                (clk_i                ),
    .rst_ni               (rst_ni               ),
    // Interface with the lane sequencer
    .vfu_operation_i      (vfu_operation_i      ),
    .vfu_operation_valid_i(vfu_operation_valid_i),
    .alu_ready_o          (alu_ready_o          ),
    .alu_vinsn_done_o     (alu_vinsn_done_o     ),
    // Interface with the operand queues
    .alu_operand_i        (alu_operand_i        ),
    .alu_operand_valid_i  (alu_operand_valid_i  ),
    .alu_operand_ready_o  (alu_operand_ready_o  ),
    // Interface with the vector register file
    .alu_result_req_o     (alu_result_req_o     ),
    .alu_result_addr_o    (alu_result_addr_o    ),
    .alu_result_id_o      (alu_result_id_o      ),
    .alu_result_wdata_o   (alu_result_wdata_o   ),
    .alu_result_be_o      (alu_result_be_o      ),
    .alu_result_gnt_i     (alu_result_gnt_i     ),
    // Interface with the Mask unit
    .mask_i               (mask_i               ),
    .mask_valid_i         (mask_valid_i         ),
    .mask_ready_o         (alu_mask_ready       )
  );

  assign mfpu_ready_o         = 1'b0;
  assign mfpu_vinsn_done_o    = '0;
  assign mfpu_operand_ready_o = '0;

  assign mfpu_result_req_o   = '0;
  assign mfpu_result_id_o    = '0;
  assign mfpu_result_addr_o  = '0;
  assign mfpu_result_wdata_o = '0;
  assign mfpu_result_be_o    = '0;


/*
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
 */
endmodule : vector_fus_stage
