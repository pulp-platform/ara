// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's SoC, containing Ariane, Ara, and a L2 cache.

module ara_soc import axi_pkg::*; import ara_pkg::*; #(
    // Number of Ara systems
    parameter int unsigned NrAraSystems = 1,
    // RVV Parameters
    parameter int unsigned NrLanes = 0, // Number of parallel vector lanes.
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
    parameter  int           unsigned AxiIdWidth   = 4,
    // AXI Resp Delay [ps] for gate-level simulation
    parameter  int           unsigned AxiRespDelay = 200,
    // Main memory
    parameter int unsigned L2NumWords = 2**20,
    // Dependant parameters. DO NOT CHANGE!
    localparam			   type axi_data_t = logic [AxiDataWidth-1:0],
    localparam			   type axi_strb_t = logic [AxiDataWidth/8-1:0],
    localparam			   type axi_addr_t = logic [AxiAddrWidth-1:0],
    localparam			   type axi_user_t = logic [AxiUserWidth-1:0],
    localparam			   type axi_id_t = logic [AxiIdWidth-1:0]
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

  // Overview of AXI buses (from a single master viewpoint)
  // One master is one ara_system (i.e., CVA6 + Ara)
  //
  //      mst_demux
  //        / |
  //       /  |  per_m   +----------+  per_s  +---------+
  //      |  0|========> | soc_xbar |========>| periph  |
  //  mst |   |          +----------+         +---------+
  // ====>|   |
  //      |   | l2       +----------+  mem    +---------+ bank  +--------+
  //      |  1|========> | axi2mem  |-------->| l2_xbar |------>| l2_mem |
  //       \  |          +----------+         +---------+       +--------+
  //        \_|
  //                      == axi ==>          -- tcdm -->

  //////////////////////
  //  Memory Regions  //
  //////////////////////

  // Multicore Ara with `NrAraSystems (CVA6 + Ara)
  // One bank per system
  localparam int unsigned NrAXIMasters     = NrAraSystems; // Actually masters, but slaves on the crossbar
  localparam int unsigned L2NumBanks       = NrAraSystems;
  localparam int unsigned NrAXIMastersLog2 = (NrAXIMasters > 1) ? $clog2(NrAXIMasters) : 1;

  // Banked L2 memory
  localparam int unsigned L2BankNumWords   = L2NumWords / L2NumBanks;
  localparam int unsigned L2BankAddrWidth  = $clog2(L2BankNumWords);
  localparam int unsigned L2BankWidth      = AxiDataWidth;
  localparam int unsigned L2BankBeWidth    = L2BankWidth/8;
  localparam int unsigned L2BankSize       = L2BankNumWords * L2BankBeWidth;

  // Multibanked memory or peripherals (1 demux per master)
  typedef enum logic {
    PERIPH = 0,
    L2MEM  = 1
  } axi_mst_slaves_e;
  // The memory is not routed by the peripheral xbar anymore!
  typedef enum logic {
    UART  = 0,
    CTRL  = 1
  } axi_periph_slaves_e;
  localparam NrMstAXISlaves = L2MEM + 1;
  // The memory is already routed by the master demuxes
  localparam NrPeriphAXISlaves = CTRL + 1;

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

  // ID width should decrease at every xbar step from masters to slaves
  // https://github.com/pulp-platform/axi/blob/master/doc/axi_xbar.md
  localparam AxiCoreIdWidth   = AxiIdWidth;
  localparam AxiSysIdWidth    = AxiCoreIdWidth + 1;
  localparam AxiSocIdWidth    = AxiSysIdWidth;
  localparam AxiPeriphIdWidth = AxiSocIdWidth + NrAXIMastersLog2;

 // // Or in the other way around to keep the ID low
 // localparam AxiPeriphIdWidth = AxiIdWidth;
 // localparam AxiSocIdWidth    = AxiPeriphIdWidth - NrAXIMastersLog2;
 // localparam AxiSysIdWidth    = AxiSocIdWidth;
 // localparam AxiCoreIdWidth   = AxiSysIdWidth - 1;

  // Internal types
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowStrbWidth-1:0] axi_narrow_strb_t;
  typedef logic [AxiPeriphIdWidth-1:0]   axi_periph_id_t;
  typedef logic [AxiSocIdWidth-1:0]      axi_soc_id_t;
  typedef logic [AxiSysIdWidth-1:0]      axi_sys_id_t;
  typedef logic [AxiCoreIdWidth-1:0]     axi_core_id_t;

  // AXI Typedefs
  // In-System types
  `AXI_TYPEDEF_ALL(ara_axi, axi_addr_t, axi_core_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(ariane_axi, axi_addr_t, axi_core_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  // In-Soc types
  `AXI_TYPEDEF_ALL(     system, axi_addr_t,    axi_sys_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(   soc_wide, axi_addr_t,    axi_soc_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(periph_wide, axi_addr_t, axi_periph_id_t, axi_data_t, axi_strb_t, axi_user_t)
  // In-Soc sub-types
  `AXI_TYPEDEF_ALL(periph_narrow, axi_addr_t, axi_periph_id_t, axi_narrow_data_t, axi_narrow_strb_t,
    axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(periph_narrow_lite, axi_addr_t, axi_narrow_data_t, axi_narrow_strb_t)

  // Buses
  // From systems to their own master demux
  system_req_t         [NrAXIMasters-1:0]      system_axi_req, system_axi_req_spill;
  system_resp_t        [NrAXIMasters-1:0]      system_axi_resp, system_axi_resp_spill, system_axi_resp_spill_del;
  // From each master demux to the banked memory (and adapters)
  soc_wide_req_t       [NrAXIMasters-1:0]      l2_wide_axi_req;
  soc_wide_resp_t      [NrAXIMasters-1:0]      l2_wide_axi_resp;
  // From each master demux to the peripheral xbar
  soc_wide_req_t       [NrAXIMasters-1:0]      periph_mst_wide_axi_req;
  soc_wide_resp_t      [NrAXIMasters-1:0]      periph_mst_wide_axi_resp;
  // From peripheral xbar to the peripherals (l2 memory excluded)
  periph_wide_req_t    [NrPeriphAXISlaves-1:0] periph_slv_wide_axi_req;
  periph_wide_resp_t   [NrPeriphAXISlaves-1:0] periph_slv_wide_axi_resp;
  // Adapted peripheral signals to peripherals
  periph_narrow_req_t  [NrPeriphAXISlaves-1:0] periph_narrow_axi_req;
  periph_narrow_resp_t [NrPeriphAXISlaves-1:0] periph_narrow_axi_resp;

  //////////////////////////
  //  Ara System Demuxes  //
  //////////////////////////

  // Each Ara system has a demux to split the l2 memory request
  // from the request to the peripherals

  localparam axi_pkg::xbar_cfg_t MstDemuxCfg = '{
    NoSlvPorts        : 1,
    NoMstPorts        : NrMstAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::NO_LATENCY,
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiWideDataWidth,
    NoAddrRules       : NrMstAXISlaves - 1
  };

  // Route either towards the memory, or the peripherals
  axi_pkg::xbar_rule_64_t [0:0] mst_routing_rules;
  assign mst_routing_rules = '{
    '{idx: L2MEM,  start_addr: DRAMBase, end_addr: DRAMBase + DRAMLength}
  };
//  '{idx: PERIPH, start_addr: UARTBase, end_addr: CTRLBase + CTRLLength} // default_mst_port_i

  for (genvar i = 0; i < NrAraSystems; i++) begin : gen_mst_demux
    axi_xbar #(
      .Cfg          (MstDemuxCfg            ),
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
    ) i_mst_demux (
      .clk_i                (clk_i                                              ),
      .rst_ni               (rst_ni                                             ),
      .test_i               (1'b0                                               ),
      .slv_ports_req_i      (system_axi_req[i]                                  ),
      .slv_ports_resp_o     (system_axi_resp[i]                                 ),
      .mst_ports_req_o      ({l2_wide_axi_req[i],  periph_mst_wide_axi_req[i]}  ),
      .mst_ports_resp_i     ({l2_wide_axi_resp[i], periph_mst_wide_axi_resp[i]} ),
      .addr_map_i           (mst_routing_rules                                  ),
      .en_default_mst_port_i(1'b1                                               ),
      .default_mst_port_i   (PERIPH                                             )
    );
  end

  ///////////////////
  //  Periph XBar  //
  ///////////////////

  // Peripheral XBar. This does not route to the memory anymore
  // (- 1) because the memory is not routed here
  localparam axi_pkg::xbar_cfg_t PeriphXBarCfg = '{
    NoSlvPorts        : NrAXIMasters,
    NoMstPorts        : NrPeriphAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiWideDataWidth,
    NoAddrRules       : NrPeriphAXISlaves - 1
  };

  axi_pkg::xbar_rule_64_t [0:0] periph_routing_rules;
  assign periph_routing_rules = '{
    '{idx: CTRL, start_addr: CTRLBase, end_addr: CTRLBase + CTRLLength}
  };
//  '{idx: UART, start_addr: UARTBase, end_addr: UARTBase + UARTLength} // default_mst_port_i

  axi_xbar #(
    .Cfg          (PeriphXBarCfg          ),
    .slv_aw_chan_t(soc_wide_aw_chan_t     ),
    .mst_aw_chan_t(periph_wide_aw_chan_t  ),
    .w_chan_t     (soc_wide_w_chan_t      ),
    .slv_b_chan_t (soc_wide_b_chan_t      ),
    .mst_b_chan_t (periph_wide_b_chan_t   ),
    .slv_ar_chan_t(soc_wide_ar_chan_t     ),
    .mst_ar_chan_t(periph_wide_ar_chan_t  ),
    .slv_r_chan_t (soc_wide_r_chan_t      ),
    .mst_r_chan_t (periph_wide_r_chan_t   ),
    .slv_req_t    (soc_wide_req_t         ),
    .slv_resp_t   (soc_wide_resp_t        ),
    .mst_req_t    (periph_wide_req_t      ),
    .mst_resp_t   (periph_wide_resp_t     ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_soc_xbar (
    .clk_i                (clk_i                   ),
    .rst_ni               (rst_ni                  ),
    .test_i               (1'b0                    ),
    .slv_ports_req_i      (periph_mst_wide_axi_req ),
    .slv_ports_resp_o     (periph_mst_wide_axi_resp),
    .mst_ports_req_o      (periph_slv_wide_axi_req ),
    .mst_ports_resp_i     (periph_slv_wide_axi_resp),
    .addr_map_i           (periph_routing_rules    ),
    .en_default_mst_port_i({NrAXIMasters{1'b1}}    ),
    .default_mst_port_i   ({NrAXIMasters{UART}}    )
  );

  //////////
  //  L2  //
  //////////

  // The L2 memory does not support atomics

  soc_wide_req_t  [NrAXIMasters-1:0] l2_wide_axi_req_wo_atomics;
  soc_wide_resp_t [NrAXIMasters-1:0] l2_wide_axi_resp_wo_atomics;

  for (genvar i = 0; i < NrAXIMasters; i++) begin : gen_l2_atop_filters
    axi_atop_filter #(
      .AxiIdWidth     (AxiSocIdWidth  ),
      .AxiMaxWriteTxns(4              ),
      .req_t          (soc_wide_req_t ),
      .resp_t         (soc_wide_resp_t)
    ) i_l2mem_atop_filter (
      .clk_i     (clk_i                            ),
      .rst_ni    (rst_ni                           ),
      .slv_req_i (l2_wide_axi_req[i]               ),
      .slv_resp_o(l2_wide_axi_resp[i]              ),
      .mst_req_o (l2_wide_axi_req_wo_atomics[i]    ),
      .mst_resp_i(l2_wide_axi_resp_wo_atomics[i]   )
    );
  end

  typedef logic [NrAXIMastersLog2-1:0] bank_ini_t;

  logic [NrAXIMasters-1:0]                      l2_req;
  logic [NrAXIMasters-1:0]                      l2_gnt;
  logic [NrAXIMasters-1:0]                      l2_rvalid;
  logic [NrAXIMasters-1:0] [AxiAddrWidth-1:0]   l2_addr;
  logic [NrAXIMasters-1:0] [AxiDataWidth-1:0]   l2_wdata;
  logic [NrAXIMasters-1:0] [AxiDataWidth/8-1:0] l2_be;
  logic [NrAXIMasters-1:0]                      l2_we;
  logic [NrAXIMasters-1:0] [AxiDataWidth-1:0]   l2_rdata;

  logic      [L2NumBanks-1:0]                       bank_req;
  logic      [L2NumBanks-1:0]                       bank_gnt;
  logic      [L2NumBanks-1:0]                       bank_rvalid;
  logic      [L2NumBanks-1:0] [L2BankAddrWidth-1:0] bank_addr;
  bank_ini_t [L2NumBanks-1:0]                       bank_ini_d, bank_ini_q;
  logic      [L2NumBanks-1:0] [AxiDataWidth-1:0]    bank_wdata;
  logic      [L2NumBanks-1:0] [AxiDataWidth/8-1:0]  bank_be;
  logic      [L2NumBanks-1:0]                       bank_we;
  logic      [L2NumBanks-1:0] [AxiDataWidth-1:0]    bank_rdata;


  // ToDo: Check BufDepth parameter!
  for (genvar i = 0; i < NrAXIMasters; i++) begin : gen_l2_adapters
    axi_to_mem #(
      .AddrWidth (AxiAddrWidth   ),
      .DataWidth (AxiDataWidth   ),
      .IdWidth   (AxiSocIdWidth  ),
      .NumBanks  (1              ),
      .BufDepth  (3              ),
      .axi_req_t (soc_wide_req_t ),
      .axi_resp_t(soc_wide_resp_t)
    ) i_axi_to_mem (
      .clk_i       (clk_i                            ),
      .rst_ni      (rst_ni                           ),
      .axi_req_i   (l2_wide_axi_req_wo_atomics[i]    ),
      .axi_resp_o  (l2_wide_axi_resp_wo_atomics[i]   ),
      .mem_req_o   (l2_req[i]                        ),
      .mem_gnt_i   (l2_gnt[i]                        ),
      .mem_we_o    (l2_we[i]                         ),
      .mem_addr_o  (l2_addr[i]                       ),
      .mem_strb_o  (l2_be[i]                         ),
      .mem_wdata_o (l2_wdata[i]                      ),
      .mem_rdata_i (l2_rdata[i]                      ),
      .mem_rvalid_i(l2_rvalid[i]                     ),
      .mem_atop_o  (/* Unused */                     ),
      .busy_o      (/* Unused */                     )
    );
  end

  variable_latency_interconnect #(
    .NumIn            (NrAXIMasters   ),
    .NumOut           (L2NumBanks     ),
    .AddrWidth        (AxiAddrWidth   ),
    .DataWidth        (L2BankWidth    ),
    .BeWidth          (L2BankBeWidth  ),
    .AddrMemWidth     (L2BankAddrWidth),
    .AxiVldRdy        (1'b1           ),
    .SpillRegisterReq (64'b1          ),
    .SpillRegisterResp(64'b1          )
  ) i_l2_xbar (
    .clk_i          (clk_i      ),
    .rst_ni         (rst_ni     ),
    // master side
    .req_valid_i    (l2_req    ),
    .req_ready_o    (l2_gnt    ),
    .req_tgt_addr_i (l2_addr   ),
    .req_wen_i      (l2_we     ),
    .req_wdata_i    (l2_wdata  ),
    .req_be_i       (l2_be     ),
    .resp_valid_o   (l2_rvalid ),
    .resp_ready_i   ('1        ),
    .resp_rdata_o   (l2_rdata  ),
    // slave side
    .req_valid_o    (bank_req   ),
    .req_ready_i    ('1         ),
    .req_ini_addr_o (bank_ini_d ),
    .req_tgt_addr_o (bank_addr  ),
    .req_wen_o      (bank_we    ),
    .req_wdata_o    (bank_wdata ),
    .req_be_o       (bank_be    ),
    .resp_valid_i   (bank_rvalid),
    .resp_ready_o   (/*unused*/ ), // This only works because resp_ready_i = 1
    .resp_ini_addr_i(bank_ini_q ),
    .resp_rdata_i   (bank_rdata )
  );

`ifndef SPYGLASS
  for (genvar i = 0; i < L2NumBanks; i++) begin : gen_l2_banks
    tc_sram #(
      .DataWidth(L2BankWidth   ),
      .NumWords (L2BankNumWords),
      .NumPorts (1             )
    ) l2_mem (
      .clk_i  (clk_i        ),
      .rst_ni (rst_ni       ),
      .req_i  (bank_req[i]  ),
      .we_i   (bank_we[i]   ),
      .addr_i (bank_addr[i] ),
      .wdata_i(bank_wdata[i]),
      .be_i   (bank_be[i]   ),
      .rdata_o(bank_rdata[i])
    );
  end
`else
  assign l2_rdata = '0;
`endif

  // One-cycle latency
  `FF(bank_rvalid, bank_req, 1'b0);
  `FF(bank_ini_q, bank_ini_d, 1'b0);

  ////////////
  //  UART  //
  ////////////

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH(AxiAddrWidth      ),
    .AXI4_RDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_WDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_ID_WIDTH     (AxiPeriphIdWidth  ),
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
    .AxiSlvPortDataWidth(AxiWideDataWidth     ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth   ),
    .AxiAddrWidth       (AxiAddrWidth         ),
    .AxiIdWidth         (AxiPeriphIdWidth     ),
    .AxiMaxReads        (2                    ),
    .ar_chan_t          (periph_wide_ar_chan_t   ),
    .mst_r_chan_t       (periph_narrow_r_chan_t  ),
    .slv_r_chan_t       (periph_wide_r_chan_t    ),
    .aw_chan_t          (periph_narrow_aw_chan_t ),
    .b_chan_t           (periph_wide_b_chan_t    ),
    .mst_w_chan_t       (periph_narrow_w_chan_t  ),
    .slv_w_chan_t       (periph_wide_w_chan_t    ),
    .axi_mst_req_t      (periph_narrow_req_t     ),
    .axi_mst_resp_t     (periph_narrow_resp_t    ),
    .axi_slv_req_t      (periph_wide_req_t       ),
    .axi_slv_resp_t     (periph_wide_resp_t      )
  ) i_axi_slave_uart_dwc (
    .clk_i     (clk_i                              ),
    .rst_ni    (rst_ni                             ),
    .slv_req_i (periph_slv_wide_axi_req[UART]   ),
    .slv_resp_o(periph_slv_wide_axi_resp[UART]  ),
    .mst_req_o (periph_narrow_axi_req[UART]        ),
    .mst_resp_i(periph_narrow_axi_resp[UART]       )
  );

  /////////////////////////
  //  Control registers  //
  /////////////////////////

  periph_narrow_lite_req_t  axi_lite_ctrl_registers_req;
  periph_narrow_lite_resp_t axi_lite_ctrl_registers_resp;

  logic [63:0] event_trigger;

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth          ),
    .AxiDataWidth   (AxiNarrowDataWidth    ),
    .AxiIdWidth     (AxiPeriphIdWidth      ),
    .AxiUserWidth   (AxiUserWidth          ),
    .AxiMaxReadTxns (1                     ),
    .AxiMaxWriteTxns(1                     ),
    .FallThrough    (1'b0                  ),
    .full_req_t     (periph_narrow_req_t      ),
    .full_resp_t    (periph_narrow_resp_t     ),
    .lite_req_t     (periph_narrow_lite_req_t ),
    .lite_resp_t    (periph_narrow_lite_resp_t)
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
    .axi_lite_req_t (periph_narrow_lite_req_t ),
    .axi_lite_resp_t(periph_narrow_lite_resp_t)
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
    .AxiIdWidth         (AxiPeriphIdWidth    ),
    .AxiMaxReads        (2                   ),
    .ar_chan_t          (periph_wide_ar_chan_t  ),
    .mst_r_chan_t       (periph_narrow_r_chan_t ),
    .slv_r_chan_t       (periph_wide_r_chan_t   ),
    .aw_chan_t          (periph_narrow_aw_chan_t),
    .b_chan_t           (periph_narrow_b_chan_t ),
    .mst_w_chan_t       (periph_narrow_w_chan_t ),
    .slv_w_chan_t       (periph_wide_w_chan_t   ),
    .axi_mst_req_t      (periph_narrow_req_t    ),
    .axi_mst_resp_t     (periph_narrow_resp_t   ),
    .axi_slv_req_t      (periph_wide_req_t      ),
    .axi_slv_resp_t     (periph_wide_resp_t     )
  ) i_axi_slave_ctrl_dwc (
    .clk_i     (clk_i                            ),
    .rst_ni    (rst_ni                           ),
    .slv_req_i (periph_slv_wide_axi_req[CTRL] ),
    .slv_resp_o(periph_slv_wide_axi_resp[CTRL]),
    .mst_req_o (periph_narrow_axi_req[CTRL]      ),
    .mst_resp_i(periph_narrow_axi_resp[CTRL]     )
  );

  //////////////
  //  System  //
  //////////////

  // Max systems supported: 8
  logic [2:0] hart_id [NrAraSystems-1:0];
  always_comb for (int unsigned i = 0; i < NrAraSystems; i++) hart_id[i] = i;

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

  for (genvar i = 0; i < NrAraSystems; i++) begin : gen_ara_systems
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
      .clk_i        (clk_i                       ),
      .rst_ni       (rst_ni                      ),
      .boot_addr_i  (DRAMBase                    ), // start fetching from DRAM
      .hart_id_i    (hart_id[i]                  ),
      .scan_enable_i(1'b0                        ),
      .scan_data_i  (1'b0                        ),
      .scan_data_o  (/* Unconnected */           ),
`ifndef TARGET_GATESIM
      .axi_req_o    (system_axi_req[i]           ),
      .axi_resp_i   (system_axi_resp[i]          )
    );
`else
      .axi_req_o    (system_axi_req_spill[i]     ),
      .axi_resp_i   (system_axi_resp_spill_del[i])
    );
`endif

`ifdef TARGET_GATESIM
  assign #(AxiRespDelay*1ps) system_axi_resp_spill_del[i] = system_axi_resp_spill[i];

  axi_cut #(
    .ar_chan_t   (system_ar_chan_t     ),
    .aw_chan_t   (system_aw_chan_t     ),
    .b_chan_t    (system_b_chan_t      ),
    .r_chan_t    (system_r_chan_t      ),
    .w_chan_t    (system_w_chan_t      ),
    .req_t       (system_req_t         ),
    .resp_t      (system_resp_t        )
  ) i_system_cut (
    .clk_i       (clk_i                   ),
    .rst_ni      (rst_ni                  ),
    .slv_req_i   (system_axi_req_spill[i] ),
    .slv_resp_o  (system_axi_resp_spill[i]),
    .mst_req_o   (system_axi_req[i]       ),
    .mst_resp_i  (system_axi_resp[i]      )
  );
`endif

  end

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
