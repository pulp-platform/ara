// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//          Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's integer multiplier and floating-point unit.

module vmfpu import ara_pkg::*; import rvv_pkg::*; import fpnew_pkg::*; #(
    parameter int  unsigned NrLanes   = 0,
    // Type used to address vector register file elements
    parameter type          vaddr_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter int  unsigned StrbWidth = DataWidth/8,
    parameter type          strb_t    = logic [DataWidth/8-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Interface with CVA6
    output logic           [4:0]         fflags_ex_o,
    output logic                         fflags_ex_valid_o,
    // Interface with the lane sequencer
    input  vfu_operation_t               vfu_operation_i,
    input  logic                         vfu_operation_valid_i,
    output logic                         mfpu_ready_o,
    output logic           [NrVInsn-1:0] mfpu_vinsn_done_o,
    // Interface with the operand queues
    input  elen_t          [2:0]         mfpu_operand_i,
    input  logic           [2:0]         mfpu_operand_valid_i,
    output logic           [2:0]         mfpu_operand_ready_o,
    // Interface with the vector register file
    output logic                         mfpu_result_req_o,
    output vid_t                         mfpu_result_id_o,
    output vaddr_t                       mfpu_result_addr_o,
    output elen_t                        mfpu_result_wdata_o,
    output strb_t                        mfpu_result_be_o,
    input  logic                         mfpu_result_gnt_i,
    // Interface with the Mask unit
    input  strb_t                        mask_i,
    input  logic                         mask_valid_i,
    output logic                         mask_ready_o
  );

  import cf_math_pkg::idx_width;

  /******************************
   *  Vector instruction queue  *
   ******************************/

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = 4;

  struct packed {
    vfu_operation_t [VInsnQueueDepth-1:0] vinsn;

    // Each instruction can be in one of the three execution phases.
    // - Being accepted (i.e., it is being stored for future execution in this
    //   vector functional unit).
    // - Being processed (i.e., its micro-operations are currently being processed
    //   by the corresponding functional units).
    // - Being issued (i.e., its micro-operations are currently being issued
    //   to the corresponding functional units).
    // - Being committed (i.e., its results are being written to the vector
    //   register file).
    // We need pointers to index which instruction is at each execution phase
    // between the VInsnQueueDepth instructions in memory.
    logic [idx_width(VInsnQueueDepth)-1:0] accept_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] processing_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] issue_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] commit_pnt;

    // We also need to count how many instructions are queueing to be
    // issued/committed, to avoid accepting more instructions than
    // we can handle.
    logic [idx_width(VInsnQueueDepth):0] issue_cnt;
    logic [idx_width(VInsnQueueDepth):0] processing_cnt;
    logic [idx_width(VInsnQueueDepth):0] commit_cnt;
  } vinsn_queue_d, vinsn_queue_q;

  // Is the vector instruction queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  vfu_operation_t vinsn_issue_d, vinsn_issue_q;
  logic           vinsn_issue_valid;
  assign vinsn_issue_d     = vinsn_queue_d.vinsn[vinsn_queue_d.issue_pnt];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

  // Do we have a vector instruction being processed?
  vfu_operation_t vinsn_processing;
  assign vinsn_processing = vinsn_queue_q.vinsn[vinsn_queue_q.processing_pnt];

  // Do we have a vector instruction with results being committed?
  vfu_operation_t vinsn_commit;
  logic           vinsn_commit_valid;
  assign vinsn_commit       = vinsn_queue_q.vinsn[vinsn_queue_q.commit_pnt];
  assign vinsn_commit_valid = (vinsn_queue_q.commit_cnt != '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_queue_q <= '0;
      vinsn_issue_q <= '0;
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
      vinsn_issue_q <= vinsn_issue_d;
    end
  end

  /******************
   *  Result queue  *
   ******************/

  localparam int unsigned ResultQueueDepth = 2;

  // There is a result queue per VFU, holding the results that were not
  // yet accepted by the corresponding lane.
  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } payload_t;

  // Result queue
  payload_t [ResultQueueDepth-1:0]            result_queue_d, result_queue_q;
  logic     [ResultQueueDepth-1:0]            result_queue_valid_d, result_queue_valid_q;
  // We need two pointers in the result queue. One pointer to
  // indicate with `payload_t` we are currently writing into (write_pnt),
  // and one pointer to indicate which `payload_t` we are currently
  // reading from and writing into the lanes (read_pnt).
  logic     [idx_width(ResultQueueDepth)-1:0] result_queue_write_pnt_d, result_queue_write_pnt_q;
  logic     [idx_width(ResultQueueDepth)-1:0] result_queue_read_pnt_d, result_queue_read_pnt_q;
  // We need to count how many valid elements are there in this result queue.
  logic     [idx_width(ResultQueueDepth):0]   result_queue_cnt_d, result_queue_cnt_q;

  // Is the result queue full?
  logic result_queue_full;
  assign result_queue_full = (result_queue_cnt_q == ResultQueueDepth);

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_result_queue_ff
    if (!rst_ni) begin
      result_queue_q           <= '0;
      result_queue_valid_q     <= '0;
      result_queue_write_pnt_q <= '0;
      result_queue_read_pnt_q  <= '0;
      result_queue_cnt_q       <= '0;
    end else begin
      result_queue_q           <= result_queue_d;
      result_queue_valid_q     <= result_queue_valid_d;
      result_queue_write_pnt_q <= result_queue_write_pnt_d;
      result_queue_read_pnt_q  <= result_queue_read_pnt_d;
      result_queue_cnt_q       <= result_queue_cnt_d;
    end
  end

  /********************
   *  Helper signals  *
   ********************/

  logic vinsn_issue_mul, vinsn_issue_div, vinsn_issue_fpu;

  assign vinsn_issue_mul = vinsn_issue_q.op inside {[VMUL:VNMSUB]};
  assign vinsn_issue_div = vinsn_issue_q.op inside {[VDIVU:VREM]};
  assign vinsn_issue_fpu = vinsn_issue_q.op inside {[VFADD:VFMAX]};

  /********************
   *  Scalar operand  *
   ********************/

  elen_t scalar_op;

  // Replicate the scalar operand on the 64-bit word, depending
  // on the element width.
  // Also check if the FP scalar is NaN boxed, otherwise return a qNaN
  always_comb begin
    // Default assignment
    scalar_op = '0;

    case (vinsn_issue_q.vtype.vsew)
      EW64: scalar_op = {1{vinsn_issue_q.scalar_op[63:0]}};
      EW32: scalar_op = {2{vinsn_issue_q.scalar_op[31:0]}};
      EW16: scalar_op = {4{vinsn_issue_q.scalar_op[15:0]}};
      EW8 : scalar_op = {8{vinsn_issue_q.scalar_op[ 7:0]}};
      default:;
    endcase
  end

  /****************
   *  Multiplier  *
   ****************/

  elen_t [3:0] vmul_simd_result;
  logic  [3:0] vmul_simd_in_valid;
  logic  [3:0] vmul_simd_in_ready;
  logic  [3:0] vmul_simd_out_valid;
  logic  [3:0] vmul_simd_out_ready;
  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the operand queues
  // Another choice would be to delay the mask grant when the vmul_result is committed
  strb_t [3:0] vmul_simd_mask;

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW64),
    .ElementWidth(EW64             )
  ) i_simd_mul_ew64 (
    .clk_i      (clk_i                                                      ),
    .rst_ni     (rst_ni                                                     ),
    .operand_a_i(vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                          ),
    .operand_c_i(mfpu_operand_i[2]                                          ),
    .mask_i     (mask_i                                                     ),
    .op_i       (vinsn_issue_q.op                                           ),
    .result_o   (vmul_simd_result[EW64]                                     ),
    .mask_o     (vmul_simd_mask[EW64]                                       ),
    .valid_i    (vmul_simd_in_valid[EW64]                                   ),
    .ready_o    (vmul_simd_in_ready[EW64]                                   ),
    .ready_i    (vmul_simd_out_ready[EW64]                                  ),
    .valid_o    (vmul_simd_out_valid[EW64]                                  )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW32),
    .ElementWidth(EW32             )
  ) i_simd_mul_ew32 (
    .clk_i      (clk_i                                                      ),
    .rst_ni     (rst_ni                                                     ),
    .operand_a_i(vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                          ),
    .operand_c_i(mfpu_operand_i[2]                                          ),
    .mask_i     (mask_i                                                     ),
    .op_i       (vinsn_issue_q.op                                           ),
    .result_o   (vmul_simd_result[EW32]                                     ),
    .mask_o     (vmul_simd_mask[EW32]                                       ),
    .valid_i    (vmul_simd_in_valid[EW32]                                   ),
    .ready_o    (vmul_simd_in_ready[EW32]                                   ),
    .ready_i    (vmul_simd_out_ready[EW32]                                  ),
    .valid_o    (vmul_simd_out_valid[EW32]                                  )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW16),
    .ElementWidth(EW16             )
  ) i_simd_mul_ew16 (
    .clk_i      (clk_i                                                      ),
    .rst_ni     (rst_ni                                                     ),
    .operand_a_i(vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                          ),
    .operand_c_i(mfpu_operand_i[2]                                          ),
    .mask_i     (mask_i                                                     ),
    .op_i       (vinsn_issue_q.op                                           ),
    .result_o   (vmul_simd_result[EW16]                                     ),
    .mask_o     (vmul_simd_mask[EW16]                                       ),
    .valid_i    (vmul_simd_in_valid[EW16]                                   ),
    .ready_o    (vmul_simd_in_ready[EW16]                                   ),
    .ready_i    (vmul_simd_out_ready[EW16]                                  ),
    .valid_o    (vmul_simd_out_valid[EW16]                                  )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW8),
    .ElementWidth(EW8             )
  ) i_simd_mul_ew8 (
    .clk_i      (clk_i                                                      ),
    .rst_ni     (rst_ni                                                     ),
    .operand_a_i(vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                          ),
    .operand_c_i(mfpu_operand_i[2]                                          ),
    .mask_i     (mask_i                                                     ),
    .op_i       (vinsn_issue_q.op                                           ),
    .result_o   (vmul_simd_result[EW8]                                      ),
    .mask_o     (vmul_simd_mask[EW8]                                        ),
    .valid_i    (vmul_simd_in_valid[EW8]                                    ),
    .ready_o    (vmul_simd_in_ready[EW8]                                    ),
    .ready_i    (vmul_simd_out_ready[EW8]                                   ),
    .valid_o    (vmul_simd_out_valid[EW8]                                   )
  );

  // The outputs of the SIMD multipliers are read in order
  elen_t vmul_result;
  logic  vmul_in_valid;
  logic  vmul_in_ready;
  logic  vmul_out_valid;
  logic  vmul_out_ready;
  strb_t vmul_mask;

  always_comb begin
    // Only one SIMD Multiplier receives the request
    vmul_simd_in_valid                           = '0;
    vmul_simd_in_valid[vinsn_issue_q.vtype.vsew] = vmul_in_valid;
    vmul_in_ready                                = vmul_simd_in_ready[vinsn_issue_q.vtype.vsew];

    // We read the responses of a single SIMD Multiplier
    vmul_result                                      = vmul_simd_result[vinsn_processing.vtype.vsew];
    vmul_mask                                        = vmul_simd_mask[vinsn_processing.vtype.vsew];
    vmul_out_valid                                   = vmul_simd_out_valid[vinsn_processing.vtype.vsew];
    vmul_simd_out_ready                              = '0;
    vmul_simd_out_ready[vinsn_processing.vtype.vsew] = vmul_out_ready;
  end

  /*************
   *  Divider  *
   ************/

  elen_t vdiv_result;
  // Short circuit to invalid input elements with a mask
  strb_t issue_be;

  logic vdiv_in_valid;
  logic vdiv_out_valid;
  logic vdiv_in_ready;
  logic vdiv_out_ready;

  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the operand queues
  // Another choice would be to delay the mask grant when the vdiv_result is committed
  strb_t vdiv_mask;

  simd_div i_simd_div (
    .clk_i      (clk_i                                                      ),
    .rst_ni     (rst_ni                                                     ),
    .operand_a_i(mfpu_operand_i[1]                                          ),
    .operand_b_i(vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .mask_i     (mask_i                                                     ),
    .op_i       (vinsn_issue_q.op                                           ),
    .be_i       (issue_be                                                   ),
    .vew_i      (vinsn_issue_q.vtype.vsew                                   ),
    .result_o   (vdiv_result                                                ),
    .mask_o     (vdiv_mask                                                  ),
    .valid_i    (vdiv_in_valid                                              ),
    .ready_o    (vdiv_in_ready                                              ),
    .ready_i    (vdiv_out_ready                                             ),
    .valid_o    (vdiv_out_valid                                             )
  );

  /*********
   *  FPU  *
   ********/

  // Features (enabled formats, vectors etc.)
  localparam fpu_features_t FPUFeatures = '{
    Width        : 64,
    EnableVectors: 1'b1,
    EnableNanBox : 1'b1,
    FpFmtMask    : {1'b1, 1'b1, 1'b1, 1'b0, 1'b0},
    IntFmtMask   : {1'b0, 1'b0, 1'b0, 1'b0}
  };

  // Implementation (number of registers etc)
  localparam fpu_implementation_t FPUImplementation = '{
    PipeRegs: '{
      '{LatFCompEW32, LatFCompEW64, LatFCompEW16, LatFCompEW8, LatFCompEW16Alt},
      '{default: LatFDivSqrt},
      '{default: LatFNonComp},
      '{default: LatFConv}},
    UnitTypes: '{
      '{default: PARALLEL}, // ADDMUL
      '{default: MERGED},   // DIVSQRT
      '{default: PARALLEL}, // NONCOMP
      '{default: MERGED}},  // CONV
    PipeConfig: DISTRIBUTED
  };

  // FPU preprocessed signals
  elen_t operand_a;
  elen_t operand_b;
  elen_t operand_c;

  operation_e       fp_op;
  logic             fp_opmod;
  fp_format_e       fp_fmt;
  roundmode_e       fp_rm;
  logic       [2:0] fp_sign;

  // FPU preprocessing stage
  always_comb begin: fpu_operand_preprocessing_p
    operand_a = mfpu_operand_i[1];                                           // vs2
    operand_b = vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]; // vs1, rs1
    operand_c = mfpu_operand_i[2];                                           // vd, or vs2 if we are performing a VFADD/VFSUB/VFRSUB
    // Default rounding-mode from fcsr.rm
    fp_rm     = vinsn_issue_q.fp_rm;
    fp_op     = ADD;
    fp_opmod  = 1'b0;
    fp_fmt    = FP64;
    fp_sign   = 3'b0;

    unique case (vinsn_issue_q.op)
      // Addition is between operands B and C, A was moved to C in the lane_sequencer
      VFADD:
        fp_op = ADD;
      VFSUB: begin
        fp_op      = ADD;
        fp_sign[1] = 1'b1;
      end
      VFRSUB: begin
        fp_op    = ADD;
        fp_opmod = 1'b1;
      end
      VFMUL :
        fp_op = MUL;
      VFMACC, VFMADD, VFMSAC, VFMSUB: begin
        fp_op      = FMADD;
        fp_sign[2] = (vinsn_issue_q.op == VFMSAC) | (vinsn_issue_q.op == VFMSUB);
      end
      VFNMACC, VFNMSAC, VFNMADD, VFNMSUB: begin
        fp_op      = FNMSUB;
        fp_sign[2] = (vinsn_issue_q.op == VFNMACC) | (vinsn_issue_q.op == VFNMADD);
      end
      VFMIN : begin
        fp_op = MINMAX;
        fp_rm = RNE;
      end
      VFMAX: begin
        fp_op = MINMAX;
        fp_rm = RTZ;
      end
      default:;
    endcase

    unique case (vinsn_issue_q.vtype.vsew)
      EW64: fp_fmt = FP64;
      EW32: fp_fmt = FP32;
      EW16: fp_fmt = FP16;
      default:;
    endcase

    // Sign injection
    unique case (vinsn_issue_q.vtype.vsew)
      EW16:
        for (int b = 0; b < 4; b++) begin
          operand_a[16*b+15] = operand_a[16*b+15] ^ fp_sign[0];
          operand_b[16*b+15] = operand_b[16*b+15] ^ fp_sign[1];
          operand_c[16*b+15] = operand_c[16*b+15] ^ fp_sign[2];
        end
      EW32:
        for (int b = 0; b < 2; b++) begin
          operand_a[32*b+31] = operand_a[32*b+31] ^ fp_sign[0];
          operand_b[32*b+31] = operand_b[32*b+31] ^ fp_sign[1];
          operand_c[32*b+31] = operand_c[32*b+31] ^ fp_sign[2];
        end
      EW64:
        for (int b = 0; b < 1; b++) begin
          operand_a[64*b+63] = operand_a[64*b+63] ^ fp_sign[0];
          operand_b[64*b+63] = operand_b[64*b+63] ^ fp_sign[1];
          operand_c[64*b+63] = operand_c[64*b+63] ^ fp_sign[2];
        end
      default:;
    endcase
  end : fpu_operand_preprocessing_p

  // FPU signals
  elen_t [2:0] vfpu_operands;
  assign vfpu_operands[0] = operand_a;
  assign vfpu_operands[1] = operand_b;
  assign vfpu_operands[2] = operand_c;

  elen_t   vfpu_result;
  status_t vfpu_ex_flag;
  strb_t   vfpu_mask;

  // Do not raise exceptions on inactive elements
  localparam FPULanes = max_num_lanes(FPUFeatures.Width, FPUFeatures.FpFmtMask, FPUFeatures.EnableVectors);
  typedef logic [FPULanes-1:0] fpu_mask_t;

  fpu_mask_t vfpu_simd_mask;
  for (genvar b = 0; b < FPULanes; b++) begin: gen_vfpu_simd_mask
    assign vfpu_simd_mask[b] = issue_be[2*b];
  end: gen_vfpu_simd_mask

  logic vfpu_in_valid;
  logic vfpu_out_valid;
  logic vfpu_in_ready;
  logic vfpu_out_ready;

  fpnew_top #(
    .Features      (FPUFeatures      ),
    .Implementation(FPUImplementation),
    .TagType       (strb_t           ),
    .NumLanes      (FPULanes         ),
    .MaskType      (fpu_mask_t       )
  ) i_fpnew_bulk (
    .clk_i         (clk_i         ),
    .rst_ni        (rst_ni        ),
    .flush_i       (1'b0          ),
    .rnd_mode_i    (fp_rm         ),
    .op_i          (fp_op         ),
    .op_mod_i      (fp_opmod      ),
    .vectorial_op_i(1'b1          ),
    .operands_i    (vfpu_operands ),
    .tag_i         (mask_i        ),
    .simd_mask_i   (vfpu_simd_mask),
    .src_fmt_i     (fp_fmt        ),
    .dst_fmt_i     (fp_fmt        ),
    .int_fmt_i     (INT8          ),
    .in_valid_i    (vfpu_in_valid ),
    .in_ready_o    (vfpu_in_ready ),
    .result_o      (vfpu_result   ),
    .status_o      (vfpu_ex_flag  ),
    .tag_o         (vfpu_mask     ),
    .out_valid_o   (vfpu_out_valid),
    .out_ready_i   (vfpu_out_ready),
    .busy_o        (/* Unused */  )
  );

  // Stabilize signals regardless of FPU latency (signals to CVA6)
  logic       fflags_ex_valid_d, fflags_ex_valid_q;
  logic [4:0] fflags_ex_d, fflags_ex_q;

  assign fflags_ex_d       = vfpu_ex_flag;
  assign fflags_ex_valid_d = vfpu_out_valid & vfpu_out_ready;

  assign fflags_ex_o       = fflags_ex_q;
  assign fflags_ex_valid_o = fflags_ex_valid_q;

  /*************
   *  Control  *
   *************/

  // Helper signal to handshake with the correct operand queues
  logic       operands_valid;
  logic [2:0] operands_ready;

  // Remaining elements of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining elements of the current instruction in the processing phase
  vlen_t to_process_cnt_d, to_process_cnt_q;
  // Remaining elements of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  // Valid, result, and mask of the unit in use
  logic  unit_out_valid;
  elen_t unit_out_result;
  strb_t unit_out_mask;

  // If vs2 and vd were swapped, re-route the handshake signals to/from the operand queues
  assign operands_valid = vinsn_issue_q.swap_vs2_vd_op
                        ? ((mfpu_operand_valid_i[2] || !vinsn_issue_q.use_vs2) && (mfpu_operand_valid_i[1] || !vinsn_issue_q.use_vd_op) && (mask_valid_i || vinsn_issue_q.vm) && (mfpu_operand_valid_i[0] || !vinsn_issue_q.use_vs1))
                        : ((mfpu_operand_valid_i[2] || !vinsn_issue_q.use_vd_op) && (mfpu_operand_valid_i[1] || !vinsn_issue_q.use_vs2) && (mask_valid_i || vinsn_issue_q.vm) && (mfpu_operand_valid_i[0] || !vinsn_issue_q.use_vs1));

  assign operands_ready = vinsn_issue_q.swap_vs2_vd_op
                        ? {vinsn_issue_q.use_vs2, vinsn_issue_q.use_vd_op, vinsn_issue_q.use_vs1}
                        : {vinsn_issue_q.use_vd_op, vinsn_issue_q.use_vs2, vinsn_issue_q.use_vs1};

  always_comb begin: p_vmfpu
    // Maintain state
    vinsn_queue_d    = vinsn_queue_q;
    issue_cnt_d      = issue_cnt_q;
    to_process_cnt_d = to_process_cnt_q;
    commit_cnt_d     = commit_cnt_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    // Inform our status to the lane controller
    mfpu_ready_o      = !vinsn_queue_full;
    mfpu_vinsn_done_o = '0;

    // Do not acknowledge any operands
    mfpu_operand_ready_o = '0;

    // Inputs to the units are not valid by default
    vmul_in_valid = 1'b0;
    vdiv_in_valid = 1'b0;
    vfpu_in_valid = 1'b0;

    // Valid of the unit in use (i.e., result queue input valid) is not asserted by default
    unit_out_valid  = 1'b0;
    unit_out_result = vmul_result;
    unit_out_mask   = vmul_mask;

    // Mask not granted by default
    mask_ready_o = 1'b0;

    // Short-circuit invalid elements divisions with a mask
    issue_be = '0;

    /***************************************
     *  Issue the instruction to the unit  *
     **************************************/

    // There is a vector instruction ready to be issued
    if (vinsn_issue_valid) begin
      // Do we have all the operands necessary for this instruction?
      if (operands_valid) begin
        // Validate the inputs of the correct unit
        vmul_in_valid = vinsn_issue_mul;
        vdiv_in_valid = vinsn_issue_div;
        vfpu_in_valid = vinsn_issue_fpu;

        // Is the unit in use ready?
        if ((vinsn_issue_mul && vmul_in_ready) || (vinsn_issue_div && vdiv_in_ready) || (vinsn_issue_fpu && vfpu_in_ready)) begin
          // Acknowledge the operands of this instruction
          mfpu_operand_ready_o = operands_ready;
          // Acknowledge the mask unit
          mask_ready_o         = ~vinsn_issue_q.vm;

          begin
            // How many elements are we issuing?
            automatic logic [3:0] issue_element_cnt = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
            // Update the number of elements still to be issued
            if (issue_element_cnt > issue_cnt_q)
              issue_element_cnt = issue_cnt_q;
            issue_cnt_d = issue_cnt_q - issue_element_cnt;

            // Give the divider the correct be signal
            issue_be = be(issue_element_cnt, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm ? {StrbWidth{1'b1}} : mask_i);
          end
          // Finished issuing the micro-operations of this vector instruction
          if (issue_cnt_d == '0) begin
            // Bump issue counter and pointers
            vinsn_queue_d.issue_cnt -= 1;
            if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1)
              vinsn_queue_d.issue_pnt = '0;
            else
              vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

            if (vinsn_queue_d.issue_cnt != 0)
              issue_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
          end
        end
      end
    end

    /**************************************
     *  Write data into the result queue  *
     **************************************/

    // If the result queue is not full, it is ready to accept a result
    vmul_out_ready = ~result_queue_full;
    vdiv_out_ready = ~result_queue_full;
    vfpu_out_ready = ~result_queue_full;

    // Select the correct valid, result, and mask, to write in the result queue
    case (vinsn_processing.op) inside
      [VMUL:VNMSUB]: begin
        unit_out_valid  = vmul_out_valid;
        unit_out_result = vmul_result;
        unit_out_mask   = vmul_mask;
      end
      [VDIVU:VREM]: begin
        unit_out_valid  = vdiv_out_valid;
        unit_out_result = vdiv_result;
        unit_out_mask   = vdiv_mask;
      end
      [VFADD:VFMAX]: begin
        unit_out_valid  = vfpu_out_valid;
        unit_out_result = vfpu_result;
        unit_out_mask   = vfpu_mask;
      end
    endcase

    // Check if we have a valid result and we can add it to the result queue
    if (unit_out_valid && !result_queue_full) begin
      // How many elements have we processed?
      automatic logic [3:0] processed_element_cnt = (1 << (int'(EW64) - int'(vinsn_processing.vtype.vsew)));

      // Update the number of elements still to be processed
      if (processed_element_cnt > to_process_cnt_q)
        processed_element_cnt = to_process_cnt_q;

      // Store the result in the result queue
      result_queue_d[result_queue_write_pnt_q].id    = vinsn_processing.id;
      result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_processing.vd, NrLanes) + ((vinsn_processing.vl - to_process_cnt_q) >> (int'(EW64) - vinsn_processing.vtype.vsew));
      result_queue_d[result_queue_write_pnt_q].wdata = unit_out_result;
      result_queue_d[result_queue_write_pnt_q].be    = be(processed_element_cnt, vinsn_processing.vtype.vsew) & (vinsn_processing.vm ? {StrbWidth{1'b1}} : unit_out_mask);
      result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

      // Update the number of elements still to be processed
      to_process_cnt_d = to_process_cnt_q - processed_element_cnt;

      // Finished issuing the micro-operations of this vector instruction
      if (to_process_cnt_d == '0) begin
        vinsn_queue_d.processing_cnt -= 1;
        // Bump issue processing pointers
        if (vinsn_queue_q.processing_pnt == VInsnQueueDepth-1)
          vinsn_queue_d.processing_pnt = '0;
        else
          vinsn_queue_d.processing_pnt = vinsn_queue_q.processing_pnt + 1;

        if (vinsn_queue_d.processing_cnt != 0)
          to_process_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.processing_pnt].vl;
      end

      // Bump pointers and counters of the result queue
      result_queue_cnt_d += 1;
      if (result_queue_write_pnt_q == ResultQueueDepth-1)
        result_queue_write_pnt_d = 0;
      else
        result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
    end

    /********************************
     *  Write results into the VRF  *
     ********************************/

    // Send result information to the VRF
    mfpu_result_req_o   = result_queue_valid_q[result_queue_read_pnt_q];
    mfpu_result_addr_o  = result_queue_q[result_queue_read_pnt_q].addr;
    mfpu_result_id_o    = result_queue_q[result_queue_read_pnt_q].id;
    mfpu_result_wdata_o = result_queue_q[result_queue_read_pnt_q].wdata;
    mfpu_result_be_o    = result_queue_q[result_queue_read_pnt_q].be;

    // Received a grant from the VRF.
    // Deactivate the request.
    if (mfpu_result_gnt_i) begin
      // How many elements are we committing?
      automatic logic [3:0] commit_element_cnt = (1 << (int'(EW64) - int'(vinsn_commit.vtype.vsew)));

      result_queue_valid_d[result_queue_read_pnt_q] = 1'b0;
      result_queue_d[result_queue_read_pnt_q]       = '0;

      // Increment the read pointer
      if (result_queue_read_pnt_q == ResultQueueDepth-1)
        result_queue_read_pnt_d = 0;
      else
        result_queue_read_pnt_d = result_queue_read_pnt_q + 1;

      // Decrement the counter of results waiting to be written
      result_queue_cnt_d -= 1;

      // Decrement the counter of remaining vector elements waiting to be written
      commit_cnt_d = commit_cnt_q - commit_element_cnt;
      if (commit_cnt_q < (1 << (int'(EW64) - vinsn_commit.vtype.vsew)))
        commit_cnt_d = '0;
    end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && commit_cnt_d == '0) begin
      // Mark the vector instruction as being done
      mfpu_vinsn_done_o[vinsn_commit.id] = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1)
        vinsn_queue_d.commit_pnt = '0;
      else
        vinsn_queue_d.commit_pnt += 1;

      // Update the commit counter for the next instruction
      if (vinsn_queue_d.commit_cnt != '0)
        commit_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl;
    end

    /****************************
     *  Accept new instruction  *
     ****************************/

    if (!vinsn_queue_full && vfu_operation_valid_i && vfu_operation_i.vfu == VFU_MFpu) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = vfu_operation_i;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d = vfu_operation_i.vl;
      if (vinsn_queue_d.processing_cnt == '0)
        to_process_cnt_d = vfu_operation_i.vl;
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = vfu_operation_i.vl;

      // Check for NaN boxing of scalar operands
      if (vfu_operation_i.op inside {[VFADD:VFMAX]} && vfu_operation_i.use_scalar_op)
        case (vfu_operation_i.vtype.vsew)
          EW16: if (~(&vfu_operation_i.scalar_op[63:16])) vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op = 64'h0000000000007e00;
          EW32: if (~(&vfu_operation_i.scalar_op[63:32])) vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op = 64'h000000007fc00000;
        endcase

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.processing_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_vmfpu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_cnt_q       <= '0;
      to_process_cnt_q  <= '0;
      commit_cnt_q      <= '0;
      fflags_ex_valid_q <= 1'b0;
      fflags_ex_q       <= '0;
    end else begin
      issue_cnt_q       <= issue_cnt_d;
      to_process_cnt_q  <= to_process_cnt_d;
      commit_cnt_q      <= commit_cnt_d;
      fflags_ex_valid_q <= fflags_ex_valid_d;
      fflags_ex_q       <= fflags_ex_d;
    end
  end

endmodule : vmfpu
