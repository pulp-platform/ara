// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
//         Matheus Cavalcante, ETH Zurich
// Date: 19.03.2017
// Description: Test harness for Ara.
//              This is loosely based on CVA6's test harness.
//              Instantiates an AXI-Bus and memories.

module ara_testharness #(
    parameter int unsigned AxiUserWidth       = 1,
    parameter int unsigned AxiIdWidth         = 4,
    parameter int unsigned AxiAddrWidth       = 64,
    parameter int unsigned AxiWideDataWidth   = 64,
    parameter int unsigned AxiNarrowDataWidth = 64,
    // Ara-specific parameters
    parameter int unsigned NrLanes            = 0,
    parameter int unsigned VectorLength       = 0,
    `ifdef DROMAJO
    parameter bit InclSimDTM = 1'b0,
    `else
    parameter bit InclSimDTM = 1'b1,
    `endif
    parameter int unsigned NumWords = 2**23 // memory size
  ) (
    input  logic        clk_i,
    input  logic        rst_ni,
    output logic [31:0] exit_o
  );

  /********************
   *  Memory Regions  *
   ********************/

  localparam NrAXIMasters = 2; // Actually masters, but slaves on the crossbar

  typedef enum int unsigned {
    DRAM = 0,
    UART = 1
  } axi_slaves_t;
  localparam NrAXISlaves = UART + 1;

  /*********
   *  AXI  *
   *********/

  `include "axi/assign.svh"
  `include "axi/typedef.svh"

  localparam AxiSlvIdWidth = AxiIdWidth + $clog2(NrAXIMasters);

  // Axi Typedefs
  typedef logic [AxiAddrWidth-1:0] axi_addr_t               ;
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t  ;
  typedef logic [AxiNarrowDataWidth/8-1:0] axi_narrow_strb_t;
  typedef logic [AxiWideDataWidth-1:0] axi_wide_data_t      ;
  typedef logic [AxiWideDataWidth/8-1:0] axi_wide_strb_t    ;
  typedef logic [AxiIdWidth-1:0] axi_id_t                   ;
  typedef logic [AxiSlvIdWidth-1:0] axi_slv_id_t            ;
  typedef logic [AxiUserWidth-1:0] axi_user_t               ;

  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(narrow_r_chan_t, axi_narrow_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(narrow_slv_r_chan_t, axi_narrow_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(wide_r_chan_t, axi_wide_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(wide_slv_r_chan_t, axi_wide_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(narrow_w_chan_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(wide_w_chan_t, axi_wide_data_t, axi_wide_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, axi_slv_id_t, axi_user_t)

  `AXI_TYPEDEF_REQ_T(axi_narrow_req_t, aw_chan_t, narrow_w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_narrow_resp_t, b_chan_t, narrow_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_narrow_slv_req_t, slv_aw_chan_t, narrow_w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_narrow_slv_resp_t, slv_b_chan_t, narrow_slv_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_wide_req_t, aw_chan_t, wide_w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_wide_resp_t, b_chan_t, wide_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_wide_slv_req_t, slv_aw_chan_t, wide_w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_wide_slv_resp_t, slv_b_chan_t, wide_slv_r_chan_t)

  // Buses
  axi_narrow_req_t  ariane_narrow_axi_req;
  axi_narrow_resp_t ariane_narrow_axi_resp;
  axi_wide_req_t    ariane_axi_req;
  axi_wide_resp_t   ariane_axi_resp;
  axi_wide_req_t    ara_axi_req;
  axi_wide_resp_t   ara_axi_resp;

  axi_wide_slv_req_t    [NrAXISlaves-1:0] periph_wide_axi_req;
  axi_wide_slv_resp_t   [NrAXISlaves-1:0] periph_wide_axi_resp;
  axi_narrow_slv_req_t  [NrAXISlaves-1:0] periph_narrow_axi_req;
  axi_narrow_slv_resp_t [NrAXISlaves-1:0] periph_narrow_axi_resp;

  /********
   *  L2  *
   ********/

  logic                          req;
  logic                          we;
  logic [AxiAddrWidth-1:0]       addr;
  logic [AxiWideDataWidth/8-1:0] be;
  logic [AxiWideDataWidth-1:0]   wdata;
  logic [AxiWideDataWidth-1:0]   rdata;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AxiAddrWidth    ),
    .AXI_DATA_WIDTH(AxiWideDataWidth),
    .AXI_ID_WIDTH  (AxiSlvIdWidth   ),
    .AXI_USER_WIDTH(AxiUserWidth    )
  ) axi_l2_wide_slave ();

  `AXI_ASSIGN_FROM_REQ(axi_l2_wide_slave, periph_wide_axi_req[DRAM])
  `AXI_ASSIGN_TO_RESP(periph_wide_axi_resp[DRAM], axi_l2_wide_slave)

  axi2mem #(
    .AXI_ID_WIDTH  (AxiSlvIdWidth   ),
    .AXI_ADDR_WIDTH(AxiAddrWidth    ),
    .AXI_DATA_WIDTH(AxiWideDataWidth),
    .AXI_USER_WIDTH(AxiUserWidth    )
  ) i_axi2mem (
    .clk_i (clk_i            ),
    .rst_ni(rst_ni           ),
    .slave (axi_l2_wide_slave),
    .req_o (req              ),
    .we_o  (we               ),
    .addr_o(addr             ),
    .be_o  (be               ),
    .data_o(wdata            ),
    .data_i(rdata            )
  );

  tc_sram #(
    .NumWords (NumWords        ),
    .NumPorts (1               ),
    .DataWidth(AxiWideDataWidth)
  ) i_sram (
    .clk_i  (clk_i                                                                         ),
    .rst_ni (rst_ni                                                                        ),
    .req_i  (req                                                                           ),
    .we_i   (we                                                                            ),
    .addr_i (addr[$clog2(NumWords)-1+$clog2(AxiWideDataWidth/8):$clog2(AxiWideDataWidth/8)]),
    .wdata_i(wdata                                                                         ),
    .be_i   (be                                                                            ),
    .rdata_o(rdata                                                                         )
  );

  /**********
   *  UART  *
   **********/

  logic        uart_penable;
  logic        uart_pwrite;
  logic [31:0] uart_paddr;
  logic        uart_psel;
  logic [31:0] uart_pwdata;
  logic [31:0] uart_prdata;
  logic        uart_pready;
  logic        uart_pslverr;

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH(AxiAddrWidth      ),
    .AXI4_RDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_WDATA_WIDTH  (AxiNarrowDataWidth),
    .AXI4_ID_WIDTH     (AxiSlvIdWidth     ),
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
    .PENABLE   (uart_penable                         ),
    .PWRITE    (uart_pwrite                          ),
    .PADDR     (uart_paddr                           ),
    .PSEL      (uart_psel                            ),
    .PWDATA    (uart_pwdata                          ),
    .PRDATA    (uart_prdata                          ),
    .PREADY    (uart_pready                          ),
    .PSLVERR   (uart_pslverr                         )
  );

  mock_uart i_mock_uart (
    .clk_i     ( clk_i        ),
    .rst_ni    ( rst_ni       ),
    .penable_i ( uart_penable ),
    .pwrite_i  ( uart_pwrite  ),
    .paddr_i   ( uart_paddr   ),
    .psel_i    ( uart_psel    ),
    .pwdata_i  ( uart_pwdata  ),
    .prdata_o  ( uart_prdata  ),
    .pready_o  ( uart_pready  ),
    .pslverr_o ( uart_pslverr )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiWideDataWidth     ),
    .AxiMstPortDataWidth(AxiNarrowDataWidth   ),
    .AxiAddrWidth       (AxiAddrWidth         ),
    .AxiIdWidth         (AxiSlvIdWidth        ),
    .AxiMaxReads        (2                    ),
    .ar_chan_t          (slv_ar_chan_t        ),
    .mst_r_chan_t       (narrow_slv_r_chan_t  ),
    .slv_r_chan_t       (wide_slv_r_chan_t    ),
    .aw_chan_t          (slv_aw_chan_t        ),
    .b_chan_t           (slv_b_chan_t         ),
    .mst_w_chan_t       (narrow_w_chan_t      ),
    .slv_w_chan_t       (wide_w_chan_t        ),
    .axi_mst_req_t      (axi_narrow_slv_req_t ),
    .axi_mst_resp_t     (axi_narrow_slv_resp_t),
    .axi_slv_req_t      (axi_wide_slv_req_t   ),
    .axi_slv_resp_t     (axi_wide_slv_resp_t  )
  ) i_axi_slave_uart_dwc (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_wide_axi_req[UART]   ),
    .slv_resp_o(periph_wide_axi_resp[UART]  ),
    .mst_req_o (periph_narrow_axi_req[UART] ),
    .mst_resp_i(periph_narrow_axi_resp[UART])
  );

  /**************
   *  Crossbar  *
   **************/

  localparam axi_pkg::xbar_cfg_t XBarCfg = '{
    NoSlvPorts        : NrAXIMasters,
    NoMstPorts        : NrAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    AxiIdWidthSlvPorts: AxiIdWidth,
    AxiIdUsedSlvPorts : AxiIdWidth,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiWideDataWidth,
    NoAddrRules       : NrAXISlaves
  };

  localparam logic[63:0] UARTLength = 64'h1000;
  localparam logic[63:0] DRAMLength = 64'h40000000; // 1GByte of DDR (split between two chips on Genesys2)

  typedef enum logic [63:0] {
    UARTBase = 64'h1000_0000,
    DRAMBase = 64'h8000_0000
  } soc_bus_start_t;

  axi_pkg::xbar_rule_64_t [NrAXISlaves-1:0] routing_rules = '{
    '{idx: UART, start_addr: UARTBase, end_addr: UARTBase + UARTLength},
    '{idx: DRAM, start_addr: DRAMBase, end_addr: DRAMBase + DRAMLength}};

  axi_xbar #(
    .Cfg          (XBarCfg                ),
    .slv_aw_chan_t(aw_chan_t              ),
    .mst_aw_chan_t(slv_aw_chan_t          ),
    .w_chan_t     (wide_w_chan_t          ),
    .slv_b_chan_t (b_chan_t               ),
    .mst_b_chan_t (slv_b_chan_t           ),
    .slv_ar_chan_t(ar_chan_t              ),
    .mst_ar_chan_t(slv_ar_chan_t          ),
    .slv_r_chan_t (wide_r_chan_t          ),
    .mst_r_chan_t (wide_slv_r_chan_t      ),
    .slv_req_t    (axi_wide_req_t         ),
    .slv_resp_t   (axi_wide_resp_t        ),
    .mst_req_t    (axi_wide_slv_req_t     ),
    .mst_resp_t   (axi_wide_slv_resp_t    ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_tesbench_xbar (
    .clk_i                (clk_i                          ),
    .rst_ni               (rst_ni                         ),
    .test_i               (1'b0                           ),
    .slv_ports_req_i      ({ariane_axi_req, ara_axi_req}  ),
    .slv_ports_resp_o     ({ariane_axi_resp, ara_axi_resp}),
    .mst_ports_req_o      (periph_wide_axi_req            ),
    .mst_ports_resp_i     (periph_wide_axi_resp           ),
    .addr_map_i           (routing_rules                  ),
    .en_default_mst_port_i('0                             ),
    .default_mst_port_i   ('0                             )
  );

  /*********
   *  DUT  *
   *********/

  // TODO: Integrate Ara
  assign ara_axi_req = '0;

  ariane #(
    .ArianeCfg(ariane_pkg::ArianeDefaultConfig)
  ) i_ariane (
    .clk_i       (clk_i                 ),
    .rst_ni      (rst_ni                ),
    .boot_addr_i (DRAMBase              ), // start fetching from DRAM
    .hart_id_i   ('0                    ),
    .irq_i       ('0                    ),
    .ipi_i       ('0                    ),
    .time_irq_i  ('0                    ),
    .debug_req_i ('0                    ),
    .axi_req_o   (ariane_narrow_axi_req ),
    .axi_resp_i  (ariane_narrow_axi_resp)
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiNarrowDataWidth),
    .AxiMstPortDataWidth(AxiWideDataWidth  ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiIdWidth        ),
    .AxiMaxReads        (4                 ),
    .ar_chan_t          (ar_chan_t         ),
    .mst_r_chan_t       (wide_r_chan_t     ),
    .slv_r_chan_t       (narrow_r_chan_t   ),
    .aw_chan_t          (aw_chan_t         ),
    .b_chan_t           (b_chan_t          ),
    .mst_w_chan_t       (wide_w_chan_t     ),
    .slv_w_chan_t       (narrow_w_chan_t   ),
    .axi_mst_req_t      (axi_wide_req_t    ),
    .axi_mst_resp_t     (axi_wide_resp_t   ),
    .axi_slv_req_t      (axi_narrow_req_t  ),
    .axi_slv_resp_t     (axi_narrow_resp_t )
  ) i_ariane_axi_dwc (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
    .slv_req_i (ariane_narrow_axi_req ),
    .slv_resp_o(ariane_narrow_axi_resp),
    .mst_req_o (ariane_axi_req        ),
    .mst_resp_i(ariane_axi_resp       )
  );

endmodule : ara_testharness
