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
// Author: Matheus Cavalcante, ETH Zurich
// Date: 20.11.2020
// Description: Functional unit that dispatches CVA6 instructions to accelerators.

module acc_dispatcher import ariane_pkg::*; import riscv::*; (
    input  logic                                  clk_i,
    input  logic                                  rst_ni,
    input  logic                                  flush_i,
    // Interface with the CSR regfile
    input  logic                                  acc_cons_en_i,        // Accelerator memory consistent mode
    // Interface with the issue stage
    input  fu_data_t                              acc_data_i,
    output logic                                  acc_ready_o,          // FU is ready
    input  logic                                  acc_valid_i,          // Output is valid
    output logic                                  acc_ld_disp_o,
    output logic                                  acc_st_disp_o,
    output logic              [TRANS_ID_BITS-1:0] acc_trans_id_o,
    output xlen_t                                 acc_result_o,
    output logic                                  acc_valid_o,
    output exception_t                            acc_exception_o,
    // Interface with the commit stage
    // This avoids sending speculative instructions to the accelerator.
    input  logic                                  acc_commit_i,
    input  logic              [TRANS_ID_BITS-1:0] acc_commit_trans_id_i,
    // Interface with the load/store unit
    input  logic                                  acc_no_st_pending_i,
    // Accelerator interface
    output accelerator_req_t                      acc_req_o,
    output logic                                  acc_req_valid_o,
    input  logic                                  acc_req_ready_i,
    input  accelerator_resp_t                     acc_resp_i,
    input  logic                                  acc_resp_valid_i,
    output logic                                  acc_resp_ready_o
  );

  `include "common_cells/registers.svh"

  /*************************
   *  Accelerator request  *
   *************************/

  // Capture any requests for which we are currently not ready in the
  // following fall-through register.
  fu_data_t acc_busy_data;
  logic     acc_busy_valid;
  logic     acc_busy_ready;

  fall_through_register #(
    .T(fu_data_t)
  ) i_acc_busy_register (
    .clk_i     (clk_i          ),
    .rst_ni    (rst_ni         ),
    .clr_i     (flush_i        ),
    .testmode_i(1'b0           ),
    .data_i    (acc_data_i     ),
    .valid_i   (acc_valid_i    ),
    .ready_o   (/* Unused */   ),
    .data_o    (acc_busy_data  ),
    .valid_o   (acc_busy_valid ),
    .ready_i   (acc_busy_ready )
  );

  //pragma translate_off
  `ifndef verilator

  acc_dispatcher_fu_data_accepted: assert property (
      @(posedge clk_i) disable iff (~rst_ni) i_acc_busy_register.valid_i |-> i_acc_busy_register.ready_o)
  else $error("[acc_dispatcher] Accelerator request from the scoreboard was lost.");

  `endif
  //pragma translate_on

  // All requests from the scoreboard should be stored in the following register
  fu_data_t acc_data;
  logic     acc_valid;
  logic     acc_ready;
  // The scoreboard ready signal comes from this register
  assign acc_ready_o = acc_busy_ready;

  stream_register #(
    .T(fu_data_t)
  ) i_acc_register (
    .clk_i     (clk_i         ),
    .rst_ni    (rst_ni        ),
    .clr_i     (flush_i       ),
    .testmode_i(1'b0          ),
    .data_i    (acc_busy_data ),
    .valid_i   (acc_busy_valid),
    .ready_o   (acc_busy_ready),
    .data_o    (acc_data      ),
    .valid_o   (acc_valid     ),
    .ready_i   (acc_ready     )
  );

  // Store whether there was a match between acc_commit_trans_id_i and acc_data.trans_id
  logic     acc_commit_trans_id_match_d, acc_commit_trans_id_match_q;
  `FF(acc_commit_trans_id_match_q, acc_commit_trans_id_match_d, 1'b0)

  always_comb begin: accelerator_req_dispatcher
    // Maintain state
    acc_commit_trans_id_match_d = acc_commit_trans_id_match_q;
    // No match. Compare the results.
    if (!acc_commit_trans_id_match_q)
      acc_commit_trans_id_match_d = acc_commit_i && acc_commit_trans_id_i == acc_data.trans_id;

    // Unpack fu_data_t into accelerator_req_t
    acc_req_o = '{
      // Instruction is forwarded from the decoder as an immediate
      insn         : acc_data.imm[31:0],
      rs1          : acc_data.operand_a,
      rs2          : acc_data.operand_b,
      trans_id     : acc_data.trans_id,
      store_pending: !acc_no_st_pending_i && acc_cons_en_i
    };

    // Wait until we receive the acc_commit_i signal
    acc_req_valid_o = acc_valid && acc_commit_trans_id_match_d;
    acc_ready       = acc_req_ready_i && acc_commit_trans_id_match_d;

    // Reset the match signal, if we acknowledged a request
    if (acc_ready)
      acc_commit_trans_id_match_d = 1'b0;
  end

  /**************************
   *  Accelerator response  *
   **************************/

  // Unpack the accelerator response
  assign acc_trans_id_o  = acc_resp_i.trans_id;
  assign acc_result_o    = acc_resp_i.result;
  assign acc_valid_o     = acc_resp_valid_i;
  assign acc_exception_o = '{
            cause: riscv::ILLEGAL_INSTR,
            tval : '0,
            valid: acc_resp_i.error
  };
  // Always ready to receive responses
  assign acc_resp_ready_o = 1'b1;

  // Signal dispatched load/store to issue stage
  assign acc_ld_disp_o = acc_req_ready_i && (acc_data.operator == ACCEL_OP_LOAD);
  assign acc_st_disp_o = acc_req_ready_i && (acc_data.operator == ACCEL_OP_STORE);
endmodule : acc_dispatcher
