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
// Date: 19.03.2017
// Description: Test-harness for Ara
//              Instantiates an AXI-Bus and memories

`include "probe.svh"

module ara_testharness #(
    parameter int unsigned AXI_ID_WIDTH          = 4   ,
    parameter int unsigned AXI_USER_WIDTH        = 1   ,
    parameter int unsigned AXI_ADDRESS_WIDTH     = 64  ,
    parameter int unsigned AXI_DATA_WIDTH        = 64  ,
    parameter int unsigned AXI_NARROW_DATA_WIDTH = 64  ,
    parameter bit InclSimDTM                     = 1'b1,
    parameter int unsigned NUM_WORDS             = 2**25 // memory size
  ) (
    input  logic        clk_i,
    input  logic        rtc_i,
    input  logic        rst_ni,
    output logic [31:0] exit_o
  );

  // disable test-enable
  logic test_en;
  logic ndmreset;
  logic ndmreset_n;
  logic debug_req_core;

  int          jtag_enable;
  logic        init_done;
  logic [31:0] jtag_exit, dmi_exit;

  logic jtag_TCK;
  logic jtag_TMS;
  logic jtag_TDI;
  logic jtag_TRSTn;
  logic jtag_TDO_data;
  logic jtag_TDO_driven;

  logic debug_req_valid;
  logic debug_req_ready;
  logic debug_resp_valid;
  logic debug_resp_ready;

  logic        jtag_req_valid;
  logic [6:0]  jtag_req_bits_addr;
  logic [1:0]  jtag_req_bits_op;
  logic [31:0] jtag_req_bits_data;
  logic        jtag_resp_ready;
  logic        jtag_resp_valid;

  logic dmi_req_valid;
  logic dmi_resp_ready;
  logic dmi_resp_valid;

  dm::dmi_req_t jtag_dmi_req;
  dm::dmi_req_t dmi_req     ;

  dm::dmi_req_t debug_req  ;
  dm::dmi_resp_t debug_resp;

  assign test_en = 1'b0;

  localparam NB_SLAVE = 3;

  localparam AXI_ID_WIDTH_SLAVES = AXI_ID_WIDTH + $clog2(NB_SLAVE);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH   ),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH     ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH   )
  ) slave [NB_SLAVE-1:0] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH  ),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH     ),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH_SLAVES),
    .AXI_USER_WIDTH(AXI_USER_WIDTH     )
  ) master [ariane_soc::NB_PERIPHERALS-1:0] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH    ),
    .AXI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH         ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH       )
  ) narrow_slave [NB_SLAVE-1:0] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH    ),
    .AXI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH_SLAVES  ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH       )
  ) narrow_master [ariane_soc::NB_PERIPHERALS-1:0] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH   ),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH     ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH   )
  ) ara_cuts [NB_SLAVE-1:0] ();

  rstgen i_rstgen_main (
    .clk_i      ( clk_i               ),
    .rst_ni     ( rst_ni & (~ndmreset)),
    .test_mode_i( test_en             ),
    .rst_no     ( ndmreset_n          ),
    .init_no    (                     ) // keep open
  );

  /***********
   *  DEBUG  *
   ***********/

  assign init_done = rst_ni;

  initial begin
    if (!$value$plusargs("jtag_rbb_enable=%b", jtag_enable)) jtag_enable = 'h0;
  end

  // debug if MUX
  assign debug_req_valid  = (jtag_enable[0]) ? jtag_req_valid   : dmi_req_valid   ;
  assign debug_resp_ready = (jtag_enable[0]) ? jtag_resp_ready  : dmi_resp_ready  ;
  assign debug_req        = (jtag_enable[0]) ? jtag_dmi_req     : dmi_req         ;
  assign exit_o           = (jtag_enable[0]) ? jtag_exit        : dmi_exit        ;
  assign jtag_resp_valid  = (jtag_enable[0]) ? debug_resp_valid : 1'b0            ;
  assign dmi_resp_valid   = (jtag_enable[0]) ? 1'b0             : debug_resp_valid;

  // SiFive's SimJTAG Module
  // Converts to DPI calls
  SimJTAG i_SimJTAG (
    .clock          (clk_i          ),
    .reset          (~rst_ni        ),
    .enable         (jtag_enable[0] ),
    .init_done      (init_done      ),
    .jtag_TCK       (jtag_TCK       ),
    .jtag_TMS       (jtag_TMS       ),
    .jtag_TDI       (jtag_TDI       ),
    .jtag_TRSTn     (jtag_TRSTn     ),
    .jtag_TDO_data  (jtag_TDO_data  ),
    .jtag_TDO_driven(jtag_TDO_driven),
    .exit           (jtag_exit      )
  );

  dmi_jtag i_dmi_jtag (
    .clk_i           ( clk_i          ),
    .rst_ni          ( rst_ni         ),
    .testmode_i      ( test_en        ),
    .dmi_req_o       ( jtag_dmi_req   ),
    .dmi_req_valid_o ( jtag_req_valid ),
    .dmi_req_ready_i ( debug_req_ready),
    .dmi_resp_i      ( debug_resp     ),
    .dmi_resp_ready_o( jtag_resp_ready),
    .dmi_resp_valid_i( jtag_resp_valid),
    .dmi_rst_no      (                ), // not connected
    .tck_i           ( jtag_TCK       ),
    .tms_i           ( jtag_TMS       ),
    .trst_ni         ( jtag_TRSTn     ),
    .td_i            ( jtag_TDI       ),
    .td_o            ( jtag_TDO_data  ),
    .tdo_oe_o        ( jtag_TDO_driven)
  );

  // SiFive's SimDTM Module
  // Converts to DPI calls
  logic [1:0] debug_req_bits_op;
  assign dmi_req.op = dm::dtm_op_t'(debug_req_bits_op );

  if (InclSimDTM) begin
    SimDTM i_SimDTM (
      .clk                 (clk_i            ),
      .reset               (~rst_ni          ),
      .debug_req_valid     (dmi_req_valid    ),
      .debug_req_ready     (debug_req_ready  ),
      .debug_req_bits_addr (dmi_req.addr     ),
      .debug_req_bits_op   (debug_req_bits_op),
      .debug_req_bits_data (dmi_req.data     ),
      .debug_resp_valid    (dmi_resp_valid   ),
      .debug_resp_ready    (dmi_resp_ready   ),
      .debug_resp_bits_resp(debug_resp.resp  ),
      .debug_resp_bits_data(debug_resp.data  ),
      .exit                (dmi_exit         )
    );
  end else begin
    assign dmi_req_valid     = '0  ;
    assign debug_req_bits_op = '0  ;
    assign dmi_exit          = 1'b0;
  end

  ariane_axi::req_t dm_axi_m_req  , dm_axi_s_req ;
  ariane_axi::resp_t dm_axi_m_resp, dm_axi_s_resp;

  logic            dm_slave_req;
  logic            dm_slave_we;
  logic [64-1:0]   dm_slave_addr;
  logic [64/8-1:0] dm_slave_be;
  logic [64-1:0]   dm_slave_wdata;
  logic [64-1:0]   dm_slave_rdata;

  logic            dm_master_req;
  logic [64-1:0]   dm_master_add;
  logic            dm_master_we;
  logic [64-1:0]   dm_master_wdata;
  logic [64/8-1:0] dm_master_be;
  logic            dm_master_gnt;
  logic            dm_master_r_valid;
  logic [64-1:0]   dm_master_r_rdata;


  // debug module
  dm_top #(
    .NrHarts         (1                    ),
    .BusWidth        (AXI_NARROW_DATA_WIDTH),
    .Selectable_Harts(1'b1                 )
  ) i_dm_top (
    .clk_i           ( clk_i            ),
    .rst_ni          ( rst_ni           ), // PoR
    .testmode_i      ( test_en          ),
    .ndmreset_o      ( ndmreset         ),
    .dmactive_o      (                  ), // active debug session
    .debug_req_o     ( debug_req_core   ),
    .unavailable_i   ( '0               ),
    .slave_req_i     ( dm_slave_req     ),
    .slave_we_i      ( dm_slave_we      ),
    .slave_addr_i    ( dm_slave_addr    ),
    .slave_be_i      ( dm_slave_be      ),
    .slave_wdata_i   ( dm_slave_wdata   ),
    .slave_rdata_o   ( dm_slave_rdata   ),
    .master_req_o    ( dm_master_req    ),
    .master_add_o    ( dm_master_add    ),
    .master_we_o     ( dm_master_we     ),
    .master_wdata_o  ( dm_master_wdata  ),
    .master_be_o     ( dm_master_be     ),
    .master_gnt_i    ( dm_master_gnt    ),
    .master_r_valid_i( dm_master_r_valid),
    .master_r_rdata_i( dm_master_r_rdata),
    .dmi_rst_ni      ( rst_ni           ),
    .dmi_req_valid_i ( debug_req_valid  ),
    .dmi_req_ready_o ( debug_req_ready  ),
    .dmi_req_i       ( debug_req        ),
    .dmi_resp_valid_o( debug_resp_valid ),
    .dmi_resp_ready_i( debug_resp_ready ),
    .dmi_resp_o      ( debug_resp       )
  );

  axi2mem #(
    .AXI_ID_WIDTH  (ariane_soc::IdWidthSlave),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH       ),
    .AXI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH   ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH          )
  ) i_dm_axi2mem (
    .clk_i (clk_i                           ),
    .rst_ni(rst_ni                          ),
    .slave (narrow_master[ariane_soc::Debug]),
    .req_o (dm_slave_req                    ),
    .we_o  (dm_slave_we                     ),
    .addr_o(dm_slave_addr                   ),
    .be_o  (dm_slave_be                     ),
    .data_o(dm_slave_wdata                  ),
    .data_i(dm_slave_rdata                  )
  );

  axi_master_connect i_dm_axi_master_connect (
    .axi_req_i (dm_axi_m_req   ),
    .axi_resp_o(dm_axi_m_resp  ),
    .master    (narrow_slave[2])
  );

  axi_adapter #(.DATA_WIDTH(AXI_NARROW_DATA_WIDTH)) i_dm_axi_master (
    .clk_i                ( clk_i                 ),
    .rst_ni               ( rst_ni                ),
    .req_i                ( dm_master_req         ),
    .type_i               ( ariane_axi::SINGLE_REQ),
    .gnt_o                ( dm_master_gnt         ),
    .gnt_id_o             (                       ),
    .addr_i               ( dm_master_add         ),
    .we_i                 ( dm_master_we          ),
    .wdata_i              ( dm_master_wdata       ),
    .be_i                 ( dm_master_be          ),
    .size_i               ( 2'b11                 ), // always do 64bit here and use byte enables to gate
    .id_i                 ( '0                    ),
    .valid_o              ( dm_master_r_valid     ),
    .rdata_o              ( dm_master_r_rdata     ),
    .id_o                 (                       ),
    .critical_word_o      (                       ),
    .critical_word_valid_o(                       ),
    .axi_req_o            ( dm_axi_m_req          ),
    .axi_resp_i           ( dm_axi_m_resp         )
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .MI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .ID_WIDTH     (AXI_ID_WIDTH         ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_master_dm_dwc (
    .clk_i ,
    .rst_ni ,
    .slv (narrow_slave[2]),
    .mst (slave[2]       )
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_dm_dwc (
    .clk_i ,
    .rst_ni ,
    .slv (master[ariane_soc::Debug]       ),
    .mst (narrow_master[ariane_soc::Debug])
  );

  /*********
   *  ROM  *
   *********/
  logic                             rom_req;
  logic [AXI_ADDRESS_WIDTH-1:0]     rom_addr;
  logic [AXI_NARROW_DATA_WIDTH-1:0] rom_rdata;

  axi2mem #(
    .AXI_ID_WIDTH  (AXI_ID_WIDTH_SLAVES  ),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH    ),
    .AXI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH       )
  ) i_axi2rom (
    .clk_i ( clk_i                         ),
    .rst_ni( ndmreset_n                    ),
    .slave ( narrow_master[ariane_soc::ROM]),
    .req_o ( rom_req                       ),
    .we_o  (                               ),
    .addr_o( rom_addr                      ),
    .be_o  (                               ),
    .data_o(                               ),
    .data_i( rom_rdata                     )
  );

  bootrom i_bootrom (
    .clk_i  (clk_i    ),
    .req_i  (rom_req  ),
    .addr_i (rom_addr ),
    .rdata_o(rom_rdata)
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_bootrom_dwc (
    .clk_i ,
    .rst_ni ,
    .slv (master[ariane_soc::ROM]       ),
    .mst (narrow_master[ariane_soc::ROM])
  );

  /********
   *  L2  *
   ********/

  logic                         req ;
  logic                         we ;
  logic [AXI_ADDRESS_WIDTH-1:0] addr ;
  logic [AXI_DATA_WIDTH/8-1:0]  be ;
  logic [AXI_DATA_WIDTH-1:0]    wdata;
  logic [AXI_DATA_WIDTH-1:0]    rdata;

  axi2mem #(
    .AXI_ID_WIDTH  (AXI_ID_WIDTH_SLAVES),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH  ),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH     ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH     )
  ) i_axi2mem (
    .clk_i (clk_i                   ),
    .rst_ni(ndmreset_n              ),
    .slave (master[ariane_soc::DRAM]),
    .req_o (req                     ),
    .we_o  (we                      ),
    .addr_o(addr                    ),
    .be_o  (be                      ),
    .data_o(wdata                   ),
    .data_i(rdata                   )
  );

  sram #(
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_WORDS (NUM_WORDS     )
  ) i_sram (
    .clk_i  (clk_i                                                                      ),
    .rst_ni (rst_ni                                                                     ),
    .req_i  (req                                                                        ),
    .we_i   (we                                                                         ),
    .addr_i (addr[$clog2(NUM_WORDS)-1+$clog2(AXI_DATA_WIDTH/8):$clog2(AXI_DATA_WIDTH/8)]),
    .wdata_i(wdata                                                                      ),
    .be_i   (be                                                                         ),
    .rdata_o(rdata                                                                      )
  );

  /**************
   *  AXI XBAR  *
   **************/

  axi_node_intf_wrap #(
    .NB_SLAVE       ( NB_SLAVE                   ),
    .NB_MASTER      ( ariane_soc::NB_PERIPHERALS ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH          ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH             ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH             ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH               )
  ) i_axi_xbar (
    .clk       ( clk_i      ),
    .rst_n     ( ndmreset_n ),
    .test_en_i ( test_en    ),
    .slave     ( slave      ),
    .master    ( master     ),
    .start_addr_i ({
        ariane_soc::DebugBase   ,
        ariane_soc::ROMBase     ,
        ariane_soc::CLINTBase   ,
        ariane_soc::PLICBase    ,
        ariane_soc::UARTBase    ,
        ariane_soc::SPIBase     ,
        ariane_soc::EthernetBase,
        ariane_soc::GPIOBase    ,
        ariane_soc::DRAMBase
      }),
    .end_addr_i ({
        ariane_soc::DebugBase + ariane_soc::DebugLength - 1      ,
        ariane_soc::ROMBase + ariane_soc::ROMLength - 1          ,
        ariane_soc::CLINTBase + ariane_soc::CLINTLength - 1      ,
        ariane_soc::PLICBase + ariane_soc::PLICLength - 1        ,
        ariane_soc::UARTBase + ariane_soc::UARTLength - 1        ,
        ariane_soc::SPIBase + ariane_soc::SPILength - 1          ,
        ariane_soc::EthernetBase + ariane_soc::EthernetLength - 1,
        ariane_soc::GPIOBase + ariane_soc::GPIOLength - 1        ,
        ariane_soc::DRAMBase + ariane_soc::DRAMLength - 1
      }),
    .valid_rule_i (ariane_soc::ValidRule)
  );

  /***********
   *  CLINT  *
   ***********/

  logic ipi;
  logic timer_irq;

  ariane_axi::req_t axi_clint_req  ;
  ariane_axi::resp_t axi_clint_resp;

  clint #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH    ),
    .AXI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH_SLAVES  ),
    .NR_CORES      (1                    )
  ) i_clint (
    .clk_i      (clk_i         ),
    .rst_ni     (ndmreset_n    ),
    .testmode_i (test_en       ),
    .axi_req_i  (axi_clint_req ),
    .axi_resp_o (axi_clint_resp),
    .rtc_i      (rtc_i         ),
    .timer_irq_o(timer_irq     ),
    .ipi_o      (ipi           )
  );

  axi_slave_connect i_axi_slave_connect_clint (
    .axi_req_o (axi_clint_req                   ),
    .axi_resp_i(axi_clint_resp                  ),
    .slave     (narrow_master[ariane_soc::CLINT])
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_clint_dwc (
    .clk_i  (clk_i                           ) ,
    .rst_ni (rst_ni                          ),
    .slv    (master[ariane_soc::CLINT]       ),
    .mst    (narrow_master[ariane_soc::CLINT])
  );

  /*****************
   *  PERIPHERALS  *
   *****************/

  logic       tx, rx;
  logic [1:0] irqs;

  ariane_peripherals #(
    .AxiAddrWidth(AXI_ADDRESS_WIDTH    ),
    .AxiDataWidth(AXI_NARROW_DATA_WIDTH),
    .AxiIdWidth  (AXI_ID_WIDTH_SLAVES  ),
    .InclUART    (1'b0                 ),
    .InclSPI     (1'b0                 ),
    .InclEthernet(1'b0                 )
  ) i_ariane_peripherals (
    .clk_i    ( clk_i                              ),
    .rst_ni   ( ndmreset_n                         ),
    .plic     ( narrow_master[ariane_soc::PLIC]    ),
    .uart     ( narrow_master[ariane_soc::UART]    ),
    .spi      ( narrow_master[ariane_soc::SPI]     ),
    .ethernet ( narrow_master[ariane_soc::Ethernet]),
    .irq_o    ( irqs                               ),
    .rx_i     ( rx                                 ),
    .tx_o     ( tx                                 ),
    .eth_txck (                                    ),
    .eth_rxck (                                    ),
    .eth_rxctl(                                    ),
    .eth_rxd  (                                    ),
    .eth_rst_n(                                    ),
    .eth_tx_en(                                    ),
    .eth_txd  (                                    ),
    .phy_mdio (                                    ),
    .eth_mdc  (                                    ),
    .mdio     (                                    ),
    .mdc      (                                    ),
    .spi_clk_o(                                    ),
    .spi_mosi (                                    ),
    .spi_miso (                                    ),
    .spi_ss   (                                    )
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_plic_dwc (
    .clk_i  (clk_i                          ),
    .rst_ni (rst_ni                         ),
    .slv    (master[ariane_soc::PLIC]       ),
    .mst    (narrow_master[ariane_soc::PLIC])
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_uart_dwc (
    .clk_i  (clk_i                          ),
    .rst_ni (rst_ni                         ),
    .slv    (master[ariane_soc::UART]       ),
    .mst    (narrow_master[ariane_soc::UART])
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_spi_dwc (
    .clk_i  (clk_i                         ),
    .rst_ni (rst_ni                        ),
    .slv    (master[ariane_soc::SPI]       ),
    .mst    (narrow_master[ariane_soc::SPI])
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .MI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .ID_WIDTH     (AXI_ID_WIDTH_SLAVES  ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_slave_ethernet_dwc (
    .clk_i  (clk_i                              ),
    .rst_ni (rst_ni                             ),
    .slv    (master[ariane_soc::Ethernet]       ),
    .mst    (narrow_master[ariane_soc::Ethernet])
  );

  uart_bus #(
    .BAUD_RATE(115200),
    .PARITY_EN(0     )
  ) i_uart_bus (
    .rx   (tx  ),
    .tx   (rx  ),
    .rx_en(1'b1)
  );

  /**********
   *  CORE  *
   **********/

  ariane_axi::req_t axi_ariane_req  ;
  ariane_axi::resp_t axi_ariane_resp;

  ara_axi_pkg::axi_req_t axi_ara_req  ;
  ara_axi_pkg::axi_resp_t axi_ara_resp;

  ara_system #(
    `ifdef PITON_ARIANE
    .SwapEndianess(0                                              ),
    .CachedAddrEnd((ariane_soc::DRAMBase + ariane_soc::DRAMLength)),
    `endif
    .CachedAddrBeg(ariane_soc::DRAMBase )
  ) i_ara_system (
    .clk_i         (clk_i              ),
    .rst_ni        (ndmreset_n         ),
    .boot_addr_i   (ariane_soc::ROMBase), // start fetching from ROM
    .hart_id_i     ('0                 ),
    .irq_i         (irqs               ),
    .ipi_i         (ipi                ),
    .time_irq_i    (timer_irq          ),
    .debug_req_i   (debug_req_core     ),
    .axi_req_o     (axi_ariane_req     ),
    .axi_resp_i    (axi_ariane_resp    ),
    .ara_axi_req_o (axi_ara_req        ),
    .ara_axi_resp_i(axi_ara_resp       )
  );

  ara_axi_master_connect i_axi_master_connect_ara (
    .axi_req_i (axi_ara_req ),
    .axi_resp_o(axi_ara_resp),
    .master    (ara_cuts[1] )
  );

  axi_master_connect i_axi_master_connect_ariane (
    .axi_req_i (axi_ariane_req ),
    .axi_resp_o(axi_ariane_resp),
    .master    (narrow_slave[0])
  );

  axi_data_width_converter #(
    .SI_DATA_WIDTH(AXI_NARROW_DATA_WIDTH),
    .MI_DATA_WIDTH(AXI_DATA_WIDTH       ),
    .ID_WIDTH     (AXI_ID_WIDTH         ),
    .USER_WIDTH   (AXI_USER_WIDTH       )
  ) i_axi_master_ariane_dwc (
    .clk_i  (clk_i          ),
    .rst_ni (rst_ni         ),
    .slv    (narrow_slave[0]),
    .mst    (ara_cuts[0]    )
  );

  for (genvar i = 0; i < NB_SLAVE-1; i++) begin: gen_cuts
    axi_multicut #(
      .ADDR_WIDTH(AXI_ADDRESS_WIDTH),
      .DATA_WIDTH(AXI_DATA_WIDTH   ),
      .ID_WIDTH  (AXI_ID_WIDTH     ),
      .USER_WIDTH(AXI_USER_WIDTH   ),
      .NUM_CUTS  (1                )
    ) i_cut (
      .clk_i (clk_i      ),
      .rst_ni(rst_ni     ),
      .in    (ara_cuts[i]),
      .out   (slave[i]   )
    );
  end : gen_cuts

  // PROBES
  `ifdef PROBES

  `ARA_PROBE(axi_ara_resp.r_valid, "VLD")
  `ARA_PROBE(axi_ara_req.w_valid, "VST")
  `ARA_PROBE(i_ara_system.i_ara.lane[0].i_lane.i_vex_stage.fpu_result_gnt_i, "VFPU")

  `endif

endmodule : ara_testharness
