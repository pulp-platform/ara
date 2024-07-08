// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This stage holds the operand queues, holding elements for the VRFs.

module operand_queues_stage import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter int     unsigned NrLanes          = 0,
    parameter int     unsigned VLEN             = 0,
    // Support for floating-point data types
    parameter fpu_support_e FPUSupport          = FPUSupportHalfSingleDouble,
    parameter type          operand_queue_cmd_t = logic
  ) (
    input  logic                                     clk_i,
    input  logic                                     rst_ni,
    input  logic            [idx_width(NrLanes)-1:0] lane_id_i,
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
    input  logic                                     stu_exception_flush_i,
    // Slide Unit/Address Generation unit
    output elen_t                                    sldu_addrgen_operand_o,
    output target_fu_e                               sldu_addrgen_operand_target_fu_o,
    output logic                                     sldu_addrgen_operand_valid_o,
    input  logic                                     addrgen_operand_ready_i,
    input  logic                                     sldu_operand_ready_i,
    // Mask unit
    output elen_t              [1:0]                 mask_operand_o,
    output logic               [1:0]                 mask_operand_valid_o,
    input  logic               [1:0]                 mask_operand_ready_i
  );

  ///////////
  //  ALU  //
  ///////////

  operand_queue #(
    .CmdBufDepth        (ValuInsnQueueDepth   ),
    .DataBufDepth       (5                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .SupportIntExt2     (1'b1                 ),
    .SupportIntExt4     (1'b1                 ),
    .SupportIntExt8     (1'b1                 ),
    .SupportReduct      (1'b1                 ),
    .SupportNtrVal      (1'b0                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_alu_a (
    .clk_i                    (clk_i                          ),
    .rst_ni                   (rst_ni                         ),
    .flush_i                  (1'b0                           ),
    .lane_id_i                (lane_id_i                      ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[AluA]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[AluA]),
    .operand_i                (operand_i[AluA]                ),
    .operand_valid_i          (operand_valid_i[AluA]          ),
    .operand_issued_i         (operand_issued_i[AluA]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[AluA]    ),
    .operand_o                (alu_operand_o[0]               ),
    .operand_target_fu_o      (/* Unused */                   ),
    .operand_valid_o          (alu_operand_valid_o[0]         ),
    .operand_ready_i          (alu_operand_ready_i[0]         )
  );

  operand_queue #(
    .CmdBufDepth        (ValuInsnQueueDepth   ),
    .DataBufDepth       (5                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .SupportIntExt2     (1'b1                 ),
    .SupportIntExt4     (1'b1                 ),
    .SupportIntExt8     (1'b1                 ),
    .SupportReduct      (1'b1                 ),
    .SupportNtrVal      (1'b1                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_alu_b (
    .clk_i                    (clk_i                          ),
    .rst_ni                   (rst_ni                         ),
    .flush_i                  (1'b0                           ),
    .lane_id_i                (lane_id_i                      ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[AluB]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[AluB]),
    .operand_i                (operand_i[AluB]                ),
    .operand_valid_i          (operand_valid_i[AluB]          ),
    .operand_issued_i         (operand_issued_i[AluB]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[AluB]    ),
    .operand_o                (alu_operand_o[1]               ),
    .operand_target_fu_o      (/* Unused */                   ),
    .operand_valid_o          (alu_operand_valid_o[1]         ),
    .operand_ready_i          (alu_operand_ready_i[1]         )
  );

  //////////////////////
  //  Multiplier/FPU  //
  //////////////////////

  operand_queue #(
    .CmdBufDepth        (MfpuInsnQueueDepth   ),
    .DataBufDepth       (5                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .SupportIntExt2     (1'b1                 ),
    .SupportReduct      (1'b1                 ),
    .SupportNtrVal      (1'b0                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t)
  ) i_operand_queue_mfpu_a (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .flush_i                  (1'b0                              ),
    .lane_id_i                (lane_id_i                         ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUA]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUA]),
    .operand_i                (operand_i[MulFPUA]                ),
    .operand_valid_i          (operand_valid_i[MulFPUA]          ),
    .operand_issued_i         (operand_issued_i[MulFPUA]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUA]    ),
    .operand_o                (mfpu_operand_o[0]                 ),
    .operand_target_fu_o      (/* Unused */                      ),
    .operand_valid_o          (mfpu_operand_valid_o[0]           ),
    .operand_ready_i          (mfpu_operand_ready_i[0]           )
  );

  operand_queue #(
    .CmdBufDepth        (MfpuInsnQueueDepth   ),
    .DataBufDepth       (5                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .SupportIntExt2     (1'b1                 ),
    .SupportReduct      (1'b1                 ),
    .SupportNtrVal      (1'b1                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_mfpu_b (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .flush_i                  (1'b0                              ),
    .lane_id_i                (lane_id_i                         ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUB]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUB]),
    .operand_i                (operand_i[MulFPUB]                ),
    .operand_valid_i          (operand_valid_i[MulFPUB]          ),
    .operand_issued_i         (operand_issued_i[MulFPUB]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUB]    ),
    .operand_o                (mfpu_operand_o[1]                 ),
    .operand_target_fu_o      (/* Unused */                      ),
    .operand_valid_o          (mfpu_operand_valid_o[1]           ),
    .operand_ready_i          (mfpu_operand_ready_i[1]           )
  );

  operand_queue #(
    .CmdBufDepth        (MfpuInsnQueueDepth   ),
    .DataBufDepth       (5                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .SupportIntExt2     (1'b1                 ),
    .SupportReduct      (1'b1                 ),
    .SupportNtrVal      (1'b1                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_mfpu_c (
    .clk_i                    (clk_i                             ),
    .rst_ni                   (rst_ni                            ),
    .flush_i                  (1'b0                              ),
    .lane_id_i                (lane_id_i                         ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MulFPUC]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MulFPUC]),
    .operand_i                (operand_i[MulFPUC]                ),
    .operand_valid_i          (operand_valid_i[MulFPUC]          ),
    .operand_issued_i         (operand_issued_i[MulFPUC]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MulFPUC]    ),
    .operand_o                (mfpu_operand_o[2]                 ),
    .operand_target_fu_o      (/* Unused */                      ),
    .operand_valid_o          (mfpu_operand_valid_o[2]           ),
    .operand_ready_i          (mfpu_operand_ready_i[2]           )
  );

  ///////////////////////
  //  Load/Store Unit  //
  ///////////////////////

  operand_queue #(
    .CmdBufDepth        (VstuInsnQueueDepth + MaskuInsnQueueDepth),
    .DataBufDepth       (2                                       ),
    .FPUSupport         (FPUSupport                              ),
    .NrLanes            (NrLanes                                 ),
    .VLEN               (VLEN                                    ),
    .operand_queue_cmd_t(operand_queue_cmd_t                     )
  ) i_operand_queue_st_mask_a (
    .clk_i                    (clk_i                         ),
    .rst_ni                   (rst_ni                        ),
    .flush_i                  (stu_exception_flush_i         ),
    .lane_id_i                (lane_id_i                     ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[StA]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[StA]),
    .operand_i                (operand_i[StA]                ),
    .operand_valid_i          (operand_valid_i[StA]          ),
    .operand_issued_i         (operand_issued_i[StA]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[StA]    ),
    .operand_o                (stu_operand_o                 ),
    .operand_target_fu_o      (/* Unused */                  ),
    .operand_valid_o          (stu_operand_valid_o           ),
    .operand_ready_i          (stu_operand_ready_i           )
  );

  /****************
   *  Slide Unit  *
   ****************/

  // This operand queue is common to slide unit and addrgen.
  // Since it's shared, we should be sure not to sample a
  // spurious ready from the wrong unit, i.e., when we are
  // feeding the addrgen, we don't want spurious readies from
  // the slide unit. The units should be responsible for avoiding
  // sampling wrong data, but spurious ready signals can happen in
  // specific corner cases. Fixing this without impacting timing is
  // hard, so we just mask the ready signals here as well to avoid
  // bugs.
  logic sldu_operand_ready_filtered;
  logic addrgen_operand_ready_filtered;
  assign sldu_operand_ready_filtered = sldu_operand_ready_i &
    (sldu_addrgen_operand_target_fu_o == ALU_SLDU);
  assign addrgen_operand_ready_filtered = addrgen_operand_ready_i &
    (sldu_addrgen_operand_target_fu_o == MFPU_ADDRGEN);

  operand_queue #(
    .CmdBufDepth        (VlduInsnQueueDepth   ),
    .DataBufDepth       (2                    ),
    .FPUSupport         (FPUSupport           ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_slide_addrgen_a (
    .clk_i                    (clk_i                                                       ),
    .rst_ni                   (rst_ni                                                      ),
    .flush_i                  (1'b0                                                        ),
    .lane_id_i                (lane_id_i                                                   ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[SlideAddrGenA]                          ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[SlideAddrGenA]                    ),
    .operand_i                (operand_i[SlideAddrGenA]                                    ),
    .operand_valid_i          (operand_valid_i[SlideAddrGenA]                              ),
    .operand_issued_i         (operand_issued_i[SlideAddrGenA]                             ),
    .operand_queue_ready_o    (operand_queue_ready_o[SlideAddrGenA]                        ),
    .operand_o                (sldu_addrgen_operand_o                                      ),
    .operand_target_fu_o      (sldu_addrgen_operand_target_fu_o                            ),
    .operand_valid_o          (sldu_addrgen_operand_valid_o                                ),
    .operand_ready_i          (addrgen_operand_ready_filtered | sldu_operand_ready_filtered)
  );

  /////////////////
  //  Mask Unit  //
  /////////////////

  operand_queue #(
    .CmdBufDepth        (MaskuInsnQueueDepth  ),
    .DataBufDepth       (1                    ),
    .FPUSupport         (FPUSupport           ),
    .SupportIntExt2     (1'b1                 ),
    .SupportIntExt4     (1'b1                 ),
    .SupportIntExt8     (1'b1                 ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_mask_b (
    .clk_i                    (clk_i                           ),
    .rst_ni                   (rst_ni                          ),
    .flush_i                  (1'b0                            ),
    .lane_id_i                (lane_id_i                       ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MaskB]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MaskB]),
    .operand_i                (operand_i[MaskB]                ),
    .operand_valid_i          (operand_valid_i[MaskB]          ),
    .operand_issued_i         (operand_issued_i[MaskB]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MaskB]    ),
    .operand_o                (mask_operand_o[1]               ),
    .operand_target_fu_o      (/* Unused */                    ),
    .operand_valid_o          (mask_operand_valid_o[1]         ),
    .operand_ready_i          (mask_operand_ready_i[1]         )
  );

  operand_queue #(
    .CmdBufDepth        (MaskuInsnQueueDepth  ),
    .DataBufDepth       (1                    ),
    .NrLanes            (NrLanes              ),
    .VLEN               (VLEN                 ),
    .operand_queue_cmd_t(operand_queue_cmd_t  )
  ) i_operand_queue_mask_m (
    .clk_i                    (clk_i                           ),
    .rst_ni                   (rst_ni                          ),
    .flush_i                  (1'b0                            ),
    .lane_id_i                (lane_id_i                       ),
    .operand_queue_cmd_i      (operand_queue_cmd_i[MaskM]      ),
    .operand_queue_cmd_valid_i(operand_queue_cmd_valid_i[MaskM]),
    .operand_i                (operand_i[MaskM]                ),
    .operand_valid_i          (operand_valid_i[MaskM]          ),
    .operand_issued_i         (operand_issued_i[MaskM]         ),
    .operand_queue_ready_o    (operand_queue_ready_o[MaskM]    ),
    .operand_o                (mask_operand_o[0]               ),
    .operand_target_fu_o      (/* Unused */                    ),
    .operand_valid_o          (mask_operand_valid_o[0]         ),
    .operand_ready_i          (mask_operand_ready_i[0]         )
  );

endmodule : operand_queues_stage
