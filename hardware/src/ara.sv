// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's top-level, interfacing with Ariane.

module ara import ara_pkg::*; #(
    // RVV Parameters
    parameter  int           unsigned NrLanes      = 0,                          // Number of parallel vector lanes.
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // AXI Interface
    parameter  int           unsigned AxiDataWidth = 0,
    parameter  int           unsigned AxiAddrWidth = 0,
    parameter  type                   axi_ar_t     = logic,
    parameter  type                   axi_r_t      = logic,
    parameter  type                   axi_aw_t     = logic,
    parameter  type                   axi_w_t      = logic,
    parameter  type                   axi_b_t      = logic,
    parameter  type                   axi_req_t    = logic,
    parameter  type                   axi_resp_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    // Ara has NrLanes + 3 processing elements: each one of the lanes, the vector load unit, the
    // vector store unit, the slide unit, and the mask unit.
    localparam int           unsigned NrPEs        = NrLanes + 4
  ) (
    // Clock and Reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Scan chain
    input  logic              scan_enable_i,
    input  logic              scan_data_i,
    output logic              scan_data_o,
    // Interface with Ariane
    input  accelerator_req_t  acc_req_i,
    input  logic              acc_req_valid_i,
    output logic              acc_req_ready_o,
    output accelerator_resp_t acc_resp_o,
    output logic              acc_resp_valid_o,
    input  logic              acc_resp_ready_i,
    // AXI interface
    output axi_req_t          axi_req_o,
    input  axi_resp_t         axi_resp_i
  );

  import cf_math_pkg::idx_width;

  ///////////////////
  //  Definitions  //
  ///////////////////

  localparam int unsigned MaxVLenPerLane  = VLEN / NrLanes;       // In bits
  localparam int unsigned MaxVLenBPerLane = VLENB / NrLanes;      // In bytes
  localparam int unsigned VRFSizePerLane  = MaxVLenPerLane * 32;  // In bits
  localparam int unsigned VRFBSizePerLane = MaxVLenBPerLane * 32; // In bytes
  // Address of an element in each lane's VRF
  typedef logic [idx_width(VRFBSizePerLane)-1:0] vaddr_t;

  localparam int unsigned DataWidth = $bits(elen_t);
  localparam int unsigned StrbWidth = DataWidth / 8;
  typedef logic [StrbWidth-1:0] strb_t;

  //////////////////
  //  Dispatcher  //
  //////////////////

  // Interface with the sequencer
  ara_req_t                     ara_req;
  logic                         ara_req_valid;
  logic                         ara_req_ready;
  ara_resp_t                    ara_resp;
  logic                         ara_resp_valid;
  logic                         ara_idle;
  // Interface with the VSTU
  logic                         core_st_pending;
  logic                         load_complete;
  logic                         store_complete;
  logic                         store_pending;
  // Interface with the lanes
  logic      [NrLanes-1:0][4:0] fflags_ex;
  logic      [NrLanes-1:0]      fflags_ex_valid;
  logic      [NrLanes-1:0]      vxsat_flag;
  vxrm_t     [NrLanes-1:0]      alu_vxrm;

  ara_dispatcher #(
    .NrLanes(NrLanes)
  ) i_dispatcher (
    .clk_i             (clk_i           ),
    .rst_ni            (rst_ni          ),
    // Interface with Ariane
    .acc_req_i         (acc_req_i       ),
    .acc_req_valid_i   (acc_req_valid_i ),
    .acc_req_ready_o   (acc_req_ready_o ),
    .acc_resp_o        (acc_resp_o      ),
    .acc_resp_valid_o  (acc_resp_valid_o),
    .acc_resp_ready_i  (acc_resp_ready_i),
    // Interface with the sequencer
    .ara_req_o         (ara_req         ),
    .ara_req_valid_o   (ara_req_valid   ),
    .ara_req_ready_i   (ara_req_ready   ),
    .ara_resp_i        (ara_resp        ),
    .ara_resp_valid_i  (ara_resp_valid  ),
    .ara_idle_i        (ara_idle        ),
    // Interface with the lanes
    .vxsat_flag_i      (vxsat_flag      ),
    .alu_vxrm_o        (alu_vxrm        ),
    .fflags_ex_i       (fflags_ex       ),
    .fflags_ex_valid_i (fflags_ex_valid ),
    // Interface with the Vector Store Unit
    .core_st_pending_o (core_st_pending ),
    .load_complete_i   (load_complete   ),
    .store_complete_i  (store_complete  ),
    .store_pending_i   (store_pending   )
  );

  /////////////////
  //  Sequencer  //
  /////////////////

  // Interface with the PEs
  pe_req_t                         pe_req;
  logic                            pe_req_valid;
  logic              [NrPEs-1:0]   pe_req_ready;
  logic              [NrVInsn-1:0] pe_vinsn_running;
  pe_resp_t          [NrPEs-1:0]   pe_resp;
  // Interface with the address generator
  logic                            addrgen_ack;
  logic                            addrgen_error;
  vlen_t                           addrgen_error_vl;
  logic              [NrLanes-1:0] alu_vinsn_done;
  logic              [NrLanes-1:0] mfpu_vinsn_done;
  // Interface with the operand requesters
  logic [NrVInsn-1:0][NrVInsn-1:0] global_hazard_table;
  // Ready for lane 0 (scalar operand fwd)
  logic pe_scalar_resp_ready;

  // Mask unit operands
  elen_t     [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand;
  logic      [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_valid;
  logic      [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_ready_masku, masku_operand_ready_lane;
  strb_t     [NrLanes-1:0]                     mask;
  logic      [NrLanes-1:0]                     mask_valid;
  logic                                        mask_valid_lane;
  logic      [NrLanes-1:0]                     lane_mask_ready;

  ara_sequencer #(.NrLanes(NrLanes)) i_sequencer (
    .clk_i                 (clk_i                    ),
    .rst_ni                (rst_ni                   ),
    // Interface with the dispatcher
    .ara_req_i             (ara_req                  ),
    .ara_req_valid_i       (ara_req_valid            ),
    .ara_req_ready_o       (ara_req_ready            ),
    .ara_resp_o            (ara_resp                 ),
    .ara_resp_valid_o      (ara_resp_valid           ),
    .ara_idle_o            (ara_idle                 ),
    // Interface with the PEs
    .pe_req_o              (pe_req                   ),
    .pe_req_valid_o        (pe_req_valid             ),
    .pe_vinsn_running_o    (pe_vinsn_running         ),
    .pe_req_ready_i        (pe_req_ready             ),
    .pe_resp_i             (pe_resp                  ),
    .alu_vinsn_done_i      (alu_vinsn_done[0]        ),
    .mfpu_vinsn_done_i     (mfpu_vinsn_done[0]       ),
    // Interface with the operand requesters
    .global_hazard_table_o (global_hazard_table      ),
    // Interface with the lane 0
    .pe_scalar_resp_i      (masku_operand[0][1]      ), // MaskB OpQueue
    .pe_scalar_resp_valid_i(masku_operand_valid[0][1]), // MaskB OpQueue Valid
    .pe_scalar_resp_ready_o(pe_scalar_resp_ready     ),
    // Interface with the address generator
    .addrgen_ack_i         (addrgen_ack              ),
    .addrgen_error_i       (addrgen_error            ),
    .addrgen_error_vl_i    (addrgen_error_vl         )
  );

  // Scalar move support
  always_comb begin
    masku_operand_ready_lane = masku_operand_ready_masku;
    // The scalar move fetches the data from lane 0 - MaskB OpQueue (idx == 1)
    masku_operand_ready_lane[0][1] = masku_operand_ready_masku[0][1] | pe_scalar_resp_ready;
  end

  /////////////
  //  Lanes  //
  /////////////

  // Interface with the vector load/store unit
  // Store unit
  elen_t     [NrLanes-1:0]                     stu_operand;
  logic      [NrLanes-1:0]                     stu_operand_valid;
  logic      [NrLanes-1:0]                     stu_operand_ready;
  // Slide unit/address generation operands
  elen_t     [NrLanes-1:0]                     sldu_addrgen_operand;
  target_fu_e[NrLanes-1:0]                     sldu_addrgen_operand_target_fu;
  logic      [NrLanes-1:0]                     sldu_addrgen_operand_valid;
  logic      [NrLanes-1:0]                     sldu_operand_ready;
  sldu_mux_e                                   sldu_mux_sel;
  logic                                        addrgen_operand_ready;
  logic      [NrLanes-1:0]                     sldu_red_valid;

  // Results
  // Load Unit
  logic      [NrLanes-1:0]                     ldu_result_req;
  vid_t      [NrLanes-1:0]                     ldu_result_id;
  vaddr_t    [NrLanes-1:0]                     ldu_result_addr;
  elen_t     [NrLanes-1:0]                     ldu_result_wdata;
  strb_t     [NrLanes-1:0]                     ldu_result_be;
  logic      [NrLanes-1:0]                     ldu_result_gnt;
  logic      [NrLanes-1:0]                     ldu_result_final_gnt;
  // Slide Unit
  logic      [NrLanes-1:0]                     sldu_result_req;
  vid_t      [NrLanes-1:0]                     sldu_result_id;
  vaddr_t    [NrLanes-1:0]                     sldu_result_addr;
  elen_t     [NrLanes-1:0]                     sldu_result_wdata;
  strb_t     [NrLanes-1:0]                     sldu_result_be;
  logic      [NrLanes-1:0]                     sldu_result_gnt;
  logic      [NrLanes-1:0]                     sldu_result_final_gnt;
  // Mask Unit
  logic      [NrLanes-1:0]                     masku_result_req;
  vid_t      [NrLanes-1:0]                     masku_result_id;
  vaddr_t    [NrLanes-1:0]                     masku_result_addr;
  elen_t     [NrLanes-1:0]                     masku_result_wdata;
  strb_t     [NrLanes-1:0]                     masku_result_be;
  logic      [NrLanes-1:0]                     masku_result_gnt;
  logic      [NrLanes-1:0]                     masku_result_final_gnt;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_lanes
    lane #(
      .NrLanes   (NrLanes   ),
      .FPUSupport(FPUSupport)
    ) i_lane (
      .clk_i                           (clk_i                               ),
      .rst_ni                          (rst_ni                              ),
      .scan_enable_i                   (scan_enable_i                       ),
      .scan_data_i                     (1'b0                                ),
      .scan_data_o                     (/* Unused */                        ),
      .lane_id_i                       (lane[idx_width(NrLanes)-1:0]        ),
      // Interface with the dispatcher
      .vxsat_flag_o                    (vxsat_flag[lane]                    ),
      .alu_vxrm_i                      (alu_vxrm[lane]                      ),
      .fflags_ex_o                     (fflags_ex[lane]                     ),
      .fflags_ex_valid_o               (fflags_ex_valid[lane]               ),
      // Interface with the sequencer
      .pe_req_i                        (pe_req                              ),
      .pe_req_valid_i                  (pe_req_valid                        ),
      .pe_vinsn_running_i              (pe_vinsn_running                    ),
      .pe_req_ready_o                  (pe_req_ready[lane]                  ),
      .pe_resp_o                       (pe_resp[lane]                       ),
      .alu_vinsn_done_o                (alu_vinsn_done[lane]                ),
      .mfpu_vinsn_done_o               (mfpu_vinsn_done[lane]               ),
      .global_hazard_table_i           (global_hazard_table                 ),
      // Interface with the slide unit
      .sldu_result_req_i               (sldu_result_req[lane]               ),
      .sldu_result_addr_i              (sldu_result_addr[lane]              ),
      .sldu_result_id_i                (sldu_result_id[lane]                ),
      .sldu_result_wdata_i             (sldu_result_wdata[lane]             ),
      .sldu_result_be_i                (sldu_result_be[lane]                ),
      .sldu_result_gnt_o               (sldu_result_gnt[lane]               ),
      .sldu_result_final_gnt_o         (sldu_result_final_gnt[lane]         ),
      // Interface with the load unit
      .ldu_result_req_i                (ldu_result_req[lane]                ),
      .ldu_result_addr_i               (ldu_result_addr[lane]               ),
      .ldu_result_id_i                 (ldu_result_id[lane]                 ),
      .ldu_result_wdata_i              (ldu_result_wdata[lane]              ),
      .ldu_result_be_i                 (ldu_result_be[lane]                 ),
      .ldu_result_gnt_o                (ldu_result_gnt[lane]                ),
      .ldu_result_final_gnt_o          (ldu_result_final_gnt[lane]          ),
      // Interface with the store unit
      .stu_operand_o                   (stu_operand[lane]                   ),
      .stu_operand_valid_o             (stu_operand_valid[lane]             ),
      .stu_operand_ready_i             (stu_operand_ready[lane]             ),
      // Interface with the slide/address generation unit
      .sldu_addrgen_operand_o          (sldu_addrgen_operand[lane]          ),
      .sldu_addrgen_operand_target_fu_o(sldu_addrgen_operand_target_fu[lane]),
      .sldu_addrgen_operand_valid_o    (sldu_addrgen_operand_valid[lane]    ),
      .addrgen_operand_ready_i         (addrgen_operand_ready               ),
      .sldu_mux_sel_i                  (sldu_mux_sel                        ),
      .sldu_operand_ready_i            (sldu_operand_ready[lane]            ),
      .sldu_red_valid_i                (sldu_red_valid[lane]                ),
      // Interface with the mask unit
      .mask_operand_o                  (masku_operand[lane]                 ),
      .mask_operand_valid_o            (masku_operand_valid[lane]           ),
      .mask_operand_ready_i            (masku_operand_ready_lane[lane]      ),
      .masku_result_req_i              (masku_result_req[lane]              ),
      .masku_result_addr_i             (masku_result_addr[lane]             ),
      .masku_result_id_i               (masku_result_id[lane]               ),
      .masku_result_wdata_i            (masku_result_wdata[lane]            ),
      .masku_result_be_i               (masku_result_be[lane]               ),
      .masku_result_gnt_o              (masku_result_gnt[lane]              ),
      .masku_result_final_gnt_o        (masku_result_final_gnt[lane]        ),
      .mask_i                          (mask[lane]                          ),
      .mask_valid_i                    (mask_valid[lane] & mask_valid_lane  ),
      .mask_ready_o                    (lane_mask_ready[lane]               )
    );
  end: gen_lanes


  //////////////////////////////
  //  Vector Load/Store Unit  //
  //////////////////////////////

  // Interface with the Mask unit
  logic vldu_mask_ready;
  logic vstu_mask_ready;

  vlsu #(
    .NrLanes     (NrLanes     ),
    .AxiDataWidth(AxiDataWidth),
    .AxiAddrWidth(AxiAddrWidth),
    .axi_ar_t    (axi_ar_t    ),
    .axi_r_t     (axi_r_t     ),
    .axi_aw_t    (axi_aw_t    ),
    .axi_w_t     (axi_w_t     ),
    .axi_b_t     (axi_b_t     ),
    .axi_req_t   (axi_req_t   ),
    .axi_resp_t  (axi_resp_t  ),
    .vaddr_t     (vaddr_t     )
  ) i_vlsu (
    .clk_i                      (clk_i                                                 ),
    .rst_ni                     (rst_ni                                                ),
    // AXI memory interface
    .axi_req_o                  (axi_req_o                                             ),
    .axi_resp_i                 (axi_resp_i                                            ),
    // Interface with the dispatcher
    .core_st_pending_i          (core_st_pending                                       ),
    .load_complete_o            (load_complete                                         ),
    .store_complete_o           (store_complete                                        ),
    .store_pending_o            (store_pending                                         ),
    // Interface with the sequencer
    .pe_req_i                   (pe_req                                                ),
    .pe_req_valid_i             (pe_req_valid                                          ),
    .pe_vinsn_running_i         (pe_vinsn_running                                      ),
    .pe_req_ready_o             (pe_req_ready[NrLanes+OffsetStore : NrLanes+OffsetLoad]),
    .pe_resp_o                  (pe_resp[NrLanes+OffsetStore : NrLanes+OffsetLoad]     ),
    .addrgen_ack_o              (addrgen_ack                                           ),
    .addrgen_error_o            (addrgen_error                                         ),
    .addrgen_error_vl_o         (addrgen_error_vl                                      ),
    // Interface with the Mask unit
    .mask_i                     (mask                                                  ),
    .mask_valid_i               (mask_valid                                            ),
    .vldu_mask_ready_o          (vldu_mask_ready                                       ),
    .vstu_mask_ready_o          (vstu_mask_ready                                       ),
    // Interface with the lanes
    // Store unit
    .stu_operand_i              (stu_operand                                           ),
    .stu_operand_valid_i        (stu_operand_valid                                     ),
    .stu_operand_ready_o        (stu_operand_ready                                     ),
    // Address Generation
    .addrgen_operand_i          (sldu_addrgen_operand                                  ),
    .addrgen_operand_target_fu_i(sldu_addrgen_operand_target_fu                        ),
    .addrgen_operand_valid_i    (sldu_addrgen_operand_valid                            ),
    .addrgen_operand_ready_o    (addrgen_operand_ready                                 ),
    // Load unit
    .ldu_result_req_o           (ldu_result_req                                        ),
    .ldu_result_addr_o          (ldu_result_addr                                       ),
    .ldu_result_id_o            (ldu_result_id                                         ),
    .ldu_result_wdata_o         (ldu_result_wdata                                      ),
    .ldu_result_be_o            (ldu_result_be                                         ),
    .ldu_result_gnt_i           (ldu_result_gnt                                        ),
    .ldu_result_final_gnt_i     (ldu_result_final_gnt                                  )
  );

  //////////////////
  //  Slide unit  //
  //////////////////

  // Interface with the Mask Unit
  logic sldu_mask_ready;

  sldu #(
    .NrLanes(NrLanes),
    .vaddr_t(vaddr_t)
  ) i_sldu (
    .clk_i                   (clk_i                            ),
    .rst_ni                  (rst_ni                           ),
    // Interface with the main sequencer
    .pe_req_i                (pe_req                           ),
    .pe_req_valid_i          (pe_req_valid                     ),
    .pe_vinsn_running_i      (pe_vinsn_running                 ),
    .pe_req_ready_o          (pe_req_ready[NrLanes+OffsetSlide]),
    .pe_resp_o               (pe_resp[NrLanes+OffsetSlide]     ),
    // Interface with the lanes
    .sldu_operand_i          (sldu_addrgen_operand             ),
    .sldu_operand_target_fu_i(sldu_addrgen_operand_target_fu   ),
    .sldu_operand_valid_i    (sldu_addrgen_operand_valid       ),
    .sldu_operand_ready_o    (sldu_operand_ready               ),
    .sldu_result_req_o       (sldu_result_req                  ),
    .sldu_result_addr_o      (sldu_result_addr                 ),
    .sldu_result_id_o        (sldu_result_id                   ),
    .sldu_result_be_o        (sldu_result_be                   ),
    .sldu_result_wdata_o     (sldu_result_wdata                ),
    .sldu_result_gnt_i       (sldu_result_gnt                  ),
    .sldu_mux_sel_o          (sldu_mux_sel                     ),
    .sldu_red_valid_o        (sldu_red_valid                   ),
    .sldu_result_final_gnt_i (sldu_result_final_gnt            ),
    // Interface with the Mask unit
    .mask_i                  (mask                             ),
    .mask_valid_i            (mask_valid                       ),
    .mask_ready_o            (sldu_mask_ready                  )
  );

  /////////////////
  //  Mask unit  //
  /////////////////

  masku #(
    .NrLanes(NrLanes),
    .vaddr_t(vaddr_t)
  ) i_masku (
    .clk_i                   (clk_i                           ),
    .rst_ni                  (rst_ni                          ),
    // Interface with the main sequencer
    .pe_req_i                (pe_req                          ),
    .pe_req_valid_i          (pe_req_valid                    ),
    .pe_vinsn_running_i      (pe_vinsn_running                ),
    .pe_req_ready_o          (pe_req_ready[NrLanes+OffsetMask]),
    .pe_resp_o               (pe_resp[NrLanes+OffsetMask]     ),
    // Interface with the lanes
    .masku_operand_i         (masku_operand                   ),
    .masku_operand_valid_i   (masku_operand_valid             ),
    .masku_operand_ready_o   (masku_operand_ready_masku       ),
    .masku_result_req_o      (masku_result_req                ),
    .masku_result_addr_o     (masku_result_addr               ),
    .masku_result_id_o       (masku_result_id                 ),
    .masku_result_wdata_o    (masku_result_wdata              ),
    .masku_result_be_o       (masku_result_be                 ),
    .masku_result_gnt_i      (masku_result_gnt                ),
    .masku_result_final_gnt_i(masku_result_final_gnt          ),
    // Interface with the VFUs
    .mask_o                  (mask                            ),
    .mask_valid_o            (mask_valid                      ),
    .mask_valid_lane_o       (mask_valid_lane                 ),
    .lane_mask_ready_i       (lane_mask_ready                 ),
    .vldu_mask_ready_i       (vldu_mask_ready                 ),
    .vstu_mask_ready_i       (vstu_mask_ready                 ),
    .sldu_mask_ready_i       (sldu_mask_ready                 )
  );

  //////////////////
  //  Assertions  //
  //////////////////

  if (NrLanes == 0)
    $error("[ara] Ara needs to have at least one lane.");

  if (NrLanes != 2**$clog2(NrLanes))
    $error("[ara] The number of lanes must be a power of two.");

  if (NrLanes > MaxNrLanes)
    $error("[ara] Ara supports at most MaxNrLanes lanes.");

  if (ara_pkg::VLEN == 0)
    $error("[ara] The vector length must be greater than zero.");

  if (ara_pkg::VLEN < ELEN)
    $error(
      "[ara] The vector length must be greater or equal than the maximum size of a single vector element"
    );

  if (ara_pkg::VLEN != 2**$clog2(ara_pkg::VLEN))
    $error("[ara] The vector length must be a power of two.");

  if (RVVD(FPUSupport) && !ariane_pkg::RVD)
    $error(
      "[ara] Cannot support double-precision floating-point on Ara if Ariane does not support it.");

  if (RVVF(FPUSupport) && !ariane_pkg::RVF)
    $error(
      "[ara] Cannot support single-precision floating-point on Ara if Ariane does not support it.");

  if (RVVH(FPUSupport) && !ariane_pkg::XF16)
    $error(
      "[ara] Cannot support half-precision floating-point on Ara if Ariane does not support it.");

endmodule : ara
