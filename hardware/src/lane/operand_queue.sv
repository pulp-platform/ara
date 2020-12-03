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
// File:   operand_queue.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   03.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This operand queue holds elements from the VRF until they are ready to be used
// by the VRFs. This unit is also able to do widening, for instructions that
// need it.

module operand_queue import ara_pkg::*; import rvv_pkg::*; #(
    parameter int unsigned BufferDepth = 2,
    parameter int unsigned NrSlaves    = 1,
    // Dependant parameters. DO NOT CHANGE!
    parameter int unsigned DataWidth   = $bits(elen_t)
  ) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    // Interface with the Vector Register File
    input  elen_t                operand_i,
    input  logic                 operand_valid_i,
    input  logic                 operand_issued_i,
    output logic                 operand_queue_ready_o,
    // Interface with the functional units
    output elen_t                operand_o,
    output logic                 operand_valid_o,
    input  logic  [NrSlaves-1:0] operand_ready_i
  );

  /************
   *  Buffer  *
   ************/

  // This FIFO holds words to be used by the VFUs.
  elen_t ibuf_operand;
  logic  ibuf_operand_valid;
  logic  ibuf_empty;
  logic  ibuf_pop;

  fifo_v3 #(
    .DEPTH       (BufferDepth),
    .DATA_WIDTH  (DataWidth  ),
    .FALL_THROUGH(1'b1       )
  ) i_input_buffer (
    .clk_i     (clk_i          ),
    .rst_ni    (rst_ni         ),
    .testmode_i(1'b0           ),
    .flush_i   (1'b0           ),
    .data_i    (operand_i      ),
    .push_i    (operand_valid_i),
    .full_o    (/* Unused */   ),
    .data_o    (ibuf_operand   ),
    .pop_i     (ibuf_pop       ),
    .empty_o   (ibuf_empty     ),
    .usage_o   (/* Unused */   )
  );
  assign ibuf_operand_valid = !ibuf_empty;

  // We used a credit based system, to ensure that the FIFO is always
  // able to accept a request.
  logic [cf_math_pkg::idx_width(BufferDepth)-1:0] ibuf_usage_d, ibuf_usage_q;

  always_comb begin: p_ibuf_usage
    // Maintain state
    ibuf_usage_d = ibuf_usage_q;

    // Will received a new operand
    if (operand_issued_i)
      ibuf_usage_d += 1;
    // Consumed an operand
    if (ibuf_pop)
      ibuf_usage_d -= 1;

    // Are we ready?
    operand_queue_ready_o = (ibuf_usage_q != BufferDepth);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_ibuf_usage_ff
    if (!rst_ni) begin
      ibuf_usage_q <= '0;
    end else begin
      ibuf_usage_q <= ibuf_usage_d;
    end
  end

  /********************
   *  Operand output  *
   *******************/

  elen_t obuf_operand;
  logic  obuf_operand_valid;

  always_comb begin: obuf_control
    // Do not pop anything from the input buffer queue
    ibuf_pop = 1'b0;

    // Send the operand
    obuf_operand       = ibuf_operand;
    obuf_operand_valid = ibuf_operand_valid;

    // Account for sent operands
    if (|operand_ready_i)
      ibuf_pop = 1'b1;
  end: obuf_control

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_obuf_ff
    if (!rst_ni) begin
      operand_o       <= '0;
      operand_valid_o <= 1'b0;
    end else begin
      operand_o       <= obuf_operand;
      operand_valid_o <= obuf_operand_valid;
    end
  end

endmodule : operand_queue
