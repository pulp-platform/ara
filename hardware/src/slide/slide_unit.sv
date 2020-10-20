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
// File          : slide_unit.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 06.02.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Slide unit

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module slide_unit (
    input  logic                             clk_i,
    input  logic                             rst_ni,
    // Operation
    input  lane_req_t                        operation_i,
    output lane_resp_t                       resp_o,
    // Operands
    input  word_t        [NR_LANES-1:0][1:0] sld_operand_i,
    output logic                             sld_operand_ready_o,
    // Results
    output arb_request_t [NR_LANES-1:0]      sld_result_o,
    input  logic         [NR_LANES-1:0]      sld_result_gnt_i
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

  vfu_op op_i;
  riscv::vwidth_t width_i;
  riscv::vrepr_t repr_i  ;
  assign op_i    = opqueue_q.insn[opqueue_q.issue_pnt].op           ;
  assign width_i = opqueue_q.insn[opqueue_q.issue_pnt].vd.dstt.width;
  assign repr_i  = opqueue_q.insn[opqueue_q.issue_pnt].vd.dstt.repr ;

  /***************
   *  DESHUFFLE  *
   ***************/

  word_t      [1:0][NR_LANES-1:0] sld_operand_transposed;
  word_full_t [1:0]               sld_operand_deshuffled;

  always_comb begin: transpose
    for (int l = 0; l < NR_LANES; l++) begin
      sld_operand_transposed[0][l] = sld_operand_i[l][0];
      sld_operand_transposed[1][l] = sld_operand_i[l][1];
    end
  end

  assign sld_operand_deshuffled[0] = operation_issue_q.mask == riscv::NOMASK ? '1 : deshuffle(sld_operand_transposed[0], width_i);
  assign sld_operand_deshuffled[1] = deshuffle(sld_operand_transposed[1], width_i);

  vsize_full_t issue_cnt_d, issue_cnt_q;
  vsize_full_t commit_cnt_d, commit_cnt_q;

  /***********************
   *  CURRENT OPERATION  *
   ***********************/

  logic        sld_in_valid;
  logic        sld_out_valid;
  union_word_t sld_result_d, sld_result_q;
  union_word_t slide_result;

  always_comb begin
    sld_result_d  = sld_result_q;
    sld_out_valid = 1'b0        ;

    if (sld_in_valid)
      case (op_i)
        VINSERT: begin
          sld_result_d  = sld_operand_deshuffled[1].word;
          sld_out_valid = 1'b1                          ;
          case (width_i)
            riscv::WD_V64B: sld_result_d.w64[operation_issue_q.offset] = operation_issue_q.rs1 & sld_operand_deshuffled[0].word.w64[0];
            riscv::WD_V32B: sld_result_d.w32[operation_issue_q.offset] = operation_issue_q.rs1 & sld_operand_deshuffled[0].word.w32[0];
            riscv::WD_V16B: sld_result_d.w16[operation_issue_q.offset] = operation_issue_q.rs1 & sld_operand_deshuffled[0].word.w16[0];
            riscv::WD_V8B : sld_result_d.w8 [operation_issue_q.offset] = operation_issue_q.rs1 & sld_operand_deshuffled[0].word.w8 [0];
          endcase
        end
        VEXTRACT: begin
          sld_result_d  = '0  ;
          sld_out_valid = 1'b1;
          case (width_i)
            riscv::WD_V64B: sld_result_d.w64[0] = repr_i == riscv::RP_SIGNED ? $signed(sld_operand_deshuffled[1].word.w64[operation_issue_q.offset]) : sld_operand_deshuffled[1].word.w64[operation_issue_q.offset];
            riscv::WD_V32B: sld_result_d.w64[0] = repr_i == riscv::RP_SIGNED ? $signed(sld_operand_deshuffled[1].word.w32[operation_issue_q.offset]) : sld_operand_deshuffled[1].word.w32[operation_issue_q.offset];
            riscv::WD_V16B: sld_result_d.w64[0] = repr_i == riscv::RP_SIGNED ? $signed(sld_operand_deshuffled[1].word.w16[operation_issue_q.offset]) : sld_operand_deshuffled[1].word.w16[operation_issue_q.offset];
            riscv::WD_V8B : sld_result_d.w64[0] = repr_i == riscv::RP_SIGNED ? $signed(sld_operand_deshuffled[1].word.w8 [operation_issue_q.offset]) : sld_operand_deshuffled[1].word.w8 [operation_issue_q.offset];
          endcase
        end
        VSLIDE: begin
          if (sld_operand_deshuffled[0].valid && sld_operand_deshuffled[1].valid)
            sld_result_d = sld_operand_deshuffled[1].word & sld_operand_deshuffled[0].word;
          sld_out_valid = 1'b1;
        end
      endcase
  end

  /*************
   *  CONTROL  *
   *************/

  // Running loops
  logic [VLOOP_ID-1:0] loop_running_d, loop_running_q;

  enum logic [1:0] { IDLE,
    SLIDE_WAIT_OP,
    SLIDE_WRITE } state_d, state_q;

  always_comb begin
    automatic logic operand_valid = 1'b0;

    // Maintain state
    state_d   = state_q  ;
    obuf_d    = obuf_q   ;
    opqueue_d = opqueue_q;

    issue_cnt_d    = issue_cnt_q                              ;
    commit_cnt_d   = commit_cnt_q                             ;
    loop_running_d = loop_running_q & operation_i.loop_running;

    // We are not ready, by default
    sld_operand_ready_o = 1'b0;
    sld_result_o        = '0  ;
    opqueue_d.loop_done = '0  ;
    slide_result        = '0  ;
    sld_in_valid        = 1'b0;

    // Inform controller if we are idle
    resp_o               = '0                         ;
    resp_o.ready         = !opqueue_full              ;
    resp_o.loop_done     = opqueue_q.loop_done        ;
    resp_o.scalar_result = {sld_result_q.w64[0], 1'b1};

    // Finished issuing micro-operations
    if (issue_valid && $signed(issue_cnt_d) <= 0) begin
      opqueue_d.issue_cnt -= 1;
      opqueue_d.issue_pnt += 1;

      if (opqueue_d.issue_cnt != 0)
        issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].vd.length;
    end

    if (issue_valid)
      case (operation_issue_q.op)
        // These instructions only use the mask
        VMFIRST, VMPOPC:
          operand_valid = sld_operand_deshuffled[0].valid || (issue_valid && operation_issue_q.mask == riscv::NOMASK);
        VEXTRACT, VINSERT, VSLIDE, VRGATHER:
          operand_valid = (sld_operand_deshuffled[0].valid || operation_issue_q.mask == riscv::NOMASK) & sld_operand_deshuffled[1].valid;
      endcase

    case (state_q)
      IDLE: begin
        // Input interface
        if (!obuf_full) begin
          if (issue_valid && (op_i == VSLIDE))
            state_d = SLIDE_WAIT_OP;

          if (operand_valid) begin
            // Activate reduction unit
            sld_in_valid = 1'b1;

            // Result is ready
            if (sld_out_valid)
              obuf_d.result_pnt += NR_LANES * 8;

            // Filled up a word.
            if (obuf_d.result_pnt == (NR_LANES * 8) || obuf_d.result_pnt == issue_cnt_q) begin
              obuf_d.result[obuf_q.write_pnt] = sld_result_d                ;
              obuf_d.write_pnt                = obuf_d.write_pnt + 1        ;
              obuf_d.cnt                      = obuf_d.cnt + 1              ;
              issue_cnt_d                     = issue_cnt_d - (NR_LANES * 8);
              sld_operand_ready_o             = 1'b1                        ;
            end
          end
        end
      end
      SLIDE_WAIT_OP: begin
        if (operand_valid) begin
          state_d             = SLIDE_WRITE;
          sld_operand_ready_o = 1'b1       ;

          // Activate reduction unit
          sld_in_valid = 1'b1;

          // Bump pointer
          issue_cnt_d -= 8 * NR_LANES ;
          commit_cnt_d -= 8 * NR_LANES;
        end
      end
      SLIDE_WRITE: begin
        //TODO(matheusd): Slide operations are still buggy.
        automatic voffset_full_t offset = operation_issue_q.rs2 << get_shamt(width_i);

        if ($signed(issue_cnt_d) >= 8 * NR_LANES) begin
          slide_result = {sld_result_d, sld_result_q} >> (8 * offset);
        end else begin
          slide_result = sld_result_q >> (8 * offset);
        end

        if ((operand_valid || $signed(issue_cnt_d) <= 0) && !obuf_full) begin
          // Activate reduction unit
          sld_in_valid = 1'b1;

          obuf_d.result[obuf_q.write_pnt] = slide_result;
          obuf_d.write_pnt += 1'b1;
          obuf_d.cnt += 1'b1      ;

          // Bump pointer
          issue_cnt_d -= 8 * NR_LANES;

          // Ask for another operand
          sld_operand_ready_o = 1'b1;
        end

        if ($signed(issue_cnt_q) <= 0)
          state_d = IDLE;
      end
    endcase

    // Output interface
    for (int l = 0; l < NR_LANES; l++) begin
      sld_result_o[l].req   = obuf_q.lane_result[l].valid;
      sld_result_o[l].wdata = obuf_q.lane_result[l].word ;
      sld_result_o[l].prio  = 1'b0                       ;
      sld_result_o[l].we    = 1'b1                       ;
      sld_result_o[l].addr  = operation_commit_q.vd.addr ;
      sld_result_o[l].id    = operation_commit_q.id      ;

      if (sld_result_gnt_i[l])
        obuf_d.lane_result[l].valid = 1'b0;
    end

    // Idle output interfaces
    for (int l = 0; l < NR_LANES; l++) begin
      lane_req_d[l] = obuf_d.lane_result[l].valid;
      lane_req_q[l] = obuf_q.lane_result[l].valid;
    end

    if (~(|lane_req_d)) begin
      // There is something waiting to be written
      if (!obuf_empty) begin
        obuf_d.lane_result = shuffle(obuf_q.result[obuf_q.read_pnt], operation_commit_q.vd.dstt.width);

        if (!(operation_commit_q.op inside {VEXTRACT, VMPOPC, VMFIRST}))
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

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      opqueue_d.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].vd.length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && !loop_running_q[operation_i.id] && operation_i.fu == VFU_SLD) begin
      opqueue_d.insn[opqueue_q.accept_pnt] = operation_i;
      loop_running_d[operation_i.id]       = 1'b1       ;

      // Unused
      begin
        opqueue_d.insn[opqueue_q.accept_pnt].loop_running = '0;
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

      state_q <= IDLE;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;

      sld_result_q <= '0;
    end else begin
      obuf_q         <= obuf_d        ;
      opqueue_q      <= opqueue_d     ;
      loop_running_q <= loop_running_d;

      state_q <= state_d;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;

      sld_result_q <= sld_result_d;
    end
  end

endmodule : slide_unit
