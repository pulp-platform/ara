// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Technology-agnostic replacement for a clock-gating cell

module clk_gating_generic (
  input  logic CLK,
  input  logic TE,
  input  logic E,
  output logic Z
);

  assign Z = E & CLK;

endmodule
