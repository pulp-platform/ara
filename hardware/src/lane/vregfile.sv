// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Matheus Cavalcante, ETH Zurich
//
// Generic vector register file that makes use of latches to store data.

module vregfile import ara_pkg::*; #(
    parameter int  unsigned NrReadPorts = 0,
    parameter int  unsigned NrWords     = 32,
    parameter int  unsigned WordWidth   = ELEN,
    // Derived parameters.  Do not change!
    parameter type          addr_t      = logic[$clog2(NrWords)-1:0],
    parameter type          data_t      = logic [WordWidth-1:0],
    parameter type          strb_t      = logic [WordWidth/8-1:0]
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    testmode_i,
    // Write ports
    input  addr_t                   waddr_i,
    input  data_t                   wdata_i,
    input  logic                    we_i,
    input  strb_t                   wbe_i,
    // Read ports
    input  addr_t [NrReadPorts-1:0] raddr_i,
    output data_t [NrReadPorts-1:0] rdata_o
  );

  /////////////
  // Signals //
  /////////////

  // Gated clock
  logic clk;

  // Register file memory
  logic [NrWords-1:0][WordWidth/8-1:0][7:0] mem;

  // Write data sampling
  data_t wdata_q;

  ///////////////////
  // Register File //
  ///////////////////

  // First-level clock gate
  tc_clk_gating i_first_level_cg (
    .clk_i    (clk_i     ),
    .en_i     (|we_i     ),
    .test_en_i(testmode_i),
    .clk_o    (clk       )
  );

  // Sample Input Data
  always_ff @(posedge clk) begin
    wdata_q <= wdata_i;
  end

  // Row decoder. Create a clock for each SCM row
  logic [NrWords-1:0] row_clk;
  for (genvar row = 0; row < NrWords; row++) begin: gen_row_decoder
    // Create latch clock signal
    logic row_onehot;
    assign row_onehot = (waddr_i == row);

    // Create a clock for each SCM row
    tc_clk_gating i_waddr_cg (
      .clk_i    (clk         ),
      .en_i     (row_onehot  ),
      .test_en_i(testmode_i  ),
      .clk_o    (row_clk[row])
    );
  end: gen_row_decoder

  // Column decoder. Create a clock for each SCM column
  logic [WordWidth/8-1:0] col_clk;
  for (genvar b = 0; b < WordWidth/8; b++) begin: gen_col_decoder
    tc_clk_gating i_wbe_cg (
      .clk_i    (clk       ),
      .en_i     (wbe_i[b]  ),
      .test_en_i(testmode_i),
      .clk_o    (col_clk[b])
    );
  end: gen_col_decoder

  // Select which destination bytes to write into

  // Store new data to memory
  /* verilator lint_off NOLATCH */
  for (genvar vreg = 0; vreg < NrWords; vreg++) begin: gen_write_mem
    for (genvar b = 0; b < WordWidth/8; b++) begin: gen_word
      logic clk_latch;
      tc_clk_and2 i_clk_and (
        .clk0_i(row_clk[vreg]),
        .clk1_i(col_clk[b]   ),
        .clk_o (clk_latch    )
      );

      always_latch begin
        if (clk_latch)
          mem[vreg][b] <= wdata_q[b*8 +: 8];
      end
    end: gen_word
  end: gen_write_mem
  /* verilator lint_on NOLATCH */

  // Read data from memory
  for (genvar port = 0; port < NrReadPorts; port++) begin: gen_read_mem
    // Reuse the decision tree from the RR arbiter
    rr_arb_tree #(
      .AxiVldRdy(1'b1     ),
      .ExtPrio  (1'b1     ),
      .DataWidth(WordWidth),
      .NumIn    (NrWords  )
    ) i_read_tree (
      .clk_i  (clk_i        ),
      .rst_ni (rst_ni       ),
      .flush_i(1'b0         ),
      .idx_o  (/* Unused */ ),
      .data_i (mem          ),
      .rr_i   (raddr_i[port]),
      .data_o (rdata_o[port]),
      .req_i  ('1),
      .gnt_o  (/* Unused */ ),
      .req_o  (/* Unused */ ),
      .gnt_i  (1'b1         )
    );
  end: gen_read_mem

endmodule : vregfile
