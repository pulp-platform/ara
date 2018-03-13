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
// File          : vstu.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 15.01.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Vector Store Unit

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

import ara_axi_pkg::AddrWidth ;
import ara_axi_pkg::DataWidth ;
import ara_axi_pkg::IdWidth   ;
import ara_axi_pkg::StrbWidth ;
import ara_axi_pkg::UserWidth ;
import ara_axi_pkg::axi_req_t ;
import ara_axi_pkg::axi_resp_t;

module vstu (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Memory interface
    output axi_req_t                       ara_axi_req_o,
    input  axi_resp_t                      ara_axi_resp_i,
    // Operation
    input  lane_req_t                      operation_i,
    output lane_resp_t                     resp_o,
    // Operands
    input  word_t      [NR_LANES-1:0][1:0] st_operand_i,
    output logic                           st_operand_ready_o,
    // Address
    input  addr_t                          addr_i,
    input  logic                           addr_valid_i,
    output logic                           addr_ready_o
  );

  /*******************
   *  OUTPUT BUFFER  *
   *******************/

  struct packed {
    // Pointers
    voffset_full_t result_pnt;
    voffset_full_t axi_pnt   ;
    vsize_full_t burst_pnt   ;

    logic b_ready;
  } obuf_q, obuf_d;

  vsize_full_t issue_cnt_d, issue_cnt_q;
  vsize_full_t commit_cnt_d, commit_cnt_q;

  /*********************
   *  OPERATION QUEUE  *
   *********************/

  struct packed {
    lane_req_t [OPQUEUE_DEPTH-1:0] insn;

    logic [$clog2(OPQUEUE_DEPTH)-1:0] issue_pnt ;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] commit_pnt;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] accept_pnt;

    logic [$clog2(OPQUEUE_DEPTH):0] issue_cnt ;
    logic [$clog2(OPQUEUE_DEPTH):0] commit_cnt;

    logic [VLOOP_ID-1:0] loop_done;
  } opqueue_d, opqueue_q;

  logic opqueue_full;
  assign opqueue_full = opqueue_q.commit_cnt == OPQUEUE_DEPTH;

  logic issue_valid;
  logic commit_valid;
  assign issue_valid  = opqueue_q.issue_cnt != 0 ;
  assign commit_valid = opqueue_q.commit_cnt != 0;

  lane_req_t operation_issue_q;
  lane_req_t operation_commit_q;
  assign operation_issue_q  = opqueue_q.insn[opqueue_q.issue_pnt] ;
  assign operation_commit_q = opqueue_q.insn[opqueue_q.commit_pnt];

  riscv::vwidth_t width_i;
  assign width_i = opqueue_q.insn[opqueue_q.issue_pnt].vd.dstt.width;

  // Running loops
  logic [VLOOP_ID-1:0] loop_running_d, loop_running_q;

  /***************
   *  DESHUFFLE  *
   ***************/

  word_t      [1:0][NR_LANES-1:0] st_operand_transposed;
  word_full_t [1:0]               st_operand_deshuffled;

  always_comb begin: transpose
    for (int l = 0; l < NR_LANES; l++) begin
      st_operand_transposed[0][l] = st_operand_i[l][0];
      st_operand_transposed[1][l] = st_operand_i[l][1];
    end
  end

  assign st_operand_deshuffled[0] = operation_issue_q.mask == riscv::NOMASK ? '1 : deshuffle(st_operand_transposed[0], width_i);
  assign st_operand_deshuffled[1] = deshuffle(st_operand_transposed[1], width_i);

  `define MIN2(a,b) (((a) < (b)) ? (a) : (b))
  `define MIN3(a,b,c) (((`MIN2(a,b)) < (c)) ? (`MIN2(a,b)) : (c))

  // How many bytes are being written
  vsize_full_t vrf_commit_cnt;
  vsize_full_t axi_commit_cnt;
  vsize_full_t burst_commit_cnt;
  vsize_full_t commit_cnt;

  assign vrf_commit_cnt   = (8 * NR_LANES) - obuf_q.result_pnt                             ; // Bytes remaining to fill a VRF word
  assign axi_commit_cnt   = StrbWidth - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]; // Bytes remaining to use a whole AXI word
  assign burst_commit_cnt = addr_i.burst_length - obuf_q.burst_pnt                         ; // Bytes remaining in the current AXI burst
  assign commit_cnt       = `MIN3(burst_commit_cnt, axi_commit_cnt, vrf_commit_cnt)        ; // Bytes effectively being read

  always_comb begin
    // Maintain state
    opqueue_d = opqueue_q;
    obuf_d    = obuf_q   ;

    issue_cnt_d    = issue_cnt_q                              ;
    commit_cnt_d   = commit_cnt_q                             ;
    loop_running_d = loop_running_q & operation_i.loop_running;

    // We are not ready, by default
    st_operand_ready_o  = 1'b0;
    addr_ready_o        = 1'b0;
    opqueue_d.loop_done = '0  ;

    // Running loop
    resp_o           = '0                 ;
    resp_o.ready     = !opqueue_full      ;
    resp_o.loop_done = opqueue_q.loop_done;

    // Initialize request
    ara_axi_req_o = '0;

    // W Channel
    begin: w_channel
      ara_axi_req_o.w_valid = issue_valid & (st_operand_deshuffled[0].valid || operation_issue_q.mask == riscv::NOMASK) & st_operand_deshuffled[1].valid & addr_valid_i;

      // Copy data
      for (int b = 0; b < StrbWidth; b++)
        // Bound check
        if (b >= obuf_q.axi_pnt + addr_i.addr[$clog2(StrbWidth)-1:0] && b < commit_cnt + obuf_q.axi_pnt + addr_i.addr[$clog2(StrbWidth)-1:0]) begin
          ara_axi_req_o.w.data[8*b +: 8] = st_operand_deshuffled[1].word.w8[obuf_q.result_pnt + b - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]]    ;
          ara_axi_req_o.w.strb[b]        = st_operand_deshuffled[0].word.w8[obuf_q.result_pnt + b - obuf_q.axi_pnt - addr_i.addr[$clog2(StrbWidth)-1:0]][0] ;
        end

      if (ara_axi_resp_i.w_ready && ara_axi_req_o.w_valid) begin
        obuf_d.result_pnt += commit_cnt;
        obuf_d.axi_pnt += commit_cnt   ;
        obuf_d.burst_pnt += commit_cnt ;

        if (obuf_d.axi_pnt == StrbWidth)
          obuf_d.axi_pnt = -addr_i.addr[$clog2(StrbWidth)-1:0];

        if (obuf_d.burst_pnt == addr_i.burst_length) begin
          ara_axi_req_o.w.last = 1'b1;
          obuf_d.axi_pnt       = '0  ;
          obuf_d.burst_pnt     = '0  ;
          obuf_d.b_ready       = 1'b1; // Send B_READY
          addr_ready_o         = 1'b1;
        end

        if (obuf_d.result_pnt == (NR_LANES * 8) || obuf_d.result_pnt == issue_cnt_q) begin
          obuf_d.result_pnt  = '0  ;
          st_operand_ready_o = 1'b1;
          issue_cnt_d -= (NR_LANES * 8) ;
          commit_cnt_d -= (NR_LANES * 8);
        end
      end
    end: w_channel

    // B Channel
    begin: b_channel
      ara_axi_req_o.b_ready = obuf_d.b_ready;
      if (ara_axi_resp_i.b_valid)
        obuf_d.b_ready = 1'b0;

      // Finished issuing micro-operations
      if (issue_valid && $signed(issue_cnt_d) <= 0) begin
        opqueue_d.issue_cnt -= 1;
        opqueue_d.issue_pnt += 1;

        if (opqueue_d.issue_cnt != 0)
          issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].vd.length;
      end
    end: b_channel

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      opqueue_d.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].vd.length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && !loop_running_q[operation_i.id] && operation_i.fu == VFU_ST) begin
      opqueue_d.insn[opqueue_q.accept_pnt] = operation_i;
      loop_running_d[operation_i.id]       = 1'b1       ;

      // Unused
      begin
        opqueue_d.insn[opqueue_q.accept_pnt].loop_running = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].rs1          = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].rs2          = '0;
        opqueue_d.insn[opqueue_q.accept_pnt].imm          = '0;
      end

      // Initialize issue and commit counters
      if (opqueue_d.issue_cnt == 0)
        issue_cnt_d = operation_i.vd.length;
      if (opqueue_d.commit_cnt == 0)
        commit_cnt_d = operation_i.vd.length;

      // Bump pointers
      opqueue_d.accept_pnt += 1;
      opqueue_d.issue_cnt += 1 ;
      opqueue_d.commit_cnt += 1;
    end
  end

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(negedge rst_ni or posedge clk_i) begin
    if (!rst_ni) begin
      opqueue_q      <= '0;
      obuf_q         <= '0;
      loop_running_q <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      opqueue_q      <= opqueue_d     ;
      obuf_q         <= obuf_d        ;
      loop_running_q <= loop_running_d;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : vstu
