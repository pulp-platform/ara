// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File          : simd_mul.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 28.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's multiplier.

`include "registers.svh"

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;
import riscv::vwidth_t    ;
import riscv::vrepr_t     ;

module simd_mul #(
    parameter int unsigned NumPipeRegs = 0
  ) (
    input  logic           clk_i,
    input  logic           rst_ni,
    input  logic    [63:0] operand_a_i,
    input  logic    [63:0] operand_b_i,
    input  logic    [63:0] operand_c_i,
    input  logic    [ 7:0] operand_m_i,
    input  vfu_op          op_i,
    input  vwidth_t        width_i,
    input  vrepr_t         repr_i,
    output logic    [63:0] result_o,
    output logic    [ 7:0] operand_m_o,
    input  logic           valid_i,
    output logic           ready_o,
    output logic           valid_o,
    input  logic           ready_i
  );

  logic signed_a, signed_b;

  // Sign select MUX
  always_comb begin
    signed_a = 1'b0;
    signed_b = 1'b0;

    if (op_i == VMULH && repr_i == riscv::RP_SIGNED)
      {signed_a, signed_b} = '1;
  end

  // Datapath
  logic [3:0][127:0] fma_result;
  logic [3:0][ 63:0] result ;

  always_comb begin
    fma_result = '0;
    result     = '0;

    // 64B
    for (int l = 0; l < 1; l++) begin
      fma_result[3][128*l+:128] = $signed({operand_a_i[64*(l+1) - 1] & signed_a, operand_a_i[64*l +: 64]}) * $signed({operand_b_i[64*(l+1) - 1] & signed_b, operand_b_i[64*l +: 64]});
      case (op_i)
        VMUL,
        VMACC : result[3][64*l +: 64] = fma_result[3][128*l +: 64]                           ;
        VMULH : result[3][64*l +: 64] = fma_result[3][128*l + 64 +: 64]                      ;
        VMADD : result[3][64*l +: 64] = fma_result[3][128*l +: 64] + operand_c_i[64*l +: 64] ;
        VMSUB : result[3][64*l +: 64] = fma_result[3][128*l +: 64] - operand_c_i[64*l +: 64] ;
        VNMSUB: result[3][64*l +: 64] = -fma_result[3][128*l +: 64] + operand_c_i[64*l +: 64];
        VNMADD: result[3][64*l +: 64] = -fma_result[3][128*l +: 64] - operand_c_i[64*l +: 64];
      endcase
    end

    // 32B
    for (int l = 0; l < 2; l++) begin
      fma_result[2][64*l+:64] = $signed({operand_a_i[32*(l+1) - 1] & signed_a, operand_a_i[32*l +: 32]}) * $signed({operand_b_i[32*(l+1) - 1] & signed_b, operand_b_i[32*l +: 32]});
      case (op_i)
        VMUL,
        VMACC : result[2][32*l +: 32] = fma_result[2][64*l +: 32]                           ;
        VMULH : result[2][32*l +: 32] = fma_result[2][64*l + 32 +: 32]                      ;
        VMADD : result[2][32*l +: 32] = fma_result[2][64*l +: 32] + operand_c_i[32*l +: 32] ;
        VMSUB : result[2][32*l +: 32] = fma_result[2][64*l +: 32] - operand_c_i[32*l +: 32] ;
        VNMSUB: result[2][32*l +: 32] = -fma_result[2][64*l +: 32] + operand_c_i[32*l +: 32];
        VNMADD: result[2][32*l +: 32] = -fma_result[2][64*l +: 32] - operand_c_i[32*l +: 32];
      endcase
    end

    // 16B
    for (int l = 0; l < 4; l++) begin
      fma_result[1][32*l+:32] = $signed({operand_a_i[16*(l+1) - 1] & signed_a, operand_a_i[16*l +: 16]}) * $signed({operand_b_i[16*(l+1) - 1] & signed_b, operand_b_i[16*l +: 16]});
      case (op_i)
        VMUL,
        VMACC : result[1][16*l +: 16] = fma_result[1][32*l +: 16]                           ;
        VMULH : result[1][16*l +: 16] = fma_result[1][32*l + 16 +: 16]                      ;
        VMADD : result[1][16*l +: 16] = fma_result[1][32*l +: 16] + operand_c_i[16*l +: 16] ;
        VMSUB : result[1][16*l +: 16] = fma_result[1][32*l +: 16] - operand_c_i[16*l +: 16] ;
        VNMSUB: result[1][16*l +: 16] = -fma_result[1][32*l +: 16] + operand_c_i[16*l +: 16];
        VNMADD: result[1][16*l +: 16] = -fma_result[1][32*l +: 16] - operand_c_i[16*l +: 16];
      endcase
    end

    for (int l = 0; l < 8; l++) begin
      fma_result[0][16*l+:16] = $signed({operand_a_i[ 8*(l+1) - 1] & signed_a, operand_a_i[ 8*l +: 8]}) * $signed({operand_b_i[ 8*(l+1) - 1] & signed_b, operand_b_i[ 8*l +: 8]});
      case (op_i)
        VMUL,
        VMACC : result[0][ 8*l +: 8] = fma_result[0][16*l +: 8]                          ;
        VMULH : result[0][ 8*l +: 8] = fma_result[0][16*l + 8 +: 8]                      ;
        VMADD : result[0][ 8*l +: 8] = fma_result[0][16*l +: 8] + operand_c_i[ 8*l +: 8] ;
        VMSUB : result[0][ 8*l +: 8] = fma_result[0][16*l +: 8] - operand_c_i[ 8*l +: 8] ;
        VNMSUB: result[0][ 8*l +: 8] = -fma_result[0][16*l +: 8] + operand_c_i[ 8*l +: 8];
        VNMADD: result[0][ 8*l +: 8] = -fma_result[0][16*l +: 8] - operand_c_i[ 8*l +: 8];
      endcase
    end
  end

  // Input signals for the next stage (= output signals of the previous stage)

  logic    [NumPipeRegs:0][ 3:0][63:0] result_d ;
  logic    [NumPipeRegs:0][ 7:0]       operand_m_d;
  logic    [NumPipeRegs:0]             valid_d ;
  vwidth_t [NumPipeRegs:0]             width_d ;
  // Ready signal is combinatorial for all stages
  logic    [NumPipeRegs:0]             stage_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign result_d[0]    = result     ;
  assign operand_m_d[0] = operand_m_i;
  assign valid_d[0]     = valid_i    ;
  assign width_d[0]     = width_i    ;

  // Generate the pipeline stages in case they are needed
  if (NumPipeRegs > 0) begin : gen_pipeline
    // Pipelined versions of signals for later stages
    logic [NumPipeRegs-1:0][3:0][63:0] result_q ;
    logic [NumPipeRegs-1:0][7:0] operand_m_q    ;
    logic [NumPipeRegs-1:0] valid_q             ;
    vwidth_t [NumPipeRegs-1:0] width_q          ;

    for (genvar i = 0; i < NumPipeRegs; i++) begin : pipeline_stages
      // Next state from previous register to form a shift register
      assign result_d[i+1]    = result_q[i]   ;
      assign operand_m_d[i+1] = operand_m_q[i];
      assign valid_d[i+1]     = valid_q[i]    ;
      assign width_d[i+1]     = width_q[i]    ;

      // Determine the ready signal of the current stage - advance the pipeline:
      // 1. if the next stage is ready for our data
      // 2. if the next stage register only holds a bubble (not valid) -> we can pop it
      assign stage_ready[i] = stage_ready[i+1] | ~valid_q[i];

      // Enable register if pipleine ready
      logic reg_ena;
      assign reg_ena = stage_ready[i];

      // Generate the pipeline
      `FFL(valid_q[i], valid_d[i], reg_ena, '0)
      `FFL(result_q[i], result_d[i], reg_ena, '0)
      `FFL(operand_m_q[i], operand_m_d[i], reg_ena, '0)
      `FFL(width_q[i], width_d[i], reg_ena, riscv::WD_V8B)
    end
  end

  // Input stage: Propagate ready signal from pipeline
  assign ready_o = stage_ready[0];

  // Output stage: bind last stage outputs to module output. Directly connects to input if no regs.
  assign result_o    = result_d[NumPipeRegs][ width_d[NumPipeRegs] ];
  assign operand_m_o = operand_m_d[NumPipeRegs]                     ;
  assign valid_o     = valid_d[NumPipeRegs]                         ;

  // Output stage: Ready travels backwards from output side
  assign stage_ready[NumPipeRegs] = ready_i;

endmodule : simd_mul
