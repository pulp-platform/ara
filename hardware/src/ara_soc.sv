// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's SoC, containing Ariane, Ara, and a L2 cache.

module ara_soc import axi_pkg::*; import ara_pkg::*; #(
    // RVV Parameters
    parameter  int           unsigned NrLanes      = 0, // Number of parallel vector lanes.
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // AXI Interface
    parameter  int           unsigned AxiDataWidth = 32*NrLanes,
    parameter  int           unsigned AxiAddrWidth = 64,
    parameter  int           unsigned AxiUserWidth = 1,
    parameter  int           unsigned AxiIdWidth   = 6,
    // Dependant parameters. DO NOT CHANGE!
    localparam type                   axi_data_t   = logic [AxiDataWidth-1:0],
    localparam type                   axi_strb_t   = logic [AxiDataWidth/8-1:0],
    localparam type                   axi_addr_t   = logic [AxiAddrWidth-1:0],
    localparam type                   axi_user_t   = logic [AxiUserWidth-1:0],
    localparam type                   axi_id_t     = logic [AxiIdWidth-1:0]
  ) (
    input  logic             clk_i,
    input  logic             rst_ni,
    output logic      [63:0] exit_o,
    // Scan chain
    input  logic             scan_enable_i,
    input  logic             scan_data_i,
    output logic             scan_data_o,
    // UART APB interface
    output logic             uart_penable_o,
    output logic             uart_pwrite_o,
    output logic      [31:0] uart_paddr_o,
    output logic             uart_psel_o,
    output logic      [31:0] uart_pwdata_o,
    input  logic      [31:0] uart_prdata_i,
    input  logic             uart_pready_i,
    input  logic             uart_pslverr_i,
    // AXI interface
    output logic             axi_aw_valid_o,
    output axi_id_t          axi_aw_id_o,
    output axi_addr_t        axi_aw_addr_o,
    output len_t             axi_aw_len_o,
    output size_t            axi_aw_size_o,
    output burst_t           axi_aw_burst_o,
    output logic             axi_aw_lock_o,
    output cache_t           axi_aw_cache_o,
    output prot_t            axi_aw_prot_o,
    output qos_t             axi_aw_qos_o,
    output region_t          axi_aw_region_o,
    output atop_t            axi_aw_atop_o,
    output axi_user_t        axi_aw_user_o,
    input  logic             axi_aw_ready_i,
    output logic             axi_w_valid_o,
    output axi_data_t        axi_w_data_o,
    output axi_strb_t        axi_w_strb_o,
    output logic             axi_w_last_o,
    output axi_user_t        axi_w_user_o,
    input  logic             axi_w_ready_i,
    input  logic             axi_b_valid_i,
    input  axi_id_t          axi_b_id_i,
    input  resp_t            axi_b_resp_i,
    input  axi_user_t        axi_b_user_i,
    output logic             axi_b_ready_o,
    output logic             axi_ar_valid_o,
    output axi_id_t          axi_ar_id_o,
    output axi_addr_t        axi_ar_addr_o,
    output len_t             axi_ar_len_o,
    output size_t            axi_ar_size_o,
    output burst_t           axi_ar_burst_o,
    output logic             axi_ar_lock_o,
    output cache_t           axi_ar_cache_o,
    output prot_t            axi_ar_prot_o,
    output qos_t             axi_ar_qos_o,
    output region_t          axi_ar_region_o,
    output axi_user_t        axi_ar_user_o,
    input  logic             axi_ar_ready_i,
    input  logic             axi_r_valid_i,
    input  axi_id_t          axi_r_id_i,
    input  axi_data_t        axi_r_data_i,
    input  resp_t            axi_r_resp_i,
    input  logic             axi_r_last_i,
    input  axi_user_t        axi_r_user_i,
    output logic             axi_r_ready_o
  );

  //////////////////////
  //  Memory Regions  //
  //////////////////////

  localparam NrAXIMasters = 2; // Actually masters, but slaves on the crossbar

  typedef enum int unsigned {
    L2MEM = 0,
    UART  = 1,
    CTRL  = 2
  } axi_slaves_e;
  localparam NrAXISlaves = CTRL + 1;

  // Memory Map
  // 1GByte of DDR (split between two chips on Genesys2)
  localparam logic [63:0] DRAMLength = 64'h40000000;
  localparam logic [63:0] UARTLength = 64'h1000;
  localparam logic [63:0] CTRLLength = 64'h1000;

  typedef enum logic [63:0] {
    DRAMBase = 64'h8000_0000,
    UARTBase = 64'hC000_0000,
    CTRLBase = 64'hD000_0000
  } soc_bus_start_e;

  ///////////
  //  AXI  //
  ///////////

  `include "axi/assign.svh"
  `include "axi/typedef.svh"

  // Ariane's AXI port data width
  localparam AxiNarrowDataWidth = 64;
  localparam AxiNarrowStrbWidth = AxiNarrowDataWidth / 8;
  // Ara's AXI port data width
  localparam AxiWideDataWidth   = AxiDataWidth;
  localparam AXiWideStrbWidth   = AxiWideDataWidth / 8;

  localparam AxiSocIdWidth  = AxiIdWidth - $clog2(NrAXIMasters);
  localparam AxiCoreIdWidth = AxiSocIdWidth - 1;

  // AXI Typedefs

  // These are used for ara_soc's AXI interface
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, axi_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(axi_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_resp_t, b_chan_t, r_chan_t)

  // Internal types
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowStrbWidth-1:0] axi_narrow_strb_t;
  typedef logic [AxiSocIdWidth-1:0] axi_soc_id_t;
  typedef logic [AxiCoreIdWidth-1:0] axi_core_id_t;

  `AXI_TYPEDEF_W_CHAN_T(axi_wide_w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(axi_narrow_w_chan_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)

  `AXI_TYPEDEF_AR_CHAN_T(axi_soc_ar_chan_t, axi_addr_t, axi_soc_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_soc_wide_r_chan_t, axi_data_t, axi_soc_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_soc_narrow_r_chan_t, axi_narrow_data_t, axi_soc_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(axi_soc_aw_chan_t, axi_addr_t, axi_soc_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(axi_soc_b_chan_t, axi_soc_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(axi_soc_wide_req_t, axi_soc_aw_chan_t, axi_wide_w_chan_t, axi_soc_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_soc_wide_resp_t, axi_soc_b_chan_t, axi_soc_wide_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_soc_narrow_req_t, axi_soc_aw_chan_t, axi_narrow_w_chan_t,
    axi_soc_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_soc_narrow_resp_t, axi_soc_b_chan_t, axi_soc_narrow_r_chan_t)

  `AXI_TYPEDEF_AR_CHAN_T(axi_core_ar_chan_t, axi_addr_t, axi_core_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_core_wide_r_chan_t, axi_data_t, axi_core_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_core_narrow_r_chan_t, axi_narrow_data_t, axi_core_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(axi_core_aw_chan_t, axi_addr_t, axi_core_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(axi_core_b_chan_t, axi_core_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(axi_core_wide_req_t, axi_core_aw_chan_t, axi_wide_w_chan_t, axi_core_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_core_wide_resp_t, axi_core_b_chan_t, axi_core_wide_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_core_narrow_req_t, axi_core_aw_chan_t, axi_narrow_w_chan_t,
    axi_core_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_core_narrow_resp_t, axi_core_b_chan_t, axi_core_narrow_r_chan_t)

  `AXI_LITE_TYPEDEF_AW_CHAN_T(axi_lite_soc_narrow_aw_t, axi_addr_t)
  `AXI_LITE_TYPEDEF_W_CHAN_T(axi_lite_soc_narrow_w_t, axi_narrow_data_t, axi_narrow_strb_t)
  `AXI_LITE_TYPEDEF_B_CHAN_T(axi_lite_soc_narrow_b_t)
  `AXI_LITE_TYPEDEF_AR_CHAN_T(axi_lite_soc_narrow_ar_t, axi_addr_t)
  `AXI_LITE_TYPEDEF_R_CHAN_T(axi_lite_soc_narrow_r_t, axi_narrow_data_t)
  `AXI_LITE_TYPEDEF_REQ_T(axi_lite_soc_narrow_req_t, axi_lite_soc_narrow_aw_t,
    axi_lite_soc_narrow_w_t, axi_lite_soc_narrow_ar_t)
  `AXI_LITE_TYPEDEF_RESP_T(axi_lite_soc_narrow_resp_t, axi_lite_soc_narrow_b_t,
    axi_lite_soc_narrow_r_t)

  // Buses
  axi_core_narrow_req_t  ariane_narrow_axi_req;
  axi_core_narrow_resp_t ariane_narrow_axi_resp;
  axi_core_wide_req_t    ariane_axi_req;
  axi_core_wide_resp_t   ariane_axi_resp;
  axi_core_wide_req_t    ara_axi_req;
  axi_core_wide_resp_t   ara_axi_resp;
  axi_core_wide_req_t    ara_axi_req_inval;
  axi_core_wide_resp_t   ara_axi_resp_inval;

  axi_soc_wide_req_t    [NrAXISlaves-1:0] periph_wide_axi_req;
  axi_soc_wide_resp_t   [NrAXISlaves-1:0] periph_wide_axi_resp;
  axi_soc_narrow_req_t  [NrAXISlaves-1:0] periph_narrow_axi_req;
  axi_soc_narrow_resp_t [NrAXISlaves-1:0] periph_narrow_axi_resp;

  ////////////////
  //  Crossbar  //
  ////////////////

  localparam axi_pkg::xbar_cfg_t XBarCfg = '{
    NoSlvPorts        : NrAXIMasters,
    NoMstPorts        : NrAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    PipelineStages    : 0,
    AxiIdWidthSlvPorts: AxiCoreIdWidth,
    AxiIdUsedSlvPorts : AxiCoreIdWidth,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiWideDataWidth,
    NoAddrRules       : NrAXISlaves
  };

  axi_pkg::xbar_rule_64_t [NrAXISlaves-1:0] routing_rules;
  assign routing_rules = '{
    '{idx: CTRL, start_addr: CTRLBase, end_addr: CTRLBase + CTRLLength},
    '{idx: UART, start_addr: UARTBase, end_addr: UARTBase + UARTLength},
    '{idx: L2MEM, start_addr: DRAMBase, end_addr: DRAMBase + DRAMLength}
  };

  axi_xbar #(
    .Cfg          (XBarCfg                ),
    .slv_aw_chan_t(axi_core_aw_chan_t     ),
    .mst_aw_chan_t(axi_soc_aw_chan_t      ),
    .w_chan_t     (axi_wide_w_chan_t      ),
    .slv_b_chan_t (axi_core_b_chan_t      ),
    .mst_b_chan_t (axi_soc_b_chan_t       ),
    .slv_ar_chan_t(axi_core_ar_chan_t     ),
    .mst_ar_chan_t(axi_soc_ar_chan_t      ),
    .slv_r_chan_t (axi_core_wide_r_chan_t ),
    .mst_r_chan_t (axi_soc_wide_r_chan_t  ),
    .slv_req_t    (axi_core_wide_req_t    ),
    .slv_resp_t   (axi_core_wide_resp_t   ),
    .mst_req_t    (axi_soc_wide_req_t     ),
    .mst_resp_t   (axi_soc_wide_resp_t    ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_soc_xbar (
    .clk_i                (clk_i                                ),
    .rst_ni               (rst_ni                               ),
    .test_i               (1'b0                                 ),
    .slv_ports_req_i      ({ariane_axi_req, ara_axi_req_inval}  ),
    .slv_ports_resp_o     ({ariane_axi_resp, ara_axi_resp_inval}),
    .mst_ports_req_o      (periph_wide_axi_req                  ),
    .mst_ports_resp_i     (periph_wide_axi_resp                 ),
    .addr_map_i           (routing_rules                        ),
    .en_default_mst_port_i('0                                   ),
    .default_mst_port_i   ('0                                   )
  );

  //////////
  //  L2  //
  //////////

  // The L2 memory does not support atomics

  axi_soc_wide_req_t  l2mem_wide_axi_req_wo_atomics;
  axi_soc_wide_resp_t l2mem_wide_axi_resp_wo_atomics;
  axi_atop_filter #(
    .AxiIdWidth     (AxiSocIdWidth      ),
    .AxiMaxWriteTxns(4                  ),
    .req_t          (axi_soc_wide_req_t ),
    .resp_t         (axi_soc_wide_resp_t)
  ) i_l2mem_atop_filter (
    .clk_i     (clk_i                         ),
    .rst_ni    (rst_ni                        ),
    .slv_req_i (periph_wide_axi_req[L2MEM]    ),
    .slv_resp_o(periph_wide_axi_resp[L2MEM]   ),
    .mst_req_o (l2mem_wide_axi_req_wo_atomics ),
    .mst_resp_i(l2mem_wide_axi_resp_wo_atomics)
  );

  // AXI interface with the DRAM
  axi_req_t  dram_wide_axi_req;
  axi_resp_t dram_wide_axi_resp;

  axi_llc_top #(
    .SetAssociativity (8                         ),
    .NumLines         (64                        ),
    .NumBlocks        (8                         ),
    .AxiIdWidth       (AxiSocIdWidth             ),
    .AxiAddrWidth     (AxiAddrWidth              ),
    .AxiDataWidth     (AxiWideDataWidth          ),
    .AxiUserWidth     (AxiUserWidth              ),
    .AxiLiteAddrWidth (AxiAddrWidth              ),
    .AxiLiteDataWidth (AxiNarrowDataWidth        ),
    .slv_req_t        (axi_soc_wide_req_t        ),
    .slv_resp_t       (axi_soc_wide_resp_t       ),
    .mst_req_t        (axi_req_t                 ),
    .mst_resp_t       (axi_resp_t                ),
    .lite_req_t       (axi_lite_soc_narrow_req_t ),
    .lite_resp_t      (axi_lite_soc_narrow_resp_t),
    .rule_full_t      (axi_pkg::xbar_rule_64_t   ),
    .axi_addr_t       (axi_addr_t                )
  ) i_l2 (
    .clk_i               (clk_i                         ),
    .rst_ni              (rst_ni                        ),
    .test_i              (1'b0                          ),
    .slv_req_i           (l2mem_wide_axi_req_wo_atomics ),
    .slv_resp_o          (l2mem_wide_axi_resp_wo_atomics),
    .mst_req_o           (dram_wide_axi_req             ),
    .mst_resp_i          (dram_wide_axi_resp            ),
    .conf_req_i          ('0                            ),
    .conf_resp_o         (/* Unused */                  ),
    .cached_start_addr_i (DRAMBase                      ),
    .cached_end_addr_i   (DRAMBase + DRAMLength         ),
    .spm_start_addr_i    ('0                            ),
    .axi_llc_events_o    (/* Unused */                  )
  );

  axi_req_t  dram_wide_axi_req_cut;
  axi_resp_t dram_wide_axi_resp_cut;

  axi_cut #(
    .ar_chan_t(ar_chan_t ),
    .r_chan_t (r_chan_t  ),
    .aw_chan_t(aw_chan_t ),
    .w_chan_t (w_chan_t  ),
    .b_chan_t (b_chan_t  ),
    .req_t    (axi_req_t ),
    .resp_t   (axi_resp_t)
  ) i_dram_axi_cut (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
    .slv_req_i (dram_wide_axi_req     ),
    .slv_resp_o(dram_wide_axi_resp    ),
    .mst_req_o (dram_wide_axi_req_cut ),
    .mst_resp_i(dram_wide_axi_resp_cut)
  );

  assign axi_aw_valid_o                  = dram_wide_axi_req_cut.aw_valid;
  assign axi_aw_id_o                     = dram_wide_axi_req_cut.aw.id;
  assign axi_aw_addr_o                   = dram_wide_axi_req_cut.aw.addr;
  assign axi_aw_len_o                    = dram_wide_axi_req_cut.aw.len;
  assign axi_aw_size_o                   = dram_wide_axi_req_cut.aw.size;
  assign axi_aw_burst_o                  = dram_wide_axi_req_cut.aw.burst;
  assign axi_aw_lock_o                   = dram_wide_axi_req_cut.aw.lock;
  assign axi_aw_cache_o                  = dram_wide_axi_req_cut.aw.cache;
  assign axi_aw_prot_o                   = dram_wide_axi_req_cut.aw.prot;
  assign axi_aw_qos_o                    = dram_wide_axi_req_cut.aw.qos;
  assign axi_aw_region_o                 = dram_wide_axi_req_cut.aw.region;
  assign axi_aw_atop_o                   = dram_wide_axi_req_cut.aw.atop;
  assign axi_aw_user_o                   = dram_wide_axi_req_cut.aw.user;
  assign dram_wide_axi_resp_cut.aw_ready = axi_aw_ready_i;
  assign axi_w_valid_o                   = dram_wide_axi_req_cut.w_valid;
  assign axi_w_data_o                    = dram_wide_axi_req_cut.w.data;
  assign axi_w_strb_o                    = dram_wide_axi_req_cut.w.strb;
  assign axi_w_last_o                    = dram_wide_axi_req_cut.w.last;
  assign axi_w_user_o                    = dram_wide_axi_req_cut.w.user;
  assign dram_wide_axi_resp_cut.w_ready  = axi_w_ready_i;
  assign dram_wide_axi_resp_cut.b_valid  = axi_b_valid_i;
  assign dram_wide_axi_resp_cut.b.id     = axi_b_id_i;
  assign dram_wide_axi_resp_cut.b.resp   = axi_b_resp_i;
  assign dram_wide_axi_resp_cut.b.user   = axi_b_user_i;
  assign axi_b_ready_o                   = dram_wide_axi_req_cut.b_ready;
  assign axi_ar_valid_o                  = dram_wide_axi_req_cut.ar_valid;
  assign axi_ar_id_o                     = dram_wide_axi_req_cut.ar.id;
  assign axi_ar_addr_o                   = dram_wide_axi_req_cut.ar.addr;
  assign axi_ar_len_o                    = dram_wide_axi_req_cut.ar.len;
  assign axi_ar_size_o                   = dram_wide_axi_req_cut.ar.size;
  assign axi_ar_burst_o                  = dram_wide_axi_req_cut.ar.burst;
  assign axi_ar_lock_o                   = dram_wide_axi_req_cut.ar.lock;
  assign axi_ar_cache_o                  = dram_wide_axi_req_cut.ar.cache;
  assign axi_ar_prot_o                   = dram_wide_axi_req_cut.ar.prot;
  assign axi_ar_qos_o                    = dram_wide_axi_req_cut.ar.qos;
  assign axi_ar_region_o                 = dram_wide_axi_req_cut.ar.region;
  assign axi_ar_user_o                   = dram_wide_axi_req_cut.ar.user;
  assign dram_wide_axi_resp_cut.ar_ready = axi_ar_ready_i;
  assign dram_wide_axi_resp_cut.r_valid  = axi_r_valid_i;
  assign dram_wide_axi_resp_cut.r.data   = axi_r_data_i;
  assign dram_wide_axi_resp_cut.r.id     = axi_r_id_i;
  assign dram_wide_axi_resp_cut.r.last   = axi_r_last_i;
  assign dram_wide_axi_resp_cut.r.resp   = axi_r_resp_i;
  assign dram_wide_axi_resp_cut.r.user   = axi_r_user_i;
  assign axi_r_ready_o                   = dram_wide_axi_req_cut.r_ready;

  ////////////
  //  UART  //
  ////////////

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH(AxiAddrWidth      ),
    .AXI4_RDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_WDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_ID_WIDTH     (AxiSocIdWidth     ),
    .AXI4_USER_WIDTH   (AxiUserWidth      ),
    .BUFF_DEPTH_SLAVE  (2                 ),
    .APB_ADDR_WIDTH    (32                )
  ) i_axi2apb_64_32_uart (
    .ACLK      (clk_i                                ),
    .ARESETn   (rst_ni                               ),
    .test_en_i (1'b0                                 ),
    .AWID_i    (periph_narrow_axi_req[UART].aw.id    ),
    .AWADDR_i  (periph_narrow_axi_req[UART].aw.addr  ),
    .AWLEN_i   (periph_narrow_axi_req[UART].aw.len   ),
    .AWSIZE_i  (periph_narrow_axi_req[UART].aw.size  ),
    .AWBURST_i (periph_narrow_axi_req[UART].aw.burst ),
    .AWLOCK_i  (periph_narrow_axi_req[UART].aw.lock  ),
    .AWCACHE_i (periph_narrow_axi_req[UART].aw.cache ),
    .AWPROT_i  (periph_narrow_axi_req[UART].aw.prot  ),
    .AWREGION_i(periph_narrow_axi_req[UART].aw.region),
    .AWUSER_i  (periph_narrow_axi_req[UART].aw.user  ),
    .AWQOS_i   (periph_narrow_axi_req[UART].aw.qos   ),
    .AWVALID_i (periph_narrow_axi_req[UART].aw_valid ),
    .AWREADY_o (periph_narrow_axi_resp[UART].aw_ready),
    .WDATA_i   (periph_narrow_axi_req[UART].w.data   ),
    .WSTRB_i   (periph_narrow_axi_req[UART].w.strb   ),
    .WLAST_i   (periph_narrow_axi_req[UART].w.last   ),
    .WUSER_i   (periph_narrow_axi_req[UART].w.user   ),
    .WVALID_i  (periph_narrow_axi_req[UART].w_valid  ),
    .WREADY_o  (periph_narrow_axi_resp[UART].w_ready ),
    .BID_o     (periph_narrow_axi_resp[UART].b.id    ),
    .BRESP_o   (periph_narrow_axi_resp[UART].b.resp  ),
    .BVALID_o  (periph_narrow_axi_resp[UART].b_valid ),
    .BUSER_o   (periph_narrow_axi_resp[UART].b.user  ),
    .BREADY_i  (periph_narrow_axi_req[UART].b_ready  ),
    .ARID_i    (periph_narrow_axi_req[UART].ar.id    ),
    .ARADDR_i  (periph_narrow_axi_req[UART].ar.addr  ),
    .ARLEN_i   (periph_narrow_axi_req[UART].ar.len   ),
    .ARSIZE_i  (periph_narrow_axi_req[UART].ar.size  ),
    .ARBURST_i (periph_narrow_axi_req[UART].ar.burst ),
    .ARLOCK_i  (periph_narrow_axi_req[UART].ar.lock  ),
    .ARCACHE_i (periph_narrow_axi_req[UART].ar.cache ),
    .ARPROT_i  (periph_narrow_axi_req[UART].ar.prot  ),
    .ARREGION_i(periph_narrow_axi_req[UART].ar.region),
    .ARUSER_i  (periph_narrow_axi_req[UART].ar.user  ),
    .ARQOS_i   (periph_narrow_axi_req[UART].ar.qos   ),
    .ARVALID_i (periph_narrow_axi_req[UART].ar_valid ),
    .ARREADY_o (periph_narrow_axi_resp[UART].ar_ready),
    .RID_o     (periph_narrow_axi_resp[UART].r.id    ),
    .RDATA_o   (periph_narrow_axi_resp[UART].r.data  ),
    .RRESP_o   (periph_narrow_axi_resp[UART].r.resp  ),
    .RLAST_o   (periph_narrow_axi_resp[UART].r.last  ),
    .RUSER_o   (periph_narrow_axi_resp[UART].r.user  ),
    .RVALID_o  (periph_narrow_axi_resp[UART].r_valid ),
    .RREADY_i  (periph_narrow_axi_req[UART].r_ready  ),
    .PENABLE   (uart_penable_o                       ),
    .PWRITE    (uart_pwrite_o                        ),
    .PADDR     (uart_paddr_o                         ),
    .PSEL      (uart_psel_o                          ),
    .PWDATA    (uart_pwdata_o                        ),
    .PRDATA    (uart_prdata_i                        ),
    .PREADY    (uart_pready_i                        ),
    .PSLVERR   (uart_pslverr_i                       )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth       ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth     ),
    .AxiAddrWidth       (AxiAddrWidth           ),
    .AxiIdWidth         (AxiSocIdWidth          ),
    .AxiMaxReads        (2                      ),
    .ar_chan_t          (axi_soc_ar_chan_t      ),
    .mst_r_chan_t       (axi_soc_narrow_r_chan_t),
    .slv_r_chan_t       (axi_soc_wide_r_chan_t  ),
    .aw_chan_t          (axi_soc_aw_chan_t      ),
    .b_chan_t           (axi_soc_b_chan_t       ),
    .mst_w_chan_t       (axi_narrow_w_chan_t    ),
    .slv_w_chan_t       (axi_wide_w_chan_t      ),
    .axi_mst_req_t      (axi_soc_narrow_req_t   ),
    .axi_mst_resp_t     (axi_soc_narrow_resp_t  ),
    .axi_slv_req_t      (axi_soc_wide_req_t     ),
    .axi_slv_resp_t     (axi_soc_wide_resp_t    )
  ) i_axi_slave_uart_dwc (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_wide_axi_req[UART]   ),
    .slv_resp_o(periph_wide_axi_resp[UART]  ),
    .mst_req_o (periph_narrow_axi_req[UART] ),
    .mst_resp_i(periph_narrow_axi_resp[UART])
  );

  /////////////////////////
  //  Control registers  //
  /////////////////////////

  axi_lite_soc_narrow_req_t  axi_lite_ctrl_registers_req;
  axi_lite_soc_narrow_resp_t axi_lite_ctrl_registers_resp;

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth              ),
    .AxiDataWidth   (AxiNarrowDataWidth        ),
    .AxiIdWidth     (AxiSocIdWidth             ),
    .AxiUserWidth   (AxiUserWidth              ),
    .AxiMaxReadTxns (1                         ),
    .AxiMaxWriteTxns(1                         ),
    .FallThrough    (1'b0                      ),
    .full_req_t     (axi_soc_narrow_req_t      ),
    .full_resp_t    (axi_soc_narrow_resp_t     ),
    .lite_req_t     (axi_lite_soc_narrow_req_t ),
    .lite_resp_t    (axi_lite_soc_narrow_resp_t)
  ) i_axi_to_axi_lite (
    .clk_i     (clk_i                        ),
    .rst_ni    (rst_ni                       ),
    .test_i    (1'b0                         ),
    .slv_req_i (periph_narrow_axi_req[CTRL]  ),
    .slv_resp_o(periph_narrow_axi_resp[CTRL] ),
    .mst_req_o (axi_lite_ctrl_registers_req  ),
    .mst_resp_i(axi_lite_ctrl_registers_resp )
  );

  ctrl_registers #(
    .DRAMBaseAddr   (DRAMBase                  ),
    .DRAMLength     (DRAMLength                ),
    .DataWidth      (AxiNarrowDataWidth        ),
    .AddrWidth      (AxiAddrWidth              ),
    .axi_lite_req_t (axi_lite_soc_narrow_req_t ),
    .axi_lite_resp_t(axi_lite_soc_narrow_resp_t)
  ) i_ctrl_registers (
    .clk_i                (clk_i                       ),
    .rst_ni               (rst_ni                      ),
    .axi_lite_slave_req_i (axi_lite_ctrl_registers_req ),
    .axi_lite_slave_resp_o(axi_lite_ctrl_registers_resp),
    .dram_base_addr_o     (/* Unused */                ),
    .dram_end_addr_o      (/* Unused */                ),
    .exit_o               (exit_o                      )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth       ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth     ),
    .AxiAddrWidth       (AxiAddrWidth           ),
    .AxiIdWidth         (AxiSocIdWidth          ),
    .AxiMaxReads        (2                      ),
    .ar_chan_t          (axi_soc_ar_chan_t      ),
    .mst_r_chan_t       (axi_soc_narrow_r_chan_t),
    .slv_r_chan_t       (axi_soc_wide_r_chan_t  ),
    .aw_chan_t          (axi_soc_aw_chan_t      ),
    .b_chan_t           (axi_soc_b_chan_t       ),
    .mst_w_chan_t       (axi_narrow_w_chan_t    ),
    .slv_w_chan_t       (axi_wide_w_chan_t      ),
    .axi_mst_req_t      (axi_soc_narrow_req_t   ),
    .axi_mst_resp_t     (axi_soc_narrow_resp_t  ),
    .axi_slv_req_t      (axi_soc_wide_req_t     ),
    .axi_slv_resp_t     (axi_soc_wide_resp_t    )
  ) i_axi_slave_ctrl_dwc (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_wide_axi_req[CTRL]   ),
    .slv_resp_o(periph_wide_axi_resp[CTRL]  ),
    .mst_req_o (periph_narrow_axi_req[CTRL] ),
    .mst_resp_i(periph_narrow_axi_resp[CTRL])
  );

  //////////////////////
  //  Ara and Ariane  //
  //////////////////////

  import ariane_pkg::accelerator_req_t;
  import ariane_pkg::accelerator_resp_t;

  localparam ariane_pkg::ariane_cfg_t ArianeAraConfig = '{
    RASDepth             : 2,
    BTBEntries           : 32,
    BHTEntries           : 128,
    // idempotent region
    NrNonIdempotentRules : 2,
    NonIdempotentAddrBase: {64'b0, 64'b0},
    NonIdempotentLength  : {64'b0, 64'b0},
    NrExecuteRegionRules : 3,
    //                      DRAM,       Boot ROM,   Debug Module
    ExecuteRegionAddrBase: {DRAMBase, 64'h1_0000, 64'h0},
    ExecuteRegionLength  : {DRAMLength, 64'h10000, 64'h1000},
    // cached region
    NrCachedRegionRules  : 1,
    CachedRegionAddrBase : {DRAMBase},
    CachedRegionLength   : {DRAMLength},
    //  cache config
    Axi64BitCompliant    : 1'b1,
    SwapEndianess        : 1'b0,
    // debug
    DmBaseAddress        : 64'h0,
    NrPMPEntries         : 0
  };

  // Accelerator ports
  accelerator_req_t                     acc_req;
  logic                                 acc_req_valid;
  logic                                 acc_req_ready;
  accelerator_resp_t                    acc_resp;
  logic                                 acc_resp_valid;
  logic                                 acc_resp_ready;
  logic                                 acc_cons_en;
  logic              [AxiAddrWidth-1:0] inval_addr;
  logic                                 inval_valid;
  logic                                 inval_ready;

  ariane #(
    .ArianeCfg(ArianeAraConfig)
  ) i_ariane (
    .clk_i            (clk_i                 ),
    .rst_ni           (rst_ni                ),
    .boot_addr_i      (DRAMBase              ), // start fetching from DRAM
    .hart_id_i        ('0                    ),
    .irq_i            ('0                    ),
    .ipi_i            ('0                    ),
    .time_irq_i       ('0                    ),
    .debug_req_i      ('0                    ),
    .axi_req_o        (ariane_narrow_axi_req ),
    .axi_resp_i       (ariane_narrow_axi_resp),
    // Accelerator ports
    .acc_req_o        (acc_req               ),
    .acc_req_valid_o  (acc_req_valid         ),
    .acc_req_ready_i  (acc_req_ready         ),
    .acc_resp_i       (acc_resp              ),
    .acc_resp_valid_i (acc_resp_valid        ),
    .acc_resp_ready_o (acc_resp_ready        ),
    .acc_cons_en_o    (acc_cons_en           ),
    .inval_addr_i     (inval_addr            ),
    .inval_valid_i    (inval_valid           ),
    .inval_ready_o    (inval_ready           )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiNarrowDataWidth      ),
    .AxiMstPortDataWidth(AxiWideDataWidth        ),
    .AxiAddrWidth       (AxiAddrWidth            ),
    .AxiIdWidth         (AxiCoreIdWidth          ),
    .AxiMaxReads        (4                       ),
    .ar_chan_t          (axi_core_ar_chan_t      ),
    .mst_r_chan_t       (axi_core_wide_r_chan_t  ),
    .slv_r_chan_t       (axi_core_narrow_r_chan_t),
    .aw_chan_t          (axi_core_aw_chan_t      ),
    .b_chan_t           (axi_core_b_chan_t       ),
    .mst_w_chan_t       (axi_wide_w_chan_t       ),
    .slv_w_chan_t       (axi_narrow_w_chan_t     ),
    .axi_mst_req_t      (axi_core_wide_req_t     ),
    .axi_mst_resp_t     (axi_core_wide_resp_t    ),
    .axi_slv_req_t      (axi_core_narrow_req_t   ),
    .axi_slv_resp_t     (axi_core_narrow_resp_t  )
  ) i_ariane_axi_dwc (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
    .slv_req_i (ariane_narrow_axi_req ),
    .slv_resp_o(ariane_narrow_axi_resp),
    .mst_req_o (ariane_axi_req        ),
    .mst_resp_i(ariane_axi_resp       )
  );

  axi_inval_filter #(
    .MaxTxns    (4                   ),
    .AddrWidth  (AxiAddrWidth        ),
    .L1LineWidth(16                  ),
    .aw_chan_t  (axi_core_aw_chan_t  ),
    .req_t      (axi_core_wide_req_t ),
    .resp_t     (axi_core_wide_resp_t)
  ) i_axi_inval_filter (
    .clk_i        (clk_i             ),
    .rst_ni       (rst_ni            ),
    .en_i         (acc_cons_en       ),
    .slv_req_i    (ara_axi_req       ),
    .slv_resp_o   (ara_axi_resp      ),
    .mst_req_o    (ara_axi_req_inval ),
    .mst_resp_i   (ara_axi_resp_inval),
    .inval_addr_o (inval_addr        ),
    .inval_valid_o(inval_valid       ),
    .inval_ready_i(inval_ready       )
  );

  ara #(
    .NrLanes     (NrLanes               ),
    .FPUSupport  (FPUSupport            ),
    .AxiDataWidth(AxiWideDataWidth      ),
    .AxiAddrWidth(AxiAddrWidth          ),
    .axi_ar_t    (axi_core_ar_chan_t    ),
    .axi_r_t     (axi_core_wide_r_chan_t),
    .axi_aw_t    (axi_core_aw_chan_t    ),
    .axi_w_t     (axi_wide_w_chan_t     ),
    .axi_b_t     (axi_core_b_chan_t     ),
    .axi_req_t   (axi_core_wide_req_t   ),
    .axi_resp_t  (axi_core_wide_resp_t  )
  ) i_ara (
    .clk_i           (clk_i         ),
    .rst_ni          (rst_ni        ),
    .scan_enable_i   (scan_enable_i ),
    .scan_data_i     (1'b0          ),
    .scan_data_o     (/* Unused */  ),
    .acc_req_i       (acc_req       ),
    .acc_req_valid_i (acc_req_valid ),
    .acc_req_ready_o (acc_req_ready ),
    .acc_resp_o      (acc_resp      ),
    .acc_resp_valid_o(acc_resp_valid),
    .acc_resp_ready_i(acc_resp_ready),
    .axi_req_o       (ara_axi_req   ),
    .axi_resp_i      (ara_axi_resp  )
  );

  //////////////////
  //  Assertions  //
  //////////////////

  if (NrLanes == 0)
    $error("[ara_soc] Ara needs to have at least one lane.");

  if (AxiDataWidth == 0)
    $error("[ara_soc] The AXI data width must be greater than zero.");

  if (AxiAddrWidth == 0)
    $error("[ara_soc] The AXI address width must be greater than zero.");

  if (AxiUserWidth == 0)
    $error("[ara_soc] The AXI user width must be greater than zero.");

  if (AxiIdWidth == 0)
    $error("[ara_soc] The AXI ID width must be greater than zero.");

endmodule : ara_soc
