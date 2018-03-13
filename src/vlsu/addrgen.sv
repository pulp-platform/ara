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
// File          : addrgen.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 26.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This block generates AXI transactions on the AX buses, given vector memory instructions.

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

module addrgen (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Memory interface
    output axi_req_t                     ara_axi_req_o,
    input  axi_resp_t                    ara_axi_resp_i,
    // Address translation
    output ara_mem_req_t                 ara_mem_req_o,
    input  ara_mem_resp_t                ara_mem_resp_i,
    output logic                         addrgen_ack_o,
    // Operation
    input  lane_req_t                    operation_i,
    // Interface with Ara's VLSU
    output addr_t                        addr_o,
    output logic                         addr_valid_o,
    input  logic                         ld_addr_ready_i,
    input  logic                         st_addr_ready_i,
    // Interface with VCONV stage (for scatters and gathers)
    input  word_t         [NR_LANES-1:0] addrgen_operand_i,
    output logic                         addrgen_operand_ready_o
  );

  // Address Queues
  logic addr_full, addr_empty;

  /*****************
   *  PTE REQUEST  *
   *****************/

  //TODO(matheusd) Virtual addresses are not functional at the current version of Ara
  typedef struct packed {
    riscv::pte_t pte   ;
    logic [63:0] addr  ;
    logic [63:0] stride;
    vaddr_t cnt        ;

    logic is_load;
    logic burst  ;
    logic valid  ;
  } pte_req_t;
  pte_req_t pte_d;
  logic     addrgen_valid;

  /*
   * The FSM of the address translation block contains three stages.
   * - PTE_IDLE: Waiting for a load/store instruction, makes no request.
   * - PTE_REQ: Requests one PTE from Ara.
   * - PTE_TRANSLATE: Translates the address(es) using PTE received from
   *   Ariane.
   * - PTE_TRANSLATE_X: Translates the address(es) using PTE received from
   *   Ariane, for scatters and gathers.
   */
  enum logic [1:0] {
    PTE_IDLE     ,
    PTE_REQ      ,
    PTE_TRANSLATE,
    PTE_TRANSLATE_X
  } pte_state_q, pte_state_d;

  // Pointer on the VCONV word for scatters/gathers
  voffset_full_t ptex_pnt_q, ptex_pnt_d;

  // Counts how many addresses were generated
  vsize_full_t addrgen_cnt_q, addrgen_cnt_d;

  // Input offsets
  word_full_t addrgen_operand;
  assign addrgen_operand = deshuffle(addrgen_operand_i, operation_i.vd.dstt.width);

  // Running loops
  logic [VLOOP_ID-1:0] loop_running_d, loop_running_q;

  always_comb begin: pte
    // Maintain state
    pte_state_d    = pte_state_q                              ;
    ptex_pnt_d     = ptex_pnt_q                               ;
    addrgen_cnt_d  = addrgen_cnt_q                            ;
    pte_d          = '0                                       ;
    loop_running_d = loop_running_q & operation_i.loop_running;

    // Make no request
    ara_mem_req_o               = '0         ;
    ara_mem_req_o.no_st_pending = !addr_empty;

    // Not ready, by default
    addrgen_ack_o           = 1'b0;
    addrgen_operand_ready_o = 1'b0;

    case (pte_state_q)
      PTE_IDLE: begin
        addrgen_cnt_d = '0;
        ptex_pnt_d    = '0;

        if (operation_i.valid && (is_load(operation_i.op) || is_store(operation_i.op)) && !loop_running_q[operation_i.id]) begin
          loop_running_d[operation_i.id] = 1'b1;
          if (ara_mem_resp_i.en_translation)
            pte_state_d = PTE_REQ;
          else
            unique case (operation_i.op)
              VLDX, VSTX: pte_state_d = PTE_TRANSLATE_X;
              default : pte_state_d = PTE_TRANSLATE;
            endcase
        end
      end
      PTE_REQ: begin
      // TODO
      end
      PTE_TRANSLATE: begin
        pte_d.valid = 1'b1;

        // Scale immediate by element size
        pte_d.addr = operation_i.rs1 + (operation_i.imm << get_shamt(operation_i.vd.dstt.width));

        // Set the stride
        case (operation_i.op)
          VLD , VST : pte_d.stride = get_width(operation_i.vd.dstt.width);
          VLDS, VSTS: pte_d.stride = operation_i.rs2                     ;
        endcase

        pte_d.cnt     = operation_i.vd.length             ;
        pte_d.is_load = is_load(operation_i.op)           ;
        pte_d.burst   = (operation_i.op inside {VLD, VST});

        if (addrgen_valid) begin
          pte_d         = '0      ;
          addrgen_ack_o = 1'b1    ;
          pte_state_d   = PTE_IDLE;
        end
      end
      PTE_TRANSLATE_X: begin
        if (addrgen_operand_i[0].valid) begin
          pte_d.valid = 1'b1;

          if (addrgen_valid) begin
            ptex_pnt_d    = ptex_pnt_q + 1                                      ;
            addrgen_cnt_d = addrgen_cnt_q + get_width(operation_i.vd.dstt.width);

            if (ptex_pnt_d >= NR_LANES * 8) begin
              ptex_pnt_d              = 0   ;
              addrgen_operand_ready_o = 1'b1;
            end

            if (addrgen_cnt_d == operation_i.vd.length) begin
              addrgen_operand_ready_o = 1'b1    ;
              addrgen_ack_o           = 1'b1    ;
              pte_state_d             = PTE_IDLE;
              pte_d.valid             = 1'b0    ;
            end
          end

          // Scale immediate by element size
          unique case (operation_i.vd.dstt.width)
            riscv::WD_V8B : pte_d.addr = $signed(operation_i.rs1) + $signed(addrgen_operand.word.w8 [ptex_pnt_d]) + $signed(operation_i.imm << 0);
            riscv::WD_V16B: pte_d.addr = $signed(operation_i.rs1) + $signed(addrgen_operand.word.w16[ptex_pnt_d]) + $signed(operation_i.imm << 1);
            riscv::WD_V32B: pte_d.addr = $signed(operation_i.rs1) + $signed(addrgen_operand.word.w32[ptex_pnt_d]) + $signed(operation_i.imm << 2);
            riscv::WD_V64B: pte_d.addr = $signed(operation_i.rs1) + $signed(addrgen_operand.word.w64[ptex_pnt_d]) + $signed(operation_i.imm << 3);
          endcase
          pte_d.stride  = '0                                  ;
          pte_d.cnt     = get_width(operation_i.vd.dstt.width); // Request one single element
          pte_d.is_load = is_load(operation_i.op)             ;
          pte_d.burst   = 1'b0                                ;
        end
      end
    endcase
  end

  /************************
   *  ADDRESS GENERATION  *
   ************************/

  addr_t addr_i;
  logic  addr_push;
  fifo_v3 #(
    .DEPTH(ADDRQ_DEPTH),
    .dtype(addr_t     )
  ) i_addr_queue (
    .clk_i     (clk_i                             ) ,
    .rst_ni    (rst_ni                            ),
    .flush_i   (1'b0                              ),
    .testmode_i(1'b0                              ),
    .full_o    (addr_full                         ),
    .empty_o   (addr_empty                        ),
    .usage_o   (/* Unused */                      ),
    .data_i    (addr_i                            ),
    .push_i    (addr_push                         ),
    .data_o    (addr_o                            ),
    .pop_i     (ld_addr_ready_i || st_addr_ready_i)
  );

  assign addr_valid_o = !addr_empty;

  enum logic { ADDRGEN_IDLE, ADDRGEN_GEN } addrgen_state_q, addrgen_state_d;
  pte_req_t addrgen_pte_q, addrgen_pte_d;

  always_comb begin: addrgen
    // Maintain state
    addrgen_state_d = addrgen_state_q;
    addrgen_pte_d   = addrgen_pte_q  ;

    // Nothing to ack
    addrgen_valid = 1'b0;

    // Do not store nothing in FIFOs
    addr_i    = '0  ;
    addr_push = 1'b0;

    // No request
    ara_axi_req_o = '0;

    case (addrgen_state_q)
      ADDRGEN_IDLE: begin
        if (pte_d.valid) begin
          addrgen_state_d = ADDRGEN_GEN;
          addrgen_pte_d   = pte_d      ;
        end
      end
      ADDRGEN_GEN: begin
        automatic logic ax_ready;

        if (addrgen_pte_q.is_load)
          ax_ready = ara_axi_resp_i.ar_ready;
        else
          ax_ready = ara_axi_resp_i.aw_ready;

        if (!addr_full) begin
          if (addrgen_pte_q.burst) begin
            addr_push      = ax_ready             ;
            addr_i.addr    = addrgen_pte_q.addr   ;
            addr_i.is_load = addrgen_pte_q.is_load;

            // How long can the burst be (in bytes).
            // Align in 256B pages
            addr_i.burst_length = $unsigned(1 << 8) - $unsigned(addrgen_pte_q.addr[7:0]);

            if (addr_i.burst_length > addrgen_pte_q.cnt)
              addr_i.burst_length = addrgen_pte_q.cnt;

            if (ax_ready) begin
              addrgen_pte_d.cnt  = addrgen_pte_q.cnt - addr_i.burst_length ;
              addrgen_pte_d.addr = addrgen_pte_q.addr + addr_i.burst_length;

              // Acknowledge early
              if (addrgen_pte_q.valid)
                addrgen_valid = 1'b1;
              addrgen_pte_d.valid = 1'b0;
            end
          end else begin
            addr_push           = ax_ready                            ;
            addr_i.addr         = addrgen_pte_q.addr                  ;
            addr_i.is_load      = addrgen_pte_q.is_load               ;
            addr_i.burst_length = get_width(operation_i.vd.dstt.width);

            if (ax_ready) begin
              addrgen_pte_d.cnt  = addrgen_pte_q.cnt - get_width(operation_i.vd.dstt.width);
              addrgen_pte_d.addr = addrgen_pte_q.addr + addrgen_pte_q.stride               ;

              if (addrgen_pte_d.cnt == 0)
                addrgen_valid = 1'b1;
            end
          end
        end

        // AR Channel
        if (addrgen_pte_q.is_load) begin
          ara_axi_req_o.ar_valid = !addr_full                                                                                  ;
          ara_axi_req_o.ar.addr  = (addr_i.addr >> $clog2(StrbWidth)) << $clog2(StrbWidth)                                     ;
          ara_axi_req_o.ar.len   = ((addr_i.burst_length + addr_i.addr[$clog2(StrbWidth)-1:0] + StrbWidth - 1) / StrbWidth) - 1;
          ara_axi_req_o.ar.size  = $clog2(StrbWidth)                                                                           ;
          ara_axi_req_o.ar.burst = axi_pkg::BURST_INCR                                                                         ;
          ara_axi_req_o.ar.cache = axi_pkg::CACHE_MODIFIABLE                                                                   ;
          ara_axi_req_o.ar.id    = 0                                                                                           ;
        end else begin
          ara_axi_req_o.aw_valid = !addr_full                                                                                  ;
          ara_axi_req_o.aw.addr  = (addr_i.addr >> $clog2(StrbWidth)) << $clog2(StrbWidth)                                     ;
          ara_axi_req_o.aw.len   = ((addr_i.burst_length + addr_i.addr[$clog2(StrbWidth)-1:0] + StrbWidth - 1) / StrbWidth) - 1;
          ara_axi_req_o.aw.size  = $clog2(StrbWidth)                                                                           ;
          ara_axi_req_o.aw.burst = axi_pkg::BURST_INCR                                                                         ;
          ara_axi_req_o.aw.cache = axi_pkg::CACHE_MODIFIABLE                                                                   ;
          ara_axi_req_o.aw.id    = 0                                                                                           ;
        end

        if (addrgen_pte_d.cnt == 0) begin
          addrgen_pte_d   = '0          ;
          addrgen_state_d = ADDRGEN_IDLE;

          if (pte_d.valid) begin
            addrgen_state_d = ADDRGEN_GEN;
            addrgen_pte_d   = pte_d      ;
          end
        end
      end
    endcase
  end : addrgen

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pte_state_q    <= PTE_IDLE;
      ptex_pnt_q     <= '0      ;
      loop_running_q <= '0      ;

      addrgen_state_q <= ADDRGEN_IDLE;
      addrgen_cnt_q   <= '0          ;
      addrgen_pte_q   <= '0          ;
    end else begin
      pte_state_q    <= pte_state_d   ;
      ptex_pnt_q     <= ptex_pnt_d    ;
      loop_running_q <= loop_running_d;

      addrgen_state_q <= addrgen_state_d;
      addrgen_cnt_q   <= addrgen_cnt_d  ;
      addrgen_pte_q   <= addrgen_pte_d  ;
    end
  end

endmodule : addrgen
