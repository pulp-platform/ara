// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's SoC, containing Ariane, Ara, and a L2 cache.

module ara_soc import axi_pkg::*; import ara_pkg::*; #(
    // RVV Parameters
    parameter  int           unsigned NrLanes      = 0,                          // Number of parallel vector lanes.
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport   = FPUSupportHalfSingleDouble,
    // External support for vfrec7, vfrsqrt7
    parameter  fpext_support_e        FPExtSupport = FPExtSupportEnable,
    // Support for fixed-point data types
    parameter  fixpt_support_e        FixPtSupport = FixedPointEnable,
    // AXI Interface
    parameter  int           unsigned AxiDataWidth = 32*NrLanes,
    parameter  int           unsigned AxiAddrWidth = 64,
    parameter  int           unsigned AxiUserWidth = 1,
    parameter  int           unsigned AxiIdWidth   = 5,
    // AXI Resp Delay [ps] for gate-level simulation
    parameter  int           unsigned AxiRespDelay = 200,
    // Main memory
    parameter  int           unsigned L2NumWords   = 2**20,
    // Dependant parameters. DO NOT CHANGE!
    localparam type                   axi_data_t   = logic [AxiDataWidth-1:0],
    localparam type                   axi_strb_t   = logic [AxiDataWidth/8-1:0],
    localparam type                   axi_addr_t   = logic [AxiAddrWidth-1:0],
    localparam type                   axi_user_t   = logic [AxiUserWidth-1:0],
    localparam type                   axi_id_t     = logic [AxiIdWidth-1:0]
  ) (
    input  logic        clk_i,
    input  logic        rst_ni,
    output logic [63:0] exit_o,
    output logic [63:0] hw_cnt_en_o,
    // Scan chain
    input  logic        scan_enable_i,
    input  logic        scan_data_i,
    output logic        scan_data_o,
    // UART APB interface
    output logic        uart_penable_o,
    output logic        uart_pwrite_o,
    output logic [31:0] uart_paddr_o,
    output logic        uart_psel_o,
    output logic [31:0] uart_pwdata_o,
    input  logic [31:0] uart_prdata_i,
    input  logic        uart_pready_i,
    input  logic        uart_pslverr_i
  );

  `include "axi/assign.svh"
  `include "axi/typedef.svh"
  `include "common_cells/registers.svh"
  `include "apb/typedef.svh"

  //////////////////////
  //  Memory Regions  //
  //////////////////////

  localparam NrAXIMasters = 1; // Actually masters, but slaves on the crossbar

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

  // Ariane's AXI port data width
  localparam AxiNarrowDataWidth = 64;
  localparam AxiNarrowStrbWidth = AxiNarrowDataWidth / 8;
  // Ara's AXI port data width
  localparam AxiWideDataWidth   = AxiDataWidth;
  localparam AXiWideStrbWidth   = AxiWideDataWidth / 8;

  localparam AxiSocIdWidth  = AxiIdWidth - $clog2(NrAXIMasters);
  localparam AxiCoreIdWidth = AxiSocIdWidth - 1;

  // Internal types
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowStrbWidth-1:0] axi_narrow_strb_t;
  typedef logic [AxiSocIdWidth-1:0] axi_soc_id_t;
  typedef logic [AxiCoreIdWidth-1:0] axi_core_id_t;

  // AXI Typedefs
  `AXI_TYPEDEF_ALL(system, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(ara_axi, axi_addr_t, axi_core_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(ariane_axi, axi_addr_t, axi_core_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  `AXI_TYPEDEF_ALL(soc_narrow, axi_addr_t, axi_soc_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  `AXI_TYPEDEF_ALL(soc_wide, axi_addr_t, axi_soc_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(soc_narrow_lite, axi_addr_t, axi_narrow_data_t, axi_narrow_strb_t)

  // Buses
  system_req_t  system_axi_req_spill;
  system_resp_t system_axi_resp_spill;
  system_resp_t system_axi_resp_spill_del;
  system_req_t  system_axi_req;
  system_resp_t system_axi_resp;

  soc_wide_req_t    [NrAXISlaves-1:0] periph_wide_axi_req;
  soc_wide_resp_t   [NrAXISlaves-1:0] periph_wide_axi_resp;
  soc_narrow_req_t  [NrAXISlaves-1:0] periph_narrow_axi_req;
  soc_narrow_resp_t [NrAXISlaves-1:0] periph_narrow_axi_resp;

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
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
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
    .slv_aw_chan_t(system_aw_chan_t       ),
    .mst_aw_chan_t(soc_wide_aw_chan_t     ),
    .w_chan_t     (system_w_chan_t        ),
    .slv_b_chan_t (system_b_chan_t        ),
    .mst_b_chan_t (soc_wide_b_chan_t      ),
    .slv_ar_chan_t(system_ar_chan_t       ),
    .mst_ar_chan_t(soc_wide_ar_chan_t     ),
    .slv_r_chan_t (system_r_chan_t        ),
    .mst_r_chan_t (soc_wide_r_chan_t      ),
    .slv_req_t    (system_req_t           ),
    .slv_resp_t   (system_resp_t          ),
    .mst_req_t    (soc_wide_req_t         ),
    .mst_resp_t   (soc_wide_resp_t        ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_soc_xbar (
    .clk_i                (clk_i               ),
    .rst_ni               (rst_ni              ),
    .test_i               (1'b0                ),
    .slv_ports_req_i      (system_axi_req      ),
    .slv_ports_resp_o     (system_axi_resp     ),
    .mst_ports_req_o      (periph_wide_axi_req ),
    .mst_ports_resp_i     (periph_wide_axi_resp),
    .addr_map_i           (routing_rules       ),
    .en_default_mst_port_i('0                  ),
    .default_mst_port_i   ('0                  )
  );

  //////////
  //  L2  //
  //////////

  // The L2 memory does not support atomics

  soc_wide_req_t  l2mem_wide_axi_req_wo_atomics;
  soc_wide_resp_t l2mem_wide_axi_resp_wo_atomics;
  axi_atop_filter #(
    .AxiIdWidth     (AxiSocIdWidth  ),
    .AxiMaxWriteTxns(4              ),
    .req_t          (soc_wide_req_t ),
    .resp_t         (soc_wide_resp_t)
  ) i_l2mem_atop_filter (
    .clk_i     (clk_i                         ),
    .rst_ni    (rst_ni                        ),
    .slv_req_i (periph_wide_axi_req[L2MEM]    ),
    .slv_resp_o(periph_wide_axi_resp[L2MEM]   ),
    .mst_req_o (l2mem_wide_axi_req_wo_atomics ),
    .mst_resp_i(l2mem_wide_axi_resp_wo_atomics)
  );

  logic                      l2_req;
  logic                      l2_we;
  logic [AxiAddrWidth-1:0]   l2_addr;
  logic [AxiDataWidth/8-1:0] l2_be;
  logic [AxiDataWidth-1:0]   l2_wdata;
  logic [AxiDataWidth-1:0]   l2_rdata;
  logic                      l2_rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth   ),
    .DataWidth (AxiDataWidth   ),
    .IdWidth   (AxiSocIdWidth  ),
    .NumBanks  (1              ),
    .axi_req_t (soc_wide_req_t ),
    .axi_resp_t(soc_wide_resp_t)
  ) i_axi_to_mem (
    .clk_i       (clk_i                         ),
    .rst_ni      (rst_ni                        ),
    .axi_req_i   (l2mem_wide_axi_req_wo_atomics ),
    .axi_resp_o  (l2mem_wide_axi_resp_wo_atomics),
    .mem_req_o   (l2_req                        ),
    .mem_gnt_i   (l2_req                        ), // Always available
    .mem_we_o    (l2_we                         ),
    .mem_addr_o  (l2_addr                       ),
    .mem_strb_o  (l2_be                         ),
    .mem_wdata_o (l2_wdata                      ),
    .mem_rdata_i (l2_rdata                      ),
    .mem_rvalid_i(l2_rvalid                     ),
    .mem_atop_o  (/* Unused */                  ),
    .busy_o      (/* Unused */                  )
  );

`ifndef SPYGLASS
  tc_sram #(
    .NumWords (L2NumWords  ),
    .NumPorts (1           ),
    .DataWidth(AxiDataWidth),
    .SimInit("random")
  ) i_dram (
    .clk_i  (clk_i                                                                      ),
    .rst_ni (rst_ni                                                                     ),
    .req_i  (l2_req                                                                     ),
    .we_i   (l2_we                                                                      ),
    .addr_i (l2_addr[$clog2(L2NumWords)-1+$clog2(AxiDataWidth/8):$clog2(AxiDataWidth/8)]),
    .wdata_i(l2_wdata                                                                   ),
    .be_i   (l2_be                                                                      ),
    .rdata_o(l2_rdata                                                                   )
  );
`else
  assign l2_rdata = '0;
`endif

  // One-cycle latency
  `FF(l2_rvalid, l2_req, 1'b0);

  ////////////
  //  UART  //
  ////////////

  `AXI_TYPEDEF_ALL(uart_axi, axi_addr_t, axi_soc_id_t, logic [31:0], logic [3:0], axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(uart_lite, axi_addr_t, logic [31:0], logic [3:0])
  `APB_TYPEDEF_ALL(uart_apb, axi_addr_t, logic [31:0], logic [3:0])

  uart_axi_req_t   uart_axi_req;
  uart_axi_resp_t  uart_axi_resp;
  uart_lite_req_t  uart_lite_req;
  uart_lite_resp_t uart_lite_resp;
  uart_apb_req_t   uart_apb_req;
  uart_apb_resp_t  uart_apb_resp;

  assign uart_penable_o = uart_apb_req.penable;
  assign uart_pwrite_o  = uart_apb_req.pwrite;
  assign uart_paddr_o   = uart_apb_req.paddr;
  assign uart_psel_o    = uart_apb_req.psel;
  assign uart_pwdata_o  = uart_apb_req.pwdata;
  assign uart_apb_resp.prdata  = uart_prdata_i;
  assign uart_apb_resp.pready  = uart_pready_i;
  assign uart_apb_resp.pslverr = uart_pslverr_i;

  typedef struct packed {
    int unsigned idx;
    axi_addr_t   start_addr;
    axi_addr_t   end_addr;
  } uart_apb_rule_t;

  uart_apb_rule_t uart_apb_map = '{idx: 0, start_addr: '0, end_addr: '1};

  axi_lite_to_apb #(
    .NoApbSlaves     (32'd1           ),
    .NoRules         (32'd1           ),
    .AddrWidth       (AxiAddrWidth    ),
    .DataWidth       (32'd32          ),
    .PipelineRequest (1'b0            ),
    .PipelineResponse(1'b0            ),
    .axi_lite_req_t  (uart_lite_req_t ),
    .axi_lite_resp_t (uart_lite_resp_t),
    .apb_req_t       (uart_apb_req_t  ),
    .apb_resp_t      (uart_apb_resp_t ),
    .rule_t          (uart_apb_rule_t )
  ) i_axi_lite_to_apb_uart (
    .clk_i          (clk_i         ),
    .rst_ni         (rst_ni        ),
    .axi_lite_req_i (uart_lite_req ),
    .axi_lite_resp_o(uart_lite_resp),
    .apb_req_o      (uart_apb_req  ),
    .apb_resp_i     (uart_apb_resp ),
    .addr_map_i     (uart_apb_map  )
  );

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth    ),
    .AxiDataWidth   (32'd32          ),
    .AxiIdWidth     (AxiSocIdWidth   ),
    .AxiUserWidth   (AxiUserWidth    ),
    .AxiMaxWriteTxns(32'd1           ),
    .AxiMaxReadTxns (32'd1           ),
    .FallThrough    (1'b1            ),
    .full_req_t     (uart_axi_req_t  ),
    .full_resp_t    (uart_axi_resp_t ),
    .lite_req_t     (uart_lite_req_t ),
    .lite_resp_t    (uart_lite_resp_t)
  ) i_axi_to_axi_lite_uart (
    .clk_i     (clk_i         ),
    .rst_ni    (rst_ni        ),
    .test_i    (1'b0          ),
    .slv_req_i (uart_axi_req  ),
    .slv_resp_o(uart_axi_resp ),
    .mst_req_o (uart_lite_req ),
    .mst_resp_i(uart_lite_resp)
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth  ),
    .AxiMstPortDataWidth(32                ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiSocIdWidth     ),
    .AxiMaxReads        (1                 ),
    .ar_chan_t          (soc_wide_ar_chan_t),
    .mst_r_chan_t       (uart_axi_r_chan_t ),
    .slv_r_chan_t       (soc_wide_r_chan_t ),
    .aw_chan_t          (uart_axi_aw_chan_t),
    .b_chan_t           (soc_wide_b_chan_t ),
    .mst_w_chan_t       (uart_axi_w_chan_t ),
    .slv_w_chan_t       (soc_wide_w_chan_t ),
    .axi_mst_req_t      (uart_axi_req_t    ),
    .axi_mst_resp_t     (uart_axi_resp_t   ),
    .axi_slv_req_t      (soc_wide_req_t    ),
    .axi_slv_resp_t     (soc_wide_resp_t   )
  ) i_axi_slave_uart_dwc (
    .clk_i     (clk_i                     ),
    .rst_ni    (rst_ni                    ),
    .slv_req_i (periph_wide_axi_req[UART] ),
    .slv_resp_o(periph_wide_axi_resp[UART]),
    .mst_req_o (uart_axi_req              ),
    .mst_resp_i(uart_axi_resp             )
  );

  /////////////////////////
  //  Control registers  //
  /////////////////////////

  soc_narrow_lite_req_t  axi_lite_ctrl_registers_req;
  soc_narrow_lite_resp_t axi_lite_ctrl_registers_resp;

  logic [63:0] event_trigger;

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth          ),
    .AxiDataWidth   (AxiNarrowDataWidth    ),
    .AxiIdWidth     (AxiSocIdWidth         ),
    .AxiUserWidth   (AxiUserWidth          ),
    .AxiMaxReadTxns (1                     ),
    .AxiMaxWriteTxns(1                     ),
    .FallThrough    (1'b0                  ),
    .full_req_t     (soc_narrow_req_t      ),
    .full_resp_t    (soc_narrow_resp_t     ),
    .lite_req_t     (soc_narrow_lite_req_t ),
    .lite_resp_t    (soc_narrow_lite_resp_t)
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
    .DRAMBaseAddr   (DRAMBase              ),
    .DRAMLength     (DRAMLength            ),
    .DataWidth      (AxiNarrowDataWidth    ),
    .AddrWidth      (AxiAddrWidth          ),
    .axi_lite_req_t (soc_narrow_lite_req_t ),
    .axi_lite_resp_t(soc_narrow_lite_resp_t)
  ) i_ctrl_registers (
    .clk_i                (clk_i                       ),
    .rst_ni               (rst_ni                      ),
    .axi_lite_slave_req_i (axi_lite_ctrl_registers_req ),
    .axi_lite_slave_resp_o(axi_lite_ctrl_registers_resp),
    .hw_cnt_en_o          (hw_cnt_en_o                 ),
    .dram_base_addr_o     (/* Unused */                ),
    .dram_end_addr_o      (/* Unused */                ),
    .exit_o               (exit_o                      ),
    .event_trigger_o      (event_trigger)
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth    ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth  ),
    .AxiAddrWidth       (AxiAddrWidth        ),
    .AxiIdWidth         (AxiSocIdWidth       ),
    .AxiMaxReads        (2                   ),
    .ar_chan_t          (soc_wide_ar_chan_t  ),
    .mst_r_chan_t       (soc_narrow_r_chan_t ),
    .slv_r_chan_t       (soc_wide_r_chan_t   ),
    .aw_chan_t          (soc_narrow_aw_chan_t),
    .b_chan_t           (soc_narrow_b_chan_t ),
    .mst_w_chan_t       (soc_narrow_w_chan_t ),
    .slv_w_chan_t       (soc_wide_w_chan_t   ),
    .axi_mst_req_t      (soc_narrow_req_t    ),
    .axi_mst_resp_t     (soc_narrow_resp_t   ),
    .axi_slv_req_t      (soc_wide_req_t      ),
    .axi_slv_resp_t     (soc_wide_resp_t     )
  ) i_axi_slave_ctrl_dwc (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_wide_axi_req[CTRL]   ),
    .slv_resp_o(periph_wide_axi_resp[CTRL]  ),
    .mst_req_o (periph_narrow_axi_req[CTRL] ),
    .mst_resp_i(periph_narrow_axi_resp[CTRL])
  );

  //////////////
  //  System  //
  //////////////

  logic [2:0] hart_id;

  assign hart_id = '0;

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
    AxiCompliant         : 1'b1,
    SwapEndianess        : 1'b0,
    // debug
    DmBaseAddress        : 64'h0,
    NrPMPEntries         : 0
  };

`ifndef TARGET_GATESIM
  ara_system #(
    .NrLanes           (NrLanes              ),
    .FPUSupport        (FPUSupport           ),
    .FPExtSupport      (FPExtSupport         ),
    .FixPtSupport      (FixPtSupport         ),
    .ArianeCfg         (ArianeAraConfig      ),
    .AxiAddrWidth      (AxiAddrWidth         ),
    .AxiIdWidth        (AxiCoreIdWidth       ),
    .AxiNarrowDataWidth(AxiNarrowDataWidth   ),
    .AxiWideDataWidth  (AxiDataWidth         ),
    .ara_axi_ar_t      (ara_axi_ar_chan_t    ),
    .ara_axi_aw_t      (ara_axi_aw_chan_t    ),
    .ara_axi_b_t       (ara_axi_b_chan_t     ),
    .ara_axi_r_t       (ara_axi_r_chan_t     ),
    .ara_axi_w_t       (ara_axi_w_chan_t     ),
    .ara_axi_req_t     (ara_axi_req_t        ),
    .ara_axi_resp_t    (ara_axi_resp_t       ),
    .ariane_axi_ar_t   (ariane_axi_ar_chan_t ),
    .ariane_axi_aw_t   (ariane_axi_aw_chan_t ),
    .ariane_axi_b_t    (ariane_axi_b_chan_t  ),
    .ariane_axi_r_t    (ariane_axi_r_chan_t  ),
    .ariane_axi_w_t    (ariane_axi_w_chan_t  ),
    .ariane_axi_req_t  (ariane_axi_req_t     ),
    .ariane_axi_resp_t (ariane_axi_resp_t    ),
    .system_axi_ar_t   (system_ar_chan_t     ),
    .system_axi_aw_t   (system_aw_chan_t     ),
    .system_axi_b_t    (system_b_chan_t      ),
    .system_axi_r_t    (system_r_chan_t      ),
    .system_axi_w_t    (system_w_chan_t      ),
    .system_axi_req_t  (system_req_t         ),
    .system_axi_resp_t (system_resp_t        ))
`else
  ara_system
`endif
  i_system (
    .clk_i        (clk_i                    ),
    .rst_ni       (rst_ni                   ),
    .boot_addr_i  (DRAMBase                 ), // start fetching from DRAM
    .hart_id_i    (hart_id                  ),
    .scan_enable_i(1'b0                     ),
    .scan_data_i  (1'b0                     ),
    .scan_data_o  (/* Unconnected */        ),
`ifndef TARGET_GATESIM
    .axi_req_o    (system_axi_req           ),
    .axi_resp_i   (system_axi_resp          )
  );
`else
    .axi_req_o    (system_axi_req_spill     ),
    .axi_resp_i   (system_axi_resp_spill_del)
  );
`endif


`ifdef TARGET_GATESIM
  assign #(AxiRespDelay*1ps) system_axi_resp_spill_del = system_axi_resp_spill;

  axi_cut #(
    .ar_chan_t   (system_ar_chan_t     ),
    .aw_chan_t   (system_aw_chan_t     ),
    .b_chan_t    (system_b_chan_t      ),
    .r_chan_t    (system_r_chan_t      ),
    .w_chan_t    (system_w_chan_t      ),
    .req_t       (system_req_t         ),
    .resp_t      (system_resp_t        )
  ) i_system_cut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .slv_req_i   (system_axi_req_spill),
    .slv_resp_o  (system_axi_resp_spill),
    .mst_req_o   (system_axi_req),
    .mst_resp_i  (system_axi_resp)
  );
`endif

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
