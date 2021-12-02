// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author:  Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's vector execution stage. This contains the functional units
// of each lane, namely the ALU and the Multiplier/FPU.

module vector_fus_stage import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter  int           unsigned NrLanes    = 0,
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport = FPUSupportHalfSingleDouble,
    // Type used to address vector register file elements
    parameter  type                   vaddr_t    = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           unsigned DataWidth  = $bits(elen_t),
    localparam type                   strb_t     = logic [DataWidth/8-1:0]
  ) (
    input  logic                              clk_i,
    input  logic                              rst_ni,
    input  logic [idx_width(NrLanes)-1:0]     lane_id_i,
    // Interface with Dispatcher
    output logic                              vxsat_flag_o,
    // Interface with CVA6
    output logic           [4:0]              fflags_ex_o,
    output logic                              fflags_ex_valid_o,
    // Interface with the lane sequencer
    input  vfu_operation_t                    vfu_operation_i,
    input  logic                              vfu_operation_valid_i,
    output logic                              alu_ready_o,
    output logic           [NrVInsn-1:0]      alu_vinsn_done_o,
    output logic                              mfpu_ready_o,
    output logic           [NrVInsn-1:0]      mfpu_vinsn_done_o,
    // Interface with the operand queues
    input  elen_t          [1:0]              alu_operand_i,
    input  logic           [1:0]              alu_operand_valid_i,
    output logic           [1:0]              alu_operand_ready_o,
    input  elen_t          [2:0]              mfpu_operand_i,
    input  logic           [2:0]              mfpu_operand_valid_i,
    output logic           [2:0]              mfpu_operand_ready_o,
    // Interface with the vector register file
    output logic                              alu_result_req_o,
    output vid_t                              alu_result_id_o,
    output vaddr_t                            alu_result_addr_o,
    output elen_t                             alu_result_wdata_o,
    output strb_t                             alu_result_be_o,
    input  logic                              alu_result_gnt_i,
    // Multiplier/FPU
    output logic                              mfpu_result_req_o,
    output vid_t                              mfpu_result_id_o,
    output vaddr_t                            mfpu_result_addr_o,
    output elen_t                             mfpu_result_wdata_o,
    output strb_t                             mfpu_result_be_o,
    input  logic                              mfpu_result_gnt_i,
    // Interface with the Slide Unit
    input  elen_t                             sldu_operand_i,
    output logic                              sldu_alu_req_valid_o,
    input  logic                              sldu_alu_valid_i,
    output logic                              sldu_alu_ready_o,
    input  logic                              sldu_alu_gnt_i,
    output logic                              sldu_mfpu_req_valid_o,
    input  logic                              sldu_mfpu_valid_i,
    output logic                              sldu_mfpu_ready_o,
    input  logic                              sldu_mfpu_gnt_i,
    // Interface with the Mask unit
    output elen_t          [NrMaskFUnits-1:0] mask_operand_o,
    output logic           [NrMaskFUnits-1:0] mask_operand_valid_o,
    input  logic           [NrMaskFUnits-1:0] mask_operand_ready_i,
    input  strb_t                             mask_i,
    input  logic                              mask_valid_i,
    output logic                              mask_ready_o
  );

  ///////////////
  //  Signals  //
  ///////////////

  // If the mask unit has instruction queue depth > 1, change the following lines.
  // If we have concurrent masked MUL and ADD operations, mask_i and mask_valid_i are
  // erroneously broadcasted and accepted to/by both the units. The mask unit must tag its
  // broadcasted signals if more masked instructions can be in different units at the same time.
  logic alu_mask_ready;
  logic mfpu_mask_ready;
  assign mask_ready_o = alu_mask_ready | mfpu_mask_ready;

  //////////////////
  //  Vector ALU  //
  //////////////////

  valu #(
    .NrLanes(NrLanes),
    .vaddr_t(vaddr_t)
  ) i_valu (
    .clk_i                (clk_i                          ),
    .rst_ni               (rst_ni                         ),
    .lane_id_i            (lane_id_i                      ),
    // Interface with Dispatcher
    .vxsat_flag_o         (vxsat_flag_o                   ),
    // Interface with the lane sequencer
    .vfu_operation_i      (vfu_operation_i                ),
    .vfu_operation_valid_i(vfu_operation_valid_i          ),
    .alu_ready_o          (alu_ready_o                    ),
    .alu_vinsn_done_o     (alu_vinsn_done_o               ),
    // Interface with the operand queues
    .alu_operand_i        (alu_operand_i                  ),
    .alu_operand_valid_i  (alu_operand_valid_i            ),
    .alu_operand_ready_o  (alu_operand_ready_o            ),
    // Interface with the vector register file
    .alu_result_req_o     (alu_result_req_o               ),
    .alu_result_addr_o    (alu_result_addr_o              ),
    .alu_result_id_o      (alu_result_id_o                ),
    .alu_result_wdata_o   (alu_result_wdata_o             ),
    .alu_result_be_o      (alu_result_be_o                ),
    .alu_result_gnt_i     (alu_result_gnt_i               ),
    // Interface with the Slide Unit
    .alu_red_valid_o      (sldu_alu_req_valid_o           ),
    .sldu_operand_i       (sldu_operand_i                 ),
    .sldu_alu_valid_i     (sldu_alu_valid_i               ),
    .sldu_alu_ready_o     (sldu_alu_ready_o               ),
    // Interface with the Slide Unit
    .alu_red_ready_i      (sldu_alu_gnt_i),
    // Interface with the Mask unit
    .mask_operand_o       (mask_operand_o[MaskFUAlu]      ),
    .mask_operand_valid_o (mask_operand_valid_o[MaskFUAlu]),
    .mask_operand_ready_i (mask_operand_ready_i[MaskFUAlu]),
    .mask_i               (mask_i                         ),
    .mask_valid_i         (mask_valid_i                   ),
    .mask_ready_o         (alu_mask_ready                 )
  );

  ///////////////////
  //  Vector MFPU  //
  ///////////////////

  vmfpu #(
    .NrLanes   (NrLanes   ),
    .FPUSupport(FPUSupport),
    .vaddr_t   (vaddr_t   )
  ) i_vmfpu (
    .clk_i                (clk_i                           ),
    .rst_ni               (rst_ni                          ),
    .lane_id_i            (lane_id_i                       ),
    // Interface with CVA6
    .fflags_ex_o          (fflags_ex_o                     ),
    .fflags_ex_valid_o    (fflags_ex_valid_o               ),
    // Interface with the lane sequencer
    .vfu_operation_i      (vfu_operation_i                 ),
    .vfu_operation_valid_i(vfu_operation_valid_i           ),
    .mfpu_ready_o         (mfpu_ready_o                    ),
    .mfpu_vinsn_done_o    (mfpu_vinsn_done_o               ),
    // Interface with the operand queues
    .mfpu_operand_i       (mfpu_operand_i                  ),
    .mfpu_operand_valid_i (mfpu_operand_valid_i            ),
    .mfpu_operand_ready_o (mfpu_operand_ready_o            ),
    // Interface with the vector register file
    .mfpu_result_req_o    (mfpu_result_req_o               ),
    .mfpu_result_id_o     (mfpu_result_id_o                ),
    .mfpu_result_addr_o   (mfpu_result_addr_o              ),
    .mfpu_result_wdata_o  (mfpu_result_wdata_o             ),
    .mfpu_result_be_o     (mfpu_result_be_o                ),
    .mfpu_result_gnt_i    (mfpu_result_gnt_i               ),
    // Interface with the Slide Unit
    .mfpu_red_valid_o     (sldu_mfpu_req_valid_o           ),
    .sldu_operand_i       (sldu_operand_i                  ),
    .sldu_mfpu_valid_i    (sldu_mfpu_valid_i               ),
    .sldu_mfpu_ready_o    (sldu_mfpu_ready_o               ),
    .mfpu_red_ready_i     (sldu_mfpu_gnt_i                 ),
    // Interface with the Mask unit
    .mask_operand_o       (mask_operand_o[MaskFUMFpu]      ),
    .mask_operand_valid_o (mask_operand_valid_o[MaskFUMFpu]),
    .mask_operand_ready_i (mask_operand_ready_i[MaskFUMFpu]),
    .mask_i               (mask_i                          ),
    .mask_valid_i         (mask_valid_i                    ),
    .mask_ready_o         (mfpu_mask_ready                 )
  );

endmodule : vector_fus_stage
