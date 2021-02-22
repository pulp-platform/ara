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
    parameter int unsigned NumWords     = 2**21, // memory size
    // AXI Parameters
    parameter int unsigned AxiUserWidth = 1,
    parameter int unsigned AxiIdWidth   = 6,
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiDataWidth = 64*NrLanes/2
  ) (
    input  logic        clk_i,
    input  logic        rst_ni,
    output logic [63:0] exit_o
  );

  `include "axi/typedef.svh"
  `include "common_cells/registers.svh"

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
    .clk_i          (clk_i             ),
    .rst_ni         (rst_ni            ),
    .exit_o         (exit_o            ),
    .scan_enable_i  (1'b0              ),
    .scan_data_i    (1'b0              ),
    .scan_data_o    (/* Unused */      ),
    // UART
    .uart_penable_o (uart_penable      ),
    .uart_pwrite_o  (uart_pwrite       ),
    .uart_paddr_o   (uart_paddr        ),
    .uart_psel_o    (uart_psel         ),
    .uart_pwdata_o  (uart_pwdata       ),
    .uart_prdata_i  (uart_prdata       ),
    .uart_pready_i  (uart_pready       ),
    .uart_pslverr_i (uart_pslverr      ),
    // AXI
    .axi_aw_valid_o (dram_req.aw_valid ),
    .axi_aw_id_o    (dram_req.aw.id    ),
    .axi_aw_addr_o  (dram_req.aw.addr  ),
    .axi_aw_len_o   (dram_req.aw.len   ),
    .axi_aw_size_o  (dram_req.aw.size  ),
    .axi_aw_burst_o (dram_req.aw.burst ),
    .axi_aw_lock_o  (dram_req.aw.lock  ),
    .axi_aw_cache_o (dram_req.aw.cache ),
    .axi_aw_prot_o  (dram_req.aw.prot  ),
    .axi_aw_qos_o   (dram_req.aw.qos   ),
    .axi_aw_region_o(dram_req.aw.region),
    .axi_aw_atop_o  (dram_req.aw.atop  ),
    .axi_aw_user_o  (dram_req.aw.user  ),
    .axi_aw_ready_i (dram_resp.aw_ready),
    .axi_w_valid_o  (dram_req.w_valid  ),
    .axi_w_data_o   (dram_req.w.data   ),
    .axi_w_strb_o   (dram_req.w.strb   ),
    .axi_w_last_o   (dram_req.w.last   ),
    .axi_w_user_o   (dram_req.w.user   ),
    .axi_w_ready_i  (dram_resp.w_ready ),
    .axi_b_valid_i  (dram_resp.b_valid ),
    .axi_b_id_i     (dram_resp.b.id    ),
    .axi_b_resp_i   (dram_resp.b.resp  ),
    .axi_b_user_i   (dram_resp.b.user  ),
    .axi_b_ready_o  (dram_req.b_ready  ),
    .axi_ar_valid_o (dram_req.ar_valid ),
    .axi_ar_id_o    (dram_req.ar.id    ),
    .axi_ar_addr_o  (dram_req.ar.addr  ),
    .axi_ar_len_o   (dram_req.ar.len   ),
    .axi_ar_size_o  (dram_req.ar.size  ),
    .axi_ar_burst_o (dram_req.ar.burst ),
    .axi_ar_lock_o  (dram_req.ar.lock  ),
    .axi_ar_cache_o (dram_req.ar.cache ),
    .axi_ar_prot_o  (dram_req.ar.prot  ),
    .axi_ar_qos_o   (dram_req.ar.qos   ),
    .axi_ar_region_o(dram_req.ar.region),
    .axi_ar_user_o  (dram_req.ar.user  ),
    .axi_ar_ready_i (dram_resp.ar_ready),
    .axi_r_valid_i  (dram_resp.r_valid ),
    .axi_r_data_i   (dram_resp.r.data  ),
    .axi_r_id_i     (dram_resp.r.id    ),
    .axi_r_resp_i   (dram_resp.r.resp  ),
    .axi_r_last_i   (dram_resp.r.last  ),
    .axi_r_user_i   (dram_resp.r.user  ),
    .axi_r_ready_o  (dram_req.r_ready  )
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

  /**********
   *  DRAM  *
   **********/

  logic                      req;
  logic                      we;
  logic [AxiAddrWidth-1:0]   addr;
  logic [AxiDataWidth/8-1:0] be;
  logic [AxiDataWidth-1:0]   wdata;
  logic [AxiDataWidth-1:0]   rdata;
  logic                      rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth),
    .DataWidth (AxiDataWidth),
    .IdWidth   (AxiIdWidth  ),
    .NumBanks  (1           ),
    .axi_req_t (axi_req_t   ),
    .axi_resp_t(axi_resp_t  )
  ) i_axi_to_mem (
    .clk_i       (clk_i       ),
    .rst_ni      (rst_ni      ),
    .axi_req_i   (dram_req    ),
    .axi_resp_o  (dram_resp   ),
    .mem_req_o   (req         ),
    .mem_gnt_i   (req         ), // Always available
    .mem_we_o    (we          ),
    .mem_addr_o  (addr        ),
    .mem_strb_o  (be          ),
    .mem_wdata_o (wdata       ),
    .mem_rdata_i (rdata       ),
    .mem_rvalid_i(rvalid      ),
    .mem_atop_o  (/* Unused */),
    .busy_o      (/* Unused */)
  );

  tc_sram #(
    .NumWords (NumWords    ),
    .NumPorts (1           ),
    .DataWidth(AxiDataWidth)
  ) i_dram (
    .clk_i  (clk_i                                                                 ),
    .rst_ni (rst_ni                                                                ),
    .req_i  (req                                                                   ),
    .we_i   (we                                                                    ),
    .addr_i (addr[$clog2(NumWords)-1+$clog2(AxiDataWidth/8):$clog2(AxiDataWidth/8)]),
    .wdata_i(wdata                                                                 ),
    .be_i   (be                                                                    ),
    .rdata_o(rdata                                                                 )
  );

  // One-cycle latency
  `FF(rvalid, req, 1'b0);

endmodule : ara_testharness
