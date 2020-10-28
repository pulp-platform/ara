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
// File          : vrf_arbiter.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 22.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Round-Robin/Priority Arbiter to access the Vector Register File.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module vrf_arbiter #(
    parameter int unsigned NUM_REQ = 16
  ) (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    // Interface with VRF
    output vrf_request_t [VRF_NBANKS-1:0] vrf_request_o,
    output logic         [NR_OPQUEUE-1:0] word_issued_o,
    // Request ports
    input  arb_request_t [ NUM_REQ-1:0]   arb_req_i,
    output logic         [ NUM_REQ-1:0]   arb_gnt_o
  );

  // REQUEST SIGNALS
  logic [VRF_NBANKS-1:0][NUM_REQ-1:0] bank_req ;
  logic [VRF_NBANKS-1:0][NUM_REQ-1:0] bank_prio;

  always_comb begin
    bank_req  = '0;
    bank_prio = '0;

    for (int r = 0; r < NUM_REQ; r++) begin
      bank_req[arb_req_i[r].addr.bank][r]  = arb_req_i[r].req ;
      bank_prio[arb_req_i[r].addr.bank][r] = arb_req_i[r].prio;
    end
  end // always_comb

  // RESPONSE SIGNALS
  logic [VRF_NBANKS-1:0][ NUM_REQ-1:0]   gnt ;
  logic [VRF_NBANKS-1:0][NR_OPQUEUE-1:0] issue;

  always_comb begin
    arb_gnt_o     = '0;
    word_issued_o = '0;

    for (int b = 0; b < VRF_NBANKS; b++) begin
      arb_gnt_o |= gnt[b]      ;
      word_issued_o |= issue[b];
    end
  end

  for (genvar b = 0; b < VRF_NBANKS; b++) begin: arbiter_bank

    logic [NUM_REQ-1:0] req        ;
    logic [$clog2(NUM_REQ)-1:0] idx;
    logic vld                      ;

    // If there's a priority request, forward them to the arbiter
    assign req = (|(bank_req[b] & bank_prio[b])) ? bank_req[b] & bank_prio[b] : bank_req[b];

    always_comb begin
      // Create request
      vrf_request_o[b].req   = vld                 ;
      vrf_request_o[b].we    = arb_req_i[idx].we   ;
      vrf_request_o[b].addr  = arb_req_i[idx].addr ;
      vrf_request_o[b].wdata = arb_req_i[idx].wdata;
      vrf_request_o[b].be    = '1                  ;
      vrf_request_o[b].dest  = arb_req_i[idx].dest ;

      // Acknowledge that loop has issued
      issue[b]                      = '0                                                     ;
      issue[b][arb_req_i[idx].dest] = arb_req_i[idx].req && !arb_req_i[idx].we && gnt[b][idx];
    end

    rrarbiter #(
      .NUM_REQ(NUM_REQ)
    ) i_rrarbiter (
      .clk_i  (clk_i ),
      .rst_ni (rst_ni),
      .flush_i(1'b0  ),
      .en_i   (|req  ),
      .req_i  (req   ),
      .ack_o  (gnt[b]),
      .vld_o  (vld   ),
      .idx_o  (idx   )
    );
  end : arbiter_bank

endmodule : vrf_arbiter
