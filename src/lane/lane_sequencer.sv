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
// File          : lane_sequencer.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 17.01.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Lane sequencer.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module lane_sequencer (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Interface with the main sequencer
    input  lane_req_t                    operation_i,
    output lane_resp_t                   resp_o,
    // Operand request
    output opreq_cmd_t  [NR_OPQUEUE-1:0] opreq_cmd_o,
    output logic        [NR_OPQUEUE-1:0] opreq_cmd_valid_o,
    input  logic        [NR_OPQUEUE-1:0] opreq_cmd_ready_i,
    // Operation
    output operation_t                   operation_o,
    input  vfu_status_t [ NR_VFU-1:0]    vfu_status_i
  );

  /***********************************
   *  OPERAND REQUEST COMMAND QUEUE  *
   ***********************************/

  opreq_cmd_t [NR_OPQUEUE-1:0] opreq_cmd_i;
  logic       [NR_OPQUEUE-1:0] opreq_cmd_push;

  struct packed {
    opreq_cmd_t cmd;
    logic valid    ;
  } [NR_OPQUEUE-1:0] opreq_cmd_q, opreq_cmd_d;

  always_comb begin
    // Maintain state
    opreq_cmd_d = opreq_cmd_q;

    for (int q = 0; q < NR_OPQUEUE; q++) begin
      if (opreq_cmd_ready_i[q])
        opreq_cmd_d[q] = '0;

      if (opreq_cmd_push[q])
        opreq_cmd_d[q] = {opreq_cmd_i[q], 1'b1};

      // Reset hazard conditions
      opreq_cmd_d[q].cmd.hzd &= operation_i.loop_running;

      // Assignments
      opreq_cmd_o[q]       = opreq_cmd_q[q].cmd  ;
      opreq_cmd_valid_o[q] = opreq_cmd_q[q].valid;
    end
  end

  /***********************
   *  OPERATION CONTROL  *
   ***********************/

  operation_t                operation_d;
  logic       [VLOOP_ID-1:0] loop_done_d, loop_done_q;

  // Running loops
  logic [VLOOP_ID-1:0] loop_running_d, loop_running_q;

  function automatic logic [NR_OPQUEUE-1:0] get_target_queues(vfu_t fu, vfu_op op, logic use_imm, logic [1:0] mask);
    logic [NR_OPQUEUE-1:0] retval = '0;

    case (fu)
      VFU_ALU : retval[ALU_B:ALU_SLD_MASK]     = '1;
      VFU_MFPU: retval[MFPU_C:MFPU_MASK]       = '1;
      VFU_SLD : retval[ALU_SLD_A:ALU_SLD_MASK] = '1;
      VFU_LD  : retval[LD_ST_MASK]             = '1;
      VFU_ST  : retval[ST_A:LD_ST_MASK]        = '1;
    endcase

    if (op inside {VLDX, VSTX})
      retval[ADDRGEN_A] = 1'b1;
    if (op == VRGATHER) begin
      retval[ADDRGEN_A]    = 1'b1;
      retval[ALU_SLD_MASK] = 1'b0;
      retval[ALU_B]        = 1'b0;
    end
    if (use_imm) begin
      retval[ALU_B]  = 1'b0;
      retval[MFPU_B] = 1'b0;
    end
    if (mask == riscv::NOMASK) begin
      retval[ALU_SLD_MASK] = 1'b0;
      retval[MFPU_MASK]    = 1'b0;
      retval[LD_ST_MASK]   = 1'b0;
    end

    return retval;
  endfunction : get_target_queues

  always_comb begin: lane_control
    // Maintain state
    loop_running_d = loop_running_q & operation_i.loop_running;

    // No operation request
    operation_d = '0;

    // No response
    resp_o           = '0         ;
    resp_o.ready     = 1'b1       ;
    resp_o.loop_done = loop_done_q;

    // Don't push nothing to operand request command queue
    opreq_cmd_i    = '0;
    opreq_cmd_push = '0;

    // Loops that finished execution
    loop_done_d = '0;
    for (int vfu = 0; vfu < NR_VFU; vfu++)
      loop_done_d |= vfu_status_i[vfu].loop_done;

    begin
      automatic logic [NR_OPQUEUE-1:0] target_queues = get_target_queues(operation_i.fu, operation_i.op, operation_i.use_imm, operation_i.mask);
      automatic logic full_cmd_queue                 = |(target_queues & opreq_cmd_valid_o)                                                    ;

      // Maintain output until functional unit acknowledges operation
      if (operation_o.valid && !vfu_status_i[operation_o.fu].ready) begin
        operation_d  = operation_o;
        resp_o.ready = 1'b0       ;
      end else
        // We got a new vector loop
        if (operation_i.valid && !loop_running_q[operation_i.id])
          if (!full_cmd_queue) begin
            // Send VLOOP to the corresponding functional unit
            operation_d.valid     = 1'b1                                             ;
            operation_d.id        = operation_i.id                                   ;
            operation_d.fu        = operation_i.fu                                   ;
            operation_d.op        = operation_i.op                                   ;
            operation_d.vd        = operation_i.vd.dstt                              ;
            operation_d.vid       = operation_i.vd.id                                ;
            operation_d.addr      = operation_i.vd.addr                              ;
            operation_d.length    = (operation_i.vd.length + NR_LANES - 1) / NR_LANES;
            operation_d.offset    = operation_i.offset                               ;
            operation_d.reduction = operation_i.reduction                            ;
            operation_d.mask      = operation_i.mask                                 ;
            operation_d.use_imm   = operation_i.use_imm                              ;
            operation_d.rs1       = operation_i.rs1                                  ;
            operation_d.rs2       = operation_i.rs2                                  ;
            operation_d.imm       = operation_i.imm                                  ;

            loop_running_d[operation_i.id] = 1'b1;

            // Stalls

            // Issue command to sequencer stage
            opreq_cmd_push = target_queues;

            for (int q = 0; q < NR_OPQUEUE; q++) begin

              if (target_queues[q]) begin
                automatic int vid = q - get_initial_channel(operation_i.fu);

                opreq_cmd_i[q].op        = operation_i.op                                        ;
                opreq_cmd_i[q].fu        = operation_i.fu                                        ;
                opreq_cmd_i[q].repr      = operation_i.vd.dstt.repr                              ;
                opreq_cmd_i[q].vs        = operation_i.vs[vid]                                   ;
                opreq_cmd_i[q].vs.length = (operation_i.vs[vid].length + NR_LANES - 1) / NR_LANES;
                opreq_cmd_i[q].length    = (operation_i.vd.length + NR_LANES - 1) / NR_LANES     ;
                opreq_cmd_i[q].hzd       = operation_i.hzd[vid]                                  ;

                if (op_dest_t'(q) inside {ALU_SLD_MASK, MFPU_MASK, LD_ST_MASK}) begin
                  opreq_cmd_i[q].mask     = operation_i.mask;
                  opreq_cmd_i[q].vs.valid = 1'b1            ;
                end
              end
            end
          end else begin
            resp_o.ready = 1'b0;
          end
    end
  end : lane_control

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(negedge rst_ni or posedge clk_i) begin
    if (!rst_ni) begin
      opreq_cmd_q <= '0;

      loop_done_q    <= '0;
      loop_running_q <= '0;

      operation_o <= '0;
    end else begin
      opreq_cmd_q <= opreq_cmd_d;

      loop_done_q    <= loop_done_d   ;
      loop_running_q <= loop_running_d;

      operation_o <= operation_d;
    end
  end

endmodule : lane_sequencer
