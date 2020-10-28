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
// File:   ara.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's top-level, interfacing with Ariane.

module ara import ara_pkg::*; #(
    // RVV Parameters
    parameter int  unsigned NrLanes      = 0,     // Number of parallel vector lanes.
    // AXI Interface
    parameter int  unsigned AxiDataWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_r_t      = logic,
    parameter type          axi_aw_t     = logic,
    parameter type          axi_w_t      = logic,
    parameter type          axi_b_t      = logic,
    parameter type          axi_req_t    = logic,
    parameter type          axi_resp_t   = logic
  ) (
    // Clock and Reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Interface with Ariane
    input  accelerator_req_t  acc_req_i,
    input  logic              acc_req_valid_i,
    output logic              acc_req_ready_o,
    output accelerator_resp_t acc_resp_o,
    output logic              acc_resp_valid_o,
    input  logic              acc_resp_ready_i,
    // AXI interface
    output axi_req_t          axi_req_o,
    input  axi_resp_t         axi_resp_i
  );

  /********************************
   *  Ariane interface registers  *
   ********************************/

  // Request
  accelerator_req_t acc_req;
  logic             acc_req_valid;
  logic             acc_req_ready;
  spill_register #(
    .T(accelerator_req_t)
  ) i_acc_req_register (
    .clk_i  (clk_i          ),
    .rst_ni (rst_ni         ),
    .data_i (acc_req_i      ),
    .valid_i(acc_req_valid_i),
    .ready_o(acc_req_ready_o),
    .data_o (acc_req        ),
    .valid_o(acc_req_valid  ),
    .ready_i(acc_req_ready  )
  );

  // Response
  accelerator_resp_t acc_resp;
  logic              acc_resp_valid;
  logic              acc_resp_ready;
  spill_register #(
    .T(accelerator_resp_t)
  ) i_acc_resp_register (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .data_i (acc_resp        ),
    .valid_i(acc_resp_valid  ),
    .ready_o(acc_resp_ready  ),
    .data_o (acc_resp_o      ),
    .valid_o(acc_resp_valid_o),
    .ready_i(acc_resp_ready_i)
  );

  /****************
   *  Dispatcher  *
   ****************/

  ara_dispatcher i_dispatcher (
    .clk_i           (clk_i         ),
    .rst_ni          (rst_ni        ),
    .acc_req_i       (acc_req       ),
    .acc_req_valid_i (acc_req_valid ),
    .acc_req_ready_o (acc_req_ready ),
    .acc_resp_o      (acc_resp      ),
    .acc_resp_valid_o(acc_resp_valid),
    .acc_resp_ready_i(acc_resp_ready)
  );

  /****************************
   *  Vector Load/Store Unit  *
   ****************************/

  // TODO: Connect the AXI interface
  assign axi_req_o = '0;

  /****************
   *  Assertions  *
   ****************/

  if (NrLanes == 0)
    $fatal(1, "[ara] Ara needs to have at least one lane.");

  if (ara_pkg::VLEN == 0)
    $fatal(1, "[ara] The vector length must be greater than zero.");

  if (ara_pkg::VLEN < ELEN)
    $fatal(1, "[ara] The vector length must be greater or equal than the maximum size of a single vector element");

  if (ara_pkg::VLEN != 2**$clog2(ara_pkg::VLEN))
    $fatal(1, "[ara] The vector length must be a power of two.");

  if (SLEN * (ara_pkg::VLEN / SLEN) != ara_pkg::VLEN)
    $fatal(1, "[ara] The vector length must be a multiple of the lane datapath width.");

  if (ara_pkg::VLEN < SLEN * NrLanes)
    $fatal(1, "[ara] There must be at least one element of a vector register at each vector lane.");

endmodule : ara
