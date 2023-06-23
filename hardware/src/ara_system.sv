// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's System, containing Ariane and Ara.

module ara_system import axi_pkg::*; import ara_pkg::*; #(
    // RVV Parameters
    parameter int                      unsigned NrLanes            = 0,                               // Number of parallel vector lanes.
    // Support for floating-point data types
    parameter fpu_support_e                     FPUSupport         = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter fpext_support_e                   FPExtSupport       = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter fixpt_support_e                   FixPtSupport       = FixedPointEnable,
    // Ariane configuration
    parameter ariane_pkg::ariane_cfg_t          ArianeCfg          = ariane_pkg::ArianeDefaultConfig,
    // AXI Interface
    parameter int                      unsigned AxiAddrWidth       = 64,
    parameter int                      unsigned AxiIdWidth         = 6,
    parameter int                      unsigned AxiNarrowDataWidth = 64,
    parameter int                      unsigned AxiWideDataWidth   = 64*NrLanes/2,
    parameter type                              ariane_axi_ar_t    = logic,
    parameter type                              ariane_axi_r_t     = logic,
    parameter type                              ariane_axi_aw_t    = logic,
    parameter type                              ariane_axi_w_t     = logic,
    parameter type                              ariane_axi_b_t     = logic,
    parameter type                              ariane_axi_req_t   = logic,
    parameter type                              ariane_axi_resp_t  = logic,
    parameter type                              ara_axi_ar_t       = logic,
    parameter type                              ara_axi_r_t        = logic,
    parameter type                              ara_axi_aw_t       = logic,
    parameter type                              ara_axi_w_t        = logic,
    parameter type                              ara_axi_b_t        = logic,
    parameter type                              ara_axi_req_t      = logic,
    parameter type                              ara_axi_resp_t     = logic,
    parameter type                              system_axi_ar_t    = logic,
    parameter type                              system_axi_r_t     = logic,
    parameter type                              system_axi_aw_t    = logic,
    parameter type                              system_axi_w_t     = logic,
    parameter type                              system_axi_b_t     = logic,
    parameter type                              system_axi_req_t   = logic,
    parameter type                              system_axi_resp_t  = logic
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic             [63:0] boot_addr_i,
    input                     [2:0] hart_id_i,
    // Scan chain
    input  logic                    scan_enable_i,
    input  logic                    scan_data_i,
    output logic                    scan_data_o,
    // AXI Interface
    output system_axi_req_t         axi_req_o,
    input  system_axi_resp_t        axi_resp_i
  );

  `include "axi/assign.svh"
  `include "axi/typedef.svh"

  ///////////
  //  AXI  //
  ///////////

  ariane_axi_req_t  ariane_narrow_axi_req;
  ariane_axi_resp_t ariane_narrow_axi_resp;
  ara_axi_req_t     ariane_axi_req, ara_axi_req_inval, ara_axi_req;
  ara_axi_resp_t    ariane_axi_resp, ara_axi_resp_inval, ara_axi_resp;

  //////////////////////
  //  Ara and Ariane  //
  //////////////////////

  import acc_pkg::accelerator_req_t;
  import acc_pkg::accelerator_resp_t;

  // Accelerator ports
  accelerator_req_t                     acc_req;
  accelerator_resp_t                    acc_resp;
  logic                                 acc_resp_valid;
  logic                                 acc_resp_ready;
  logic                                 acc_cons_en;
  logic              [AxiAddrWidth-1:0] inval_addr;
  logic                                 inval_valid;
  logic                                 inval_ready;

  // Support max 8 cores, for now
  logic [63:0] hart_id;
  assign hart_id = {'0, hart_id_i};

  // Pack invalidation interface into acc interface
  accelerator_resp_t                    acc_resp_pack;
  always_comb begin : pack_inval
    acc_resp_pack             = acc_resp;
    acc_resp_pack.inval_valid = inval_valid;
    acc_resp_pack.inval_addr  = inval_addr;
    inval_ready               = acc_req.inval_ready;
    acc_cons_en               = acc_req.acc_cons_en;
  end

`ifdef IDEAL_DISPATCHER
  // Perfect dispatcher to Ara
  accel_dispatcher_ideal i_accel_dispatcher_ideal (
    .clk_i            (clk_i                 ),
    .rst_ni           (rst_ni                ),
    .acc_req_o        (acc_req               ),
    .acc_resp_i       (acc_resp              ),
    .acc_resp_valid_i (acc_resp_valid        ),
    .acc_resp_ready_o (acc_resp_ready        )
  );
`else
  cva6 #(
    .ArianeCfg(ArianeCfg),
    .cvxif_req_t (acc_pkg::accelerator_req_t),
    .cvxif_resp_t (acc_pkg::accelerator_resp_t),
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiNarrowDataWidth ),
    .AxiIdWidth ( AxiIdWidth ),
    .axi_ar_chan_t (ariane_axi_ar_t),
    .axi_aw_chan_t (ariane_axi_aw_t),
    .axi_w_chan_t (ariane_axi_w_t),
    .axi_req_t (ariane_axi_req_t),
    .axi_rsp_t (ariane_axi_resp_t)
  ) i_ariane (
    .clk_i            (clk_i                 ),
    .rst_ni           (rst_ni                ),
    .boot_addr_i      (boot_addr_i           ),
    .hart_id_i        (hart_id               ),
    .irq_i            ('0                    ),
    .ipi_i            ('0                    ),
    .time_irq_i       ('0                    ),
    .debug_req_i      ('0                    ),
    .rvfi_o           (                      ),
    // Accelerator ports
    .cvxif_req_o      (acc_req               ),
    .cvxif_resp_i     (acc_resp_pack         ),
    .l15_req_o        (                      ),
    .l15_rtrn_i       ( '0                   ),
    // Memory interface
    .axi_req_o        (ariane_narrow_axi_req ),
    .axi_resp_i       (ariane_narrow_axi_resp)
  );
`endif

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiNarrowDataWidth),
    .AxiMstPortDataWidth(AxiWideDataWidth  ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiIdWidth        ),
    .AxiMaxReads        (2                 ),
    .ar_chan_t          (ariane_axi_ar_t   ),
    .mst_r_chan_t       (ara_axi_r_t       ),
    .slv_r_chan_t       (ariane_axi_r_t    ),
    .aw_chan_t          (ariane_axi_aw_t   ),
    .b_chan_t           (ariane_axi_b_t    ),
    .mst_w_chan_t       (ara_axi_w_t       ),
    .slv_w_chan_t       (ariane_axi_w_t    ),
    .axi_mst_req_t      (ara_axi_req_t     ),
    .axi_mst_resp_t     (ara_axi_resp_t    ),
    .axi_slv_req_t      (ariane_axi_req_t  ),
    .axi_slv_resp_t     (ariane_axi_resp_t )
  ) i_ariane_axi_dwc (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
`ifdef IDEAL_DISPATCHER
    .slv_req_i ('0                    ),
`else
    .slv_req_i (ariane_narrow_axi_req ),
`endif
    .slv_resp_o(ariane_narrow_axi_resp),
    .mst_req_o (ariane_axi_req        ),
    .mst_resp_i(ariane_axi_resp       )
  );

  axi_inval_filter #(
    .MaxTxns    (4                              ),
    .AddrWidth  (AxiAddrWidth                   ),
    .L1LineWidth(ariane_pkg::DCACHE_LINE_WIDTH/8),
    .aw_chan_t  (ara_axi_aw_t                   ),
    .req_t      (ara_axi_req_t                  ),
    .resp_t     (ara_axi_resp_t                 )
  ) i_axi_inval_filter (
    .clk_i        (clk_i             ),
    .rst_ni       (rst_ni            ),
`ifdef IDEAL_DISPATCHER
    .en_i         (1'b0              ),
`else
    .en_i         (acc_cons_en       ),
`endif
    .slv_req_i    (ara_axi_req       ),
    .slv_resp_o   (ara_axi_resp      ),
    .mst_req_o    (ara_axi_req_inval ),
    .mst_resp_i   (ara_axi_resp_inval),
    .inval_addr_o (inval_addr        ),
    .inval_valid_o(inval_valid       ),
`ifdef IDEAL_DISPATCHER
    .inval_ready_i(1'b0              )
`else
    .inval_ready_i(inval_ready       )
`endif
  );

  ara #(
    .NrLanes     (NrLanes         ),
    .FPUSupport  (FPUSupport      ),
    .FPExtSupport(FPExtSupport    ),
    .FixPtSupport(FixPtSupport    ),
    .AxiDataWidth(AxiWideDataWidth),
    .AxiAddrWidth(AxiAddrWidth    ),
    .axi_ar_t    (ara_axi_ar_t    ),
    .axi_r_t     (ara_axi_r_t     ),
    .axi_aw_t    (ara_axi_aw_t    ),
    .axi_w_t     (ara_axi_w_t     ),
    .axi_b_t     (ara_axi_b_t     ),
    .axi_req_t   (ara_axi_req_t   ),
    .axi_resp_t  (ara_axi_resp_t  )
  ) i_ara (
    .clk_i           (clk_i         ),
    .rst_ni          (rst_ni        ),
    .scan_enable_i   (scan_enable_i ),
    .scan_data_i     (1'b0          ),
    .scan_data_o     (/* Unused */  ),
    .acc_req_i       (acc_req       ),
    .acc_resp_o      (acc_resp      ),
    .axi_req_o       (ara_axi_req   ),
    .axi_resp_i      (ara_axi_resp  )
  );

  axi_mux #(
    .SlvAxiIDWidth(AxiIdWidth       ),
    .slv_ar_chan_t(ara_axi_ar_t     ),
    .slv_aw_chan_t(ara_axi_aw_t     ),
    .slv_b_chan_t (ara_axi_b_t      ),
    .slv_r_chan_t (ara_axi_r_t      ),
    .slv_req_t    (ara_axi_req_t    ),
    .slv_resp_t   (ara_axi_resp_t   ),
    .mst_ar_chan_t(system_axi_ar_t  ),
    .mst_aw_chan_t(system_axi_aw_t  ),
    .w_chan_t     (system_axi_w_t   ),
    .mst_b_chan_t (system_axi_b_t   ),
    .mst_r_chan_t (system_axi_r_t   ),
    .mst_req_t    (system_axi_req_t ),
    .mst_resp_t   (system_axi_resp_t),
    .NoSlvPorts   (2                ),
    .SpillAr      (1'b1             ),
    .SpillR       (1'b1             ),
    .SpillAw      (1'b1             ),
    .SpillW       (1'b1             ),
    .SpillB       (1'b1             )
  ) i_system_mux (
    .clk_i      (clk_i                                ),
    .rst_ni     (rst_ni                               ),
    .test_i     (1'b0                                 ),
    .slv_reqs_i ({ara_axi_req_inval, ariane_axi_req}  ),
    .slv_resps_o({ara_axi_resp_inval, ariane_axi_resp}),
    .mst_req_o  (axi_req_o                            ),
    .mst_resp_i (axi_resp_i                           )
  );

endmodule : ara_system
