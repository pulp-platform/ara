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
    parameter int unsigned AxiDataWidth = 64*NrLanes/2,
    // AXI Resp Delay [ps] for gate-level simulation
    parameter int unsigned AxiRespDelay = 200
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
    .AxiUserWidth(AxiUserWidth ),
    .AxiRespDelay(AxiRespDelay )
  ) i_ara_soc (
    .clk_i         (clk_i       ),
    .rst_ni        (rst_ni      ),
    .hw_cnt_en_o   (/* Unused */),
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

`ifndef TARGET_GATESIM

  /***************
   *  V_RUNTIME  *
   ***************/

  // Software runtime measurements are not precise since there is some overhead when the vector
  // function starts and when it's over. Moreover, the csr value should be retreived.
  // When the vector function runtime is short, these overhead can compromise the measurement.
  // This is a way to measure the runtime more precisely.
  //
  // The vector runtime counter starts counting up as soon as the first vector instruction is
  // dispatched to Ara. Then, it will count up forever. When there are no more vector instructions
  // dispatched AND Ara is idle again, the csr runtime is updated.
  // If a new vector instruction is dispathced, the runtime will be updated once again as soon as
  // the previous updating conditions applies again.
  //
  // The counter has now a SW enable. This enable allows the hw-counter to start counting when
  // the start conditions happen.
  //
  // This leads to accurate measurements IF:
  //   1) Every program run contains only a single benchmark to be measured
  //   2) The SW reads the runtime value when Ara is idle and all the vector instructions are over!
  // The last point implies that the function should fence() to let all the vector stores finish,
  // and also depend on the scalar returned value if the last vector instruction is of this type.

  logic [63:0] runtime_cnt_d, runtime_cnt_q;
  logic [63:0] runtime_buf_d, runtime_buf_q;
  logic runtime_cnt_en_d, runtime_cnt_en_q;
  logic	runtime_to_be_updated_d, runtime_to_be_updated_q;

  // The counter can start only if it's enabled. When it's disabled, it will go on counting until
  // the last vector instruciton is over.
  logic cnt_en_mask;
`ifndef IDEAL_DISPATCHER
  assign cnt_en_mask = i_ara_soc.hw_cnt_en_o[0];
`else
  assign cnt_en_mask = 1'b1;
`endif
  always_comb begin
    // Keep the previous value
    runtime_cnt_en_d = runtime_cnt_en_q;
    // If disabled
    if (!runtime_cnt_en_q)
      // Start only if the software allowed the enable and we detect the first V instruction
      runtime_cnt_en_d = i_ara_soc.i_system.i_ara.acc_req_i.req_valid & cnt_en_mask;
    // If enabled
    if (runtime_cnt_en_q)
      // Stop counting only if the software disabled the counter and Ara returned idle
      runtime_cnt_en_d = cnt_en_mask | ~i_ara_soc.i_system.i_ara.ara_idle;
  end

  // Vector runtime counter
  always_comb begin
    runtime_cnt_d = runtime_cnt_q;
    if (runtime_cnt_en_q) runtime_cnt_d = runtime_cnt_q + 1;
  end

  // Update logic
  always_comb begin
    // The following lines allows for SW management of the runtime.
    // Disabled since Verilator is not compatible with the `force` statement
    //// Force the internal runtime CSR to the most updated runtime value
    //force i_ara_soc.i_ctrl_registers.i_axi_lite_regs.reg_q[31:24] = runtime_buf_q;

    // Keep the previous value
    runtime_to_be_updated_d = runtime_to_be_updated_q;

    // Assert the update flag upon a new valid vector instruction
    if (!runtime_to_be_updated_q && i_ara_soc.i_system.i_ara.acc_req_i.req_valid) begin
      runtime_to_be_updated_d = 1'b1;
    end

    // Update the internal runtime and reset the update flag
    if (runtime_to_be_updated_q           &&
        i_ara_soc.i_system.i_ara.ara_idle &&
        !i_ara_soc.i_system.i_ara.acc_req_i.req_valid) begin
      runtime_buf_d = runtime_cnt_q;
      runtime_to_be_updated_d = 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      runtime_cnt_en_q        <= 1'b0;
      runtime_cnt_q           <= '0;
      runtime_to_be_updated_q <= '0;
      runtime_buf_q           <= '0;
   end else begin
      runtime_cnt_en_q        <= runtime_cnt_en_d;
      runtime_cnt_q           <= runtime_cnt_d;
      runtime_to_be_updated_q <= runtime_to_be_updated_d;
      runtime_buf_q           <= runtime_buf_d;
    end
  end

`endif
endmodule : ara_testharness
