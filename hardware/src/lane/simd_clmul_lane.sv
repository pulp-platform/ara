// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
//   Per-lane Zvbc carry-less multiplier (64 x 64 -> 128, GF(2)).
//   Implements VCLMUL (low 64 bits of the product) and VCLMULH (high
//   64 bits of the product). Operates on one 64-bit element per lane;
//   no cross-lane communication is needed.
//
//   Interface mirrors simd_mul so this module can be instantiated
//   alongside the EW64 integer multiplier in vmfpu.sv with the same
//   valid/ready handshake and pipeline depth.

module simd_clmul_lane import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int    unsigned NumPipeRegs  = 0,
    // Dependent parameters. DO NOT CHANGE!
    localparam int    unsigned DataWidth    = $bits(elen_t),
    localparam int    unsigned StrbWidth    = DataWidth/8,
    localparam type            strb_t       = logic [DataWidth/8-1:0]
  ) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  elen_t      operand_a_i,
    input  elen_t      operand_b_i,
    input  strb_t      mask_i,
    input  ara_op_e    op_i,
    output elen_t      result_o,
    // Post-pipeline op — aligned with result_o so the caller can use it
    // to mux the clmul result in against the integer multiplier's output.
    output ara_op_e    op_o,
    output strb_t      mask_o,
    input  logic       valid_i,
    output logic       ready_o,
    input  logic       ready_i,
    output logic       valid_o
  );

`include "common_cells/registers.svh"

  ///////////////////////
  //  Pipeline stages  //
  ///////////////////////

  elen_t   [NumPipeRegs:0] opa_d, opb_d;
  ara_op_e [NumPipeRegs:0] op_d;
  strb_t   [NumPipeRegs:0] mask_d;
  logic    [NumPipeRegs:0] valid_d;
  logic    [NumPipeRegs:0] stage_ready;

  assign opa_d[0]   = operand_a_i;
  assign opb_d[0]   = operand_b_i;
  assign op_d[0]    = op_i;
  assign mask_d[0]  = mask_i;
  assign valid_d[0] = valid_i;

  if (NumPipeRegs > 0) begin : gen_pipeline
    elen_t   [NumPipeRegs-1:0] opa_q, opb_q;
    strb_t   [NumPipeRegs-1:0] mask_q;
    ara_op_e [NumPipeRegs-1:0] op_q;
    logic    [NumPipeRegs-1:0] valid_q;

    for (genvar i = 0; i < NumPipeRegs; i++) begin : gen_pipeline_stages
      assign opa_d[i+1]   = opa_q[i];
      assign opb_d[i+1]   = opb_q[i];
      assign op_d[i+1]    = op_q[i];
      assign mask_d[i+1]  = mask_q[i];
      assign valid_d[i+1] = valid_q[i];

      assign stage_ready[i] = stage_ready[i+1] | ~valid_q[i];

      logic reg_ena;
      assign reg_ena = stage_ready[i];

      `FFL(valid_q[i], valid_d[i], reg_ena, '0)
      `FFL(opa_q[i],   opa_d[i],   reg_ena, '0)
      `FFL(opb_q[i],   opb_d[i],   reg_ena, '0)
      `FFL(op_q[i],    op_d[i],    reg_ena, ara_op_e'('0))
      `FFL(mask_q[i],  mask_d[i],  reg_ena, '0)
    end
  end

  assign ready_o                   = stage_ready[0];
  assign stage_ready[NumPipeRegs]  = ready_i;
  assign valid_o                   = valid_d[NumPipeRegs];
  assign mask_o                    = mask_d[NumPipeRegs];

  // Output-stage signals (post last pipeline register).
  elen_t   opa;
  elen_t   opb;
  ara_op_e op;
  assign opa = opa_d[NumPipeRegs];
  assign opb = opb_d[NumPipeRegs];
  assign op  = op_d[NumPipeRegs];

  assign op_o = op;

  ////////////////////////////////
  //  64 x 64 carry-less mul    //
  ////////////////////////////////
  //
  // Per bit i of opb: if set, XOR (opa << i) into the 128-bit accumulator.
  // Equivalent to polynomial multiplication over GF(2). Synthesizes to a
  // two-input AND-XOR reduction tree of depth log2(64) = 6.

  logic [127:0] clm_result;
  always_comb begin
    logic [127:0] acc;
    acc = 128'h0;
    for (int i = 0; i < 64; i++) begin
      if (opb[i]) acc = acc ^ ({64'h0, opa} << i);
    end
    clm_result = acc;
  end

  // vclmul  -> low 64 bits
  // vclmulh -> high 64 bits
  assign result_o = (op == VCLMULH) ? clm_result[127:64] : clm_result[63:0];

endmodule
