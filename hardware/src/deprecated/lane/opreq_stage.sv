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
// File          : opreq_stage.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 13.11.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This pipeline stage includes the VRF arbiter and the operand request logic.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module opreq_stage (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    // Interface with VLOOP
    input  opreq_cmd_t   [NR_OPQUEUE-1:0] opreq_cmd_i,
    input  logic         [NR_OPQUEUE-1:0] opreq_cmd_valid_i,
    output logic         [NR_OPQUEUE-1:0] opreq_cmd_ready_o,
    input  logic         [ VLOOP_ID-1:0]  loop_running_i,
    // Interface with VACCESS
    output vrf_request_t [VRF_NBANKS-1:0] vrf_request_o,
    output opqueue_cmd_t [NR_OPQUEUE-1:0] opqueue_cmd_o,
    input  logic         [NR_OPQUEUE-1:0] opqueue_ready_i,
    output logic         [NR_OPQUEUE-1:0] word_issued_o,
    // Interface with VEX
    input  arb_request_t                  alu_result_i,
    input  arb_request_t                  mfpu_result_i,
    output logic                          alu_result_gnt_o,
    output logic                          mfpu_result_gnt_o,
    // Interface with reduction unit
    input  arb_request_t                  sld_result_i,
    output logic                          sld_result_gnt_o,
    // Interface with the VLSU
    input  arb_request_t                  ld_result_i,
    output logic                          ld_result_gnt_o
  );

  /*********************
   *  OPERAND REQUEST  *
   *********************/

  arb_request_t [NR_OPQUEUE-1:0] operand_req;
  logic         [NR_OPQUEUE-1:0] operand_gnt;

  function automatic conv_type_t get_conv_type(riscv::vrepr_t repr, op_dest_t ch);
    if (ch inside {MFPU_MASK, ALU_SLD_MASK, LD_ST_MASK})
      return MASK_CONV;
    else
      return (repr == riscv::RP_FPOINT ? FLOAT_CONV : INT_CONV);
  endfunction : get_conv_type

  typedef enum logic {
    OP_IDLE,
    OP_REQ
  } op_req_state_t;

  // Operand request struct
  struct packed {
    op_req_state_t state;
    logic [1:0] mask    ;
    vfu_t fu            ;
    riscv::vrepr_t repr ;

    vsize_t length    ;
    vdesc_t vs        ;
    vsize_t dif_length;

    logic [VLOOP_ID-1:0] hzd;
  } [NR_OPQUEUE-1:0] op_req_q, op_req_d;

  // Operand conversion
  opqueue_cmd_t [NR_OPQUEUE-1:0] opqueue_cmd_d;

  logic [VLOOP_ID-1:0] write_d, write_q; // Result written last cycle

  // Stalls
  logic [NR_OPQUEUE-1:0] stall;

  always_comb begin
    write_d = '0;

    // Which loops wrote something last cycle
    write_d[ alu_result_i.id ] |= alu_result_gnt_o  ;
    write_d[ mfpu_result_i.id ] |= mfpu_result_gnt_o;
    write_d[ sld_result_i.id ] |= sld_result_gnt_o  ;
    write_d[ ld_result_i.id ] |= ld_result_gnt_o    ;

    for (int ch = 0; ch < NR_OPQUEUE; ch++)
      stall[ch] = (|(op_req_q[ch].hzd & ~write_q));
  end

  // Operand request
  always_comb begin: operand_request
    // Maintain state
    op_req_d = op_req_q;

    // Make no requests
    operand_req   = '0;
    opqueue_cmd_d = '0;

    // Do not ack any operand request commands
    opreq_cmd_ready_o = '0;

    // Set destination of each channel
    for (int ch = 0; ch < NR_OPQUEUE; ch++) begin
      automatic logic end_req = !op_req_q[ch].vs.valid;
      operand_req[ch].dest    = op_dest_t'(ch)        ;

      if (op_req_q[ch].state == OP_REQ) begin

        if (opqueue_ready_i[ch]) begin
          // Send conversion commands
          opqueue_cmd_d[ch].slave_select = (op_req_q[ch].fu inside {VFU_LD, VFU_SLD}) && (op_dest_t'(ch) != ADDRGEN_A);
          opqueue_cmd_d[ch].conv_type    = get_conv_type(op_req_q[ch].repr, op_dest_t'(ch))                           ;
          opqueue_cmd_d[ch].srct         = op_req_q[ch].vs.srct                                                       ;
          opqueue_cmd_d[ch].dstt         = op_req_q[ch].vs.dstt                                                       ;
          opqueue_cmd_d[ch].mask         = op_req_q[ch].mask                                                          ;

          // Operand request
          operand_req[ch].req  = op_req_q[ch].vs.valid && !stall[ch]                         ;
          operand_req[ch].addr = op_req_q[ch].vs.addr                                        ;
          operand_req[ch].prio = !(operand_req[ch].dest inside {LD_ST_MASK, ST_A, ADDRGEN_A});

          if (op_req_q[ch].vs.srct.shape == riscv::SH_SCALAR) begin
            opqueue_cmd_d[ch].cnt = op_req_q[ch].length;

            // Scalars are only sent once
            if (operand_gnt[ch])
              end_req = 1'b1;
          end else begin
            if (op_req_q[ch].vs.srct.width != op_req_q[ch].vs.dstt.width)
              opqueue_cmd_d[ch].cnt <<= 1;
          end

          // Went past vector end. Just send zero.
          if ($signed(op_req_d[ch].vs.length) <= 0) begin
            operand_req[ch].req = !stall[ch] && op_req_d[ch].vs.valid;

            opqueue_cmd_d[ch].cnt = op_req_q[ch].dif_length;
            if (op_req_q[ch].vs.srct.width != op_req_q[ch].vs.dstt.width)
              opqueue_cmd_d[ch].cnt <<= 1;

            if (operand_gnt[ch])
              op_req_d[ch].dif_length = 0;
          end

          // Received a grant. Bump pointers.
          if (operand_gnt[ch]) begin
            if (op_req_d[ch].vs.srct.width == op_req_d[ch].vs.dstt.width)
              op_req_d[ch].vs.length = op_req_q[ch].vs.length - 8;
            else
              op_req_d[ch].vs.length = op_req_q[ch].vs.length - 4;
            op_req_d[ch].vs.addr = increment_addr(op_req_q[ch].vs.addr, op_req_q[ch].vs.id);

            if ($signed(op_req_d[ch].vs.length) <= 0)
              if ($signed(op_req_d[ch].dif_length) <= 0)
                end_req = 1'b1;
          end

          if (end_req)
            op_req_d[ch] = '0;
        end
      end

      // Update stalls
      op_req_d[ch].hzd = op_req_q[ch].hzd & loop_running_i;

      if (op_req_d[ch].state == OP_IDLE) begin
        // Accept new instruction
        if (opreq_cmd_valid_i[ch]) begin
          op_req_d[ch].mask   = opreq_cmd_i[ch].mask  ;
          op_req_d[ch].fu     = opreq_cmd_i[ch].fu    ;
          op_req_d[ch].repr   = opreq_cmd_i[ch].repr  ;
          op_req_d[ch].length = opreq_cmd_i[ch].length;
          op_req_d[ch].vs     = opreq_cmd_i[ch].vs    ;
          if (opreq_cmd_i[ch].vs.srct.width == opreq_cmd_i[ch].vs.dstt.width)
            op_req_d[ch].dif_length = opreq_cmd_i[ch].length - opreq_cmd_i[ch].vs.length;
          else
            op_req_d[ch].dif_length = opreq_cmd_i[ch].length - opreq_cmd_i[ch].vs.length * 2;
          op_req_d[ch].hzd      = opreq_cmd_i[ch].hzd & loop_running_i;
          op_req_d[ch].state    = OP_REQ                              ;
          opreq_cmd_ready_o[ch] = 1'b1                                ;
        end
      end
    end
  end : operand_request

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(negedge rst_ni or posedge clk_i) begin
    if (!rst_ni) begin
      op_req_q <= '0;
      write_q  <= '0;

      opqueue_cmd_o <= '0;
    end else begin
      op_req_q <= op_req_d;
      write_q  <= write_d ;

      opqueue_cmd_o <= opqueue_cmd_d;
    end
  end

  /*************
   *  ARBITER  *
   *************/

  vrf_arbiter #(
    .NUM_REQ(NR_OPQUEUE + 4)
  ) i_vrf_arbiter (
    .clk_i         (clk_i                                                                                ),
    .rst_ni        (rst_ni                                                                               ),
    .vrf_request_o (vrf_request_o                                                                        ),
    .word_issued_o (word_issued_o                                                                        ),
    .arb_req_i     ({ld_result_i, sld_result_i, alu_result_i, mfpu_result_i, operand_req}                ),
    .arb_gnt_o     ({ld_result_gnt_o, sld_result_gnt_o, alu_result_gnt_o, mfpu_result_gnt_o, operand_gnt})
  );

endmodule : opreq_stage
