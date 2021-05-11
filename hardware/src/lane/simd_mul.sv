// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//          Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's SIMD Multiplier, operating on elements 64-bit wide.
// The parametric number of pipeline register determines the intrinsic latency of the unit.
// Once the pipeline is full, the unit can generate 64 bits per cycle.

module simd_mul import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int   unsigned NumPipeRegs  = 0,
    parameter  vew_e          ElementWidth = EW64,
    // Dependant parameters. DO NOT CHANGE!
    localparam int   unsigned DataWidth    = $bits(elen_t),
    localparam int   unsigned StrbWidth    = DataWidth/8,
    localparam type           strb_t       = logic [DataWidth/8-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  elen_t   operand_c_i,
    input  strb_t   mask_i,
    input  ara_op_e op_i,
    output elen_t   result_o,
    output strb_t   mask_o,
    input  logic    valid_i,
    output logic    ready_o,
    input  logic    ready_i,
    output logic    valid_o
  );

`include "common_cells/registers.svh"

  ///////////////////
  //  Definitions  //
  ///////////////////

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } mul_operand_t;

  mul_operand_t opa, opb, opc;
  ara_op_e      op;

  ///////////////////////
  //  Pipeline stages  //
  ///////////////////////

  // Input signals for the next stage (= output signals of the previous stage)
  mul_operand_t [NumPipeRegs:0] opa_d, opb_d, opc_d;
  ara_op_e      [NumPipeRegs:0] op_d;
  strb_t        [NumPipeRegs:0] mask_d;
  logic         [NumPipeRegs:0] valid_d;
  // Ready signal is combinatorial for all stages
  logic         [NumPipeRegs:0] stage_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign opa_d[0]   = operand_a_i;
  assign opb_d[0]   = operand_b_i;
  assign opc_d[0]   = operand_c_i;
  assign op_d[0]    = op_i;
  assign mask_d[0]  = mask_i;
  assign valid_d[0] = valid_i;

  // Generate the pipeline stages in case they are needed
  if (NumPipeRegs > 0) begin : gen_pipeline
    // Pipelined versions of signals for later stages
    mul_operand_t [NumPipeRegs-1:0] opa_q, opb_q, opc_q;
    strb_t [NumPipeRegs-1:0] mask_q;
    ara_op_e [NumPipeRegs-1:0] op_q;
    logic [NumPipeRegs-1:0] valid_q;

    for (genvar i = 0; i < NumPipeRegs; i++) begin : gen_pipeline_stages
      // Next state from previous register to form a shift register
      assign opa_d[i+1]   = opa_q[i];
      assign opb_d[i+1]   = opb_q[i];
      assign opc_d[i+1]   = opc_q[i];
      assign op_d[i+1]    = op_q[i];
      assign mask_d[i+1]  = mask_q[i];
      assign valid_d[i+1] = valid_q[i];

      // Determine the ready signal of the current stage - advance the pipeline:
      // 1. if the next stage is ready for our data
      // 2. if the next stage register only holds a bubble (not valid) -> we can pop it
      assign stage_ready[i] = stage_ready[i+1] | ~valid_q[i];

      // Enable register if pipeline ready
      logic reg_ena;
      assign reg_ena = stage_ready[i];

      // Generate the pipeline
      `FFL(valid_q[i], valid_d[i], reg_ena, '0)
      `FFL(opa_q[i], opa_d[i], reg_ena, '0)
      `FFL(opb_q[i], opb_d[i], reg_ena, '0)
      `FFL(opc_q[i], opc_d[i], reg_ena, '0)
      `FFL(op_q[i], op_d[i], reg_ena, ara_op_e'('0))
      `FFL(mask_q[i], mask_d[i], reg_ena, '0)
    end : gen_pipeline_stages
  end

  // Input stage: Propagate ready signal from pipeline
  assign ready_o = stage_ready[0];

  // Output stage: bind last stage outputs to the pipeline output. Directly connects to input if no
  // regs.
  assign opa     = opa_d[NumPipeRegs];
  assign opb     = opb_d[NumPipeRegs];
  assign opc     = opc_d[NumPipeRegs];
  assign op      = op_d[NumPipeRegs];
  assign mask_o  = mask_d[NumPipeRegs];
  assign valid_o = valid_d[NumPipeRegs];

  // Output stage: Ready travels backwards from output side
  assign stage_ready[NumPipeRegs] = ready_i;

  //////////////////
  //  Multiplier  //
  //////////////////

  typedef union packed {
    logic [0:0][127:0] w128;
    logic [1:0][63:0] w64;
    logic [3:0][31:0] w32;
    logic [7:0][15:0] w16;
  } mul_result_t;
  mul_result_t mul_res;

  logic signed_a, signed_b;

  // Sign select MUX
  assign signed_a = op inside {VMULH};
  assign signed_b = op inside {VMULH, VMULHSU};

  if (ElementWidth == EW64) begin: gen_p_mul_ew64
    for (genvar l = 0; l < 1; l++) begin: gen_mul
      assign mul_res.w128[l] =
      $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
    end : gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 1; l++) result_o[64*l +: 64] = mul_res.w128[l][63:0];
        VMULH,
        VMULHU,
        VMULHSU: for (int l = 0; l < 1; l++) result_o[64*l +: 64] = mul_res.w128[l][127:64];
        // Single-Width integer multiply-add instructions
        VMACC,
        VMADD: begin
          for (int l = 0; l < 1; l++) result_o[64*l +: 64] = mul_res.w128[l][63:0] + opc.w64[l];
        end
        VNMSAC,
        VNMSUB: begin
          for (int l = 0; l < 1; l++) result_o[64*l +: 64] = -mul_res.w128[l][63:0] + opc.w64[l];
        end
        default: result_o = '0;
      endcase
    end
  end : gen_p_mul_ew64 else if (ElementWidth == EW32) begin: gen_p_mul_ew32
    for (genvar l = 0; l < 2; l++) begin: gen_mul
      assign mul_res.w64[l] =
      $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
    end: gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 2; l++) result_o[32*l +: 32] = mul_res.w64[l][31:0];
        VMULH,
        VMULHU,
        VMULHSU: for (int l = 0; l < 2; l++) result_o[32*l +: 32] = mul_res.w64[l][63:32];
        // Single-Width integer multiply-add instructions
        VMACC,
        VMADD: for (int l = 0; l < 2; l++) result_o[32*l +: 32] = mul_res.w64[l][31:0] + opc.w32[l];
        VNMSAC,
        VNMSUB: for (int l = 0; l < 2; l++) begin
            result_o[32*l +: 32] = -mul_res.w64[l][31:0] + opc.w32[l];
          end
        default: result_o = '0;
      endcase
    end
  end : gen_p_mul_ew32 else if (ElementWidth == EW16) begin: gen_p_mul_ew16
    for (genvar l = 0; l < 4; l++) begin: gen_mul
      assign mul_res.w32[l] =
      $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l] [15] & signed_b, opb.w16[l]});
    end : gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 4; l++) result_o[16*l +: 16] = mul_res.w32[l][15:0];
        VMULH,
        VMULHU,
        VMULHSU: for (int l = 0; l < 4; l++) result_o[16*l +: 16] = mul_res.w32[l][31:16];
        // Single-Width integer multiply-add instructions
        VMACC,
        VMADD: for (int l = 0; l < 4; l++) result_o[16*l +: 16] = mul_res.w32[l][15:0] + opc.w16[l];
        VNMSAC,
        VNMSUB: for (int l = 0; l < 4; l++) begin
            result_o[16*l +: 16] = -mul_res.w32[l][15:0] + opc.w16[l];
          end
        default: result_o = '0;
      endcase
    end
  end : gen_p_mul_ew16 else if (ElementWidth == EW8) begin: gen_p_mul_ew8
    for (genvar l = 0; l < 8; l++) begin: gen_mul
      assign mul_res.w16[l] =
      $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
    end : gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 8; l++) result_o[8*l +: 8] = mul_res.w16[l][7:0];
        VMULH,
        VMULHU,
        VMULHSU: for (int l = 0; l < 8; l++) result_o[8*l +: 8] = mul_res.w16[l][15:8];
        // Single-Width integer multiply-add instructions
        VMACC,
        VMADD: for (int l = 0; l < 8; l++) result_o[8*l +: 8] = mul_res.w16[l][7:0] + opc.w8[l];
        VNMSAC,
        VNMSUB: for (int l = 0; l < 8; l++) result_o[8*l +: 8] = -mul_res.w16[l][7:0] + opc.w8[l];
        default: result_o = '0;
      endcase
    end
  end : gen_p_mul_ew8 else begin: gen_p_mul_error
    $error("[simd_vmul] Invalid ElementWidth.");
  end : gen_p_mul_error

endmodule : simd_mul
