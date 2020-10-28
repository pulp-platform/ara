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
// File          : opqueue.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 20.04.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This module converts between vector types, and serializes the result.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;
import riscv::*           ;

module opqueue #(
    parameter int unsigned IBUF_DEPTH = 2,
    parameter int unsigned NR_SLAVES  = 1
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  word_t                        word_i,
    output word_t                        word_o,
    // Controls the conversion
    input  opqueue_cmd_t                 opqueue_cmd_i,
    // Word issued
    input  logic                         word_issued_i,
    // Pipeline control
    input  logic         [NR_SLAVES-1:0] ready_i,
    output logic                         ready_o
  );

  /******************
   *  INPUT BUFFER  *
   ******************/

  struct packed {
    logic [IBUF_DEPTH-1:0][63:0] buffer              ;
    opqueue_cmd_t [IBUF_DEPTH-1:0] opqueue_cmd_buffer;

    logic [$clog2(IBUF_DEPTH)-1:0] read_pnt ;
    logic [$clog2(IBUF_DEPTH)-1:0] write_pnt;
    logic [$clog2(IBUF_DEPTH):0] cnt        ;

    logic [$clog2(IBUF_DEPTH):0] issue_cnt;
  } ibuf_d, ibuf_q;

  logic                ibuf_full;
  logic                ibuf_empty;
  logic                ibuf_pop;
  logic         [63:0] ibuf;
  opqueue_cmd_t        opqueue_cmd_d, opqueue_cmd_q;

  // Assignments
  assign ibuf_full     = ibuf_q.cnt == IBUF_DEPTH                  ;
  assign ibuf_empty    = ibuf_d.cnt == 0                           ;
  assign ready_o       = ibuf_q.issue_cnt != IBUF_DEPTH            ;
  assign ibuf          = ibuf_d.buffer[ibuf_d.read_pnt]            ;
  assign opqueue_cmd_d = ibuf_d.opqueue_cmd_buffer[ibuf_d.read_pnt];
  assign opqueue_cmd_q = ibuf_q.opqueue_cmd_buffer[ibuf_q.read_pnt];

  // Input buffer control
  always_comb begin: ibuf_ctrl
    // Maintain state
    ibuf_d = ibuf_q;

    // Not popping any words
    ibuf_pop = 1'b0;

    // Writing to buffer
    if (word_i.valid) begin
      ibuf_d.buffer[ibuf_q.write_pnt]             = word_i.word  ;
      ibuf_d.opqueue_cmd_buffer[ibuf_q.write_pnt] = opqueue_cmd_i;
      ibuf_d.cnt += 1'b1      ;
      ibuf_d.write_pnt += 1'b1;
      if (ibuf_q.write_pnt == IBUF_DEPTH - 1)
        ibuf_d.write_pnt = 0;
    end

    // Word issued
    if (word_issued_i)
      ibuf_d.issue_cnt += 1'b1;

    // Reading from buffer
    if (ibuf_q.cnt != 0 && ready_i[opqueue_cmd_q.slave_select]) begin
      if (opqueue_cmd_q.srct.width == opqueue_cmd_q.dstt.width)
        ibuf_d.opqueue_cmd_buffer[ibuf_q.read_pnt].cnt = opqueue_cmd_q.cnt - 8;
      else
        ibuf_d.opqueue_cmd_buffer[ibuf_q.read_pnt].cnt = opqueue_cmd_q.cnt - 4;

      if ($signed(ibuf_d.opqueue_cmd_buffer[ibuf_q.read_pnt].cnt) <= 0) begin // Used all repetitions of this word
        ibuf_d.cnt -= 1'b1      ;
        ibuf_d.issue_cnt -= 1'b1;
        ibuf_d.read_pnt += 1'b1 ;
        ibuf_pop = 1'b1;
        if (ibuf_q.read_pnt == IBUF_DEPTH - 1)
          ibuf_d.read_pnt = 0;
      end
    end
  end : ibuf_ctrl

  `ifndef SYNTHESIS
  `ifndef verilator
  assert property (@(posedge clk_i) ibuf_full |=> ~word_i.valid)
  else $fatal (1, "Tried to write into a full IBUF.");
  `endif
  `endif

  /*********************
   *  TYPE CONVERSION  *
   *********************/

  logic [63:0] conv_result;
  logic        hilo_q, hilo_d;

  function automatic logic [31:0] sext16 (logic [15:0] operand);
    return {{16{operand[15]}}, operand[15:0]}                  ;
  endfunction : sext16

  function automatic logic [15:0] sext8 (logic [7:0] operand);
    return {{ 8{operand[ 7]}}, operand[ 7:0]}                ;
  endfunction : sext8

  always_comb begin: type_conversion
    // Default value
    conv_result = '0;

    case (opqueue_cmd_d.conv_type)
      INT_CONV: begin
        automatic logic sext = opqueue_cmd_d.srct.repr == RP_SIGNED;

        case ({opqueue_cmd_d.srct.width, opqueue_cmd_d.dstt.width})
          { WD_V8B, WD_V16B}:
            for (int b = 0; b < 4; b++)
              conv_result[16*b +: 16] = sext ? sext8(ibuf[ 8*hilo_d + 16*b +: 8]) : { 8'b0, ibuf[ 8*hilo_d + 16*b +: 8]};
          {WD_V16B, WD_V32B}:
            for (int b = 0; b < 2; b++)
              conv_result[32*b +: 32] = sext ? sext16(ibuf[16*hilo_d + 32*b +: 16]) : {16'b0, ibuf[16*hilo_d + 32*b +: 16]};
          {WD_V32B, WD_V64B}:
            conv_result = sext ? sext32(ibuf[32*hilo_d +: 32]) : {32'b0, ibuf[32*hilo_d +: 32]};
          default:
            // No conversion
            conv_result = ibuf;
        endcase
      end

      FLOAT_CONV: begin
        case ({opqueue_cmd_d.srct.width, opqueue_cmd_d.dstt.width})
          {WD_V16B, WD_V32B}:
            for (int b = 0; b < 2; b++) begin
              automatic fp16_t fp16 = ibuf[16*hilo_d + 32*b +: 16];
              automatic fp32_t fp32;

              fp32.sign     = fp16.sign                 ;
              fp32.exponent = (fp16.exponent - 15) + 127;
              fp32.mantissa = {fp16.mantissa, 13'b0}    ;

              conv_result[32*b +: 32] = fp32;
            end
          {WD_V32B, WD_V64B}: begin
            automatic fp32_t fp32 = ibuf[32*hilo_d +: 32];
            automatic fp64_t fp64;

            fp64.sign     = fp32.sign                   ;
            fp64.exponent = (fp32.exponent - 127) + 1023;
            fp64.mantissa = {fp32.mantissa, 29'b0}      ;

            conv_result = fp64;
          end
          default:
            // No conversion.
            conv_result = ibuf;
        endcase
      end

      MASK_CONV: begin
        // Non-negated mask
        automatic logic neg = opqueue_cmd_d.mask == riscv::LSBMASK;

        case ({opqueue_cmd_d.srct.width, opqueue_cmd_d.dstt.width})
          { WD_V8B, WD_V8B}:
            for (int b = 0; b < 8; b++) conv_result[ 8*b +: 8] = neg ? { 8{ibuf[8*b]}} : ~{ 8{ibuf[8*b]}};
          { WD_V8B, WD_V16B}:
            for (int b = 0; b < 4; b++) conv_result[16*b +: 16] = neg ? {16{ibuf[ 8*hilo_d + 16*b]}} : ~{16{ibuf[ 8*hilo_d + 16*b]}};
          {WD_V16B, WD_V16B}:
            for (int b = 0; b < 4; b++) conv_result[16*b +: 16] = neg ? {16{ibuf[16*b]}} : ~{16{ibuf[16*b]}};
          {WD_V16B, WD_V32B}:
            for (int b = 0; b < 2; b++) conv_result[32*b +: 32] = neg ? {32{ibuf[16*hilo_d + 32*b]}} : ~{32{ibuf[16*hilo_d + 32*b]}};
          {WD_V32B, WD_V32B}:
            for (int b = 0; b < 2; b++) conv_result[32*b +: 32] = neg ? {32{ibuf[32*b]}} : ~{32{ibuf[32*b]}};
          {WD_V32B, WD_V64B}:
            conv_result = neg ? {64{ibuf[32*hilo_d]}} : ~{64{ibuf[32*hilo_d]}};
          {WD_V64B, WD_V64B}:
            conv_result = neg ? {64{ibuf[32*hilo_d]}} : ~{64{ibuf[32*hilo_d]}};
        endcase
      end
    endcase

    // Replicate conversion result if source is scalar
    if (opqueue_cmd_d.srct.shape == SH_SCALAR)
      case (opqueue_cmd_d.dstt.width)
        WD_V8B:
          for (int b = 0; b < 8; b++) conv_result[ 8*b +: 8] = conv_result[ 7:0];
        WD_V16B:
          for (int b = 0; b < 4; b++) conv_result[16*b +: 16] = conv_result[15:0];
        WD_V32B:
          for (int b = 0; b < 2; b++) conv_result[32*b +: 32] = conv_result[31:0];
      endcase
  end : type_conversion

  /********************
   *  OPERAND OUTPUT  *
   ********************/

  word_t word_d;

  always_comb begin: obuf_ctrl
    // Maintain state
    hilo_d = hilo_q;

    // No output
    word_d = '0;

    // Send operand
    word_d = {conv_result, !ibuf_empty};

    // Account for sent operands
    if (ready_i[opqueue_cmd_q.slave_select] && opqueue_cmd_q.srct.shape != SH_SCALAR) begin
      if (opqueue_cmd_q.srct.width == opqueue_cmd_q.dstt.width)
        hilo_d = 1'b0;
      else
        hilo_d = ~hilo_q;
    end

    // Reset pointer
    if (ibuf_pop)
      hilo_d = 1'b0;
    if ($signed(opqueue_cmd_q.cnt) <= 0)
      hilo_d = 1'b0;
  end : obuf_ctrl

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(negedge rst_ni or posedge clk_i) begin
    if (!rst_ni) begin
      ibuf_q <= '0;
      hilo_q <= '0;

      word_o <= '0;
    end else begin
      ibuf_q <= ibuf_d;
      hilo_q <= hilo_d;

      word_o <= word_d;
    end
  end

endmodule : opqueue
