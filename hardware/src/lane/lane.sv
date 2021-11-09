// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is one of Ara's  lanes. It contains part of the vector register file
// together with the execution units.

`include "ara/ara.svh"

module lane import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int           unsigned NrLanes         = 1, // Number of lanes
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport      = FPUSupportHalfSingleDouble,
    // Dependant parameters. DO NOT CHANGE!
    // VRF Parameters
    localparam int           unsigned MaxVLenPerLane  = VLEN / NrLanes,       // In bits
    localparam int           unsigned MaxVLenBPerLane = VLENB / NrLanes,      // In bytes
    localparam int           unsigned VRFSizePerLane  = MaxVLenPerLane * 32,  // In bits
    localparam int           unsigned VRFBSizePerLane = MaxVLenBPerLane * 32, // In bytes
    // Address of an element in the lane's VRF
    localparam type                   vaddr_t         = logic [$clog2(VRFBSizePerLane)-1:0],
    localparam int           unsigned DataWidth       = $bits(elen_t), // Width of the lane datapath
    localparam type                   strb_t          = logic [DataWidth/8-1:0] // Byte-strobe type
  ) (
    input  logic                                           clk_i,
    input  logic                                           rst_ni,
    // Scan chain
    input  logic                                           scan_enable_i,
    input  logic                                           scan_data_i,
    output logic                                           scan_data_o,
    // Lane ID
    input  logic     [cf_math_pkg::idx_width(NrLanes)-1:0] lane_id_i,
    // Interface with the dispatcher
    output logic     [4:0]                                 fflags_ex_o,
    output logic                                           fflags_ex_valid_o,
    // Interface with the sequencer
    input  `STRUCT_PORT(pe_req_t)                          pe_req_i,
    input  logic                                           pe_req_valid_i,
    input  logic     [NrVInsn-1:0]                         pe_vinsn_running_i,
    output logic                                           pe_req_ready_o,
    output `STRUCT_PORT(pe_resp_t)                         pe_resp_o,
    output logic                                           alu_vinsn_done_o,
    output logic                                           mfpu_vinsn_done_o,
    // Interface with the Store unit
    output elen_t                                          stu_operand_o,
    output logic                                           stu_operand_valid_o,
    input  logic                                           stu_operand_ready_i,
    // Interface with the Slide/Address Generation unit
    output elen_t                                          sldu_addrgen_operand_o,
    output logic                                           sldu_addrgen_operand_valid_o,
    input  logic                                           sldu_operand_ready_i,
    input  logic                                           addrgen_operand_ready_i,
    // Interface with the Slide unit
    input  logic                                           sldu_result_req_i,
    input  vid_t                                           sldu_result_id_i,
    input  vaddr_t                                         sldu_result_addr_i,
    input  elen_t                                          sldu_result_wdata_i,
    input  strb_t                                          sldu_result_be_i,
    output logic                                           sldu_result_gnt_o,
    // Interface with the Load unit
    input  logic                                           ldu_result_req_i,
    input  vid_t                                           ldu_result_id_i,
    input  vaddr_t                                         ldu_result_addr_i,
    input  elen_t                                          ldu_result_wdata_i,
    input  strb_t                                          ldu_result_be_i,
    output logic                                           ldu_result_gnt_o,
    // Interface with the Mask unit
    output `STRUCT_VECT(elen_t, [NrMaskFUnits+2-1:0])      mask_operand_o,
    output logic                [NrMaskFUnits+2-1:0]       mask_operand_valid_o,
    input  logic                [NrMaskFUnits+2-1:0]       mask_operand_ready_i,
    input  logic                                           masku_result_req_i,
    input  vid_t                                           masku_result_id_i,
    input  vaddr_t                                         masku_result_addr_i,
    input  elen_t                                          masku_result_wdata_i,
    input  strb_t                                          masku_result_be_i,
    output logic                                           masku_result_gnt_o,
    // Interface between the Mask unit and the VFUs
    input  strb_t                                          mask_i,
    input  logic                                           mask_valid_i,
    output logic                                           mask_ready_o
  );

  /////////////////
  //  Spill Reg  //
  /////////////////

  // Cut the mask_ready_o timing-critical path
  strb_t mask;
  logic  mask_valid, mask_ready;

  spill_register #(
    .T(strb_t)
  ) i_mask_ready_spill_register (
    .clk_i  (clk_i       ),
    .rst_ni (rst_ni      ),
    .valid_i(mask_valid_i),
    .ready_o(mask_ready_o),
    .data_i (mask_i      ),
    .valid_o(mask_valid  ),
    .ready_i(mask_ready  ),
    .data_o (mask        )
  );

  /////////////////
  //  Sequencer  //
  /////////////////

  // Interface with the operand requesters
  operand_request_cmd_t [NrOperandQueues-1:0] operand_request;
  logic                 [NrOperandQueues-1:0] operand_request_valid;
  logic                 [NrOperandQueues-1:0] operand_request_ready;
  logic                 [NrVInsn-1:0]         vinsn_running;
  // Interface with the vector functional units
  vfu_operation_t                             vfu_operation;
  logic                                       vfu_operation_valid;
  logic                                       alu_ready;
  logic                 [NrVInsn-1:0]         alu_vinsn_done;
  logic                                       mfpu_ready;
  logic                 [NrVInsn-1:0]         mfpu_vinsn_done;

  lane_sequencer #(.NrLanes(NrLanes)) i_lane_sequencer (
    .clk_i                  (clk_i                ),
    .rst_ni                 (rst_ni               ),
    .lane_id_i              (lane_id_i            ),
    // Interface with the main sequencer
    .pe_req_i               (pe_req_i             ),
    .pe_req_valid_i         (pe_req_valid_i       ),
    .pe_vinsn_running_i     (pe_vinsn_running_i   ),
    .pe_req_ready_o         (pe_req_ready_o       ),
    .pe_resp_o              (pe_resp_o            ),
    // Interface with the operand requesters
    .operand_request_o      (operand_request      ),
    .operand_request_valid_o(operand_request_valid),
    .operand_request_ready_i(operand_request_ready),
    .vinsn_running_o        (vinsn_running        ),
    .alu_vinsn_done_o       (alu_vinsn_done_o     ),
    .mfpu_vinsn_done_o      (mfpu_vinsn_done_o    ),
    // Interface with the VFUs
    .vfu_operation_o        (vfu_operation        ),
    .vfu_operation_valid_o  (vfu_operation_valid  ),
    .alu_ready_i            (alu_ready            ),
    .alu_vinsn_done_i       (alu_vinsn_done       ),
    .mfpu_ready_i           (mfpu_ready           ),
    .mfpu_vinsn_done_i      (mfpu_vinsn_done      )
  );

  /////////////////////////
  //  Operand Requester  //
  /////////////////////////

  // Interface with the VRF
  logic               [NrVRFBanksPerLane-1:0] vrf_req;
  vaddr_t             [NrVRFBanksPerLane-1:0] vrf_addr;
  logic               [NrVRFBanksPerLane-1:0] vrf_wen;
  elen_t              [NrVRFBanksPerLane-1:0] vrf_wdata;
  strb_t              [NrVRFBanksPerLane-1:0] vrf_be;
  opqueue_e           [NrVRFBanksPerLane-1:0] vrf_tgt_opqueue;
  // Interface with the operand queues
  logic               [NrOperandQueues-1:0]   operand_queue_ready;
  logic               [NrOperandQueues-1:0]   operand_issued;
  operand_queue_cmd_t [NrOperandQueues-1:0]   operand_queue_cmd;
  logic               [NrOperandQueues-1:0]   operand_queue_cmd_valid;
  // Interface with the VFUs
  // ALU
  logic                                       alu_result_req;
  vid_t                                       alu_result_id;
  vaddr_t                                     alu_result_addr;
  elen_t                                      alu_result_wdata;
  strb_t                                      alu_result_be;
  logic                                       alu_result_gnt;
  // Multiplier/FPU
  logic                                       mfpu_result_req;
  vid_t                                       mfpu_result_id;
  vaddr_t                                     mfpu_result_addr;
  elen_t                                      mfpu_result_wdata;
  strb_t                                      mfpu_result_be;
  logic                                       mfpu_result_gnt;

  operand_requester #(
    .NrBanks(NrVRFBanksPerLane),
    .NrLanes(NrLanes          ),
    .vaddr_t(vaddr_t          )
  ) i_operand_requester (
    .clk_i                    (clk_i                  ),
    .rst_ni                   (rst_ni                 ),
    // Interface with the lane sequencer
    .operand_request_i        (operand_request        ),
    .operand_request_valid_i  (operand_request_valid  ),
    .operand_request_ready_o  (operand_request_ready  ),
    .vinsn_running_i          (vinsn_running          ),
    // Interface with the VRF
    .vrf_req_o                (vrf_req                ),
    .vrf_addr_o               (vrf_addr               ),
    .vrf_wen_o                (vrf_wen                ),
    .vrf_wdata_o              (vrf_wdata              ),
    .vrf_be_o                 (vrf_be                 ),
    .vrf_tgt_opqueue_o        (vrf_tgt_opqueue        ),
    // Interface with the operand queues
    .operand_issued_o         (operand_issued         ),
    .operand_queue_ready_i    (operand_queue_ready    ),
    .operand_queue_cmd_o      (operand_queue_cmd      ),
    .operand_queue_cmd_valid_o(operand_queue_cmd_valid),
    // Interface with the VFUs
    // ALU
    .alu_result_req_i         (alu_result_req         ),
    .alu_result_id_i          (alu_result_id          ),
    .alu_result_addr_i        (alu_result_addr        ),
    .alu_result_wdata_i       (alu_result_wdata       ),
    .alu_result_be_i          (alu_result_be          ),
    .alu_result_gnt_o         (alu_result_gnt         ),
    // MFPU
    .mfpu_result_req_i        (mfpu_result_req        ),
    .mfpu_result_id_i         (mfpu_result_id         ),
    .mfpu_result_addr_i       (mfpu_result_addr       ),
    .mfpu_result_wdata_i      (mfpu_result_wdata      ),
    .mfpu_result_be_i         (mfpu_result_be         ),
    .mfpu_result_gnt_o        (mfpu_result_gnt        ),
    // Mask Unit
    .masku_result_req_i       (masku_result_req_i     ),
    .masku_result_id_i        (masku_result_id_i      ),
    .masku_result_addr_i      (masku_result_addr_i    ),
    .masku_result_wdata_i     (masku_result_wdata_i   ),
    .masku_result_be_i        (masku_result_be_i      ),
    .masku_result_gnt_o       (masku_result_gnt_o     ),
    // Slide Unit
    .sldu_result_req_i        (sldu_result_req_i      ),
    .sldu_result_id_i         (sldu_result_id_i       ),
    .sldu_result_addr_i       (sldu_result_addr_i     ),
    .sldu_result_wdata_i      (sldu_result_wdata_i    ),
    .sldu_result_be_i         (sldu_result_be_i       ),
    .sldu_result_gnt_o        (sldu_result_gnt_o      ),
    // Load Unit
    .ldu_result_req_i         (ldu_result_req_i       ),
    .ldu_result_id_i          (ldu_result_id_i        ),
    .ldu_result_addr_i        (ldu_result_addr_i      ),
    .ldu_result_wdata_i       (ldu_result_wdata_i     ),
    .ldu_result_be_i          (ldu_result_be_i        ),
    .ldu_result_gnt_o         (ldu_result_gnt_o       )
  );

  ////////////////////////////
  //  Vector Register File  //
  ////////////////////////////

  // Interface with the operand queues
  elen_t [NrOperandQueues-1:0] vrf_operand;
  logic  [NrOperandQueues-1:0] vrf_operand_valid;

  vector_regfile #(
    .VRFSize(VRFSizePerLane   ),
    .NrBanks(NrVRFBanksPerLane),
    .vaddr_t(vaddr_t          )
  ) i_vrf (
    .clk_i          (clk_i            ),
    .rst_ni         (rst_ni           ),
    // Interface with the operand requester
    .req_i          (vrf_req          ),
    .addr_i         (vrf_addr         ),
    .wen_i          (vrf_wen          ),
    .wdata_i        (vrf_wdata        ),
    .be_i           (vrf_be           ),
    .tgt_opqueue_i  (vrf_tgt_opqueue  ),
    // Interface with the operand queues
    .operand_o      (vrf_operand      ),
    .operand_valid_o(vrf_operand_valid)
  );

  //////////////////////
  //  Operand queues  //
  //////////////////////

  // Interface with the VFUs
  // ALU
  elen_t [1:0] alu_operand;
  logic  [1:0] alu_operand_valid;
  logic  [1:0] alu_operand_ready;
  // Multiplier/FPU
  elen_t [2:0] mfpu_operand;
  logic  [2:0] mfpu_operand_valid;
  logic  [2:0] mfpu_operand_ready;

  operand_queues_stage #(
    .FPUSupport(FPUSupport)
  ) i_operand_queues (
    .clk_i                        (clk_i                       ),
    .rst_ni                       (rst_ni                      ),
    // Interface with the Vector Register File
    .operand_i                    (vrf_operand                 ),
    .operand_valid_i              (vrf_operand_valid           ),
    // Interface with the operand requester
    .operand_issued_i             (operand_issued              ),
    .operand_queue_ready_o        (operand_queue_ready         ),
    .operand_queue_cmd_i          (operand_queue_cmd           ),
    .operand_queue_cmd_valid_i    (operand_queue_cmd_valid     ),
    // Interface with the VFUs
    // ALU
    .alu_operand_o                (alu_operand                 ),
    .alu_operand_valid_o          (alu_operand_valid           ),
    .alu_operand_ready_i          (alu_operand_ready           ),
    // Multiplier/FPU
    .mfpu_operand_o               (mfpu_operand                ),
    .mfpu_operand_valid_o         (mfpu_operand_valid          ),
    .mfpu_operand_ready_i         (mfpu_operand_ready          ),
    // Store Unit
    .stu_operand_o                (stu_operand_o               ),
    .stu_operand_valid_o          (stu_operand_valid_o         ),
    .stu_operand_ready_i          (stu_operand_ready_i         ),
    // Address Generation Unit
    .sldu_addrgen_operand_o       (sldu_addrgen_operand_o      ),
    .sldu_addrgen_operand_valid_o (sldu_addrgen_operand_valid_o),
    .sldu_operand_ready_i         (sldu_operand_ready_i        ),
    .addrgen_operand_ready_i      (addrgen_operand_ready_i     ),
    // Mask Unit
    .mask_operand_o               (mask_operand_o[1:0]         ),
    .mask_operand_valid_o         (mask_operand_valid_o[1:0]   ),
    .mask_operand_ready_i         (mask_operand_ready_i[1:0]   )
  );

  ///////////////////////////////
  //  Vector Functional Units  //
  ///////////////////////////////

  vector_fus_stage #(
    .NrLanes   (NrLanes   ),
    .FPUSupport(FPUSupport),
    .vaddr_t   (vaddr_t   )
  ) i_vfus (
    .clk_i                (clk_i                                  ),
    .rst_ni               (rst_ni                                 ),
    // Interface with CVA6
    .fflags_ex_o          (fflags_ex_o                            ),
    .fflags_ex_valid_o    (fflags_ex_valid_o                      ),
    // Interface with the lane sequencer
    .vfu_operation_i      (vfu_operation                          ),
    .vfu_operation_valid_i(vfu_operation_valid                    ),
    .alu_ready_o          (alu_ready                              ),
    .alu_vinsn_done_o     (alu_vinsn_done                         ),
    .mfpu_ready_o         (mfpu_ready                             ),
    .mfpu_vinsn_done_o    (mfpu_vinsn_done                        ),
    // Interface with the operand requester
    // ALU
    .alu_result_req_o     (alu_result_req                         ),
    .alu_result_id_o      (alu_result_id                          ),
    .alu_result_addr_o    (alu_result_addr                        ),
    .alu_result_wdata_o   (alu_result_wdata                       ),
    .alu_result_be_o      (alu_result_be                          ),
    .alu_result_gnt_i     (alu_result_gnt                         ),
    // MFPU
    .mfpu_result_req_o    (mfpu_result_req                        ),
    .mfpu_result_id_o     (mfpu_result_id                         ),
    .mfpu_result_addr_o   (mfpu_result_addr                       ),
    .mfpu_result_wdata_o  (mfpu_result_wdata                      ),
    .mfpu_result_be_o     (mfpu_result_be                         ),
    .mfpu_result_gnt_i    (mfpu_result_gnt                        ),
    // Interface with the operand queues
    // ALU
    .alu_operand_i        (alu_operand                            ),
    .alu_operand_valid_i  (alu_operand_valid                      ),
    .alu_operand_ready_o  (alu_operand_ready                      ),
    // Multiplier/FPU
    .mfpu_operand_i       (mfpu_operand                           ),
    .mfpu_operand_valid_i (mfpu_operand_valid                     ),
    .mfpu_operand_ready_o (mfpu_operand_ready                     ),
    // Interface with the Mask unit
    .mask_operand_o       (mask_operand_o[2 +: NrMaskFUnits]      ),
    .mask_operand_valid_o (mask_operand_valid_o[2 +: NrMaskFUnits]),
    .mask_operand_ready_i (mask_operand_ready_i[2 +: NrMaskFUnits]),
    .mask_i               (mask                                   ),
    .mask_valid_i         (mask_valid                             ),
    .mask_ready_o         (mask_ready                             )
  );

  //////////////////
  //  Assertions  //
  //////////////////

  if (NrLanes == 0)
    $error("[lane] Ara needs to have at least one lane.");

endmodule : lane
