// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This operand queue holds elements from the VRF until they are ready to be used
// by the VRFs. This unit is also able to do widening, for instructions that
// need it.

module operand_queue import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter  int           unsigned BufferDepth    = 2,
    parameter  int           unsigned NrSlaves       = 1,
    parameter  int           unsigned NrLanes        = 0,
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport     = FPUSupportHalfSingleDouble,
    // Supported conversions
    parameter  logic                  SupportIntExt2 = 1'b0,
    parameter  logic                  SupportIntExt4 = 1'b0,
    parameter  logic                  SupportIntExt8 = 1'b0,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           unsigned DataWidth      = $bits(elen_t),
    localparam int           unsigned StrbWidth      = DataWidth/8
  ) (
    input  logic                              clk_i,
    input  logic                              rst_ni,
    // Lane ID
    input  logic [idx_width(NrLanes)-1:0]     lane_id_i,
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
    output target_fu_e                        operand_target_fu_o,
    output logic                              operand_valid_o,
    input  logic               [NrSlaves-1:0] operand_ready_i
  );

  //////////////////////
  //  Command Buffer  //
  //////////////////////

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

  //////////////
  //  Buffer  //
  //////////////

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
  logic [idx_width(BufferDepth):0] ibuf_usage_d, ibuf_usage_q;

  always_comb begin: p_ibuf_usage
    // Maintain state
    ibuf_usage_d = ibuf_usage_q;

    // Will received a new operand
    if (operand_issued_i) ibuf_usage_d += 1;
    // Consumed an operand
    if (ibuf_pop) ibuf_usage_d -= 1;

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

  ///////////////////////
  //  Type conversion  //
  ///////////////////////

  elen_t                            conv_operand;
  // Decide whether we are taking the operands from the lower or from the upper half of the input
  // buffer operand
  logic  [idx_width(StrbWidth)-1:0] select_d, select_q;

  always_comb begin: type_conversion
    // Helper variables for reductions
    logic ntrh, ntrl;
    // Shuffle the input operand
    automatic logic [idx_width(StrbWidth)-1:0] select = deshuffle_index(select_q, 1, cmd.eew);

    // Default: no conversion
    conv_operand = ibuf_operand;

    // Calculate the neutral values for reductions
    // Examples with EW8:
    // VREDSUM, VREDOR, VREDXOR, VREDMAXU, VWREDSUMU, VWRESUM: 0x00
    // VREDAND, VREDMINU:                                      0xff
    // VREDMIN:                                                0x7f
    // VREDMAX:                                                0x80
    // Neutral low bits
    ntrl = cmd.ntr_red[0];
    // Neutral high bit
    ntrh = cmd.ntr_red[1];

    unique case (cmd.conv)
      // Sign extension
      OpQueueConversionSExt2: begin
        if (SupportIntExt2) unique case (cmd.eew)
            EW8 : for (int e = 0; e < 4; e++) conv_operand[16*e +: 16] =
                {{8 {ibuf_operand[16*e + 8*select + 7]}}, ibuf_operand[16*e + 8*select +: 8]};
            EW16: for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] =
                {{16{ibuf_operand[32*e + 8*select + 15]}}, ibuf_operand[32*e + 8*select +: 16]};
            EW32: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {{32{ibuf_operand[64*e + 8*select + 31]}}, ibuf_operand[64*e + 8*select +: 32]};
            default:;
          endcase
      end
      OpQueueConversionSExt4: begin
        if (SupportIntExt4) unique case (cmd.eew)
            EW8 : for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] =
                {{24{ibuf_operand[32*e + 8* select + 7]}}, ibuf_operand[32*e + 8*select +: 8]};
            EW16: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {{48{ibuf_operand[64*e + 8*select + 15]}}, ibuf_operand[64*e + 8*select +: 16]};
            default:;
          endcase
      end
      OpQueueConversionSExt8: begin
        if (SupportIntExt8) unique case (cmd.eew)
            EW8: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {{56{ibuf_operand[64*e + 8*select + 7]}}, ibuf_operand[64*e + 8*select +: 8]};
            default:;
          endcase
      end

      // Zero extension
      OpQueueConversionZExt2: begin
        if (SupportIntExt2) unique case (cmd.eew)
            EW8 : for (int e = 0; e < 4; e++) conv_operand[16*e +: 16] =
                { 8'b0, ibuf_operand[16*e + 8*select +: 8]};
            EW16: for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] =
                {16'b0, ibuf_operand[32*e + 8*select +: 16]};
            EW32: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {32'b0, ibuf_operand[64*e + 8*select +: 32]};
            default:;
          endcase
      end
      OpQueueConversionZExt4: begin
        if (SupportIntExt4) unique case (cmd.eew)
            EW8 : for (int e = 0; e < 2; e++) conv_operand[32*e +: 32] =
                {24'b0, ibuf_operand[32*e + 8*select +: 8]};
            EW16: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {48'b0, ibuf_operand[64*e + 8*select +: 16]};
            default:;
          endcase
      end
      OpQueueConversionZExt8: begin
        if (SupportIntExt8) unique case (cmd.eew)
            EW8: for (int e = 0; e < 1; e++) conv_operand[64*e +: 64] =
                {56'b0, ibuf_operand[64*e + 8*select +: 8]};
            default:;
          endcase
      end

      OpQueueIntReductionZExt: begin
        if (lane_id_i == '0) begin
          unique case (cmd.eew)
            EW8 : conv_operand = {{7{ntrh, { 7{ntrl}}}}, ibuf_operand[7:0]};
            EW16: conv_operand = {{3{ntrh, {15{ntrl}}}}, ibuf_operand[15:0]};
            EW32: conv_operand = {{1{ntrh, {31{ntrl}}}}, ibuf_operand[31:0]};
            default:;
          endcase
        end else begin
          unique case (cmd.eew)
            // Lane != 0, just send harmless values
            EW8 : conv_operand = {8{ntrh, { 7{ntrl}}}};
            EW16: conv_operand = {4{ntrh, {15{ntrl}}}};
            EW32: conv_operand = {2{ntrh, {31{ntrl}}}};
            default: // EW64
              conv_operand = {1{ntrh, {63{ntrl}}}};
          endcase
        end
      end

      // Floating-point neutral value
      // pinf -> positive infinity, ninf -> negative infinity
      OpQueueFloatReductionZExt: begin
        if (lane_id_i == '0) begin
          unique case (cmd.ntr_red)
            2'b00: begin
              unique case (cmd.eew)
                EW16: conv_operand = {{3{16'd0}}, ibuf_operand[15:0]};
                EW32: conv_operand = {32'd0, ibuf_operand[31:0]};
                default:;
              endcase
            end
            2'b01: begin
              unique case (cmd.eew)
                EW16: conv_operand = {{3{16'h7c00}}, ibuf_operand[15:0]};
                EW32: conv_operand = {32'h7f800000, ibuf_operand[31:0]};
                default:;
              endcase
            end
            2'b10: begin
              unique case (cmd.eew)
                EW16: conv_operand = {{3{16'hfc00}}, ibuf_operand[15:0]};
                EW32: conv_operand = {32'hff800000, ibuf_operand[31:0]};
                default:;
              endcase
            end
          endcase
        end else begin
            // Lane != 0, just send harmless values
          unique case (cmd.ntr_red)
            2'b00: begin
              unique case (cmd.eew)
                EW16: conv_operand = '0;
                EW32: conv_operand = '0;
                default: // EW64
                  conv_operand = '0;
              endcase
            end
            2'b01: begin
              unique case (cmd.eew)
                EW16: conv_operand = {4{16'h7c00}};
                EW32: conv_operand = {2{32'h7f800000}};
                default: // EW64
                  conv_operand = 64'h7ff0000000000000;
              endcase
            end
            2'b10: begin
              unique case (cmd.eew)
                EW16: conv_operand = {4{16'hfc00}};
                EW32: conv_operand = {2{32'hff800000}};
                default: // EW64
                  conv_operand = 64'hfff0000000000000;
              endcase
            end
          endcase
        end
      end

      // Widening floating-point reduction
      OpQueueFloatReductionWideZExt: begin
        if (lane_id_i == '0) begin
          unique case (cmd.ntr_red)
            2'b00: begin
              unique case (cmd.eew)
                EW16: conv_operand = {32'd0, ibuf_operand[31:0]};
                EW32: conv_operand = ibuf_operand;
                default:;
              endcase
            end
            2'b01: begin
              unique case (cmd.eew)
                EW16: conv_operand = {32'h7f800000, ibuf_operand[31:0]};
                EW32: conv_operand = ibuf_operand;
                default:;
              endcase
            end
            2'b10: begin
              unique case (cmd.eew)
                EW16: conv_operand = {32'hff800000, ibuf_operand[31:0]};
                EW32: conv_operand = ibuf_operand;
                default:;
              endcase
            end
          endcase
        end else begin
            // Lane != 0, just send harmless values
          unique case (cmd.ntr_red)
            2'b00: begin
              unique case (cmd.eew)
                EW16: conv_operand = '0;
                EW32: conv_operand = '0;
                default:;
              endcase
            end
            2'b01: begin
              unique case (cmd.eew)
                EW16: conv_operand = {2{32'h7f800000}};
                EW32: conv_operand = 64'h7ff0000000000000;
                default:;
              endcase
            end
            2'b10: begin
              unique case (cmd.eew)
                EW16: conv_operand = {2{32'hff800000}};
                EW32: conv_operand = 64'hfff0000000000000;
                default:;
              endcase
            end
          endcase
        end
      end

      // Floating-Point re-encoding
      OpQueueConversionWideFP2: begin
        if (FPUSupport != FPUSupportNone) begin
          unique casez ({cmd.eew, RVVH(FPUSupport), RVVF(FPUSupport), RVVD(FPUSupport)})
            {EW16, 1'b1, 1'b1, 1'b?}: begin
              for (int e = 0; e < 2; e++) begin
                automatic fp16_t fp16 = ibuf_operand[8*select + 32*e +: 16];
                automatic fp32_t fp32;

                fp32.s = fp16.s;
                fp32.e = (fp16.e - 15) + 127;
                fp32.m = {fp16.m, 13'b0};

                conv_operand[32*e +: 32] = fp32;
              end
            end
            {EW32, 1'b?, 1'b1, 1'b1}: begin
              automatic fp32_t fp32 = ibuf_operand[8*select +: 32];
              automatic fp64_t fp64;

              fp64.s = fp32.s;
              fp64.e = (fp32.e - 127) + 1023;
              fp64.m = {fp32.m, 29'b0};

              conv_operand = fp64;
            end
            default:;
          endcase
        end
      end

      // Zero extension + Reordering for FP conversions
      OpQueueAdjustFPCvt: begin
        unique case (cmd.eew)
          EW16: conv_operand = {32'b0, ibuf_operand[32 + 8*select +: 16], ibuf_operand[8*select +: 16]};
          EW32: conv_operand = {32'b0, ibuf_operand[8*select +: 32]};
          default:;
        endcase
      end

      default:;
    endcase
  end : type_conversion

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
    // Encode the target functional unit when it is not clear
    // Default encoding: SLDU == 1'b0, ADDRGEN == 1'b1
    operand_target_fu_o = cmd.target_fu;

    // Account for sent operands
    if (operand_valid_o && |operand_ready_i) begin
      // Count the used elements
      unique case (cmd.conv)
        OpQueueConversionSExt2,
        OpQueueConversionZExt2,
        OpQueueConversionWideFP2,
        OpQueueAdjustFPCvt:
          if (SupportIntExt2) vl_d = vl_q + (1 << (int'(EW64) - int'(cmd.eew))) / 2;
        OpQueueConversionSExt4,
        OpQueueConversionZExt4:
          if (SupportIntExt4) vl_d = vl_q + (1 << (int'(EW64) - int'(cmd.eew))) / 4;
        OpQueueConversionSExt8,
        OpQueueConversionZExt8:
          if (SupportIntExt8) vl_d = vl_q + (1 << (int'(EW64) - int'(cmd.eew))) / 8;
        OpQueueIntReductionZExt, OpQueueFloatReductionZExt, OpQueueFloatReductionWideZExt:
          vl_d = vl_q + 1;
        default: vl_d = vl_q + (1 << (int'(EW64) - int'(cmd.eew)));
      endcase

      // Update the pointer to the input operand
      unique case (cmd.conv)
        OpQueueConversionSExt2, OpQueueConversionZExt2, OpQueueConversionWideFP2, OpQueueAdjustFPCvt:
          if (SupportIntExt2) select_d = select_q + 4;
        OpQueueConversionSExt4, OpQueueConversionZExt4: if (SupportIntExt4) select_d = select_q + 2;
        OpQueueConversionSExt8, OpQueueConversionZExt8: if (SupportIntExt8) select_d = select_q + 1;
        default:; // Do nothing.
      endcase

      // Finished using an operand
      if ((select_q != '0 && select_d == '0) || cmd.conv == OpQueueConversionNone) ibuf_pop = 1'b1;

      // Finished execution
      if (vl_d >= cmd.vl) begin
        ibuf_pop = 1'b1;
        cmd_pop  = 1'b1;
        select_d = '0;
        vl_d     = '0;
      end
    end
  end : obuf_control

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_type_conversion_ff
    if (!rst_ni) begin
      select_q <= '0;
      vl_q     <= '0;
    end else begin
      select_q <= select_d;
      vl_q     <= vl_d;
    end
  end : p_type_conversion_ff

endmodule : operand_queue
