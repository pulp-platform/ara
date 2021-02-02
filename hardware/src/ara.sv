// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's top-level, interfacing with Ariane.

module ara import ara_pkg::*; #(
    // RVV Parameters
    parameter int  unsigned NrLanes      = 0,          // Number of parallel vector lanes.
    // AXI Interface
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_r_t      = logic,
    parameter type          axi_aw_t     = logic,
    parameter type          axi_w_t      = logic,
    parameter type          axi_b_t      = logic,
    parameter type          axi_req_t    = logic,
    parameter type          axi_resp_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    // Ara has NrLanes + 3 processing elements: each one of the lanes, the vector load unit, the vector store unit, the slide unit, and the mask unit.
    parameter int  unsigned NrPEs        = NrLanes + 4
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
    output logic        [2:0] acc_fflags_ex_o,
    output logic              acc_fflags_ex_valid_o,
    // AXI interface
    output axi_req_t          axi_req_o,
    input  axi_resp_t         axi_resp_i
  );

  import cf_math_pkg::idx_width;

  /*****************
   *  Definitions  *
   ****************/

  localparam int unsigned MaxVLenPerLane  = VLEN / NrLanes;       // In bits
  localparam int unsigned MaxVLenBPerLane = VLENB / NrLanes;      // In bytes
  localparam int unsigned VRFSizePerLane  = MaxVLenPerLane * 32;  // In bits
  localparam int unsigned VRFBSizePerLane = MaxVLenBPerLane * 32; // In bytes
  typedef logic [idx_width(VRFBSizePerLane)-1:0] vaddr_t; // Address of an element in each lane's VRF

  localparam int unsigned DataWidth = $bits(elen_t);
  localparam int unsigned StrbWidth = DataWidth / 8;
  typedef logic [StrbWidth-1:0] strb_t;

  /****************
   *  Dispatcher  *
   ****************/

  // Interface with the sequencer
  ara_req_t  ara_req;
  logic      ara_req_valid;
  logic      ara_req_ready;
  ara_resp_t ara_resp;
  logic      ara_resp_valid;
  logic      ara_idle;
  // Interface with the VSTU
  logic      core_st_pending;
  logic      load_complete;
  logic      store_complete;
  logic      store_pending;

  ara_dispatcher i_dispatcher (
    .clk_i            (clk_i           ),
    .rst_ni           (rst_ni          ),
    // Interface with Ariane
    .acc_req_i        (acc_req_i       ),
    .acc_req_valid_i  (acc_req_valid_i ),
    .acc_req_ready_o  (acc_req_ready_o ),
    .acc_resp_o       (acc_resp_o      ),
    .acc_resp_valid_o (acc_resp_valid_o),
    .acc_resp_ready_i (acc_resp_ready_i),
    // Interface with the sequencer
    .ara_req_o        (ara_req         ),
    .ara_req_valid_o  (ara_req_valid   ),
    .ara_req_ready_i  (ara_req_ready   ),
    .ara_resp_i       (ara_resp        ),
    .ara_resp_valid_i (ara_resp_valid  ),
    .ara_idle_i       (ara_idle        ),
    // Interface with the Vector Store Unit
    .core_st_pending_o(core_st_pending ),
    .load_complete_i  (load_complete   ),
    .store_complete_i (store_complete  ),
    .store_pending_i  (store_pending   )
  );

  /***************
   *  Sequencer  *
   ***************/

  // Interface with the PEs
  pe_req_t              pe_req;
  logic                 pe_req_valid;
  logic     [NrPEs-1:0] pe_req_ready;
  pe_resp_t [NrPEs-1:0] pe_resp;
  // Interface with the address generator
  logic                 addrgen_ack;
  logic                 addrgen_error;

  ara_sequencer #(
    .NrLanes(NrLanes),
    .NrPEs  (NrPEs  )
  ) i_sequencer (
    .clk_i                 (clk_i          ),
    .rst_ni                (rst_ni         ),
    // Interface with the dispatcher
    .ara_req_i             (ara_req        ),
    .ara_req_valid_i       (ara_req_valid  ),
    .ara_req_ready_o       (ara_req_ready  ),
    .ara_resp_o            (ara_resp       ),
    .ara_resp_valid_o      (ara_resp_valid ),
    .ara_idle_o            (ara_idle       ),
    // Interface with the PEs
    .pe_req_o              (pe_req         ),
    .pe_req_valid_o        (pe_req_valid   ),
    .pe_req_ready_i        (pe_req_ready   ),
    .pe_resp_i             (pe_resp        ),
    // Interface with the slide unit
    .pe_scalar_resp_i      ('0             ),
    .pe_scalar_resp_valid_i(1'b0           ),
    // Interface with the address generator
    .addrgen_ack_i         (addrgen_ack    ),
    .addrgen_error_i       (addrgen_error  )
  );

  /***********
   *  Lanes  *
   ***********/

  // Interface with CVA6
  logic   [NrLanes-1:0][2:0] fflags_ex;
  logic   [NrLanes-1:0]      fflags_ex_valid;
  // Interface with the vector load/store unit
  // Store unit
  elen_t  [NrLanes-1:0]      stu_operand;
  logic   [NrLanes-1:0]      stu_operand_valid;
  logic                      stu_operand_ready;
  // Address generation operands
  elen_t  [NrLanes-1:0]      addrgen_operand;
  logic   [NrLanes-1:0]      addrgen_operand_valid;
  logic                      addrgen_operand_ready;
  // Mask unit operands
  elen_t  [NrLanes-1:0][2:0] masku_operand;
  logic   [NrLanes-1:0][2:0] masku_operand_valid;
  logic   [NrLanes-1:0][2:0] masku_operand_ready;
  strb_t  [NrLanes-1:0]      mask;
  logic   [NrLanes-1:0]      mask_valid;
  logic   [NrLanes-1:0]      lane_mask_ready;
  // Results
  // Load Unit
  logic   [NrLanes-1:0]      ldu_result_req;
  vid_t   [NrLanes-1:0]      ldu_result_id;
  vaddr_t [NrLanes-1:0]      ldu_result_addr;
  elen_t  [NrLanes-1:0]      ldu_result_wdata;
  strb_t  [NrLanes-1:0]      ldu_result_be;
  logic   [NrLanes-1:0]      ldu_result_gnt;
  // Mask Unit
  logic   [NrLanes-1:0]      masku_result_req;
  vid_t   [NrLanes-1:0]      masku_result_id;
  vaddr_t [NrLanes-1:0]      masku_result_addr;
  elen_t  [NrLanes-1:0]      masku_result_wdata;
  strb_t  [NrLanes-1:0]      masku_result_be;
  logic   [NrLanes-1:0]      masku_result_gnt;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_lanes
    lane #(
      .NrLanes(NrLanes)
    ) i_lane (
      .clk_i                  (clk_i                       ),
      .rst_ni                 (rst_ni                      ),
      .scan_enable_i          (scan_enable_i               ),
      .scan_data_i            (1'b0                        ),
      .scan_data_o            (/* Unused */                ),
      .lane_id_i              (lane[idx_width(NrLanes)-1:0]),
      // Interface with CVA6
      .fflags_ex_o            (fflags_ex[lane]             ),
      .fflags_ex_valid_o      (fflags_ex_valid[lane]       ),
      // Interface with the sequencer
      .pe_req_i               (pe_req                      ),
      .pe_req_valid_i         (pe_req_valid                ),
      .pe_req_ready_o         (pe_req_ready[lane]          ),
      .pe_resp_o              (pe_resp[lane]               ),
      // Interface with the slide unit
      .sldu_result_req_i      (1'b0                        ),
      .sldu_result_addr_i     ('0                          ),
      .sldu_result_id_i       ('0                          ),
      .sldu_result_wdata_i    ('0                          ),
      .sldu_result_be_i       ('0                          ),
      .sldu_result_gnt_o      (/* Unused */                ),
      // Interface with the load unit
      .ldu_result_req_i       (ldu_result_req[lane]        ),
      .ldu_result_addr_i      (ldu_result_addr[lane]       ),
      .ldu_result_id_i        (ldu_result_id[lane]         ),
      .ldu_result_wdata_i     (ldu_result_wdata[lane]      ),
      .ldu_result_be_i        (ldu_result_be[lane]         ),
      .ldu_result_gnt_o       (ldu_result_gnt[lane]        ),
      // Interface with the store unit
      .stu_operand_o          (stu_operand[lane]           ),
      .stu_operand_valid_o    (stu_operand_valid[lane]     ),
      .stu_operand_ready_i    (stu_operand_ready           ),
      // Interface with the address generation unit
      .addrgen_operand_o      (addrgen_operand[lane]       ),
      .addrgen_operand_valid_o(addrgen_operand_valid[lane] ),
      .addrgen_operand_ready_i(addrgen_operand_ready       ),
      // Interface with the mask unit
      .mask_operand_o         (masku_operand[lane]         ),
      .mask_operand_valid_o   (masku_operand_valid[lane]   ),
      .mask_operand_ready_i   (masku_operand_ready[lane]   ),
      .masku_result_req_i     (masku_result_req[lane]      ),
      .masku_result_addr_i    (masku_result_addr[lane]     ),
      .masku_result_id_i      (masku_result_id[lane]       ),
      .masku_result_wdata_i   (masku_result_wdata[lane]    ),
      .masku_result_be_i      (masku_result_be[lane]       ),
      .masku_result_gnt_o     (masku_result_gnt[lane]      ),
      .mask_i                 (mask[lane]                  ),
      .mask_valid_i           (mask_valid[lane]            ),
      .mask_ready_o           (lane_mask_ready[lane]       )
    );
  end: gen_lanes

  // Combine imprecise FP exception signals and send them to CVA6 to update fcsr.fflags
  always_comb begin
      acc_fflags_ex_o       = 3'b0;
      acc_fflags_ex_valid_o = 1'b0;
    for (int lane = 0; lane < NrLanes; lane++) begin
      acc_fflags_ex_o       |= fflags_ex[lane];
      acc_fflags_ex_valid_o |= fflags_ex_valid[lane];
    end
  end

  /****************************
   *  Vector Load/Store Unit  *
   ****************************/

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
    .clk_i                  (clk_i                                                 ),
    .rst_ni                 (rst_ni                                                ),
    // AXI memory interface
    .axi_req_o              (axi_req_o                                             ),
    .axi_resp_i             (axi_resp_i                                            ),
    // Interface with the dispatcher
    .core_st_pending_i      (core_st_pending                                       ),
    .load_complete_o        (load_complete                                         ),
    .store_complete_o       (store_complete                                        ),
    .store_pending_o        (store_pending                                         ),
    // Interface with the sequencer
    .pe_req_i               (pe_req                                                ),
    .pe_req_valid_i         (pe_req_valid                                          ),
    .pe_req_ready_o         (pe_req_ready[NrLanes+OffsetStore : NrLanes+OffsetLoad]),
    .pe_resp_o              (pe_resp[NrLanes+OffsetStore : NrLanes+OffsetLoad]     ),
    .addrgen_ack_o          (addrgen_ack                                           ),
    .addrgen_error_o        (addrgen_error                                         ),
    // Interface with the Mask unit
    .mask_i                 (mask                                                  ),
    .mask_valid_i           (mask_valid                                            ),
    .vldu_mask_ready_o      (vldu_mask_ready                                       ),
    .vstu_mask_ready_o      (vstu_mask_ready                                       ),
    // Interface with the lanes
    // Store unit
    .stu_operand_i          (stu_operand                                           ),
    .stu_operand_valid_i    (stu_operand_valid                                     ),
    .stu_operand_ready_o    (stu_operand_ready                                     ),
    // Address Generation
    .addrgen_operand_i      (addrgen_operand                                       ),
    .addrgen_operand_valid_i(addrgen_operand_valid                                 ),
    .addrgen_operand_ready_o(addrgen_operand_ready                                 ),
    // Load unit
    .ldu_result_req_o       (ldu_result_req                                        ),
    .ldu_result_addr_o      (ldu_result_addr                                       ),
    .ldu_result_id_o        (ldu_result_id                                         ),
    .ldu_result_wdata_o     (ldu_result_wdata                                      ),
    .ldu_result_be_o        (ldu_result_be                                         ),
    .ldu_result_gnt_i       (ldu_result_gnt                                        )
  );

  /****************
   *  Slide unit  *
   ****************/

  assign pe_req_ready[NrLanes+OffsetSlide] = 1'b1;
  assign pe_resp[NrLanes+OffsetSlide]      = '0;

  /***************
   *  Mask unit  *
   ***************/

  masku #(
    .NrLanes(NrLanes),
    .vaddr_t(vaddr_t)
  ) i_masku (
    .clk_i                (clk_i                           ),
    .rst_ni               (rst_ni                          ),
    // Interface with the main sequencer
    .pe_req_i             (pe_req                          ),
    .pe_req_valid_i       (pe_req_valid                    ),
    .pe_req_ready_o       (pe_req_ready[NrLanes+OffsetMask]),
    .pe_resp_o            (pe_resp[NrLanes+OffsetMask]     ),
    // Interface with the lanes
    .masku_operand_i      (masku_operand                   ),
    .masku_operand_valid_i(masku_operand_valid             ),
    .masku_operand_ready_o(masku_operand_ready             ),
    .masku_result_req_o   (masku_result_req                ),
    .masku_result_addr_o  (masku_result_addr               ),
    .masku_result_id_o    (masku_result_id                 ),
    .masku_result_wdata_o (masku_result_wdata              ),
    .masku_result_be_o    (masku_result_be                 ),
    .masku_result_gnt_i   (masku_result_gnt                ),
    // Interface with the VFUs
    .mask_o               (mask                            ),
    .mask_valid_o         (mask_valid                      ),
    .lane_mask_ready_i    (lane_mask_ready                 ),
    .vldu_mask_ready_i    (vldu_mask_ready                 ),
    .vstu_mask_ready_i    (vstu_mask_ready                 )
  );

  /****************
   *  Assertions  *
   ****************/

  if (NrLanes == 0)
    $error("[ara] Ara needs to have at least one lane.");

  if (NrLanes != 2**$clog2(NrLanes))
    $error("[ara] The number of lanes must be a power of two.");

  if (NrLanes > MaxNrLanes)
    $error("[ara] Ara supports at most MaxNrLanes lanes.");

  if (ara_pkg::VLEN == 0)
    $error("[ara] The vector length must be greater than zero.");

  if (ara_pkg::VLEN < ELEN)
    $error("[ara] The vector length must be greater or equal than the maximum size of a single vector element");

  if (ara_pkg::VLEN != 2**$clog2(ara_pkg::VLEN))
    $error("[ara] The vector length must be a power of two.");

endmodule : ara
