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
// File          : valu.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 28.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's ALU.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module valu (
    input  logic               clk_i,
    input  logic               rst_ni,
    // Operation
    input  operation_t         operation_i,
    output vfu_status_t        vfu_status_o,
    // Operands
    input  word_t        [2:0] alu_operand_i,
    output logic               alu_operand_ready_o,
    // Result
    output arb_request_t       alu_result_o,
    input  logic               alu_result_gnt_i
  );

  /*******************
   *  OUTPUT BUFFER  *
   *******************/

  localparam int unsigned OBUF_DEPTH = 2;
  struct packed {
    logic [OBUF_DEPTH-1:0][63:0] result;

    logic [$clog2(OBUF_DEPTH)-1:0] read_pnt ;
    logic [$clog2(OBUF_DEPTH)-1:0] write_pnt;
    logic [$clog2(OBUF_DEPTH):0] cnt        ;

    voffset_t offset;
  } obuf_d, obuf_q;

  logic obuf_full;
  logic obuf_empty;
  assign obuf_full  = obuf_q.cnt == OBUF_DEPTH;
  assign obuf_empty = obuf_q.cnt == 0         ;

  /*********************
   *  OPERATION QUEUE  *
   *********************/

  struct packed {
    operation_t [OPQUEUE_DEPTH-1:0] insn;

    logic [$clog2(OPQUEUE_DEPTH)-1:0] issue_pnt ;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] commit_pnt;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] accept_pnt;

    logic [$clog2(OPQUEUE_DEPTH):0] issue_cnt ;
    logic [$clog2(OPQUEUE_DEPTH):0] commit_cnt;
  } opqueue_d, opqueue_q;

  logic opqueue_full;
  assign opqueue_full = opqueue_q.commit_cnt == OPQUEUE_DEPTH;

  logic issue_valid;
  logic commit_valid;
  assign issue_valid  = opqueue_q.issue_cnt != 0 ;
  assign commit_valid = opqueue_q.commit_cnt != 0;

  operation_t operation_issue_q;
  operation_t operation_commit_q;
  assign operation_issue_q  = opqueue_q.insn[opqueue_q.issue_pnt] ;
  assign operation_commit_q = opqueue_q.insn[opqueue_q.commit_pnt];

  vfu_op op_i;
  riscv::vwidth_t width_i;
  riscv::vrepr_t repr_i  ;
  assign op_i    = opqueue_q.insn[opqueue_q.issue_pnt].op      ;
  assign width_i = opqueue_q.insn[opqueue_q.issue_pnt].vd.width;
  assign repr_i  = opqueue_q.insn[opqueue_q.issue_pnt].vd.repr ;

  /***********
   *  STATE  *
   ***********/

  vsize_t issue_cnt_d, issue_cnt_q;
  vsize_t commit_cnt_d, commit_cnt_q;

  /**************
   *  OPERANDS  *
   **************/

  logic [63:0] operand_a;
  logic [63:0] operand_b;
  logic [63:0] operand_m;

  assign operand_m = operation_issue_q.mask == riscv::NOMASK ? '1 : alu_operand_i[0].word;
  assign operand_a = alu_operand_i[1].word;
  assign operand_b = operation_issue_q.use_imm ? operation_issue_q.imm : alu_operand_i[2].word;

  /**************
   *  SIMD ALU  *
   **************/

  logic [63:0] result_int;
  logic        alu_in_valid;

  simd_alu i_simd_alu (
    .op_i       (op_i        ),
    .width_i    (width_i     ),
    .repr_i     (repr_i      ),
    .operand_a_i(operand_a   ),
    .operand_b_i(operand_b   ),
    .operand_m_i(operand_m   ),
    .valid_i    (alu_in_valid),
    .result_o   (result_int  )
  );

  /*************
   *  CONTROL  *
   *************/

  always_comb begin
    automatic logic operand_valid = 1'b0;

    // Maintain state
    opqueue_d = opqueue_q;
    obuf_d    = obuf_q   ;

    issue_cnt_d  = issue_cnt_q ;
    commit_cnt_d = commit_cnt_q;

    // We are not acknowledging any operands
    alu_operand_ready_o = 1'b0;
    alu_in_valid        = '0  ;

    // Inform controller of our status
    vfu_status_o.ready     = !opqueue_full;
    vfu_status_o.loop_done = '0           ;

    // No result
    alu_result_o = '0;

    if (issue_valid)
      // Valid input operands?
      case (operation_issue_q.op)
        // This instruction only use one operand
        VPOPC:
          operand_valid = (alu_operand_i[0].valid || operation_issue_q.mask == riscv::NOMASK) & alu_operand_i[1].valid;
        default:
          operand_valid = (alu_operand_i[0].valid || operation_issue_q.mask == riscv::NOMASK) & alu_operand_i[1].valid & (alu_operand_i[2].valid || operation_issue_q.use_imm);
      endcase

    // Input interface
    if (!obuf_full)
      if (operand_valid) begin
        // Activate ALUs
        alu_in_valid = '1;

        // Acknowledge operand
        alu_operand_ready_o = 1'b1;

        // Store intermediate results
        obuf_d.result[obuf_q.write_pnt] = result_int;

        // Bump issue pointer
        issue_cnt_d -= 8;

        // Filled up a word.
        obuf_d.cnt += 1'b1;
        obuf_d.write_pnt = obuf_q.write_pnt + 1'b1;
        if (obuf_q.write_pnt == OBUF_DEPTH - 1)
          obuf_d.write_pnt = 0;
      end

    // Output interface
    if (!obuf_empty) begin
      alu_result_o.req   = 1'b1                          ;
      alu_result_o.prio  = 1'b1                          ;
      alu_result_o.we    = 1'b1                          ;
      alu_result_o.addr  = operation_commit_q.addr       ;
      alu_result_o.id    = operation_commit_q.id         ;
      alu_result_o.wdata = obuf_q.result[obuf_q.read_pnt];

      if (alu_result_gnt_i) begin
        opqueue_d.insn[opqueue_q.commit_pnt].addr = increment_addr(operation_commit_q.addr, operation_commit_q.vid);
        commit_cnt_d -= 8;
        obuf_d.result[obuf_q.read_pnt] = '0;

        obuf_d.cnt -= 1'b1;
        obuf_d.read_pnt = obuf_q.read_pnt + 1'b1;
        if (obuf_q.read_pnt == OBUF_DEPTH - 1)
          obuf_d.read_pnt = 0;
      end
    end

    // Finished issuing micro-operations
    if (issue_valid && $signed(issue_cnt_d) <= 0) begin
      opqueue_d.issue_cnt -= 1;
      opqueue_d.issue_pnt += 1;

      if (opqueue_d.issue_cnt != 0)
        issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].length;
    end

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      vfu_status_o.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && operation_i.fu == VFU_ALU) begin
      opqueue_d.insn[opqueue_q.accept_pnt] = operation_i;

      // Initialize issue and commit counters
      if (opqueue_d.issue_cnt == 0)
        issue_cnt_d = operation_i.length;
      if (opqueue_d.commit_cnt == 0)
        commit_cnt_d = operation_i.length;

      // Bump pointers
      opqueue_d.accept_pnt += 1;
      opqueue_d.issue_cnt += 1 ;
      opqueue_d.commit_cnt += 1;
    end
  end

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      opqueue_q <= '0;
      obuf_q    <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      opqueue_q <= opqueue_d;
      obuf_q    <= obuf_d   ;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : valu
