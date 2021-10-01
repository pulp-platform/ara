// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description: Test harness for Ara.
//              This is loosely based on CVA6's test harness.
//              Instantiates an AXI-Bus and memories.

module ara_testharness #(
    // Ara-specific parameters
    parameter int unsigned NrLanes      = 0,
    // AXI Parameters
    parameter int unsigned AxiUserWidth = 1,
    parameter int unsigned AxiIdWidth   = 5,
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiDataWidth = 64*NrLanes/2
  ) (
    input  logic        clk_i,
    input  logic        rst_ni,
    output logic [63:0] exit_o
  );

  `include "axi/typedef.svh"

  /*****************
   *  Definitions  *
   *****************/

  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiDataWidth/8-1:0] axi_strb_t;
  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  typedef logic [AxiIdWidth-1:0] axi_id_t;

  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, axi_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(axi_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_resp_t, b_chan_t, r_chan_t)

  /*************
   *  Signals  *
   *************/

  // UART
  logic        uart_penable;
  logic        uart_pwrite;
  logic [31:0] uart_paddr;
  logic        uart_psel;
  logic [31:0] uart_pwdata;
  logic [31:0] uart_prdata;
  logic        uart_pready;
  logic        uart_pslverr;

  // AXI
  axi_req_t  dram_req;
  axi_resp_t dram_resp;

  /*********
   *  SoC  *
   *********/

  ara_soc #(
    .NrLanes     (NrLanes      ),
    .AxiAddrWidth(AxiAddrWidth ),
    .AxiDataWidth(AxiDataWidth ),
    .AxiIdWidth  (AxiIdWidth   ),
    .AxiUserWidth(AxiUserWidth )
  ) i_ara_soc (
    .clk_i         (clk_i       ),
    .rst_ni        (rst_ni      ),
    .exit_o        (exit_o      ),
    .scan_enable_i (1'b0        ),
    .scan_data_i   (1'b0        ),
    .scan_data_o   (/* Unused */),
    // UART
    .uart_penable_o(uart_penable),
    .uart_pwrite_o (uart_pwrite ),
    .uart_paddr_o  (uart_paddr  ),
    .uart_psel_o   (uart_psel   ),
    .uart_pwdata_o (uart_pwdata ),
    .uart_prdata_i (uart_prdata ),
    .uart_pready_i (uart_pready ),
    .uart_pslverr_i(uart_pslverr)
  );

  /**********
   *  UART  *
   **********/

  mock_uart i_mock_uart (
    .clk_i    (clk_i       ),
    .rst_ni   (rst_ni      ),
    .penable_i(uart_penable),
    .pwrite_i (uart_pwrite ),
    .paddr_i  (uart_paddr  ),
    .psel_i   (uart_psel   ),
    .pwdata_i (uart_pwdata ),
    .prdata_o (uart_prdata ),
    .pready_o (uart_pready ),
    .pslverr_o(uart_pslverr)
  );

endmodule : ara_testharness
