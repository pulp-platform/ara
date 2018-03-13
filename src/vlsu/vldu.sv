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
// File          : vldu.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 15.01.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Vector Load Unit

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

module vldu (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    // Memory interface
    output axi_req_t                    ara_axi_req_o,
    input  axi_resp_t                   ara_axi_resp_i,
    // Operation
    input  lane_req_t                   operation_i,
    output lane_resp_t                  resp_o,
    // Operands
    input  word_t        [NR_LANES-1:0] ld_operand_i,
    output logic                        ld_operand_ready_o,
    // Address
    input  addr_t                       addr_i,
    input  logic                        addr_valid_i,
    output logic                        addr_ready_o,
    // Results
    output arb_request_t [NR_LANES-1:0] ld_result_o,
    input  logic         [NR_LANES-1:0] ld_result_gnt_i
  );

  /*******************
   *  OUTPUT BUFFER  *
   *******************/

  localparam OBUF_DEPTH = 2;

  struct packed {
    word_t [NR_LANES-1:0] lane_result;

    union_word_t [OBUF_DEPTH-1:0] result    ;
    logic [$clog2(OBUF_DEPTH)-1:0] read_pnt ;
    logic [$clog2(OBUF_DEPTH)-1:0] write_pnt;
    logic [$clog2(OBUF_DEPTH):0] cnt        ;

    voffset_full_t result_pnt;

    // AXI pointers
    logic [$clog2(StrbWidth):0] axi_pnt;
    vsize_full_t burst_pnt             ;
    logic first_word                   ;
  } obuf_d, obuf_q;

  logic obuf_full;
  logic obuf_empty;

  assign obuf_full  = obuf_q.cnt == OBUF_DEPTH;
  assign obuf_empty = obuf_q.cnt == 0         ;

  logic [NR_LANES-1:0] lane_req_d, lane_req_q;

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

  /***********************
   *  SHUFFLE/DESHUFFLE  *
   ***********************/

  word_full_t ld_operand;

  vsize_full_t issue_cnt_d, issue_cnt_q;
  vsize_full_t commit_cnt_d, commit_cnt_q;

  `define MIN2(a,b) (((a) < (b)) ? (a) : (b))
  `define MIN3(a,b,c) (((`MIN2(a,b)) < (c)) ? (`MIN2(a,b)) : (c))

  // Number of bytes being committed
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
    obuf_d         = obuf_q                                   ;
    opqueue_d      = opqueue_q                                ;
    loop_running_d = loop_running_q & operation_i.loop_running;

    issue_cnt_d  = issue_cnt_q ;
    commit_cnt_d = commit_cnt_q;

    // We are not ready, by default
    ld_operand_ready_o  = 1'b0;
    addr_ready_o        = 1'b0;
    ld_result_o         = '0  ;
    opqueue_d.loop_done = '0  ;

    // Inform controller if we are idle
    resp_o           = '0                 ;
    resp_o.ready     = !opqueue_full      ;
    resp_o.loop_done = opqueue_q.loop_done;

    // Initialize request
    ara_axi_req_o = '0;

    // Operands
    ld_operand = operation_issue_q.mask == riscv::NOMASK ? '1 : deshuffle(ld_operand_i, width_i);

    // R Channel
    begin: r_channel
      if (ara_axi_resp_i.r_valid) begin
        if (issue_valid && !obuf_full && (ld_operand.valid || operation_issue_q.mask == riscv::NOMASK) & addr_valid_i) begin

          // Copy data
          for (int b = 0; b < StrbWidth; b++)
            if (b < commit_cnt) begin
              obuf_d.result[obuf_q.write_pnt].w8[obuf_q.result_pnt + b] = ara_axi_resp_i.r.data[8*b + 8*obuf_q.axi_pnt + 8*addr_i.addr[$clog2(StrbWidth)-1:0] +: 8] & ld_operand.word.w8[obuf_q.result_pnt + b];
            end

          // Bump pointers
          obuf_d.axi_pnt += commit_cnt   ;
          obuf_d.burst_pnt += commit_cnt ;
          obuf_d.result_pnt += commit_cnt;

          if (obuf_d.axi_pnt == StrbWidth) begin
            ara_axi_req_o.r_ready = 1'b1                               ;
            obuf_d.axi_pnt        = -addr_i.addr[$clog2(StrbWidth)-1:0];
            obuf_d.first_word     = 1'b0                               ;
          end

          if (obuf_d.burst_pnt == addr_i.burst_length) begin
            ara_axi_req_o.r_ready = 1'b1;
            obuf_d.axi_pnt        = '0  ;
            obuf_d.burst_pnt      = '0  ;
            obuf_d.first_word     = 1'b1;
            addr_ready_o          = 1'b1;
          end

          // Filled up a word.
          if (obuf_d.result_pnt == (NR_LANES * 8) || obuf_d.result_pnt == issue_cnt_q) begin
            obuf_d.write_pnt += 1;
            obuf_d.cnt += 1      ;
            obuf_d.result_pnt = '0;
            issue_cnt_d -= (NR_LANES * 8);
            ld_operand_ready_o = 1'b1;
          end
        end
      end
    end: r_channel

    // Output interface
    for (int l = 0; l < NR_LANES; l++) begin
      ld_result_o[l].req   = obuf_q.lane_result[l].valid;
      ld_result_o[l].wdata = obuf_q.lane_result[l].word ;
      ld_result_o[l].prio  = 1'b0                       ;
      ld_result_o[l].we    = 1'b1                       ;
      ld_result_o[l].addr  = operation_commit_q.vd.addr ;
      ld_result_o[l].id    = operation_commit_q.id      ;

      if (ld_result_gnt_i[l]) begin
        obuf_d.lane_result[l].word  = '0  ;
        obuf_d.lane_result[l].valid = 1'b0;
      end
    end

    // Idle output interfaces
    for (int l = 0; l < NR_LANES; l++) begin
      lane_req_d[l] = obuf_d.lane_result[l].valid;
      lane_req_q[l] = obuf_q.lane_result[l].valid;
    end

    if (~(|lane_req_d)) begin
      // There is something waiting to be written
      if (!obuf_empty) begin
        obuf_d.lane_result             = shuffle(obuf_q.result[obuf_q.read_pnt], opqueue_q.insn[opqueue_q.commit_pnt].vd.dstt.width);
        obuf_d.result[obuf_q.read_pnt] = '0                                                                                         ;

        // If this is a scalar, broadcast result into all lanes.
        if (operation_commit_q.vd.dstt.shape == riscv::SH_SCALAR) begin
          for (int l = 0; l < NR_LANES; l++)
            obuf_d.lane_result[l] = obuf_d.lane_result[0];
        end

        obuf_d.read_pnt += 1;
        obuf_d.cnt -= 1     ;
      end

      // Finished writing
      if (|lane_req_q) begin
        commit_cnt_d -= 8 * NR_LANES;
        opqueue_d.insn[opqueue_q.commit_pnt].vd.addr = increment_addr(operation_commit_q.vd.addr, operation_commit_q.vd.id);
      end
    end

    // Finished issuing micro-operations
    if (issue_valid && $signed(issue_cnt_d) <= 0) begin
      opqueue_d.issue_cnt -= 1;
      opqueue_d.issue_pnt += 1;

      if (opqueue_d.issue_cnt != 0)
        issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].vd.length;
    end

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      opqueue_d.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].vd.length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && !loop_running_q[operation_i.id] && operation_i.fu == VFU_LD) begin
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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      obuf_q         <= '0;
      opqueue_q      <= '0;
      loop_running_q <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      obuf_q         <= obuf_d        ;
      opqueue_q      <= opqueue_d     ;
      loop_running_q <= loop_running_d;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : vldu
