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
    // Interface with the issue stage
    input  fu_data_t                              acc_data_i,
    output logic                                  acc_ready_o,          // FU is ready
    input  logic                                  acc_valid_i,          // Output is valid
    output logic              [TRANS_ID_BITS-1:0] acc_trans_id_o,
    output xlen_t                                 acc_result_o,
    output logic                                  acc_valid_o,
    output exception_t                            acc_exception_o,
    // Interface with the commit stage
    // This avoids sending speculative instructions to the accelerator.
    input  logic                                  acc_commit_i,
    input  logic              [TRANS_ID_BITS-1:0] acc_commit_trans_id_i,
    // Accelerator interface
    output accelerator_req_t                      acc_req_o,
    output logic                                  acc_req_valid_o,
    input  logic                                  acc_req_ready_i,
    input  accelerator_resp_t                     acc_resp_i,
    input  logic                                  acc_resp_valid_i,
    output logic                                  acc_resp_ready_o
  );

  /*************************
   *  Accelerator request  *
   *************************/

  accelerator_req_t acc_req;
  logic             acc_req_valid;
  logic             acc_req_ready;

  // Register all requests going to the accelerator
  spill_register #(
    .T(accelerator_req_t)
  ) i_accelerator_req_register (
    .clk_i  (clk_i          ),
    .rst_ni (rst_ni         ),
    .data_i (acc_req        ),
    .valid_i(acc_req_valid  ),
    .ready_o(acc_req_ready  ),
    .data_o (acc_req_o      ),
    .valid_o(acc_req_valid_o),
    .ready_i(acc_req_ready_i)
  );

  always_comb begin: accelerator_req_dispatcher
    // Default values
    acc_req       = '0;
    acc_req_valid = 1'b0;
    acc_ready_o   = 1'b0;

    if (acc_commit_i && acc_commit_trans_id_i == acc_data_i.trans_id) begin
      // Unpack fu_data_t into accelerator_req_t
      acc_req = '{
        // Instruction is forwarded from the decoder as an immediate
        insn    : acc_data_i.imm[31:0],
        rs1     : acc_data_i.operand_a,
        rs2     : acc_data_i.operand_b,
        trans_id: acc_data_i.trans_id
      };
      acc_req_valid = acc_valid_i;
      acc_ready_o   = acc_req_ready;
    end
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

endmodule : acc_dispatcher
