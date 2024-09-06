// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's SIMD ALU, operating on elements 64-bit wide, and generating 64 bits per cycle.

module simd_alu import ara_pkg::*; import rvv_pkg::*; #(
    // Support for fixed-point data types
    parameter  fixpt_support_e FixPtSupport = FixedPointEnable,
    // Dependant parameters. DO NOT CHANGE!
    localparam int    unsigned DataWidth    = $bits(elen_t),
    localparam int    unsigned StrbWidth    = DataWidth/8,
    localparam type            strb_t       = logic [StrbWidth-1:0]
  ) (
    input  elen_t      operand_a_i,
    input  elen_t      operand_b_i,
    input  logic       valid_i,
    input  logic       vm_i,
    input  strb_t      mask_i,
    input  logic       narrowing_select_i,
    input  ara_op_e    op_i,
    input  vew_e       vew_i,
    output vxsat_t     vxsat_o,
    input  strb_t      rm,
    input  vxrm_t      vxrm_i,
    output elen_t      result_o
  );

  ///////////////////
  //  Definitions  //
  ///////////////////

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } alu_operand_t;

  alu_operand_t opa, opb, res;
  assign opa      = operand_a_i;
  assign opb      = operand_b_i;
  assign result_o = res;


  typedef union packed {
    logic [0:0][71:0] w64;
    logic [1:0][35:0] w32;
    logic [3:0][17:0] w16;
    logic [7:0][ 8:0] w8;
  } alu_sat_operand_t;

  alu_sat_operand_t sat_sum, sat_sub;
  vxsat_t     vxsat;
  vxrm_t      vxrm;
  logic       r;

  assign vxrm = vxrm_i;
  assign vxsat_o = vxsat;
  ///////////////////
  //  Comparisons  //
  ///////////////////

  // Comparison instructions that use signed operands
  logic is_signed;
  assign is_signed = op_i inside {VMAX, VREDMAX, VMIN, VREDMIN, VMSLT, VMSLE, VMSGT};
  // Compare operands.
  // For vew_i = EW8, all bits are valid.
  // For vew_i = EW16, bits 0, 2, 4, and 6 are valid.
  // For vew_i = EW32, bits 0 and 4 are valid.
  // For vew_i = EW64, only bit 0 indicates the result of the comparison.
  logic [7:0] less;
  logic [7:0] equal;

  always_comb begin: p_comparison
    // Default assignment
    less  = '0;
    equal = '0;

    if (valid_i) begin
      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) less[1*b] =
            $signed({is_signed & opb.w8 [b][ 7], opb.w8 [b]}) <
            $signed({is_signed & opa.w8 [b][ 7], opa.w8 [b]});
        EW16: for (int b = 0; b < 4; b++) less[2*b] =
            $signed({is_signed & opb.w16[b][15], opb.w16[b]}) <
            $signed({is_signed & opa.w16[b][15], opa.w16[b]});
        EW32: for (int b = 0; b < 2; b++) less[4*b] =
            $signed({is_signed & opb.w32[b][31], opb.w32[b]}) <
            $signed({is_signed & opa.w32[b][31], opa.w32[b]});
        EW64: for (int b = 0; b < 1; b++) less[8*b] =
            $signed({is_signed & opb.w64[b][63], opb.w64[b]}) <
            $signed({is_signed & opa.w64[b][63], opa.w64[b]});
        default:;
      endcase

      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) equal[1*b] = opa.w8 [b] == opb.w8 [b];
        EW16: for (int b = 0; b < 4; b++) equal[2*b] = opa.w16[b] == opb.w16[b];
        EW32: for (int b = 0; b < 2; b++) equal[4*b] = opa.w32[b] == opb.w32[b];
        EW64: for (int b = 0; b < 1; b++) equal[8*b] = opa.w64[b] == opb.w64[b];
        default:;
      endcase
    end
  end : p_comparison

  ///////////
  //  ALU  //
  ///////////

  always_comb begin: p_alu
    // Default assignment
    res       = '0;
    vxsat.w64 = '0;

    if (valid_i)
      unique case (op_i)
        // Logical operations
        VAND, VREDAND: res = operand_a_i & operand_b_i;
        VOR, VREDOR  : res = operand_a_i | operand_b_i;
        VXOR, VREDXOR: res = operand_a_i ^ operand_b_i;

        // Mask logical operations
        VMAND   : res = operand_a_i & operand_b_i;
        VMANDNOT: res = ~operand_a_i & operand_b_i;
        VMNAND  : res = ~(operand_a_i & operand_b_i);
        VMOR    : res = operand_a_i | operand_b_i;
        VMNOR   : res = ~(operand_a_i | operand_b_i);
        VMORNOT : res = ~operand_a_i | operand_b_i;
        VMXOR   : res = operand_a_i ^ operand_b_i;
        VMXNOR  : res = ~(operand_a_i ^ operand_b_i);

        // vmsbf, vmsof, vmsif and viota operand generation
        VMSBF, VMSOF, VMSIF, VIOTA : res = opb;

	      // Vector count population and find first set bit instructions
        VCPOP, VFIRST : res = operand_b_i;

        // Arithmetic instructions
        VSADDU: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sum = opa.w8[b] + opb.w8[b];
                vxsat.w8[b]   = sum[8];
                res.w8[b]     = vxsat.w8[b] ? {8{1'b1}} : sum[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b];
                vxsat.w16[b]   = {2{sum[16]}};
                res.w16[b]     = &vxsat.w16[b] ? {16{1'b1}} : sum[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b];
                vxsat.w32[b]   = {4{sum[32]}};
                res.w32[b]     = &vxsat.w32[b] ? {32{1'b1}} : sum[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b];
                vxsat.w64[b]   = {8{sum[64]}};
                res.w64[b]     = &vxsat.w64[b] ? {64{1'b1}} : sum[63:0];
              end
          endcase
        VSADD: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sum = opa.w8[b] + opb.w8[b];
                vxsat.w8[b]   = (sum[7]^opa.w8[b][7]) & ~(opa.w8[b][7] ^ opb.w8[b][7]);
                res.w8[b]     = vxsat.w8[b] ? (sum[7] ? {1'b0, {7{1'b1}}} : {1'b1, {7{1'b0}}} ) : sum[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b];
                vxsat.w16[b]   = {2{(sum[15] ^ opa.w16[b][15]) & ~(opa.w16[b][15] ^ opb.w16[b][15])}};
                res.w16[b]     = &vxsat.w16[b] ? (sum[15] ? {1'b0, {15{1'b1}}} : {1'b1, {15{1'b0}}} ) : sum[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b];
                vxsat.w32[b]   = {4{(sum[31] ^ opa.w32[b][31]) && !(opa.w32[b][31] ^ opb.w32[b][31])}};
                res.w32[b]     = &vxsat.w32[b] ? (sum[31] ? {1'b0, {31{1'b1}}} : {1'b1, {31{1'b0}}} ) : sum[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b];
                vxsat.w64[b]   = {8{(sum[63] ^ opa.w64[b][63]) & ~(opa.w64[b][63] ^ opb.w64[b][63])}};
                res.w64[b]     = &vxsat.w64[b] ? (sum[63] ? {1'b0, {63{1'b1}}} : {1'b1, {63{1'b0}}} ) : sum[63:0];
              end
          endcase
        VAADD, VAADDU: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
              automatic logic [ 8:0] sum = opa.w8 [b] + opb.w8 [b];
                unique case (vxrm)
                  2'b00: r = sum[0];
                  2'b01: r = &sum[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sum[1] & (sum[0]!=0);
                endcase
                res.w8[b] = (op_i == VAADDU) ? sum[8:1] + r : {sum[7], sum[7:1]} + r;
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b];
                unique case (vxrm)
                  2'b00: r = sum[0];
                  2'b01: r = &sum[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sum[1] & (sum[0]!=0);
                endcase
                res.w16[b] = (op_i == VAADDU) ? sum[16:1] + r : {sum[15], sum[15:1]} + r;
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b];
                unique case (vxrm)
                  2'b00: r = sum[0];
                  2'b01: r = &sum[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sum[1] & (sum[0]!=0);
                endcase
                res.w32[b] = (op_i == VAADDU) ? sum[32:1] + r : {sum[31], sum[31:1]} + r;
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b];
                unique case (vxrm)
                  2'b00: r = sum[0];
                  2'b01: r = &sum[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sum[1] & (sum[0]!=0);
                endcase
                res.w64[b] = (op_i == VAADDU) ? sum[64:1] + r : {sum[63], sum[63:1]} + r;
              end
          endcase
        VADD, VADC, VMADC, VREDSUM, VWREDSUMU, VWREDSUM: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [ 8:0] sum = opa.w8 [b] + opb.w8 [b] +
                logic'(op_i inside {VADC, VMADC} && mask_i[1*b] & ~vm_i);
                res.w8[b] = (op_i == VMADC) ? {6'b0, 1'b1, sum[8]} : sum[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b] +
                logic'(op_i inside {VADC, VMADC} && mask_i[2*b] & ~vm_i);
                res.w16[b] = (op_i == VMADC) ? {14'b0, 1'b1, sum[16]} : sum[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b] +
                logic'(op_i inside {VADC, VMADC} && mask_i[4*b] & ~vm_i);
                res.w32[b] = (op_i == VMADC) ? {30'b0, 1'b1, sum[32]} : sum[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b] +
                logic'(op_i inside {VADC, VMADC} && mask_i[8*b] & ~vm_i);
                res.w64[b] = (op_i == VMADC) ? {62'b0, 1'b1, sum[64]} : sum[63:0];
              end
          endcase
        VSUB, VSBC, VMSBC: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [ 8:0] sub = opb.w8 [b] - opa.w8 [b] -
                logic'(op_i inside {VSBC, VMSBC} && mask_i[1*b] & ~vm_i);
                res.w8[b] = (op_i == VMSBC) ? {6'b0, 1'b1, sub[8]} : sub[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sub = opb.w16[b] - opa.w16[b] -
                logic'(op_i inside {VSBC, VMSBC} && mask_i[2*b] & ~vm_i);
                res.w16[b] = (op_i == VMSBC) ? {14'b0, 1'b1, sub[16]} : sub[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sub = opb.w32[b] - opa.w32[b] -
                logic'(op_i inside {VSBC, VMSBC} && mask_i[4*b] & ~vm_i);
                res.w32[b] = (op_i == VMSBC) ? {30'b0, 1'b1, sub[32]} : sub[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sub = opb.w64[b] - opa.w64[b] -
                logic'(op_i inside {VSBC, VMSBC} && mask_i[8*b] & ~vm_i);
                res.w64[b] = (op_i == VMSBC) ? {62'b0, 1'b1, sub[64]} : sub[63:0];
              end
          endcase
        VRSUB: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opa.w8 [b] - opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opa.w16[b] - opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opa.w32[b] - opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opa.w64[b] - opb.w64[b];
          endcase
        VSSUBU: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sub = opb.w8 [b] - opa.w8 [b];
                vxsat.w8[b]   = sub[8];
                res.w8[b]     = vxsat.w8[b] ? {8{1'b0}} : sub[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sub = opb.w16[b] - opa.w16[b];
                vxsat.w16[b]   = {2{sub[16]}};
                res.w16[b]     = &vxsat.w16[b] ? {16{1'b0}} : sub[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sub = opb.w32[b] - opa.w32[b];
                vxsat.w32[b]   = {4{sub[32]}};
                res.w32[b]     = &vxsat.w32[b] ? {32{1'b0}} : sub[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sub = opb.w64[b] - opa.w64[b];
                vxsat.w64[b]   = {8{sub[64]}};
                res.w64[b]     = &vxsat.w64[b] ? {64{1'b0}} : sub[63:0];
              end
          endcase
        VSSUB: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sub = opb.w8 [b] - opa.w8 [b];
                vxsat.w8[b]   = ^sub[8:7];
                res.w8[b]     = vxsat.w8[b] ? {8{1'b0}} : sub[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sub = opb.w16[b] - opa.w16[b];
                vxsat.w16[b]   = {2{^sub[16:15]}};
                res.w16[b]     = &vxsat.w16[b] ? {16{1'b0}} : sub[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sub = opb.w32[b] - opa.w32[b];
                vxsat.w32[b]   = {4{^sub[32:31]}};
                res.w32[b]     = &vxsat.w32[b] ? {32{1'b0}} : sub[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sub = opb.w64[b] - opa.w64[b];
                vxsat.w64[b]   = {8{^sub[64:63]}};
                res.w64[b]     = &vxsat.w64[b] ? {64{1'b0}} : sub[63:0];
              end
          endcase
        VASUB, VASUBU: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [ 8:0] sub = opb.w8 [b] - opa.w8 [b];
                unique case (vxrm)
                  2'b00: r = sub[0];
                  2'b01: r = &sub[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sub[1] & (sub[0]!=0);
                endcase
                res.w8[b] = (op_i == VASUBU) ? (sub[7:0] >> 1) + r : ($signed(sub[7:0]) >>> 1) + r;
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [ 16:0] sub = opb.w16[b] - opa.w16[b];
                unique case (vxrm)
                  2'b00: r = sub[0];
                  2'b01: r = &sub[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sub[1] & (sub[0]!=0);
                endcase
                res.w16[b] = (op_i == VASUBU) ? (sub[15:0] >> 1) + r : ($signed(sub[15:0]) >>> 1) + r;
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [ 32:0] sub = opb.w32[b] - opa.w32[b];
                unique case (vxrm)
                  2'b00: r = sub[0];
                  2'b01: r = &sub[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sub[1] & (sub[0]!=0);
                endcase
                res.w32[b] = (op_i == VASUBU) ? (sub[31:0] >> 1) + r : ($signed(sub[31:0]) >>> 1) + r;
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [ 64:0] sub = opb.w64[b] - opa.w64[b];
                unique case (vxrm)
                  2'b00: r = sub[0];
                  2'b01: r = &sub[1:0];
                  2'b10: r = 1'b0;
                  2'b11: r = !sub[1] & (sub[0]!=0);
                endcase
                res.w64[b] = (op_i == VASUBU) ? (sub[63:0] >> 1) + r : ($signed(sub[63:0]) >>> 1) + r;
              end
          endcase

        // Shift instructions
        VSLL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] << opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] << opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] << opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] << opa.w64[b][5:0];
          endcase
        VSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] >> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] >> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] >> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] >> opa.w64[b][5:0];
          endcase
        VSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = $signed(opb.w8 [b]) >>> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
          endcase
        VNSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] = opb.w16[b] >>
                opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] = opb.w32[b] >>
                opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] = opb.w64[b] >>
                opa.w64[b][5:0];
          endcase
        VNSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] =
                $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] =
                $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] =
                $signed(opb.w64[b]) >>> opa.w64[b][5:0];
          endcase

        // Fixed point shift instructions
        VSSRA: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [7:0] sra = $signed(opb.w8 [b]) >>> opa.w8 [b][2:0];
                res.w8[b] = sra + rm[b];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [15:0] sra = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
                res.w16[b] = sra + rm[b];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [31:0] sra = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
                res.w32[b] = sra + rm[b];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [63:0] sra = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
                res.w64[b] = sra + rm[b];
              end
          endcase
        VSSRL: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] srl = opb.w8 [b] >> opa.w8 [b];
                res.w8[b] = srl + rm[b];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] srl = opb.w16[b] >> opa.w16[b];
                res.w16[b] = srl + rm[b];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] srl = opb.w32[b] >> opa.w32[b];
                res.w32[b] = srl + rm[b];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] srl = opb.w64[b] >> opa.w64[b];
                res.w64[b] = srl + rm[b];
              end
          endcase

        // Fixed point clip instructions
        VNCLIP: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) begin
                automatic logic [15:0] clip = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
                vxsat.w8[b]   = |clip[15:8];
                res.w8 [2*b + narrowing_select_i] = ($signed(opb.w16[b]) >>> opa.w16[b][3:0]) + rm[b];
              end
            EW16: for (int b = 0; b < 2; b++) begin
                automatic logic [31:0] clip = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
                vxsat.w8[b]   = |clip[31:16];
                res.w16[2*b + narrowing_select_i] = ($signed(opb.w32[b]) >>> opa.w32[b][4:0]) + rm[b];
              end
            EW32: for (int b = 0; b < 1; b++) begin
                automatic logic [63:0] clip = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
                vxsat.w8[b]   = |clip[63:32];
                res.w32[2*b + narrowing_select_i] = ($signed(opb.w64[b]) >>> opa.w64[b][5:0]) + rm[b];
              end
          endcase
        VNCLIPU: if (FixPtSupport == FixedPointEnable) unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) begin
                automatic logic [15:0] clipu = opb.w16[b] >> opa.w16[b][3:0];
                vxsat.w8[b]   = |clipu[15:8];
                res.w8 [2*b + narrowing_select_i] = (opb.w16[b] >> opa.w16[b][3:0]) + rm[b];
              end
            EW16: for (int b = 0; b < 2; b++) begin
                automatic logic [31:0] clipu = opb.w32[b] >> opa.w32[b][4:0];
                vxsat.w8[b]   = |clipu[31:16];
                res.w16[2*b + narrowing_select_i] = (opb.w32[b] >> opa.w32[b][4:0]) + rm[b];
              end
            EW32: for (int b = 0; b < 1; b++) begin
                automatic logic [63:0] clipu = opb.w64[b] >> opa.w64[b][5:0];
                vxsat.w8[b]   = |clipu[63:32];
                res.w32[2*b + narrowing_select_i] = (opb.w64[b] >> opa.w64[b][5:0]) + rm[b];
              end
          endcase

        // Merge instructions
        VMERGE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = mask_i[1*b] ? opa.w8 [b] : opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = mask_i[2*b] ? opa.w16[b] : opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = mask_i[4*b] ? opa.w32[b] : opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = mask_i[8*b] ? opa.w64[b] : opb.w64[b];
          endcase

        // Scalar move
        VMVSX, VFMVSF: res = opa;

        // Comparison instructions
        VMIN, VMINU, VMAX, VMAXU,
        VREDMINU, VREDMIN, VREDMAXU, VREDMAX: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] =
                (less[1*b] ^ (op_i == VMAX || op_i == VMAXU || op_i == VREDMAXU || op_i == VREDMAX)) ? opb.w8 [b] : opa.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] =
                (less[2*b] ^ (op_i == VMAX || op_i == VMAXU || op_i == VREDMAXU || op_i == VREDMAX)) ? opb.w16[b] : opa.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] =
                (less[4*b] ^ (op_i == VMAX || op_i == VMAXU || op_i == VREDMAXU || op_i == VREDMAX)) ? opb.w32[b] : opa.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] =
                (less[8*b] ^ (op_i == VMAX || op_i == VMAXU || op_i == VREDMAXU || op_i == VREDMAX)) ? opb.w64[b] : opa.w64[b];
          endcase
        VMSEQ, VMSNE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][1:0] =
                {mask_i[1*b], equal[1*b] ^ (op_i == VMSNE)};
            EW16: for (int b = 0; b < 4; b++) res.w16[b][1:0] =
                {mask_i[2*b], equal[2*b] ^ (op_i == VMSNE)};
            EW32: for (int b = 0; b < 2; b++) res.w32[b][1:0] =
                {mask_i[4*b], equal[4*b] ^ (op_i == VMSNE)};
            EW64: for (int b = 0; b < 1; b++) res.w64[b][1:0] =
                {mask_i[8*b], equal[8*b] ^ (op_i == VMSNE)};
          endcase
        VMSLT, VMSLTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][1:0] = {mask_i[1*b], less[1*b]};
            EW16: for (int b = 0; b < 4; b++) res.w16[b][1:0] = {mask_i[2*b], less[2*b]};
            EW32: for (int b = 0; b < 2; b++) res.w32[b][1:0] = {mask_i[4*b], less[4*b]};
            EW64: for (int b = 0; b < 1; b++) res.w64[b][1:0] = {mask_i[8*b], less[8*b]};
          endcase
        VMSLE, VMSLEU, VMSGT, VMSGTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][1:0] =
                {mask_i[1*b], (less[1*b] || equal[1*b]) ^ (op_i inside {VMSGT, VMSGTU})};
            EW16: for (int b = 0; b < 4; b++) res.w16[b][1:0] =
                {mask_i[2*b], (less[2*b] || equal[2*b]) ^ (op_i inside {VMSGT, VMSGTU})};
            EW32: for (int b = 0; b < 2; b++) res.w32[b][1:0] =
                {mask_i[4*b], (less[4*b] || equal[4*b]) ^ (op_i inside {VMSGT, VMSGTU})};
            EW64: for (int b = 0; b < 1; b++) res.w64[b][1:0] =
                {mask_i[8*b], (less[8*b] || equal[8*b]) ^ (op_i inside {VMSGT, VMSGTU})};
          endcase

        default:;
      endcase
  end : p_alu

  //////////////////
  //  Assertions  //
  //////////////////

  if (DataWidth != $bits(alu_operand_t))
    $error("[simd_valu] The SIMD vector ALU only works for a datapath 64-bit wide.");

endmodule : simd_alu
