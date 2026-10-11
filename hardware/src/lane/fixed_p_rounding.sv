// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Muhammad Ijaz
// Description:
// Ara's fixed point rounding module, operating on elements 64-bit wide, and generating rounding r for each stream of elements.

module fixed_p_rounding import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t),
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  logic    valid_i,
    input  ara_op_e op_i,
    input  vew_e    vew_i,
    input  vxrm_t   vxrm_i,
    output strb_t   r_o
  );

  /////////////////
  // Definitions //
  /////////////////

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } rounding_args;

  rounding_args opa, opb;
  assign opa = operand_a_i;
  assign opb = operand_b_i;

  vxrm_t vxrm;
  assign vxrm = vxrm_i;

  // Rounding increment for v >> d under vxrm (RVV 1.0, 3.8). d is already reduced to the
  // element's shift range, so v[d] is in range; d == 0 shifts nothing and never rounds.
  function automatic logic round_incr(logic [63:0] v, int unsigned d, vxrm_t mode);
    logic below, last, kept;
    if (d == 0) return 1'b0;
    last  = v[d-1];
    kept  = v[d];
    below = (d > 1) ? |(v & ((64'd1 << (d-1)) - 64'd1)) : 1'b0;
    unique case (mode)
      2'b00: return last;                   // rnu
      2'b01: return last & (below | kept);  // rne
      2'b10: return 1'b0;                   // rdn
      2'b11: return !kept & (last | below); // rod
    endcase
  endfunction

  // vssra/vssrl round SEW-wide elements; vnclip/vnclipu round their 2*SEW-wide source.
  // r_o[i] belongs to the i-th element of that width in the 64-bit word.
  always_comb begin
    r_o = '0;
    if (valid_i) begin
      unique case (op_i)
        VSSRA, VSSRL: unique case (vew_i)
          EW8 : for (int i = 0; i < 8; i++) r_o[i] = round_incr(64'(opb.w8[i]),  opa.w8[i][2:0],  vxrm);
          EW16: for (int i = 0; i < 4; i++) r_o[i] = round_incr(64'(opb.w16[i]), opa.w16[i][3:0], vxrm);
          EW32: for (int i = 0; i < 2; i++) r_o[i] = round_incr(64'(opb.w32[i]), opa.w32[i][4:0], vxrm);
          EW64: r_o[0] = round_incr(opb.w64[0], opa.w64[0][5:0], vxrm);
          default:;
        endcase
        VNCLIP, VNCLIPU: unique case (vew_i)
          EW8 : for (int i = 0; i < 4; i++) r_o[i] = round_incr(64'(opb.w16[i]), opa.w16[i][3:0], vxrm);
          EW16: for (int i = 0; i < 2; i++) r_o[i] = round_incr(64'(opb.w32[i]), opa.w32[i][4:0], vxrm);
          EW32: r_o[0] = round_incr(opb.w64[0], opa.w64[0][5:0], vxrm);
          default:;
        endcase
        default:;
      endcase
    end
  end

endmodule : fixed_p_rounding
