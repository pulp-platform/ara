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
// File:   operand_queues_stage.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   03.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This stage holds the operand queues, holding elements for the VRFs.

module operand_queues_stage import ara_pkg::*; import rvv_pkg::*; (
    input  logic                                     clk_i,
    input  logic                                     rst_ni,
    // Interface with the Vector Register File
    input  elen_t              [NrOperandQueues-1:0] operand_i,
    input  logic               [NrOperandQueues-1:0] operand_valid_i,
    // Input with the Operand Requester
    input  logic               [NrOperandQueues-1:0] operand_issued_i,
    output logic               [NrOperandQueues-1:0] operand_queue_ready_o,
    input  operand_queue_cmd_t [NrOperandQueues-1:0] operand_queue_cmd_i,
    input  logic               [NrOperandQueues-1:0] operand_queue_cmd_valid_i,
    // Interface with the VFUs
    // ALU
    output elen_t              [1:0]                 alu_operand_o,
    output logic               [1:0]                 alu_operand_valid_o,
    input  logic               [1:0]                 alu_operand_ready_i,
    // Multiplier/FPU
    output elen_t              [2:0]                 mfpu_operand_o,
    output logic               [2:0]                 mfpu_operand_valid_o,
    input  logic               [2:0]                 mfpu_operand_ready_i,
    // Store unit
    output elen_t                                    stu_operand_o,
    output logic                                     stu_operand_valid_o,
    input  logic                                     stu_operand_ready_i,
    // Address Generation unit
    output elen_t                                    addrgen_operand_o,
    output logic                                     addrgen_operand_valid_o,
    input  logic                                     addrgen_operand_ready_i,
    // Mask unit
    output elen_t              [1:0]                 mask_operand_o,
    output logic               [1:0]                 mask_operand_valid_o,
    input  logic               [1:0]                 mask_operand_ready_i
  );

  /*********
   *  ALU  *
   *********/

  operand_queue #(
    .BufferDepth   (5   ),
    .SupportIntExt2(1'b1),
    .SupportIntExt4(1'b1),
    .SupportIntExt8(1'b1)
  ) i_operand_queue_alu_a (
    .clk_i                    (clk_i                          ),
    .rst_ni                   (rst_ni                         ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[AluA]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[AluA]),
    .operand_i                (operand_i[AluA]                ),
    .operand_valid_i          (operand_valid_i[AluA]          ),
    .operand_issued_i         (operand_issued_i[AluA]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[AluA]    ),
    .operand_o                (alu_operand_o[0]               ),
    .operand_valid_o          (alu_operand_valid_o[0]         ),
    .operand_ready_i          (alu_operand_ready_i[0]         )
  );

  operand_queue #(
    .BufferDepth   (5   ),
    .SupportIntExt2(1'b1),
    .SupportIntExt4(1'b1),
    .SupportIntExt8(1'b1)
  ) i_operand_queue_alu_b (
    .clk_i                    (clk_i                          ),
    .rst_ni                   (rst_ni                         ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[AluB]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[AluB]),
    .operand_i                (operand_i[AluB]                ),
    .operand_valid_i          (operand_valid_i[AluB]          ),
    .operand_issued_i         (operand_issued_i[AluB]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[AluB]    ),
    .operand_o                (alu_operand_o[1]               ),
    .operand_valid_o          (alu_operand_valid_o[1]         ),
    .operand_ready_i          (alu_operand_ready_i[1]         )
  );

  /********************
   *  Multiplier/FPU  *
   ********************/

  operand_queue #(
    .BufferDepth   (5    ),
    .SupportIntExt2(1'b1 )
  ) i_operand_queue_mfpu_a (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUA]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUA]),
    .operand_i                (operand_i[MulFPUA]                ),
    .operand_valid_i          (operand_valid_i[MulFPUA]          ),
    .operand_issued_i         (operand_issued_i[MulFPUA]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUA]    ),
    .operand_o                (mfpu_operand_o[0]                 ),
    .operand_valid_o          (mfpu_operand_valid_o[0]           ),
    .operand_ready_i          (mfpu_operand_ready_i[0]           )
  );

  operand_queue #(
    .BufferDepth   (5    ),
    .SupportIntExt2(1'b1 )
  ) i_operand_queue_mfpu_b (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUB]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUB]),
    .operand_i                (operand_i[MulFPUB]                ),
    .operand_valid_i          (operand_valid_i[MulFPUB]          ),
    .operand_issued_i         (operand_issued_i[MulFPUB]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUB]    ),
    .operand_o                (mfpu_operand_o[1]                 ),
    .operand_valid_o          (mfpu_operand_valid_o[1]           ),
    .operand_ready_i          (mfpu_operand_ready_i[1]           )
  );

  operand_queue #(
    .BufferDepth   (5    ),
    .SupportIntExt2(1'b1 )
  ) i_operand_queue_mfpu_c (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUC]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUC]),
    .operand_i                (operand_i[MulFPUC]                ),
    .operand_valid_i          (operand_valid_i[MulFPUC]          ),
    .operand_issued_i         (operand_issued_i[MulFPUC]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUC]    ),
    .operand_o                (mfpu_operand_o[2]                 ),
    .operand_valid_o          (mfpu_operand_valid_o[2]           ),
    .operand_ready_i          (mfpu_operand_ready_i[2]           )
  );

  /*********************
   *  Load/Store Unit  *
   *********************/

  operand_queue #(
    .BufferDepth(2)
  ) i_operand_queue_st_mask_a (
    .clk_i                    (clk_i                                         ),
    .rst_ni                   (rst_ni                                        ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[StMaskA]                  ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[StMaskA]            ),
    .operand_i                (operand_i[StMaskA]                            ),
    .operand_valid_i          (operand_valid_i[StMaskA]                      ),
    .operand_issued_i         (operand_issued_i[StMaskA]                     ),
    .operand_queue_ready_o    (operand_queue_ready_o[StMaskA]                ),
    .operand_o                (stu_operand_o                                 ),
    .operand_valid_o          (stu_operand_valid_o                           ),
    .operand_ready_i          (stu_operand_ready_i || mask_operand_ready_i[1])
  );

  operand_queue #(
    .BufferDepth(2)
  ) i_operand_queue_addrgen_a (
    .clk_i                    (clk_i                               ),
    .rst_ni                   (rst_ni                              ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[AddrGenA]       ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[AddrGenA] ),
    .operand_i                (operand_i[AddrGenA]                 ),
    .operand_valid_i          (operand_valid_i[AddrGenA]           ),
    .operand_issued_i         (operand_issued_i[AddrGenA]          ),
    .operand_queue_ready_o    (operand_queue_ready_o[AddrGenA]     ),
    .operand_o                (addrgen_operand_o                   ),
    .operand_valid_o          (addrgen_operand_valid_o             ),
    .operand_ready_i          (addrgen_operand_ready_i             )
  );

  /***************
   *  Mask Unit  *
   ***************/

  operand_queue #(
    .BufferDepth(1)
  ) i_operand_queue_mask_m (
    .clk_i                    (clk_i                            ),
    .rst_ni                   (rst_ni                           ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MaskM]       ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MaskM] ),
    .operand_i                (operand_i[MaskM]                 ),
    .operand_valid_i          (operand_valid_i[MaskM]           ),
    .operand_issued_i         (operand_issued_i[MaskM]          ),
    .operand_queue_ready_o    (operand_queue_ready_o[MaskM]     ),
    .operand_o                (mask_operand_o[0]                ),
    .operand_valid_o          (mask_operand_valid_o[0]          ),
    .operand_ready_i          (mask_operand_ready_i[0]          )
  );

  assign mask_operand_o[1]       = stu_operand_o;
  assign mask_operand_valid_o[1] = stu_operand_valid_o;

endmodule : operand_queues_stage
