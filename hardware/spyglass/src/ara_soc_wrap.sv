// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description: Ara-SoC wrap for SpyGlass analysis.

module ara_soc_wrap (
 input logic clk_i,
 input logic rst_ni
);

  localparam int unsigned NrLanes      = `NR_LANES;
  localparam int unsigned AxiAddrWidth = 64;
  localparam int unsigned AxiDataWidth = 64 * NrLanes / 2;
  localparam int unsigned AxiUserWidth = 1;
  localparam int unsigned AxiIdWidth   = 5;

  logic clk_i, rst_ni;

  ara_soc #(
    .NrLanes     (NrLanes      ),
    .AxiAddrWidth(AxiAddrWidth ),
    .AxiDataWidth(AxiDataWidth ),
    .AxiIdWidth  (AxiIdWidth   ),
    .AxiUserWidth(AxiUserWidth )
  ) i_ara_soc (
    .clk_i         (clk_i       ),
    .rst_ni        (rst_ni      ),
    .scan_enable_i (1'b0        ),
    .scan_data_i   (1'b0        ),
    .uart_prdata_i ('0          ),
    .uart_pready_i ('0          ),
    .uart_pslverr_i('0          )
  );

endmodule
