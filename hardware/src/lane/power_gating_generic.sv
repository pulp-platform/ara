// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Technology-agnostic replacement for a glitch-free gating combinatorial cell

module power_gating_generic #(
  parameter type         T = logic,
  parameter int  NO_GLITCH = 0
) (
  input  T     in_i,
  input  logic en_i,
  output T     out_o
);

  T en_wide;

  // Gate with an AND
  assign en_wide = en_i ? T'('1) : T'('0);
  assign out_o   = T'(in_i & en_wide);

endmodule
