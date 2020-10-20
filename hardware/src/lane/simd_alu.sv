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
// File          : simd_alu.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 11.04.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's ALU.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;
import riscv::vwidth_t    ;
import riscv::vrepr_t     ;

module simd_alu (
    input  logic    [63:0] operand_a_i,
    input  logic    [63:0] operand_b_i,
    input  logic    [63:0] operand_m_i,
    input  vfu_op          op_i,
    input  vwidth_t        width_i,
    input  vrepr_t         repr_i,
    input  logic           valid_i,
    output logic    [63:0] result_o
  );

  // Structs

  union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8 ;
  } op_a, op_b, op_m, result;
  assign op_a     = operand_a_i;
  assign op_b     = operand_b_i;
  assign op_m     = operand_m_i;
  assign result_o = result     ;

  // Pop count

  logic [7:0][3:0] popc;

  for (genvar b = 0; b < 8; b++) begin
    popcount #(
      .INPUT_WIDTH(8)
    ) i_popcount (
      .data_i    (op_a.w8[b]),
      .popcount_o(popc[b]   )
    );
  end

  // ALU

  always_comb begin
    automatic logic [7:0] less = 'b0                       ;
    automatic logic rp_signed  = repr_i == riscv::RP_SIGNED;

    // No output, by default
    result = '0;

    if (valid_i) begin
      // Comparisons
      unique case (width_i)
        riscv::WD_V8B : for (int b = 0; b < 8; b++) less[1*b] = $signed({rp_signed & op_a.w8 [b][ 7], op_a.w8 [b]}) < $signed({rp_signed & op_b.w8 [b][ 7], op_b.w8 [b]});
        riscv::WD_V16B: for (int b = 0; b < 4; b++) less[2*b] = $signed({rp_signed & op_a.w16[b][15], op_a.w16[b]}) < $signed({rp_signed & op_b.w16[b][15], op_b.w16[b]});
        riscv::WD_V32B: for (int b = 0; b < 2; b++) less[4*b] = $signed({rp_signed & op_a.w32[b][31], op_a.w32[b]}) < $signed({rp_signed & op_b.w32[b][31], op_b.w32[b]});
        riscv::WD_V64B: for (int b = 0; b < 1; b++) less[8*b] = $signed({rp_signed & op_a.w64[b][63], op_a.w64[b]}) < $signed({rp_signed & op_b.w64[b][63], op_b.w64[b]});
      endcase // width_i

      unique case (op_i)
        VAND: result = operand_a_i & operand_b_i;
        VOR : result = operand_a_i | operand_b_i;
        VXOR: result = operand_a_i ^ operand_b_i;
        VSLL: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = $unsigned(op_a.w8 [b]) << op_b.w8[b][2:0];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = $unsigned(op_a.w16[b]) << op_b.w16[b][3:0];
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = $unsigned(op_a.w32[b]) << op_b.w32[b][4:0];
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = $unsigned(op_a.w64[b]) << op_b.w64[b][5:0];
          endcase
        VSRL: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = $unsigned(op_a.w8 [b]) >> op_b.w8[b][2:0];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = $unsigned(op_a.w16[b]) >> op_b.w16[b][3:0];
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = $unsigned(op_a.w32[b]) >> op_b.w32[b][4:0];
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = $unsigned(op_a.w64[b]) >> op_b.w64[b][5:0];
          endcase
        VSRA: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = $signed(op_a.w8 [b]) >>> op_b.w8[b][2:0];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = $signed(op_a.w16[b]) >>> op_b.w16[b][3:0];
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = $signed(op_a.w32[b]) >>> op_b.w32[b][4:0];
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = $signed(op_a.w64[b]) >>> op_b.w64[b][5:0];
          endcase
        VADD: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = $signed(op_a.w8 [b]) + $signed(op_b.w8 [b]);
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = $signed(op_a.w16[b]) + $signed(op_b.w16[b]);
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = $signed(op_a.w32[b]) + $signed(op_b.w32[b]);
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = $signed(op_a.w64[b]) + $signed(op_b.w64[b]);
          endcase
        VSUB: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = $signed(op_a.w8 [b]) - $signed(op_b.w8 [b]);
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = $signed(op_a.w16[b]) - $signed(op_b.w16[b]);
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = $signed(op_a.w32[b]) - $signed(op_b.w32[b]);
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = $signed(op_a.w64[b]) - $signed(op_b.w64[b]);
          endcase
        VPOPC: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = popc[1 * b + 0];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = (popc[2 * b + 0] + popc[2 * b + 1]);
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = (popc[4 * b + 0] + popc[4 * b + 1]) + (popc[4 * b + 2] + popc[4 * b + 3]);
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = ((popc[8 * b + 0] + popc[8 * b + 1]) + (popc[8 * b + 2] + popc[8 * b + 3])) +
                ((popc[8 * b + 4] + popc[8 * b + 5]) + (popc[8 * b + 6] + popc[8 * b + 7]));
          endcase
        VMERGE: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = ~op_m.w8 [b][0] ? op_a.w8 [b] : op_b.w8 [b];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = ~op_m.w16[b][0] ? op_a.w16[b] : op_b.w16[b];
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = ~op_m.w32[b][0] ? op_a.w32[b] : op_b.w32[b];
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = ~op_m.w64[b][0] ? op_a.w64[b] : op_b.w64[b];
          endcase
        VEQ, VNE: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b][0] = (op_a.w8 [b] == op_b.w8 [b]) ^ (op_i == VNE);
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b][0] = (op_a.w16[b] == op_b.w16[b]) ^ (op_i == VNE);
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b][0] = (op_a.w32[b] == op_b.w32[b]) ^ (op_i == VNE);
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b][0] = (op_a.w64[b] == op_b.w64[b]) ^ (op_i == VNE);
          endcase
        VLT, VGE: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b][0] = less[1*b] ^ (op_i == VGE);
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b][0] = less[2*b] ^ (op_i == VGE);
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b][0] = less[4*b] ^ (op_i == VGE);
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b][0] = less[8*b] ^ (op_i == VGE);
          endcase
        VMIN, VMAX: unique case (width_i)
            riscv::WD_V8B : for (int b = 0; b < 8; b++) result.w8 [b] = (less[1*b] ^ (op_i == VMAX)) ? op_a.w8 [b] : op_b.w8 [b];
            riscv::WD_V16B: for (int b = 0; b < 4; b++) result.w16[b] = (less[2*b] ^ (op_i == VMAX)) ? op_a.w16[b] : op_b.w16[b];
            riscv::WD_V32B: for (int b = 0; b < 2; b++) result.w32[b] = (less[4*b] ^ (op_i == VMAX)) ? op_a.w32[b] : op_b.w32[b];
            riscv::WD_V64B: for (int b = 0; b < 1; b++) result.w64[b] = (less[8*b] ^ (op_i == VMAX)) ? op_a.w64[b] : op_b.w64[b];
          endcase
      endcase

      // Mask result
      if (op_i != VMERGE)
        for (int b = 0; b < 8; b++) result.w8[b] = result.w8[b] & op_m.w8[b];
    end
  end

endmodule : simd_alu
