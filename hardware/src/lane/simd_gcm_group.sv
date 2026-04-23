// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
//   Combinational Zvkg vector-crypto element-group datapath.
//   Operates on a single 128-bit element group (EGS=4 x SEW=32) and
//   implements the two Zvkg instructions:
//     - VGHSH_VV: vd = brev8( GFMUL( brev8(vd ^ vs1), brev8(vs2) ) )
//     - VGMUL_VV: vd = brev8( GFMUL( brev8(vd)       , brev8(vs2) ) )
//   GFMUL is GF(2^128) multiplication with reduction polynomial
//   x^128 + x^7 + x^2 + x + 1 (low-byte XOR constant = 8'h87).
//
//   This module is fully combinational; 128-iter shift/XOR unrolled.
//   If it does not close timing, the caller can pipeline it by
//   registering inputs, outputs, or one of the H_iter/Z_iter midpoints.

module simd_gcm_group
  import ara_pkg::*;
  import rvv_pkg::*;
(
  // Selects VGHSH_VV or VGMUL_VV.
  input  ara_op_e          op_i,
  // One element group (4 SEW=32 elements) from each source.
  //   vd_group_i  : current partial hash Y (also the multiplier for vgmul)
  //   vs2_group_i : hash subkey / multiplicand H
  //   vs1_group_i : cipher-text / AAD block X (used only by vghsh; ignored for vgmul)
  input  logic [3:0][31:0] vd_group_i,
  input  logic [3:0][31:0] vs2_group_i,
  input  logic [3:0][31:0] vs1_group_i,
  // One element group of result words.
  output logic [3:0][31:0] result_group_o
);

  // Byte-wise bit reversal of a 128-bit value.
  function automatic logic [127:0] brev8_128(input logic [127:0] x);
    logic [127:0] r;
    for (int b = 0; b < 16; b++) begin
      for (int i = 0; i < 8; i++) begin
        r[b*8 + i] = x[b*8 + (7 - i)];
      end
    end
    return r;
  endfunction

  logic [127:0] packed_Y;
  logic [127:0] packed_H;
  logic [127:0] packed_X;
  logic [127:0] packed_M;
  logic [127:0] packed_S;
  logic [127:0] packed_H_brev;
  logic [127:0] packed_Z_out;

  always_comb begin
    // Pack the element group into a 128-bit word (element 0 = LSBs).
    packed_Y = vd_group_i;
    packed_H = vs2_group_i;
    packed_X = vs1_group_i;

    // Multiplier S: vgmul -> Y, vghsh -> Y ^ X. brev8 applied post-XOR.
    packed_M = (op_i == VGHSH_VV) ? (packed_Y ^ packed_X) : packed_Y;

    // brev8 pre-step on multiplier and multiplicand.
    packed_S      = brev8_128(packed_M);
    packed_H_brev = brev8_128(packed_H);

    // 128-iteration shift-and-XOR GF(2^128) multiply.
    begin
      automatic logic [127:0] H_cur;
      automatic logic [127:0] Z_cur;
      automatic logic         reduce;
      H_cur = packed_H_brev;
      Z_cur = 128'h0;
      for (int b = 0; b < 128; b++) begin
        if (packed_S[b]) Z_cur = Z_cur ^ H_cur;
        reduce = H_cur[127];
        H_cur  = H_cur << 1;
        if (reduce) H_cur = H_cur ^ 128'h87;
      end
      // brev8 post-step.
      packed_Z_out = brev8_128(Z_cur);
    end

    // Unpack back to 4 x 32-bit element group.
    for (int i = 0; i < 4; i++) begin
      result_group_o[i] = packed_Z_out[i*32 +: 32];
    end
  end

endmodule
