// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Power-of-two stride generator and sequencer
// Load a new stride with stride_valid_i
// Generate the next power-of-two stride with update_i
// valid_o asserted if stride_p2_o is non-zero

module p2_stride_gen import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
  parameter integer unsigned NrLanes = 0
) (
  input  logic                                     clk_i,
  input  logic                                     rst_ni,
  input  logic          [idx_width(8*NrLanes)-1:0] stride_i,
  input  logic                                     valid_i,
  input  logic                                     update_i,
  output logic [idx_width(idx_width(8*NrLanes)):0] popc_o,
  output logic          [idx_width(8*NrLanes)-1:0] stride_p2_o,
  output logic                                     valid_o
);

  `include "common_cells/registers.svh"

  logic   [idx_width(idx_width(8*NrLanes)):0] popc_d, popc_q;
  logic [idx_width(idx_width(8*NrLanes))-1:0] next_stride_first_d, next_stride_first_q;
  logic            [idx_width(8*NrLanes)-1:0] next_spare_stride, next_stride;
  logic            [idx_width(8*NrLanes)-1:0] spare_stride_d, spare_stride_q;
  logic                                       ff_en, next_stride_zero_d, next_stride_zero_q;

  assign next_stride = valid_i ? stride_i : next_spare_stride;
  assign next_spare_stride = spare_stride_q ^ stride_p2_o;
  assign popc_o  = popc_q;
  assign ff_en   = valid_i | update_i;
  assign valid_o = ~next_stride_zero_q;
  assign spare_stride_d = next_stride;

  `FFL(             popc_q,              popc_d, ff_en, '0);
  `FFL(next_stride_first_q, next_stride_first_d, ff_en, '0);
  `FFL( next_stride_zero_q,  next_stride_zero_d, ff_en, '0);
  `FFL(     spare_stride_q,      spare_stride_d, ff_en, '0);

  // Is the stride power of two?
  popcount #(
    .INPUT_WIDTH (idx_width(8*NrLanes))
  ) i_sldu_stride_popc (
    .data_i     (next_stride),
    .popcount_o (popc_d     )
  );

  // Where is the first one in the stride?
  lzc #(
    .WIDTH (idx_width(8*NrLanes)),
    .MODE  (0                   )
  ) i_sldu_stride_clz (
    .in_i    (next_stride        ),
    .cnt_o   (next_stride_first_d),
    .empty_o (next_stride_zero_d )
  );

  always_comb begin
    stride_p2_o = '0;
    for (int b = 0; b < idx_width(8*NrLanes); b++)
      if (b == next_stride_first_q)
        stride_p2_o[b] = ~next_stride_zero_q;
  end

endmodule
