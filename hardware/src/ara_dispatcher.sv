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
// File:   ara_dispatcher.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's dispatcher interfaces Ariane's requests with the vector lanes.
// It also acknowledges instructions back to Ariane, perhaps with a
// response or an error message.

module ara_dispatcher import ara_pkg::*; (
    // Clock and reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Interfaces with Ariane
    input  accelerator_req_t  acc_req_i,
    input  logic              acc_req_valid_i,
    output logic              acc_req_ready_o,
    output accelerator_resp_t acc_resp_o,
    output logic              acc_resp_valid_o,
    input  logic              acc_resp_ready_i
  );

  `include "common_cells/registers.svh"

  /**********
   *  CSRs  *
   **********/

  riscv::xlen_t vstart_d, vstart_q;
  riscv::xlen_t vl_d, vl_q;
  rvv_pkg::vtype_t vtype_d, vtype_q;

  `FF(vstart_q, vstart_d, '0)
  `FF(vl_q, vl_d, '0)
  `FF(vtype_q, vtype_d, '{vill: 1'b1, default: '0})

  /*************
   *  Decoder  *
   *************/

  always_comb begin: decoder
    // Default values
    vstart_d = vstart_q;
    vl_d     = vl_q;
    vtype_d  = vtype_q;

    acc_req_ready_o  = 1'b0;
    acc_resp_valid_o = 1'b0;
    acc_resp_o       = '{
      trans_id: acc_req_i.trans_id,
      default : '0
    };

    // Decode the instructions based on their opcode
    case (acc_req_i.insn.itype.opcode)
      // CSR Reads/Writes
      riscv::OpcodeSystem: begin

      end
    endcase
  end: decoder

endmodule : ara_dispatcher
