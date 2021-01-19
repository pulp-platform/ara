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
    parameter int unsigned DataWidth   = $bits(elen_t),
    parameter int unsigned StrbWidth   = DataWidth/8
  ) (
    input  logic                              clk_i,
    input  logic                              rst_ni,
    // Interface with the Operand Requester
    input  operand_queue_cmd_t                operand_queue_cmd_i,
    input  logic                              operand_queue_cmd_valid_i,
    // Interface with the Vector Register File
    input  elen_t                             operand_i,
    input  logic                              operand_valid_i,
    input  logic                              operand_issued_i,
    output logic                              operand_queue_ready_o,
    // Interface with the functional units
    output elen_t                             operand_o,
    output logic                              operand_valid_o,
    input  logic               [NrSlaves-1:0] operand_ready_i
  );

  /********************
   *  Command Buffer  *
   ********************/

  operand_queue_cmd_t cmd;
  logic               cmd_pop;

  fifo_v3 #(
    .DEPTH(BufferDepth        ),
    .dtype(operand_queue_cmd_t)
  ) i_cmd_buffer (
    .clk_i     (clk_i                    ),
    .rst_ni    (rst_ni                   ),
    .testmode_i(1'b0                     ),
    .flush_i   (1'b0                     ),
    .data_i    (operand_queue_cmd_i      ),
    .push_i    (operand_queue_cmd_valid_i),
    .full_o    (/* Unused */             ),
    .data_o    (cmd                      ),
    .empty_o   (/* Unused */             ),
    .pop_i     (cmd_pop                  ),
    .usage_o   (/* Unused */             )
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
    .DEPTH     (BufferDepth),
    .DATA_WIDTH(DataWidth  )
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
  logic [cf_math_pkg::idx_width(BufferDepth):0] ibuf_usage_d, ibuf_usage_q;

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

  /*********************
   *  Type conversion  *
   *********************/

  elen_t                                         conv_operand;
  // Decide whether we are taking the operands from the lower or from the upper half of the input buffer operand
  logic  [cf_math_pkg::idx_width(StrbWidth)-1:0] select_d, select_q;

  always_comb begin: type_conversion
    // Shuffle the input operand
    automatic logic [cf_math_pkg::idx_width(StrbWidth)-1:0] select = deshuffle_index(select_q, 1, cmd.eew);

    unique case (cmd.conv)
      // No conversion
      OpQueueConversionNone: conv_operand = ibuf_operand;

      // Sign extension
      OpQueueConversionSExt2: begin
        unique case (cmd.eew)
          EW8 : for (int e = 0; e < 4; e++) conv_operand[16*e +: 16] = {{8 {ibuf_operand[16*e + 8*select + 7]}}, ibuf_operand[16*e + 8*select +: 8]};
          EW16: for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] = {{16{ibuf_operand[32*e + 8*select + 15]}}, ibuf_operand[32*e + 8*select +: 16]};
          EW32: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {{32{ibuf_operand[64*e + 8*select + 31]}}, ibuf_operand[64*e + 8*select +: 32]};
        endcase
      end
      OpQueueConversionSExt4: begin
        unique case (cmd.eew)
          EW8 : for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] = {{24{ibuf_operand[32*e + 8*select + 7]}}, ibuf_operand[32*e + 8*select +: 8]};
          EW16: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {{48{ibuf_operand[64*e + 8*select + 15]}}, ibuf_operand[64*e + 8*select +: 16]};
        endcase
      end
      OpQueueConversionSExt8: begin
        unique case (cmd.eew)
          EW8: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {{56{ibuf_operand[64*e + 8*select + 7]}}, ibuf_operand[64*e + 8*select +: 8]};
        endcase
      end

      // Zero extension
      OpQueueConversionZExt2: begin
        unique case (cmd.eew)
          EW8 : for (int e = 0; e < 4; e++) conv_operand[16*e +: 16] = { 8'b0, ibuf_operand[16*e + 8*select +: 8]};
          EW16: for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] = {16'b0, ibuf_operand[32*e + 8*select +: 16]};
          EW32: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {32'b0, ibuf_operand[64*e + 8*select +: 32]};
        endcase
      end
      OpQueueConversionZExt4: begin
        unique case (cmd.eew)
          EW8 : for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] = {24'b0, ibuf_operand[32*e + 8*select +: 8]};
          EW16: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {48'b0, ibuf_operand[64*e + 8*select +: 16]};
        endcase
      end
      OpQueueConversionZExt8: begin
        unique case (cmd.eew)
          EW8: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] = {56'b0, ibuf_operand[64*e + 8*select +: 8]};
        endcase
      end
    endcase
  end: type_conversion

  /********************
   *  Operand output  *
   *******************/

  // Count how many operands were already produced
  vlen_t vl_d, vl_q;

  always_comb begin: obuf_control
    // Do not pop anything from the any of the queues
    ibuf_pop = 1'b0;
    cmd_pop  = 1'b0;

    // Maintain state
    select_d = select_q;
    vl_d     = vl_q;

    // Send the operand
    operand_o       = conv_operand;
    operand_valid_o = ibuf_operand_valid;

    // Account for sent operands
    if (operand_valid_o && |operand_ready_i) begin
      // Count the used elements
      vl_d = vl_q + (1 << (int'(EW64) - int'(cmd.sew)));

      // Update the pointer to the input operand
      unique case (cmd.conv)
        OpQueueConversionSExt2, OpQueueConversionZExt2: select_d = select_q + 4;
        OpQueueConversionSExt4, OpQueueConversionZExt4: select_d = select_q + 2;
        OpQueueConversionSExt8, OpQueueConversionZExt8: select_d = select_q + 1;
        default:; // Do nothing.
      endcase

      // Finished using an operand
      if ((select_q != '0 && select_d == '0) || cmd.conv == OpQueueConversionNone)
        ibuf_pop = 1'b1;

      // Finished execution
      if (vl_d >= cmd.vl) begin
        ibuf_pop = 1'b1;
        cmd_pop  = 1'b1;
        select_d = '0;
        vl_d     = '0;
      end
    end
  end: obuf_control

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_type_conversion_ff
    if (!rst_ni) begin
      select_q <= '0;
      vl_q     <= '0;
    end else begin
      select_q <= select_d;
      vl_q     <= vl_d;
    end
  end

endmodule : operand_queue
