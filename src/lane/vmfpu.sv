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
// File          : vmfpu.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 08.04.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's integer multiplier and floating-point unit.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;
import riscv::vwidth_t    ;
import riscv::vrepr_t     ;
import fpnew_pkg::fp_format_e;
import fpnew_pkg::operation_e;

module vmfpu (
    input  logic               clk_i,
    input  logic               rst_ni,
    // Operation
    input  operation_t         operation_i,
    output vfu_status_t        vfu_status_o,
    // Operands
    input  word_t        [3:0] mfpu_operand_i,
    output logic               mfpu_operand_ready_o,
    // Result
    output arb_request_t       mfpu_result_o,
    input  logic               mfpu_result_gnt_i
  );

  /*******************
   *  OUTPUT BUFFER  *
   *******************/

  localparam int unsigned OBUF_DEPTH = 4;
  struct packed {
    logic [OBUF_DEPTH-1:0][63:0] result;

    logic [$clog2(OBUF_DEPTH)-1:0] read_pnt ;
    logic [$clog2(OBUF_DEPTH)-1:0] write_pnt;
    logic [$clog2(OBUF_DEPTH):0] cnt        ;
  } obuf_d, obuf_q;

  logic obuf_full;
  logic obuf_empty;

  // Assignments
  assign obuf_full  = obuf_q.cnt == OBUF_DEPTH;
  assign obuf_empty = obuf_q.cnt == 0         ;

  /***********
   *  STATE  *
   ***********/

  vsize_t issue_cnt_d, issue_cnt_q;
  vsize_t commit_cnt_d, commit_cnt_q;

  /*********************
   *  OPERATION QUEUE  *
   *********************/

  struct packed {
    operation_t [OPQUEUE_DEPTH-1:0] insn;

    logic [$clog2(OPQUEUE_DEPTH)-1:0] issue_pnt ;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] commit_pnt;
    logic [$clog2(OPQUEUE_DEPTH)-1:0] accept_pnt;

    logic [$clog2(OPQUEUE_DEPTH):0] issue_cnt ;
    logic [$clog2(OPQUEUE_DEPTH):0] commit_cnt;
  } opqueue_d, opqueue_q;

  logic opqueue_full ;
  assign opqueue_full = opqueue_q.commit_cnt == OPQUEUE_DEPTH;

  logic issue_valid ;
  logic commit_valid;
  assign issue_valid  = opqueue_q.issue_cnt != 0 ;
  assign commit_valid = opqueue_q.commit_cnt != 0;

  operation_t operation_issue_q ;
  operation_t operation_commit_q;
  assign operation_issue_q  = opqueue_q.insn[opqueue_q.issue_pnt] ;
  assign operation_commit_q = opqueue_q.insn[opqueue_q.commit_pnt];

  vfu_op   op_i ;
  vwidth_t width_i;
  vrepr_t  repr_i ;
  assign op_i    = opqueue_q.insn[opqueue_q.issue_pnt].op      ;
  assign width_i = opqueue_q.insn[opqueue_q.issue_pnt].vd.width;
  assign repr_i  = opqueue_q.insn[opqueue_q.issue_pnt].vd.repr ;

  /**************
   *  OPERANDS  *
   **************/
  //-----------------------------------
  // FPnew config from FPnew package
  //-----------------------------------
  localparam OPBITS  =  fpnew_pkg::OP_BITS;
  localparam FMTBITS =  $clog2(fpnew_pkg::NUM_FP_FORMATS);

  logic [63:0] operand_a;
  logic [63:0] operand_b;
  logic [63:0] operand_c;
  logic [ 7:0] operand_m;

  logic [OPBITS-1:0]  fp_op ;
  logic               fp_opmod ;
  logic [FMTBITS-1:0] fp_fmt ;
  logic [2:0]         fp_rm ;
  logic [2:0]         fp_sign ;
  logic               fp_vect_op;

  always_comb begin: operands
    operand_a = mfpu_operand_i[1].word;
    operand_b = mfpu_operand_i[2].word;
    operand_c = mfpu_operand_i[3].word;

    // Send operand_m as trans_id_i
    for (int b = 0; b < 8; b++)
      operand_m[b] = operation_issue_q.mask == riscv::NOMASK ? '1 : mfpu_operand_i[0].word[8*b];

    // Sign injection
    case (width_i)
      riscv::WD_V16B:
        for (int b = 0; b < 4; b++) begin
          operand_a[16*b+15] = operand_a[16*b+15] ^ fp_sign[0];
          operand_b[16*b+15] = operand_b[16*b+15] ^ fp_sign[1];
          operand_c[16*b+15] = operand_c[16*b+15] ^ fp_sign[2];
        end
      riscv::WD_V32B:
        for (int b = 0; b < 2; b++) begin
          operand_a[32*b+31] = operand_a[32*b+31] ^ fp_sign[0];
          operand_b[32*b+31] = operand_b[32*b+31] ^ fp_sign[1];
          operand_c[32*b+31] = operand_c[32*b+31] ^ fp_sign[2];
        end
      riscv::WD_V64B:
        for (int b = 0; b < 1; b++) begin
          operand_a[64*b+63] = operand_a[64*b+63] ^ fp_sign[0];
          operand_b[64*b+63] = operand_b[64*b+63] ^ fp_sign[1];
          operand_c[64*b+63] = operand_c[64*b+63] ^ fp_sign[2];
        end
    endcase

    // Addition is between operands B and C
    if (op_i inside {VADD, VSUB})
      operand_c = operand_a;

    // Avoid a NaN on the unused operand of the FPU.
    if (op_i == VSQRT)
      operand_b = operand_a;
  end : operands

  /*********
   *  FPU  *
   *********/
  // Features (enabled formats, vectors etc.)
  localparam fpnew_pkg::fpu_features_t FPU_FEATURES = '{
    Width:         64,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     {1'b1, 1'b1, 1'b1, 1'b0, 1'b0},
    IntFmtMask:    {1'b0, 1'b0, 1'b0, 1'b0}
  };

  localparam int unsigned LAT_COMP_VFP32    = 'd4;
  localparam int unsigned LAT_COMP_VFP64    = 'd5;
  localparam int unsigned LAT_COMP_VFP16    = 'd3;
  localparam int unsigned LAT_COMP_VFP16ALT = 'd3;
  localparam int unsigned LAT_COMP_VFP8     = 'd2;
  localparam int unsigned LAT_VDIVSQRT      = 'd3;
  localparam int unsigned LAT_VNONCOMP      = 'd1;
  localparam int unsigned LAT_VCONV         = 'd2;

  // Implementation (number of registers etc)
  localparam fpnew_pkg::fpu_implementation_t FPU_IMPLEMENTATION = '{
    PipeRegs:  '{// FP32, FP64, FP16, FP8, FP16alt
      '{LAT_COMP_VFP32, LAT_COMP_VFP64, LAT_COMP_VFP16, LAT_COMP_VFP8, LAT_COMP_VFP16ALT}, // ADDMUL
      '{default: LAT_VDIVSQRT}, // DIVSQRT
      '{default: LAT_VNONCOMP}, // NONCOMP
      '{default: LAT_VCONV}},   // CONV
    UnitTypes: '{'{default: fpnew_pkg::PARALLEL}, // ADDMUL
      '{default: fpnew_pkg::MERGED},   // DIVSQRT
      '{default: fpnew_pkg::PARALLEL}, // NONCOMP
      '{default: fpnew_pkg::MERGED}},  // CONV
    PipeConfig: fpnew_pkg::DISTRIBUTED
  };

  logic [2:0][FLEN-1:0] fpu_operands;

  assign fpu_operands[0] = operand_a;
  assign fpu_operands[1] = operand_b;
  assign fpu_operands[2] = operand_c;

  logic [63:0] fpu_result;
  logic [7:0]  fpu_operand_m;

  logic fpu_in_valid;
  logic fpu_out_valid;
  logic fpu_in_ready;
  logic fpu_out_ready;
  logic fpu_flush;

  fpnew_top #(
    .Features       ( FPU_FEATURES              ),
    .Implementation ( FPU_IMPLEMENTATION        ),
    .TagType        ( logic [7:0]               )
  ) i_fpnew_bulk (
    .clk_i,
    .rst_ni,
    .operands_i     ( fpu_operands                        ),
    .rnd_mode_i     ( fpnew_pkg::roundmode_e'(fp_rm)      ),
    .op_i           ( fpnew_pkg::operation_e'(fp_op)      ),
    .op_mod_i       ( fp_opmod                            ),
    .src_fmt_i      ( fpnew_pkg::fp_format_e'(fp_fmt)     ),
    .dst_fmt_i      ( fpnew_pkg::fp_format_e'(fp_fmt)     ),
    .int_fmt_i      ( fpnew_pkg::int_format_e'(fp_fmt)    ),
    .vectorial_op_i ( fp_vect_op                          ),
    .tag_i          ( operand_m                           ),
    .in_valid_i     ( fpu_in_valid                        ),
    .in_ready_o     ( fpu_in_ready                        ),
    .flush_i        ( fpu_flush                           ),
    .result_o       ( fpu_result                          ),
    .status_o       ( /* unused */                        ),
    .tag_o          ( fpu_operand_m                       ),
    .out_valid_o    ( fpu_out_valid                       ),
    .out_ready_i    ( fpu_out_ready                       ),
    .busy_o         ( /* unused */                        )
  );

  /****************
   *  MULTIPLIER  *
   ****************/

  logic [63:0] mul_result;
  logic [7:0]  mul_operand_m;

  logic mul_in_valid;
  logic mul_out_valid;
  logic mul_in_ready;
  logic mul_out_ready;

  simd_mul #(
    .NumPipeRegs(LAT_MULTIPLIER)
  ) i_simd_mul (
    .clk_i      (clk_i                 ),
    .rst_ni     (rst_ni                ),
    .op_i       (op_i                  ),
    .width_i    (width_i               ),
    .repr_i     (repr_i                ),
    .operand_a_i(mfpu_operand_i[1].word),
    .operand_b_i(mfpu_operand_i[2].word),
    .operand_c_i(mfpu_operand_i[3].word),
    .operand_m_i(operand_m             ),
    .result_o   (mul_result            ),
    .operand_m_o(mul_operand_m         ),
    .valid_i    (mul_in_valid          ),
    .ready_o    (mul_in_ready          ),
    .ready_i    (mul_out_ready         ),
    .valid_o    (mul_out_valid         )
  );

  /*********
   *  MUX  *
   *********/

  logic using_fpu_in ;
  logic using_fpu_out;
  assign using_fpu_in  = (opqueue_q.insn[opqueue_q.issue_pnt].vd.repr == riscv::RP_FPOINT) || is_comparison(opqueue_q.insn[opqueue_q.issue_pnt].op)  ;
  assign using_fpu_out = (opqueue_q.insn[opqueue_q.commit_pnt].vd.repr == riscv::RP_FPOINT) || is_comparison(opqueue_q.insn[opqueue_q.commit_pnt].op);

  logic [63:0] result_int ;
  logic [ 7:0] operand_m_int;

  logic mfpu_in_valid ;
  logic mfpu_out_valid;
  logic mfpu_in_ready ;
  logic mfpu_out_ready;

  assign mul_in_valid  = ~using_fpu_in & mfpu_in_valid;
  assign fpu_in_valid  = using_fpu_in & mfpu_in_valid ;
  assign mfpu_in_ready = using_fpu_in ? fpu_in_ready : mul_in_ready;

  assign result_int    = using_fpu_out ? fpu_result    : mul_result   ;
  assign operand_m_int = using_fpu_out ? fpu_operand_m : mul_operand_m;

  assign mul_out_ready  = ~using_fpu_out & mfpu_out_ready;
  assign fpu_out_ready  = using_fpu_out & mfpu_out_ready ;
  assign mfpu_out_valid = using_fpu_out ? fpu_out_valid : mul_out_valid;

  logic [63:0] result;

  always_comb begin
    // Mask
    for (int b = 0; b < 8; b++)
      result[8*b +: 8] = result_int[8*b +: 8] & {8{operand_m_int[b]}};
  end

  /*************
   *  CONTROL  *
   *************/

  always_comb begin: control
    automatic logic operand_valid = 1'b0;

    // Maintain state
    opqueue_d = opqueue_q;
    obuf_d    = obuf_q   ;

    issue_cnt_d  = issue_cnt_q ;
    commit_cnt_d = commit_cnt_q;

    // We are not acknowledging any operands
    mfpu_operand_ready_o = 1'b0;
    mfpu_in_valid        = '0  ;

    // Initialize fu commands
    fp_op      = '0  ;
    fp_opmod   = '0  ;
    fp_fmt     = '0  ;
    fp_rm      = '0  ;
    fp_sign    = '0  ;
    fp_vect_op = 1'b1;
    fpu_flush  = 1'b0;

    // Ready to accept outputs
    mfpu_out_ready = '1;

    // Inform controller of our status
    vfu_status_o.ready     = !opqueue_full;
    vfu_status_o.loop_done = '0           ;

    // No result
    mfpu_result_o = '0;

    if (issue_valid)
      // Valid input operands?
      if (op_i inside {VSQRT, VCLASS}) begin
        // Operations that use one operand
        operand_valid = (mfpu_operand_i[0].valid || operation_issue_q.mask == riscv::NOMASK) && mfpu_operand_i[1].valid;
      end else if (op_i inside {VMADD, VMSUB, VNMADD, VNMSUB}) begin
        // Operations that use three operands
        operand_valid = (mfpu_operand_i[0].valid || operation_issue_q.mask == riscv::NOMASK) && mfpu_operand_i[1].valid && mfpu_operand_i[2].valid && mfpu_operand_i[3].valid;
      end else begin
        operand_valid = (mfpu_operand_i[0].valid || operation_issue_q.mask == riscv::NOMASK) && mfpu_operand_i[1].valid && mfpu_operand_i[2].valid;
      end

    // Decode operation

    // Choose correct width
    case (width_i)
      riscv::WD_V64B: fp_fmt = fpnew_pkg::FP64;
      riscv::WD_V32B: fp_fmt = fpnew_pkg::FP32;
      riscv::WD_V16B: fp_fmt = fpnew_pkg::FP16;
    endcase

    // Decode operator
    case (op_i)
      VMACC, VMADD, VMSUB: begin
        fp_op      = fpnew_pkg::FMADD       ;
        fp_sign[2] = (op_i == VMSUB);
      end
      VNMADD, VNMSUB: begin
        fp_op      = fpnew_pkg::FNMSUB       ;
        fp_sign[2] = (op_i == VNMADD);
      end
      VADD, VSUB: begin
        fp_op      = fpnew_pkg::ADD        ;
        fp_sign[1] = (op_i == VSUB);
      end
      VEQ, VNE, VGE, VLT: begin
        fp_op    = fpnew_pkg::CMP                        ;
        fp_opmod = (op_i == VNE) || (op_i == VGE);

        case (op_i)
          VEQ, VNE: fp_rm = 3'b010;
          VLT, VGE: fp_rm = 3'b001;
        endcase // case (op_i)
      end       // case: VEQ, VNE, VGE, VLT
      VMIN  : {fp_op, fp_rm} = {fpnew_pkg::MINMAX, 3'b000};
      VMAX  : {fp_op, fp_rm} = {fpnew_pkg::MINMAX, 3'b001};
      VMUL  : fp_op          = fpnew_pkg::MUL             ;
      VDIV  : fp_op          = fpnew_pkg::DIV             ;
      VSQRT : fp_op          = fpnew_pkg::SQRT            ;
      VCLASS: fp_op          = fpnew_pkg::CLASSIFY        ;
      VSGNJ : {fp_op, fp_rm} = {fpnew_pkg::SGNJ, 3'b000}  ;
      VSGNJN: {fp_op, fp_rm} = {fpnew_pkg::SGNJ, 3'b001}  ;
      VSGNJX: {fp_op, fp_rm} = {fpnew_pkg::SGNJ, 3'b010}  ;
    endcase

    // Input interface

    if (operand_valid)
      // Activate FPUs
      mfpu_in_valid = '1;

    // The FPU acked the operation
    if (mfpu_in_valid & mfpu_in_ready) begin
      // Acknowledge operands with VCONV
      mfpu_operand_ready_o = 1'b1;

      // Bump issue pointer
      issue_cnt_d -= 8;
    end

    if (!obuf_full) begin
      // We got a valid result
      if (mfpu_out_valid) begin
        // Store intermediate results
        obuf_d.result[obuf_q.write_pnt] = result;
        obuf_d.cnt += 1'b1;
        obuf_d.write_pnt = obuf_q.write_pnt + 1'b1;
        if (obuf_q.write_pnt == OBUF_DEPTH - 1)
          obuf_d.write_pnt = 0;
      end
    end else
      mfpu_out_ready = '0;

    // Output interface
    if (!obuf_empty) begin
      mfpu_result_o.req   = 1'b1                          ;
      mfpu_result_o.prio  = 1'b1                          ;
      mfpu_result_o.we    = 1'b1                          ;
      mfpu_result_o.addr  = operation_commit_q.addr       ;
      mfpu_result_o.id    = operation_commit_q.id         ;
      mfpu_result_o.wdata = obuf_q.result[obuf_q.read_pnt];

      if (mfpu_result_gnt_i) begin
        opqueue_d.insn[opqueue_q.commit_pnt].addr = increment_addr(operation_commit_q.addr, operation_commit_q.vid);
        commit_cnt_d -= 8;
        obuf_d.result[obuf_q.read_pnt] = '0;

        obuf_d.cnt -= 1'b1;
        obuf_d.read_pnt = obuf_q.read_pnt + 1'b1;
        if (obuf_q.read_pnt == OBUF_DEPTH - 1)
          obuf_d.read_pnt = 0;
      end
    end

    // Finished issuing micro-operations
    if (issue_valid && $signed(issue_cnt_d) <= 0) begin
      opqueue_d.issue_cnt -= 1;
      opqueue_d.issue_pnt += 1;

      if (opqueue_d.issue_cnt != 0)
        issue_cnt_d = opqueue_q.insn[opqueue_d.issue_pnt].length;
    end

    // Finished committing results
    if (commit_valid && $signed(commit_cnt_d) <= 0) begin
      vfu_status_o.loop_done[operation_commit_q.id] = 1'b1;

      opqueue_d.commit_cnt -= 1;
      opqueue_d.commit_pnt += 1;

      if (opqueue_d.commit_cnt != 0)
        commit_cnt_d = opqueue_q.insn[opqueue_d.commit_pnt].length;
    end

    // Accept new instruction
    if (!opqueue_full && operation_i.valid && operation_i.fu == VFU_MFPU) begin
      opqueue_d.insn[opqueue_q.accept_pnt] = operation_i;

      // Initialize issue and commit counters
      if (opqueue_d.issue_cnt == 0)
        issue_cnt_d = operation_i.length;
      if (opqueue_d.commit_cnt == 0)
        commit_cnt_d = operation_i.length;

      // Bump pointers
      opqueue_d.accept_pnt += 1;
      opqueue_d.issue_cnt += 1 ;
      opqueue_d.commit_cnt += 1;
    end
  end : control

  /***************
   *  REGISTERS  *
   ***************/

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      opqueue_q <= '0;
      obuf_q    <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      opqueue_q <= opqueue_d;
      obuf_q    <= obuf_d   ;

      issue_cnt_q  <= issue_cnt_d ;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : vmfpu
