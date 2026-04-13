// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
//   Combinational Zvknha/Zvknhb SHA-2 element-group datapath.
//
//   Operates on a 4-element group (EGS=4) of SEW=32 (SHA-256) or SEW=64
//   (SHA-512) words taken from three vector sources (vd, vs2, vs1).
//   Implements the three SHA-2 vector instructions:
//     - VSHA2MS_VV: message schedule (produces w16..w19)
//     - VSHA2CH_VV: two compression rounds using kw2/kw3 slots
//     - VSHA2CL_VV: two compression rounds using kw0/kw1 slots
//
//   All logic is purely combinational; the caller (SLDU) drives one
//   instance per element group per beat.
//
//   The SEW=64 SHA-512 variant is only generated when CryptoSupport
//   includes Zvknhb (i.e. Zvknh512 helper is true).

module simd_sha_group
  import ara_pkg::*;
  import rvv_pkg::*;
#(
  parameter crypto_support_e CryptoSupport = CryptoSupportNone
) (
  // Selects which of VSHA2MS_VV / VSHA2CH_VV / VSHA2CL_VV to run
  input  ara_op_e              op_i,
  // Element width selector (EW32 => SHA-256, EW64 => SHA-512)
  input  rvv_pkg::vew_e        sew_i,
  // One element group (4 elements) from each of the three sources.
  // Each element is placed in the low bits of a 64-bit slot; upper bits
  // are ignored for SEW=32.
  input  logic [3:0][63:0]     vd_group_i,
  input  logic [3:0][63:0]     vs2_group_i,
  input  logic [3:0][63:0]     vs1_group_i,
  // One element group of result words.
  output logic [3:0][63:0]     result_group_o
);

  /////////////////////////
  //  SHA-256 primitives //
  /////////////////////////

  function automatic logic [31:0] ror32(input logic [31:0] x, input int unsigned n);
    ror32 = (x >> n) | (x << (32 - n));
  endfunction

  function automatic logic [31:0] sha256_sum0(input logic [31:0] x);
    sha256_sum0 = ror32(x, 2) ^ ror32(x, 13) ^ ror32(x, 22);
  endfunction

  function automatic logic [31:0] sha256_sum1(input logic [31:0] x);
    sha256_sum1 = ror32(x, 6) ^ ror32(x, 11) ^ ror32(x, 25);
  endfunction

  function automatic logic [31:0] sha256_sig0(input logic [31:0] x);
    sha256_sig0 = ror32(x, 7) ^ ror32(x, 18) ^ (x >> 3);
  endfunction

  function automatic logic [31:0] sha256_sig1(input logic [31:0] x);
    sha256_sig1 = ror32(x, 17) ^ ror32(x, 19) ^ (x >> 10);
  endfunction

  function automatic logic [31:0] ch32(input logic [31:0] x, y, z);
    ch32 = (x & y) ^ (~x & z);
  endfunction

  function automatic logic [31:0] maj32(input logic [31:0] x, y, z);
    maj32 = (x & y) ^ (x & z) ^ (y & z);
  endfunction

  /////////////////////////
  //  SHA-512 primitives //
  /////////////////////////

  function automatic logic [63:0] ror64(input logic [63:0] x, input int unsigned n);
    ror64 = (x >> n) | (x << (64 - n));
  endfunction

  function automatic logic [63:0] sha512_sum0(input logic [63:0] x);
    sha512_sum0 = ror64(x, 28) ^ ror64(x, 34) ^ ror64(x, 39);
  endfunction

  function automatic logic [63:0] sha512_sum1(input logic [63:0] x);
    sha512_sum1 = ror64(x, 14) ^ ror64(x, 18) ^ ror64(x, 41);
  endfunction

  function automatic logic [63:0] sha512_sig0(input logic [63:0] x);
    sha512_sig0 = ror64(x, 1) ^ ror64(x, 8) ^ (x >> 7);
  endfunction

  function automatic logic [63:0] sha512_sig1(input logic [63:0] x);
    sha512_sig1 = ror64(x, 19) ^ ror64(x, 61) ^ (x >> 6);
  endfunction

  function automatic logic [63:0] ch64(input logic [63:0] x, y, z);
    ch64 = (x & y) ^ (~x & z);
  endfunction

  function automatic logic [63:0] maj64(input logic [63:0] x, y, z);
    maj64 = (x & y) ^ (x & z) ^ (y & z);
  endfunction

  ///////////////////////
  //  SHA-256 datapath //
  ///////////////////////
  // Element mapping per RVV crypto spec Zvknh:
  //   vd  = { W[ 3], W[ 2], W[ 1], W[ 0] }
  //   vs2 = { W[11], W[10], W[ 9], W[ 4] }  (ms)
  //   vs1 = { W[15], W[14], W[13], W[12] }
  //   For ch/cl:  vd = {d,c,b,a}, vs2 = {h,g,f,e}, vs1 = {k+w[i+3],...,k+w[i+0]}

  logic [3:0][31:0] res32;
  logic [3:0][63:0] res64;

  always_comb begin
    res32 = '0;

    unique case (op_i)
      VSHA2MS_VV: begin
        // vd  = {W3,W2,W1,W0}, vs2 = {W11,W10,W9,W4}, vs1 = {W15,W14,W13,W12}
        // new: {W19,W18,W17,W16}, with W18,W19 depending on W16,W17 intra-group.
        res32[0] = sha256_sig1(vs1_group_i[2][31:0]) + vs2_group_i[1][31:0]  + sha256_sig0(vd_group_i[1][31:0]) + vd_group_i[0][31:0];
        res32[1] = sha256_sig1(vs1_group_i[3][31:0]) + vs2_group_i[2][31:0] + sha256_sig0(vd_group_i[2][31:0]) + vd_group_i[1][31:0];
        res32[2] = sha256_sig1(res32[0]) + vs2_group_i[3][31:0] + sha256_sig0(vd_group_i[3][31:0]) + vd_group_i[2][31:0];
        res32[3] = sha256_sig1(res32[1]) + vs1_group_i[0][31:0] + sha256_sig0(vs2_group_i[0][31:0]) + vd_group_i[3][31:0];
      end
      VSHA2CH_VV, VSHA2CL_VV: begin
        // Per Zvknh spec (MSB-first concatenation, so element[3] is the top word):
        //   vd  = {c,d,g,h}   -> vd[3]=c, vd[2]=d, vd[1]=g, vd[0]=h
        //   vs2 = {a,b,e,f}   -> vs2[3]=a, vs2[2]=b, vs2[1]=e, vs2[0]=f
        //   vs1 = {MsC3,MsC2,MsC1,MsC0}
        //   CH: W0 = MsC2 (vs1[2]), W1 = MsC3 (vs1[3])
        //   CL: W0 = MsC0 (vs1[0]), W1 = MsC1 (vs1[1])
        //   Output vd = {a2,b2,e2,f2} (MSB-first)
        automatic logic [31:0] a = vs2_group_i[3][31:0];
        automatic logic [31:0] b = vs2_group_i[2][31:0];
        automatic logic [31:0] e = vs2_group_i[1][31:0];
        automatic logic [31:0] f = vs2_group_i[0][31:0];
        automatic logic [31:0] c = vd_group_i[3][31:0];
        automatic logic [31:0] d = vd_group_i[2][31:0];
        automatic logic [31:0] g = vd_group_i[1][31:0];
        automatic logic [31:0] h = vd_group_i[0][31:0];
        automatic logic [31:0] w0 = (op_i == VSHA2CL_VV) ? vs1_group_i[0][31:0] : vs1_group_i[2][31:0];
        automatic logic [31:0] w1 = (op_i == VSHA2CL_VV) ? vs1_group_i[1][31:0] : vs1_group_i[3][31:0];

        // Round 1
        automatic logic [31:0] t1_1 = h + sha256_sum1(e) + ch32(e, f, g) + w0;
        automatic logic [31:0] t2_1 = sha256_sum0(a) + maj32(a, b, c);
        automatic logic [31:0] a1 = t1_1 + t2_1;
        automatic logic [31:0] b1 = a;
        automatic logic [31:0] c1 = b;
        automatic logic [31:0] d1 = c;
        automatic logic [31:0] e1 = d + t1_1;
        automatic logic [31:0] f1 = e;
        automatic logic [31:0] g1 = f;
        automatic logic [31:0] h1 = g;

        // Round 2
        automatic logic [31:0] t1_2 = h1 + sha256_sum1(e1) + ch32(e1, f1, g1) + w1;
        automatic logic [31:0] t2_2 = sha256_sum0(a1) + maj32(a1, b1, c1);
        automatic logic [31:0] a2 = t1_2 + t2_2;
        automatic logic [31:0] b2 = a1;
        automatic logic [31:0] e2 = d1 + t1_2;
        automatic logic [31:0] f2 = e1;

        res32[3] = a2;
        res32[2] = b2;
        res32[1] = e2;
        res32[0] = f2;
      end
      default: res32 = '0;
    endcase
  end

  ////////////////////////////
  //  SHA-512 datapath (Zvknhb)
  ////////////////////////////
  if (Zvknhb(CryptoSupport)) begin : gen_sha512
    always_comb begin
      res64 = '0;

      unique case (op_i)
        VSHA2MS_VV: begin
          res64[0] = sha512_sig1(vs1_group_i[2]) + vs2_group_i[1]  + sha512_sig0(vd_group_i[1]) + vd_group_i[0];
          res64[1] = sha512_sig1(vs1_group_i[3]) + vs2_group_i[2] + sha512_sig0(vd_group_i[2]) + vd_group_i[1];
          res64[2] = sha512_sig1(res64[0]) + vs2_group_i[3] + sha512_sig0(vd_group_i[3]) + vd_group_i[2];
          res64[3] = sha512_sig1(res64[1]) + vs1_group_i[0] + sha512_sig0(vs2_group_i[0]) + vd_group_i[3];
        end
        VSHA2CH_VV, VSHA2CL_VV: begin
          automatic logic [63:0] a = vs2_group_i[3];
          automatic logic [63:0] b = vs2_group_i[2];
          automatic logic [63:0] e = vs2_group_i[1];
          automatic logic [63:0] f = vs2_group_i[0];
          automatic logic [63:0] c = vd_group_i[3];
          automatic logic [63:0] d = vd_group_i[2];
          automatic logic [63:0] g = vd_group_i[1];
          automatic logic [63:0] h = vd_group_i[0];
          automatic logic [63:0] w0 = (op_i == VSHA2CL_VV) ? vs1_group_i[0] : vs1_group_i[2];
          automatic logic [63:0] w1 = (op_i == VSHA2CL_VV) ? vs1_group_i[1] : vs1_group_i[3];

          automatic logic [63:0] t1_1 = h + sha512_sum1(e) + ch64(e, f, g) + w0;
          automatic logic [63:0] t2_1 = sha512_sum0(a) + maj64(a, b, c);
          automatic logic [63:0] a1 = t1_1 + t2_1;
          automatic logic [63:0] b1 = a;
          automatic logic [63:0] c1 = b;
          automatic logic [63:0] d1 = c;
          automatic logic [63:0] e1 = d + t1_1;
          automatic logic [63:0] f1 = e;
          automatic logic [63:0] g1 = f;
          automatic logic [63:0] h1 = g;

          automatic logic [63:0] t1_2 = h1 + sha512_sum1(e1) + ch64(e1, f1, g1) + w1;
          automatic logic [63:0] t2_2 = sha512_sum0(a1) + maj64(a1, b1, c1);
          automatic logic [63:0] a2 = t1_2 + t2_2;
          automatic logic [63:0] b2 = a1;
          automatic logic [63:0] e2 = d1 + t1_2;
          automatic logic [63:0] f2 = e1;

          res64[3] = a2;
          res64[2] = b2;
          res64[1] = e2;
          res64[0] = f2;
        end
        default: res64 = '0;
      endcase
    end
  end else begin : gen_no_sha512
    assign res64 = '0;
  end

  ////////////////////
  //  Output mux    //
  ////////////////////
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      if (sew_i == EW64) begin
        result_group_o[i] = res64[i];
      end else begin
        result_group_o[i] = {32'h0, res32[i]};
      end
    end
  end

endmodule
