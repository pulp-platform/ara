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
// File          : vaccess_stage.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 23.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This pipeline stage accesses the Vector Register File.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module vaccess_stage (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    input  vrf_request_t [VRF_NBANKS-1:0] vrf_request_i,
    // Operands
    output word_t        [NR_OPQUEUE-1:0] word_o
  );

  // Output from VRF
  logic         [VRF_NBANKS-1:0][63:0] vac_rdata;
  vrf_request_t [VRF_NBANKS-1:0]       vrf_request_q;

  /***********
   *  BANKS  *
   ***********/

  for (genvar i = 0; i < VRF_NBANKS; i++) begin: gen_banks
    sram #(
      .DATA_WIDTH(64                          ),
      .NUM_WORDS (VRF_SIZE / (VRF_NBANKS * 64))
    ) data_sram (
      .clk_i  (clk_i                      ),
      .req_i  (vrf_request_i[i].req       ),
      .we_i   (vrf_request_i[i].we        ),
      .addr_i (vrf_request_i[i].addr.index),
      .wdata_i(vrf_request_i[i].wdata     ),
      .be_i   (vrf_request_i[i].be        ),
      .rdata_o(vac_rdata[i]               ),
      .*
    );
  end : gen_banks

  /*****************
   *  MULTIPLEXER  *
   *****************/

  always_comb begin: vrf_mux
    word_o = '0;

    for (int i = 0; i < VRF_NBANKS; i++)
      if (vrf_request_q[i].req && !vrf_request_q[i].we) begin
        word_o[vrf_request_q[i].dest].word  = vac_rdata[i];
        word_o[vrf_request_q[i].dest].valid = 1'b1        ;
      end
  end : vrf_mux

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vrf_request_q <= '0;
    end else begin
      vrf_request_q <= vrf_request_i;
    end
  end

endmodule : vaccess_stage
