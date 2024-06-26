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
    parameter  int           unsigned CmdBufDepth         = 2,
    parameter  int           unsigned DataBufDepth        = 2,
    parameter  int           unsigned NrSlaves            = 1,
    parameter  int           unsigned NrLanes             = 0,
    parameter  int           unsigned VLEN                = 0,
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport          = FPUSupportHalfSingleDouble,
    // Supported conversions
    parameter  logic                  SupportIntExt2      = 1'b0,
    parameter  logic                  SupportIntExt4      = 1'b0,
    parameter  logic                  SupportIntExt8      = 1'b0,
    // Support neutral value filling
    parameter  logic                  SupportReduct       = 1'b0,
    parameter  logic                  SupportNtrVal       = 1'b0,
    parameter  type                   operand_queue_cmd_t = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           unsigned DataWidth      = $bits(elen_t),
    localparam int           unsigned StrbWidth      = DataWidth/8,
    localparam type                   vlen_t         = logic[$clog2(VLEN+1)-1:0]
  ) (
    input  logic                              clk_i,
    input  logic                              rst_ni,
    input  logic                              flush_i,
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
    .DEPTH(CmdBufDepth        ),
    .dtype(operand_queue_cmd_t)
  ) i_cmd_buffer (
    .clk_i     (clk_i                    ),
    .rst_ni    (rst_ni                   ),
    .testmode_i(1'b0                     ),
    .flush_i   (flush_i                  ),
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
    .DEPTH     (DataBufDepth),
    .DATA_WIDTH(DataWidth   )
  ) i_input_buffer (
    .clk_i     (clk_i          ),
    .rst_ni    (rst_ni         ),
    .testmode_i(1'b0           ),
    .flush_i   (flush_i        ),
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
  logic [idx_width(DataBufDepth):0] ibuf_usage_d, ibuf_usage_q;

  always_comb begin: p_ibuf_usage
    // Maintain state
    ibuf_usage_d = ibuf_usage_q;

    // Will received a new operand
    if (operand_issued_i) ibuf_usage_d += 1;
    // Consumed an operand
    if (ibuf_pop) ibuf_usage_d -= 1;
    // Flush the ibuf_usage_d
    if (flush_i) ibuf_usage_d = '0;

    // Are we ready?
    operand_queue_ready_o = (ibuf_usage_q != DataBufDepth);
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

  // Count how many operands were already produced
  vlen_t elem_count_d, elem_count_q;

  elen_t                            conv_operand;
  // Decide whether we are taking the operands from the lower or from the upper half of the input
  // buffer operand
  logic  [idx_width(StrbWidth)-1:0] select_d, select_q;

  // Neutral value for the computational operation
  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } ntr_operand_t;
  ntr_operand_t ntr;

  // Helper variables for reductions
  logic ntrh_int, ntrl_int;

  // Helper to fill with neutral values the last packet
  logic incomplete_packet, last_packet;

  ////////////////////////////////
  //  Floating-point conversion //
  ////////////////////////////////

  logic [$clog2(fp_mantissa_bits(EW16, 0))-1:0] fp16_m_lzc[2]; // 4 bits each
  logic [$clog2(fp_mantissa_bits(EW32, 0))-1:0] fp32_m_lzc;    // 5 bits each

  fp16_t fp16[2];
  fp32_t fp32;

  // To convert subnormal numbers to normalized form in floating-point numbers,
  // it is necessary to determine the number of leading zeros in the mantissa.
  // This is typically accomplished using a lzc (leading zero count) module,
  // which can accurately count the number of leading zeros in a given number.
  // By knowing the number of leading zeros in the mantissa, we can properly
  // adjust the exponent and shift the binary point to achieve a normalized
  // representation of the number.
  if ({RVVH(FPUSupport), RVVF(FPUSupport)} == 2'b11) begin
    // sew: 16-bit
    for (genvar i = 0; i < 2; i++) begin
      lzc #(
        .WIDTH(fp_mantissa_bits(EW16, 0)),
        .MODE (1)
      ) leading_zero_e16_i (
        .in_i   (fp16[i].m    ),
        .cnt_o  (fp16_m_lzc[i]),
        .empty_o(/*Unused*/   )
      );
    end
  end

  if ({RVVF(FPUSupport), RVVD(FPUSupport)} == 2'b11) begin
    // sew: 32-bit
    lzc #(
       .WIDTH(fp_mantissa_bits(EW32, 0)),
       .MODE (1)
     ) leading_zero_e32 (
       .in_i   (fp32.m    ),
       .cnt_o  (fp32_m_lzc),
       .empty_o(/*Unused*/)
     );
  end

  always_comb begin: type_conversion
    // Shuffle the input operand
    automatic logic [idx_width(StrbWidth)-1:0] select = deshuffle_index(select_q, 1, cmd.eew);

    // Default: no conversion
    conv_operand = ibuf_operand;
    // Default: packet complete
    incomplete_packet = 1'b0;
    last_packet       = 1'b0;

    for (int i = 0; i < 2; i++) fp16[i] = '0;
    for (int i = 0; i < 1; i++) fp32[i] = '0;

    // Reductions need to mask away the inactive elements
    // A temporary solution is to send a neutral value directly
    // from the opqueues
    if (SupportNtrVal || SupportReduct) begin
      // Calculate the neutral values for reductions
      // Examples with EW8:
      // VREDSUM, VREDOR, VREDXOR, VREDMAXU, VWREDSUMU, VWRESUM: 0x00
      // VREDAND, VREDMINU:                                      0xff
      // VREDMIN:                                                0x7f
      // VREDMAX:                                                0x80
      // Neutral low bits
      ntrl_int = cmd.ntr_red[0];
      ntrh_int = cmd.ntr_red[1];

      // During a reduction, all the elements that should not contribute
      // should have a neutral value.
      // If the 64-bit packet is not complete, the
      // upper MSb can corrupt the result.
      // The following neutral values will be inserted wherever an
      // harmless value is needed not to change the result of the
      // legit operation.
      // Power optimization:
      // The optimal solution would be to act on the mask bits in the two
      // processing units (valu and vmfpu), masking the unused elements.
      ntr = '0;
      // Gate for power saving
      if (cmd.is_reduct) begin
        unique case (cmd.target_fu)
          ALU_SLDU: begin
            unique case (cmd.eew)
              EW8 :    ntr.w64 = {8{ntrh_int, { 7{ntrl_int}}}};
              EW16:    ntr.w64 = {4{ntrh_int, {15{ntrl_int}}}};
              EW32:    ntr.w64 = {2{ntrh_int, {31{ntrl_int}}}};
              default: ntr.w64 = {1{ntrh_int, {63{ntrl_int}}}};
            endcase
          end
          MFPU_ADDRGEN: begin
            unique case (cmd.eew)
              EW16: begin
                unique case (cmd.ntr_red)
                  2'b01: ntr.w64 = {4{16'h7c00}};
                  2'b10: ntr.w64 = {4{16'hfc00}};
                  default:;
                endcase
              end
              EW32: begin
                unique case (cmd.ntr_red)
                  2'b01: ntr.w64 = {2{32'h7f800000}};
                  2'b10: ntr.w64 = {2{32'hff800000}};
                  default:;
                endcase
              end
              // Add EW64 for convenience of coding
              default: begin
                unique case (cmd.ntr_red)
                  2'b01: ntr.w64 = {1{64'h7ff0000000000000}};
                  2'b10: ntr.w64 = {1{64'hfff0000000000000}};
                  default:;
                endcase
              end
            endcase
          end
          default:;
        endcase
      end

      // Assert the signal if the last 64-bit packet will contain also
      // elements with idx >= elem_count (they should not contribute to the result!).
      // Gate for power saving
      // Power optimization:
      // The optimal solution would be to act on the mask bits in the two
      // processing units (valu and vmfpu), masking the unused elements.
      unique case (cmd.eew)
        EW8 : begin
          incomplete_packet = |cmd.elem_count[2:0];
          last_packet       = ((cmd.elem_count - elem_count_q) <= 8) ? 1'b1 : 1'b0;
        end
        EW16: begin
          incomplete_packet = |cmd.elem_count[1:0];
          last_packet       = ((cmd.elem_count - elem_count_q) <= 4) ? 1'b1 : 1'b0;
        end
        EW32: begin
          incomplete_packet = |cmd.elem_count[0:0];
          last_packet       = ((cmd.elem_count - elem_count_q) <= 2) ? 1'b1 : 1'b0;
        end
        default: begin
          incomplete_packet = 1'b0;
          last_packet       = 1'b0;
        end
      endcase
    end

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

      OpQueueReductionZExt: begin
        if (SupportReduct) begin
          if (lane_id_i == '0) begin
            unique case (cmd.eew)
              EW8 : conv_operand = {ntr.w8[7:1] , ibuf_operand[7:0]};
              EW16: conv_operand = {ntr.w16[3:1], ibuf_operand[15:0]};
              EW32: conv_operand = {ntr.w32[1:1], ibuf_operand[31:0]};
              default:;
            endcase
          end else begin
            conv_operand = ntr.w64;
          end
        end
      end

      // Floating-Point re-encoding
      OpQueueConversionWideFP2: begin
        if (FPUSupport != FPUSupportNone) begin
          unique casez ({cmd.eew, RVVH(FPUSupport), RVVF(FPUSupport), RVVD(FPUSupport)})
            {EW16, 1'b1, 1'b1, 1'b?}: begin
              for (int e = 0; e < 2; e++) begin
                fp16[e] = ibuf_operand[8*select + 32*e +: 16];
                conv_operand[32*e +: 32] = fp32_from_fp16(fp16[e], fp16_m_lzc[e]);
              end
            end
            {EW32, 1'b?, 1'b1, 1'b1}: begin
              fp32 = ibuf_operand[8*select +: 32];
              conv_operand = fp64_from_fp32(fp32, fp32_m_lzc);
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

      // Pad with neutral values the MSb of an incomplete 64-bit packet
      // not to compromise reductions.
      default: begin
        // Pad only the last packet during a reduction, and pad the correct bytes only!
        if (last_packet && incomplete_packet) begin
          if (SupportNtrVal) unique case (cmd.eew)
            EW8 : for (int unsigned b = 0; b < 8; b++) begin
                    automatic int unsigned bs = shuffle_index(b, 1, EW8);
                    if ((b >> 0) >= cmd.elem_count[2:0]) conv_operand[8*bs +: 8] = ntr.w8[b];
                  end
            EW16: for (int unsigned b = 0; b < 8; b++) begin
                    automatic int unsigned bs = shuffle_index(b, 1, EW16);
                    if ((b >> 1) >= cmd.elem_count[1:0]) conv_operand[8*bs +: 8] = ntr.w8[b];
                  end
            EW32: for (int unsigned b = 0; b < 8; b++) begin
                    automatic int unsigned bs = shuffle_index(b, 1, EW32);
                    if ((b >> 2) >= cmd.elem_count[0:0]) conv_operand[8*bs +: 8] = ntr.w8[b];
                  end
            default:;
          endcase
        end
      end
    endcase
  end : type_conversion

  /********************
   *  Operand output  *
   *******************/

  always_comb begin: obuf_control
    // Do not pop anything from the any of the queues
    ibuf_pop = 1'b0;
    cmd_pop  = 1'b0;

    // Maintain state
    select_d = select_q;
    elem_count_d     = elem_count_q;

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
          if (SupportIntExt2) elem_count_d = elem_count_q + (1 << (unsigned'(EW64) - unsigned'(cmd.eew))) / 2;
        OpQueueConversionSExt4,
        OpQueueConversionZExt4:
          if (SupportIntExt4) elem_count_d = elem_count_q + (1 << (unsigned'(EW64) - unsigned'(cmd.eew))) / 4;
        OpQueueConversionSExt8,
        OpQueueConversionZExt8:
          if (SupportIntExt8) elem_count_d = elem_count_q + (1 << (unsigned'(EW64) - unsigned'(cmd.eew))) / 8;
        OpQueueReductionZExt:
          elem_count_d = elem_count_q + 1;
        default: elem_count_d = elem_count_q + (1 << (unsigned'(EW64) - unsigned'(cmd.eew)));
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
      if (elem_count_d >= cmd.elem_count) begin : finished_elems
        ibuf_pop = 1'b1;
        cmd_pop  = 1'b1;
        select_d = '0;
        elem_count_d     = '0;
      end : finished_elems
    end
    // Flush sequential signals
    if (flush_i) begin
      select_d     = '0;
      elem_count_d = '0;
    end
  end : obuf_control

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_type_conversion_ff
    if (!rst_ni) begin
      select_q <= '0;
      elem_count_q     <= '0;
    end else begin
      select_q <= select_d;
      elem_count_q     <= elem_count_d;
    end
  end : p_type_conversion_ff

endmodule : operand_queue
