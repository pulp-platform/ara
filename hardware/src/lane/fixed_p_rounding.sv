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

  elen_t [DataWidth-1:0] bit_select;
  int j;

  always_comb begin
    j   =  0;
    r_o = '0;

    if (valid_i) begin
      unique case (op_i)
        VSSRA, VSSRL, VNCLIP, VNCLIPU : begin
          unique case (vew_i)
            EW8 : begin
              unique case (vxrm)
                2'b00: begin
                  for (int i=0; i<8; i++) begin
                    j      = opa.w8[i];
                    r_o[i] = opb.w8[i][j-1];
                  end
                end
                2'b01: begin
                  for (int i=0; i<8; i++) begin
                    j      = opa.w8[i];
                    r_o[i] = opb.w8[i][j-1] & opb.w8[i][j];
                  end
                end
                2'b10: begin
                  r_o = '0;
                end
                2'b11: begin
                  for (int i=0; i<8; i++) begin
                    j      = opa.w8[i];
                    r_o[i] = !opb.w8[i][j] & |(opb.w8[i] & bit_select);
                  end
                end
              endcase
            end
            EW16: begin
              unique case (vxrm)
                2'b00: begin
                  for (int i=0; i<4; i++) begin
                    j      = opa.w16[i];
                    r_o[i] = opb.w16[i][j-1];
                  end
                end
                2'b01: begin
                  for (int i=0; i<4; i++) begin
                    j      = opa.w16[i];
                    r_o[i] = opb.w16[i][j-1] & opb.w16[i][j];
                  end
                end
                2'b10: begin
                  r_o = '0;
                end
                2'b11: begin
                  for (int i=0; i<4; i++) begin
                    j      = opa.w16[i];
                    r_o[i] = !opb.w16[i][j] & |(opb.w16[i] & bit_select);
                  end
                end
              endcase
            end
            EW32: begin
              unique case (vxrm)
                2'b00: begin
                  for (int i=0; i<2; i++) begin
                    j      = opa.w32[i];
                    r_o[i] = opb.w32[i][j-1];
                  end
                end
                2'b01: begin
                  for (int i=0; i<2; i++) begin
                    j      = opa.w32[i];
                    r_o[i] = opb.w32[i][j-1] & opb.w32[i][j];
                  end
                end
                2'b10: begin
                  r_o = '0;
                end
                2'b11: begin
                  for (int i=0; i<2; i++) begin
                    j      = opa.w32[i];
                    r_o[i] = !opb.w32[i][j] & |(opb.w32[i] & bit_select);
                  end
                end
              endcase
            end
            EW64: begin
              unique case (vxrm)
                2'b00: begin
                  for (int i=0; i<1; i++) begin
                    j      = opa.w64[i];
                    r_o[i] = opb.w64[i][j-1];
                  end
                end
                2'b01: begin
                  for (int i=0; i<1; i++) begin
                    j      = opa.w64[i];
                    r_o[i] = opb.w64[i][j-1] & opb.w64[i][j];
                  end
                end
                2'b10: begin
                  r_o = '0;
                end
                2'b11: begin
                  for (int i=0; i<1; i++) begin
                    j      = opa.w64[i];
                    r_o[i] = !opb.w64[i][j] & |(opb.w64[i] & bit_select);
                  end
                end
              endcase
            end
          endcase
        end
        default: r_o = '0;
      endcase
    end else begin
      r_o = '0;
    end
  end

  //////////////////
  // Lookup Table //
  //////////////////

  assign bit_select = {64'h0000000000000000, 64'h0000000000000001, 64'h0000000000000003, 64'h0000000000000007,
                       64'h000000000000000F, 64'h000000000000001F, 64'h000000000000003F, 64'h000000000000007F,
                       64'h00000000000000FF, 64'h00000000000001FF, 64'h00000000000003FF, 64'h00000000000007FF,
                       64'h0000000000000FFF, 64'h0000000000001FFF, 64'h0000000000003FFF, 64'h0000000000007FFF,
                       64'h000000000000FFFF, 64'h000000000001FFFF, 64'h000000000003FFFF, 64'h000000000007FFFF,
                       64'h00000000000FFFFF, 64'h00000000001FFFFF, 64'h00000000003FFFFF, 64'h00000000007FFFFF,
                       64'h0000000000FFFFFF, 64'h0000000001FFFFFF, 64'h0000000003FFFFFF, 64'h0000000007FFFFFF,
                       64'h000000000FFFFFFF, 64'h000000001FFFFFFF, 64'h000000003FFFFFFF, 64'h000000007FFFFFFF,
                       64'h00000000FFFFFFFF, 64'h00000001FFFFFFFF, 64'h00000003FFFFFFFF, 64'h00000007FFFFFFFF,
                       64'h0000000FFFFFFFFF, 64'h0000001FFFFFFFFF, 64'h0000003FFFFFFFFF, 64'h0000007FFFFFFFFF,
                       64'h000000FFFFFFFFFF, 64'h000001FFFFFFFFFF, 64'h000003FFFFFFFFFF, 64'h000007FFFFFFFFFF,
                       64'h00000FFFFFFFFFFF, 64'h00001FFFFFFFFFFF, 64'h00003FFFFFFFFFFF, 64'h00007FFFFFFFFFFF,
                       64'h0000FFFFFFFFFFFF, 64'h0001FFFFFFFFFFFF, 64'h0003FFFFFFFFFFFF, 64'h0007FFFFFFFFFFFF,
                       64'h000FFFFFFFFFFFFF, 64'h001FFFFFFFFFFFFF, 64'h003FFFFFFFFFFFFF, 64'h007FFFFFFFFFFFFF,
                       64'h00FFFFFFFFFFFFFF, 64'h01FFFFFFFFFFFFFF, 64'h03FFFFFFFFFFFFFF, 64'h07FFFFFFFFFFFFFF,
                       64'h0FFFFFFFFFFFFFFF, 64'h1FFFFFFFFFFFFFFF, 64'h3FFFFFFFFFFFFFFF, 64'h7FFFFFFFFFFFFFFF};

endmodule : fixed_p_rounding
