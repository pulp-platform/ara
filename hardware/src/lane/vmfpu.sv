// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//          Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's integer multiplier and floating-point unit.

module vmfpu import ara_pkg::*; import rvv_pkg::*; import fpnew_pkg::*;
  import cf_math_pkg::idx_width; #(
    parameter  int           unsigned NrLanes    = 0,
    // Support for floating-point data types
    parameter  fpu_support_e          FPUSupport = FPUSupportHalfSingleDouble,
    // Type used to address vector register file elements
    parameter  type                   vaddr_t    = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int           unsigned DataWidth  = $bits(elen_t),
    localparam int           unsigned StrbWidth  = DataWidth/8,
    localparam type                   strb_t     = logic [DataWidth/8-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic[idx_width(NrLanes)-1:0] lane_id_i,
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
    // Interface with the Slide Unit
    output logic                         mfpu_red_valid_o,
    input  logic                         mfpu_red_ready_i,
    input  elen_t                        sldu_operand_i,
    input  logic                         sldu_mfpu_valid_i,
    output logic                         sldu_mfpu_ready_o,
    // Interface with the Mask unit
    output elen_t                        mask_operand_o,
    output logic                         mask_operand_valid_o,
    input  logic                         mask_operand_ready_i,
    input  strb_t                        mask_i,
    input  logic                         mask_valid_i,
    output logic                         mask_ready_o
  );

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = MfpuInsnQueueDepth;

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
    logic [idx_width(VInsnQueueDepth)-1:0] issue_pnt;
    logic [idx_width(VInsnQueueDepth)-1:0] processing_pnt;
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
  vfu_operation_t vinsn_processing_d, vinsn_processing_q;
  logic           vinsn_processing_valid;
  assign vinsn_processing_d     = vinsn_queue_d.vinsn[vinsn_queue_d.processing_pnt];
  assign vinsn_processing_q     = vinsn_queue_q.vinsn[vinsn_queue_q.processing_pnt];
  assign vinsn_processing_valid = (vinsn_queue_q.processing_cnt != '0);

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

  ////////////////////
  //  Result queue  //
  ////////////////////

  localparam int unsigned ResultQueueDepth = 2;

  // There is a result queue per VFU, holding the results that were not
  // yet accepted by the corresponding lane.
  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
    logic mask;
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

  //////////////////////
  //  Helper signals  //
  //////////////////////

  logic vinsn_issue_mul, vinsn_issue_div, vinsn_issue_fpu;

  assign vinsn_issue_mul = vinsn_issue_q.op inside {[VMUL:VNMSUB]};
  assign vinsn_issue_div = vinsn_issue_q.op inside {[VDIVU:VREM]};
  assign vinsn_issue_fpu = vinsn_issue_q.op inside {[VFADD:VMFGE]};

  // This function returns the latency of the FPU operation,
  // depending on the sew as well
  typedef logic [idx_width(LatFMax)-1:0] fpu_latency_t;
  function automatic fpu_latency_t fpu_latency(vew_e sew, ara_op_e op);
    case (op) inside
      VFDIV, VFRDIV, VFSQRT:  fpu_latency = LatFDivSqrt;
      [VFREDMIN:VFREDMAX]:    fpu_latency = LatFNonComp;
      [VFCVTXUF:VFCVTFF]:     fpu_latency = LatFConv;
      [VFMIN:VFSGNJX]:        fpu_latency = LatFNonComp;
      default: begin
        case (sew)
          EW64:    fpu_latency = LatFCompEW64;
          EW32:    fpu_latency = LatFCompEW32;
          default: fpu_latency = LatFCompEW16;
        endcase
      end
    endcase
  endfunction: fpu_latency

  //////////////////////
  //  Scalar operand  //
  //////////////////////

  elen_t scalar_op;

  // Replicate the scalar operand on the 64-bit word, depending
  // on the element width.
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

  /////////////////////
  //  Mask operands  //
  /////////////////////

  logic mask_operand_ready;
  logic mask_operand_gnt;

  assign mask_operand_gnt = mask_operand_ready && result_queue_q[result_queue_read_pnt_q].mask && result_queue_valid_q[result_queue_read_pnt_q];

  stream_register #(
    .T(elen_t)
  ) i_mask_operand_register (
    .clk_i     (clk_i                                                                                        ),
    .rst_ni    (rst_ni                                                                                       ),
    .clr_i     (1'b0                                                                                         ),
    .testmode_i(1'b0                                                                                         ),
    .data_o    (mask_operand_o                                                                               ),
    .valid_o   (mask_operand_valid_o                                                                         ),
    .ready_i   (mask_operand_ready_i                                                                         ),
    .data_i    (result_queue_q[result_queue_read_pnt_q].wdata                                                ),
    .valid_i   (result_queue_q[result_queue_read_pnt_q].mask && result_queue_valid_q[result_queue_read_pnt_q]),
    .ready_o   (mask_operand_ready                                                                           )
  );

  //////////////////////////////
  //  Narrowing instructions  //
  //////////////////////////////

  // This function returns 1'b1 if `op` is a narrowing instruction, i.e.,
  // it produces only EEW/2 per cycle.
  function automatic logic narrowing(resize_e resize);
    narrowing = 1'b0;
    if (resize == CVT_NARROW)
      narrowing = 1'b1;
  endfunction: narrowing

  // If this is a narrowing instruction, point to which half of the
  // output EEW word we are producing.
  // Input selector, used to acknowledge the mask operands once every two cycles
  logic narrowing_select_in_d, narrowing_select_in_q;
  // Output selector, used to control the Result MUX and validate the results
  logic narrowing_select_out_d, narrowing_select_out_q;
  // FPU SIMD result needs to be shuffled for narrowing instructions before commit
  elen_t narrowing_shuffled_result;
  // Helper signal to shuffle the narrowed result
  logic [3:0] narrowing_shuffle_be;

  //////////////////
  //  Multiplier  //
  //////////////////

  elen_t [3:0] vmul_simd_result;
  logic  [3:0] vmul_simd_in_valid;
  logic  [3:0] vmul_simd_in_ready;
  logic  [3:0] vmul_simd_out_valid;
  logic  [3:0] vmul_simd_out_ready;
  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the
  // operand queues
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
    vmul_result         = vmul_simd_result[vinsn_processing_q.vtype.vsew];
    vmul_mask           = vmul_simd_mask[vinsn_processing_q.vtype.vsew];
    vmul_out_valid      = vmul_simd_out_valid[vinsn_processing_q.vtype.vsew];
    vmul_simd_out_ready = '0;
    vmul_simd_out_ready[vinsn_processing_q.vtype.vsew] = vmul_out_ready;
  end

  ///////////////
  //  Divider  //
  ///////////////

  elen_t vdiv_result;
  // Short circuit to invalid input elements with a mask
  strb_t issue_be;

  logic vdiv_in_valid;
  logic vdiv_out_valid;
  logic vdiv_in_ready;
  logic vdiv_out_ready;

  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the
  // operand queues. Another choice would be to delay the mask grant when the vdiv_result is
  // committed.
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

  //////////////////
  //  Reductions  //
  //////////////////

  // Cut the path between the SLDU and the MFPU. This increase latency
  // but does has negligible impact on long vectors
  elen_t sldu_operand_q;
  logic  sldu_mfpu_valid_q, sldu_mfpu_ready_d;
  spill_register #(
    .T(elen_t)
  ) i_mfpu_reduction_spill_register (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .valid_i(sldu_mfpu_valid_i),
    .ready_o(sldu_mfpu_ready_o),
    .data_i (sldu_operand_i  ),
    .valid_o(sldu_mfpu_valid_q),
    .ready_i(sldu_mfpu_ready_d),
    .data_o (sldu_operand_q  )
  );

  // During an inter-lane reduction (after the intra-lane reduction), the NrLanes partial results
  // must be reduced to only one. The first reduction is done by NrLanes/2 FUs, then NrLanes/4, and
  // so on. In the end, the result is collected in Lane 0 and the last SIMD reduction is performed.
  // The following function determines how many partial results this lane must process during the
  // inter-lane reduction.
  typedef logic [idx_width(NrLanes/2):0] reduction_rx_cnt_t;
  reduction_rx_cnt_t reduction_rx_cnt_d, reduction_rx_cnt_q;
  reduction_rx_cnt_t simd_red_cnt_max_d, simd_red_cnt_max_q;

  // Reductions commit by zeroing the commit counter
  // When the workload is unbalanced, some lanes can start the operation with a zeroed commit counter
  // In this case, the ALU should NOT commit until the inter-lanes phase is over
  logic prevent_commit;

  // Count how many transactions we must do in total to complete the reduction operation
  logic [idx_width($clog2(NrLanes)+1):0] sldu_transactions_cnt_d, sldu_transactions_cnt_q;

  // Handshake synchronizer
  // Since the SLDU must receive a valid signals also from lanes that should not send anything,
  // we need to synchronize the dummy valids. A valid is given, then it is deleted after an
  // handshake. It will be given again only after a valid_o by the SLDU
  logic red_hs_synch_d, red_hs_synch_q;

  // Counter to drive SIMD reductions
  logic [1:0] simd_red_cnt_d, simd_red_cnt_q;

  // Signal the first operation of an instruction. The first operation of a reduction instruction
  // the operation is performed between the first vector element and the scalar.
  // This signal has the highest privilage in multiple if-else loops
  logic first_op_d, first_op_q;

  // Signal to indicate the state of the MFPU
  typedef enum logic [2:0] {
    NO_REDUCTION, INTRA_LANE_REDUCTION, INTER_LANES_REDUCTION,
    WAIT_STATE, SIMD_REDUCTION, OSUM_REDUCTION, MFPU_WAIT
  } mfpu_state_e;
  mfpu_state_e mfpu_state_d, mfpu_state_q;

  // ntr_filling indicates that the neutral value is being sent to the FPU as an operand
  logic ntr_filling_d, ntr_filling_q;

  // Check if there is a valid result data that can be used as an operand (result_queue_q)
  // Because result_queue_valid may be set to 0, we need a signal to indicate that the old value is still valid
  logic first_result_op_valid_d, first_result_op_valid_q;

  // Count until the first result is avaible, used to end the neutral value filling
  logic [3:0] intra_issued_op_cnt_d, intra_issued_op_cnt_q;
  // Count how many operands received from the operand queue
  vlen_t intra_op_rx_cnt_d, intra_op_rx_cnt_q;
  logic  intra_op_rx_cnt_en;

  // This signal is used to cut a in2reg bad path
  // This works since the signal is never checked
  // twice in two consecutive cycles
  logic  mfpu_red_ready_q;

  // Input multiplexers.
  elen_t simd_red_operand;
  strb_t red_mask;

  // The ordered sum issue counter indicates how many elements in the operand data (64 bits) have been issued
  // e.g. assume EEW=16, there are four elements in the operand data (4 * 16bits = 64 bits), the osum_issue_cnt counts from 0 to 3
  logic [3:0] osum_issue_cnt_d, osum_issue_cnt_q;

  // This function returns 1'b1 if `op` is a reduction instruction, i.e.,
  // it must accumulate the result (intra-lane reduction) before sending it to the
  // sliding unit (inter-lane and SIMD reduction).
  function automatic logic is_reduction(ara_op_e op);
    is_reduction = 1'b0;
    if (op inside {[VFREDUSUM:VFWREDOSUM]})
      is_reduction = 1'b1;
  endfunction: is_reduction

  // This function returns the next mfpu_state for the next instruction
  function automatic mfpu_state_e next_mfpu_state(ara_op_e op);
    if (op inside {VFREDUSUM, VFREDMIN, VFREDMAX, VFWREDUSUM})
      next_mfpu_state = INTRA_LANE_REDUCTION;
    else if (op inside {VFREDOSUM, VFWREDOSUM})
      next_mfpu_state = OSUM_REDUCTION;
    else
      next_mfpu_state = NO_REDUCTION;
  endfunction : next_mfpu_state

  // Deactivate all masked or position disabled elements
  function automatic elen_t processed_red_operand(elen_t mfpu_operand, logic is_masked, strb_t mask, logic [3:0] issue_element_cnt, elen_t ntr_val);
    automatic strb_t pos_mask = be(issue_element_cnt, vinsn_issue_q.vtype.vsew);
    for (int i=0; i<8; i++)
      processed_red_operand[8*i +: 8] = ((~is_masked | mask[i]) & pos_mask[i]) ? mfpu_operand[8*i +: 8] : ntr_val[8*i +: 8];
  endfunction : processed_red_operand

  // This function returns the element pointed by the osum_issue_cnt
  // For EW16, the positions of the elements in one 64-bit data are as follows:
  // e12     |   e4      |  e8      |  e0
  // [63:48] |   [47:32] |  [31:16] |  [15:0]
  function automatic elen_t processed_osum_operand(elen_t mfpu_operand, logic [2:0] osum_issue_cnt, vew_e ew, logic is_masked, strb_t mask, elen_t ntr_val);
    case (ew)
      EW16: begin
        case (osum_issue_cnt)
          4'd0: processed_osum_operand = (is_masked & ~mask[0]) ? {48'd0, ntr_val[15:0] } : {48'd0, mfpu_operand[15:0] };
          4'd1: processed_osum_operand = (is_masked & ~mask[4]) ? {48'd0, ntr_val[47:32]} : {48'd0, mfpu_operand[47:32]};
          4'd2: processed_osum_operand = (is_masked & ~mask[2]) ? {48'd0, ntr_val[31:16]} : {48'd0, mfpu_operand[31:16]};
          4'd3: processed_osum_operand = (is_masked & ~mask[6]) ? {48'd0, ntr_val[63:48]} : {48'd0, mfpu_operand[63:48]};
          // Default case, no meaning
          default: processed_osum_operand = (is_masked & ~mask[6]) ? {48'd0, ntr_val[63:48]} : {48'd0, mfpu_operand[63:48]};
        endcase
      end
      EW32: begin
        case (osum_issue_cnt)
          4'd0: processed_osum_operand = (is_masked & ~mask[0]) ? {32'd0, ntr_val[31:0]} : {32'd0, mfpu_operand[31:0] };
          4'd1: processed_osum_operand = (is_masked & ~mask[4]) ? {32'd0, ntr_val[31:0]} : {32'd0, mfpu_operand[63:32]};
          // Default case, no meaning
          default: processed_osum_operand = (is_masked & ~mask[4]) ? {32'd0, ntr_val[31:0]} : {32'd0, mfpu_operand[63:32]};
        endcase
      end
      //EW32: processed_osum_operand = (is_masked & ~mask[osum_issue_cnt * 4]) ?
      //                               {32'd0, ntr_val[osum_issue_cnt * 32 +: 31]} :
      //                               {32'd0, mfpu_operand[osum_issue_cnt * 32 +: 31]};
      EW64: processed_osum_operand = (is_masked & ~mask[0]) ? ntr_val : mfpu_operand;
      default:;
    endcase
  endfunction : processed_osum_operand

  // Use this function to assign a counter value to each lane if you can use in-lane parameters with your flow
  function automatic reduction_rx_cnt_t reduction_rx_cnt_init(int unsigned NrLanes, logic [3:0] lane_id);
    // The even lanes do not receive intermediate results. Only Lane 0 will receive the final result, but this is not checked here.
    case (lane_id)
      0:  reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      1:  reduction_rx_cnt_init = reduction_rx_cnt_t'(1);
      2:  reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      3:  reduction_rx_cnt_init = reduction_rx_cnt_t'(2);
      4:  reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      5:  reduction_rx_cnt_init = reduction_rx_cnt_t'(1);
      6:  reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      7:  reduction_rx_cnt_init = reduction_rx_cnt_t'(3);
      8:  reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      9:  reduction_rx_cnt_init = reduction_rx_cnt_t'(1);
      10: reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      11: reduction_rx_cnt_init = reduction_rx_cnt_t'(2);
      12: reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      13: reduction_rx_cnt_init = reduction_rx_cnt_t'(1);
      14: reduction_rx_cnt_init = reduction_rx_cnt_t'(0);
      15: reduction_rx_cnt_init = reduction_rx_cnt_t'(4);
    endcase
  endfunction: reduction_rx_cnt_init
  ///////////
  //  FPU  //
  ///////////

  // FPU-related signals
  elen_t         vfpu_result, vfpu_processed_result;
  status_t       vfpu_ex_flag;
  strb_t         vfpu_mask;
  logic          vfpu_in_valid;
  logic          vfpu_out_valid;
  logic          vfpu_in_ready;
  logic          vfpu_out_ready;
  logic          fflags_ex_valid_d, fflags_ex_valid_q;
  logic    [4:0] fflags_ex_d, fflags_ex_q;

  // In floating-point comparisons the tag is used as mask,
  // In unordered reductions the tag is used as ntr indicator.
  // 0: no neutral value,
  // 1: only one of the operands is neutral value,
  // 2: both operands are neutral values
  strb_t vfpu_tag_in, vfpu_tag_out;

  assign vfpu_mask = vfpu_tag_out;

  // neutral value for Intraline reduction optimization
  elen_t         ntr_val;

  // FPU preprocessed signals
  elen_t operand_a;
  elen_t operand_b;
  elen_t operand_c;

  // fp_sign is used in control block
  logic [2:0] fp_sign;

  // Is the FPU enabled?
  if (FPUSupport != FPUSupportNone) begin : fpu_gen
    // Features (enabled formats, vectors etc.)
    localparam fpu_features_t FPUFeatures = '{
      Width        : 64,
      EnableVectors: 1'b1,
      EnableNanBox : 1'b1,
      FpFmtMask    : {RVVF(FPUSupport), RVVD(FPUSupport), RVVH(FPUSupport), 1'b0, 1'b0},
      IntFmtMask   : {1'b0, 1'b1, 1'b1, 1'b1}
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
        '{default: MERGED}}, // CONV
      PipeConfig: DISTRIBUTED
    };


    operation_e fp_op;
    logic fp_opmod;
    fp_format_e fp_src_fmt, fp_dst_fmt;
    int_format_e fp_int_fmt;
    roundmode_e fp_rm;
    // FPU preprocessing stage
    always_comb begin: fpu_operand_preprocessing_p
      // Default rounding-mode from fcsr.rm
      fp_rm      = vinsn_issue_q.fp_rm;
      fp_op      = ADD;
      fp_opmod   = 1'b0;
      fp_src_fmt = FP64;
      fp_dst_fmt = FP64;
      fp_int_fmt = INT64;
      fp_sign    = 3'b0;

      // Default neutral value
      ntr_val    = '0;

      unique case (vinsn_issue_q.op)
        // Addition is between operands B and C, A was moved to C in the lane_sequencer
        VFADD: fp_op = ADD;
        VFSUB: begin
          fp_op      = ADD;
          fp_sign[1] = 1'b1;
        end
        VFRSUB: begin
          fp_op    = ADD;
          fp_opmod = 1'b1;
        end
        VFMUL : fp_op = MUL;
        VFMACC,
        VFMADD,
        VFMSAC,
        VFMSUB: begin
          fp_op      = FMADD;
          fp_sign[2] = (vinsn_issue_q.op == VFMSAC) | (vinsn_issue_q.op == VFMSUB);
        end
        VFNMACC,
        VFNMSAC,
        VFNMADD,
        VFNMSUB: begin
          fp_op      = FNMSUB;
          fp_sign[2] = (vinsn_issue_q.op == VFNMACC) | (vinsn_issue_q.op == VFNMADD);
        end
        VFMIN: begin
          fp_op = MINMAX;
          fp_rm = RNE;
        end
        VFMAX: begin
          fp_op = MINMAX;
          fp_rm = RTZ;
        end
        VFSGNJ : begin
          fp_op = SGNJ;
          fp_rm = RNE;
        end
        VFSGNJN : begin
          fp_op = SGNJ;
          fp_rm = RTZ;
        end
        VFSGNJX : begin
          fp_op = SGNJ;
          fp_rm = RDN;
        end
        VMFEQ, VMFNE: begin
          fp_op = CMP;
          fp_rm = RDN;
        end
        VMFLE: begin
          fp_op = CMP;
          fp_rm = RNE;
        end
        VMFLT: begin
          fp_op = CMP;
          fp_rm = RTZ;
        end
        VMFGT: begin
          fp_sign[0] = 1'b1;
          fp_sign[1] = 1'b1;
          fp_op = CMP;
          fp_rm = RTZ;
        end
        VMFGE: begin
          fp_sign[0] = 1'b1;
          fp_sign[1] = 1'b1;
          fp_op = CMP;
          fp_rm = RNE;
        end
        VFCVTXUF: begin
          fp_op    = F2I;
          fp_opmod = 1'b1;
        end
        VFCVTXF: begin
          fp_op    = F2I;
          fp_opmod = 1'b0;
        end
        VFCVTFXU: begin
          fp_op    = I2F;
          fp_opmod = 1'b1;
        end
        VFCVTFX: begin
          fp_op    = I2F;
          fp_opmod = 1'b0;
        end
        VFCVTRTZXUF: begin
          fp_op    = F2I;
          fp_opmod = 1'b1;
          fp_rm    = RTZ;
        end
        VFCVTRTZXF: begin
          fp_op    = F2I;
          fp_opmod = 1'b0;
          fp_rm    = RTZ;
        end
        VFCVTFF: fp_op = F2F;
        VFREDUSUM, VFWREDUSUM, VFREDOSUM, VFWREDOSUM: fp_op = ADD;
        VFREDMIN: begin
          fp_op = MINMAX;
          fp_rm = RNE;
          // positive infinity
          case (vinsn_issue_q.vtype.vsew)
            EW16: ntr_val = {4{16'h7c00}};
            EW32: ntr_val = {2{32'h7f800000}};
            default: // EW64
              ntr_val = 64'h7ff0000000000000;
          endcase
        end
        VFREDMAX: begin
          fp_op = MINMAX;
          fp_rm = RTZ;
          // negative infinity
          case (vinsn_issue_q.vtype.vsew)
            EW16: ntr_val = {4{16'hfc00}};
            EW32: ntr_val = {2{32'hff800000}};
            default: // EW64
              ntr_val = 64'hfff0000000000000;
          endcase
        end
        default:;
      endcase

      // vtype.vsew encodes the destination format
      // cvt_resize is reused as neutral value for reductions
      unique case (vinsn_issue_q.vtype.vsew)
        EW16: begin
          fp_src_fmt = (vinsn_issue_q.cvt_resize == CVT_NARROW && !is_reduction(vinsn_issue_q.op)) ? FP32 : FP16;
          fp_dst_fmt = FP16;
          fp_int_fmt = (vinsn_issue_q.cvt_resize == CVT_NARROW && !is_reduction(vinsn_issue_q.op) && fp_op == I2F) ? INT32 : INT16;
        end
        EW32: begin
          fp_src_fmt = (vinsn_issue_q.cvt_resize == CVT_WIDE && !is_reduction(vinsn_issue_q.op)) ? FP16 :
            ((vinsn_issue_q.cvt_resize == CVT_NARROW && !is_reduction(vinsn_issue_q.op)) ? FP64 : FP32);
          fp_dst_fmt = FP32;
          fp_int_fmt = (vinsn_issue_q.cvt_resize == CVT_WIDE && !is_reduction(vinsn_issue_q.op) && fp_op == I2F) ? INT16 :
            ((vinsn_issue_q.cvt_resize == CVT_NARROW && !is_reduction(vinsn_issue_q.op) && fp_op == I2F) ? INT64 : INT32);
        end
        EW64: begin
          fp_src_fmt = (vinsn_issue_q.cvt_resize == CVT_WIDE && !is_reduction(vinsn_issue_q.op)) ? FP32 : FP64;
          fp_dst_fmt = FP64;
          fp_int_fmt = (vinsn_issue_q.cvt_resize == CVT_WIDE && !is_reduction(vinsn_issue_q.op) && fp_op == I2F) ? INT32 : INT64;
        end
        default:;
      endcase
    end : fpu_operand_preprocessing_p

    // FPU signals
    elen_t [2:0] vfpu_operands;
    assign vfpu_operands[0] = operand_a;
    assign vfpu_operands[1] = operand_b;
    assign vfpu_operands[2] = operand_c;

    // Do not raise exceptions on inactive elements
    localparam FPULanes = FPUSupport == FPUSupportNone ?
      1 :
      max_num_lanes(FPUFeatures.Width, FPUFeatures.FpFmtMask, FPUFeatures.EnableVectors);
    typedef logic [FPULanes-1:0] fpu_mask_t;

    fpu_mask_t vfpu_simd_mask;
    for (genvar b = 0; b < FPULanes; b++) begin: gen_vfpu_simd_mask
      assign vfpu_simd_mask[b] = issue_be[2*b];
    end: gen_vfpu_simd_mask

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
      .tag_i         (vfpu_tag_in   ),
      .simd_mask_i   (vfpu_simd_mask),
      .src_fmt_i     (fp_src_fmt    ),
      .dst_fmt_i     (fp_dst_fmt    ),
      .int_fmt_i     (fp_int_fmt    ),
      .in_valid_i    (vfpu_in_valid ),
      .in_ready_o    (vfpu_in_ready ),
      .result_o      (vfpu_result   ),
      .status_o      (vfpu_ex_flag  ),
      .tag_o         (vfpu_tag_out  ),
      .out_valid_o   (vfpu_out_valid),
      .out_ready_i   (vfpu_out_ready),
      .busy_o        (/* Unused */  )
    );

    always_comb begin: fpu_result_processing_p
      // Forward the result
      vfpu_processed_result = vfpu_result;
      // After a comparison, send the mask back to the mask unit
      // 1) Negate the result if op == VMFNE (fpnew does not natively support a not-equal comparison)
      // 2) Encode the mask in the bit after each comparison result
      if (vinsn_processing_q.op inside {[VMFEQ:VMFGE]}) begin
        unique case (vinsn_processing_q.vtype.vsew)
          EW16: begin
            for (int b = 0; b < 4; b++) vfpu_processed_result[16*b] =
              (vinsn_processing_q.op == VMFNE) ?
                ~vfpu_processed_result[16*b] :
                vfpu_processed_result[16*b];
            for (int b = 0; b < 4; b++) vfpu_processed_result[16*b+1] = vfpu_mask[2*b];
          end
          EW32: begin
            for (int b = 0; b < 2; b++) vfpu_processed_result[32*b] =
              (vinsn_processing_q.op == VMFNE) ?
                ~vfpu_processed_result[32*b] :
                vfpu_processed_result[32*b];
            for (int b = 0; b < 2; b++) vfpu_processed_result[32*b+1] = vfpu_mask[4*b];
          end
          EW64: begin
            for (int b = 0; b < 1; b++) vfpu_processed_result[b] =
              (vinsn_processing_q.op == VMFNE) ?
                ~vfpu_processed_result[b] :
                vfpu_processed_result[b];
            for (int b = 0; b < 1; b++) vfpu_processed_result[b+1] = vfpu_mask[8*b];
          end
        endcase
      end
    end

    // Stabilize signals regardless of FPU latency (signals to CVA6)
    assign fflags_ex_d       = vfpu_ex_flag;
    assign fflags_ex_valid_d = vfpu_out_valid & vfpu_out_ready;
  end else begin : no_fpu_gen // The FPU is disabled
    assign vfpu_in_ready     = 1'b0;
    assign vfpu_result       = '0;
    assign vfpu_ex_flag      = '0;
    assign vfpu_mask         = '0;
    assign vfpu_out_valid    = 1'b0;
    assign fflags_ex_d       = '0;
    assign fflags_ex_valid_d = 1'b0;
  end : no_fpu_gen

  assign fflags_ex_o       = fflags_ex_q;
  assign fflags_ex_valid_o = fflags_ex_valid_q;


  ///////////////
  //  Control  //
  ///////////////

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

  // Latency stall mechanism to ensure in-order FPU execution when needed
  // i.e. when issue insn has latency lower than processing insn latency
  fpu_latency_t vinsn_issue_lat_d, vinsn_processing_lat_d;
  logic latency_stall, latency_problem_d, latency_problem_q;

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

    narrowing_select_in_d  = narrowing_select_in_q;
    narrowing_select_out_d = narrowing_select_out_q;

    // Inform our status to the lane controller
    mfpu_ready_o      = !vinsn_queue_full;
    mfpu_vinsn_done_o = '0;

    // Do not acknowledge any operands
    mfpu_operand_ready_o = '0;

    // Inputs to the units are not valid by default
    vmul_in_valid = 1'b0;
    vdiv_in_valid = 1'b0;
    vfpu_in_valid = 1'b0;

    // If the result queue is not full, it is ready to accept a result
    vmul_out_ready = ~result_queue_full;
    vdiv_out_ready = ~result_queue_full;
    vfpu_out_ready = ~result_queue_full;

    // Valid of the unit in use (i.e., result queue input valid) is not asserted by default
    unit_out_valid  = 1'b0;
    unit_out_result = vmul_result;
    unit_out_mask   = vmul_mask;

    // Mask not granted by default
    mask_ready_o = 1'b0;

    // Short-circuit invalid elements divisions with a mask
    issue_be = '0;

    // Get latencies
    vinsn_issue_lat_d      = fpu_latency(vinsn_issue_d.vtype.vsew, vinsn_issue_d.op);
    vinsn_processing_lat_d = fpu_latency(vinsn_processing_d.vtype.vsew, vinsn_processing_d.op);

    // fpnew allows out-of-order execution and different instruction
    // types have different latencies. We have to enforce in-order execution.
    // If we are about to issue an instruction while another one is processing,
    // issue only if the new instruction is slower than the previous one
    latency_problem_d = vinsn_issue_lat_d < vinsn_processing_lat_d;
    latency_stall     = vinsn_issue_valid & vinsn_processing_valid & latency_problem_q;

    operand_a = mfpu_operand_i[1]; // vs2
    operand_b = vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]; // vs1, rs1
    operand_c = mfpu_operand_i[2]; // vd, or vs2 if we are performing a VFADD/VFSUB/VFRSUB

    // If vs2 and vd were swapped, re-route the handshake signals to/from the operand queues
    operands_valid = vinsn_issue_q.swap_vs2_vd_op
                   ? ((mfpu_operand_valid_i[2] || !vinsn_issue_q.use_vs2) &&
                      (mfpu_operand_valid_i[1] || !vinsn_issue_q.use_vd_op) &&
                      (mask_valid_i || vinsn_issue_q.vm) &&
                      (mfpu_operand_valid_i[0] || !vinsn_issue_q.use_vs1))
                   : ((mfpu_operand_valid_i[2] || !vinsn_issue_q.use_vd_op) &&
                      (mfpu_operand_valid_i[1] || !vinsn_issue_q.use_vs2) &&
                      (mask_valid_i || vinsn_issue_q.vm) &&
                      (mfpu_operand_valid_i[0] || !vinsn_issue_q.use_vs1));
    operands_ready = vinsn_issue_q.swap_vs2_vd_op
                   ? {vinsn_issue_q.use_vs2, vinsn_issue_q.use_vd_op, vinsn_issue_q.use_vs1}
                   : {vinsn_issue_q.use_vd_op, vinsn_issue_q.use_vs2, vinsn_issue_q.use_vs1};

    first_op_d              = first_op_q;
    simd_red_cnt_d          = simd_red_cnt_q;
    reduction_rx_cnt_d      = reduction_rx_cnt_q;
    sldu_transactions_cnt_d = sldu_transactions_cnt_q;
    red_hs_synch_d          = red_hs_synch_q;
    mfpu_red_valid_o        = 1'b0;
    sldu_mfpu_ready_d       = 1'b0;
    simd_red_cnt_max_d      = simd_red_cnt_max_q;
    simd_red_operand        = '0;
    red_mask                = '0;

    // Do not issue any operations
    vfpu_tag_in             = '0;
    mfpu_state_d            = mfpu_state_q;

    ntr_filling_d           = ntr_filling_q;
    intra_issued_op_cnt_d   = intra_issued_op_cnt_q;
    first_result_op_valid_d = first_result_op_valid_q;
    intra_op_rx_cnt_d       = intra_op_rx_cnt_q;
    intra_op_rx_cnt_en      = 1'b0;

    osum_issue_cnt_d        = osum_issue_cnt_q;

    // Don't prevent commit by default
    prevent_commit = 1'b0;

    //////////////////////////////////////////////////////////////////
    //  Issue the instruction and Write data into the result queue  //
    //////////////////////////////////////////////////////////////////

    case (mfpu_state_q)
      NO_REDUCTION: begin
        vfpu_tag_in = mask_i;

        // Sign injection
        unique case (vinsn_issue_q.vtype.vsew)
          EW16: for (int b = 0; b < 4; b++) begin
              operand_a[16*b+15] = operand_a[16*b+15] ^ fp_sign[0];
              operand_b[16*b+15] = operand_b[16*b+15] ^ fp_sign[1];
              operand_c[16*b+15] = operand_c[16*b+15] ^ fp_sign[2];
            end
          EW32: for (int b = 0; b < 2; b++) begin
              operand_a[32*b+31] = operand_a[32*b+31] ^ fp_sign[0];
              operand_b[32*b+31] = operand_b[32*b+31] ^ fp_sign[1];
              operand_c[32*b+31] = operand_c[32*b+31] ^ fp_sign[2];
            end
          EW64: for (int b = 0; b < 1; b++) begin
              operand_a[64*b+63] = operand_a[64*b+63] ^ fp_sign[0];
              operand_b[64*b+63] = operand_b[64*b+63] ^ fp_sign[1];
              operand_c[64*b+63] = operand_c[64*b+63] ^ fp_sign[2];
            end
          default:;
        endcase

        // Is there a vector instruction ready to be issued and do we have all the operands necessary for this instruction?
        if (operands_valid && vinsn_issue_valid && !is_reduction(vinsn_issue_q.op) && issue_cnt_q != '0 && !latency_stall) begin
          // Valiudate the inputs of the correct unit
          vmul_in_valid = vinsn_issue_mul;
          vdiv_in_valid = vinsn_issue_div;
          vfpu_in_valid = vinsn_issue_fpu;

          // Is the unit in use ready?
          if ((vinsn_issue_mul && vmul_in_ready) || (vinsn_issue_div && vdiv_in_ready) ||
              (vinsn_issue_fpu && vfpu_in_ready)) begin
            // Acknowledge the operands of this instruction
            mfpu_operand_ready_o = operands_ready;

            // Update the element issue counter and the related issue_be signal for the divider
            begin
              // How many elements are we issuing?
              automatic logic [3:0] issue_element_cnt =
                (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
              automatic logic [3:0] issue_element_cnt_narrow =
                (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew))) / 2;

              // Update the number of elements still to be issued
              if (issue_element_cnt > issue_cnt_q) issue_element_cnt = issue_cnt_q;
              if (issue_element_cnt_narrow > issue_cnt_q) issue_element_cnt_narrow = issue_cnt_q;

              // If the instruction is a narrowing one, we are issuing elements for one half of vtype.vsew
              issue_cnt_d = (narrowing(vinsn_issue_q.cvt_resize)) ? (issue_cnt_q - issue_element_cnt_narrow) : (issue_cnt_q - issue_element_cnt);

              // Give the correct be signal to the divider/FPU
              issue_be = narrowing(vinsn_issue_q.cvt_resize) ?
                be(issue_element_cnt_narrow, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm ? {StrbWidth{1'b1}} : mask_i) :
                be(issue_element_cnt, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm ? {StrbWidth{1'b1}} : mask_i);
            end

            // Update the narrowing selector and acknowledge the mask operatnds if needed
            if (narrowing(vinsn_issue_q.cvt_resize)) begin
              // Issued one half of the elements for the related narrowed result
              narrowing_select_in_d = ~narrowing_select_in_q;

              // Did we fill up a word?
              if (issue_cnt_d == '0 || narrowing_select_in_q) begin

                // Acknowledge the mask operand, if needed
                if (vinsn_issue_q != VFU_MaskUnit)
                  mask_ready_o = ~vinsn_issue_q.vm;
              end
            end else begin
              // Immediately acknowledge the mask unit M operands if this is a VMFPU operation
              if (vinsn_issue_q != VFU_MaskUnit)
                mask_ready_o = ~vinsn_issue_q.vm;
            end

            // Finished issuing the micro-operations of this vector instruction
            if (issue_cnt_d == '0) begin
              // Reset the input narrowing pointer
              narrowing_select_in_d = 1'b0;

              // Bump issue counter and pointers
              vinsn_queue_d.issue_cnt -= 1;
              if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1) vinsn_queue_d.issue_pnt = '0;
              else vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

              if (vinsn_queue_d.issue_cnt != 0) issue_cnt_d =
                vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
            end
          end
        end

        // Select the correct valid, result, and mask, to write in the result queue
        case (vinsn_processing_q.op) inside
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
          [VFADD:VFCVTFF], [VMFEQ:VMFGE]: begin
            unit_out_valid  = vfpu_out_valid;
            unit_out_result = vfpu_processed_result;
            unit_out_mask   = vfpu_mask;
          end
        endcase

        // Narrowing FPU results need to be shuffled before being saved for storing
        unique case (vinsn_processing_q.vtype.vsew)
          EW16: begin
            narrowing_shuffled_result[63:48] = unit_out_result[31:16];
            narrowing_shuffled_result[47:32] = unit_out_result[31:16];
            narrowing_shuffled_result[31:16] = unit_out_result[15:0];
            narrowing_shuffled_result[15:0]  = unit_out_result[15:0];
            narrowing_shuffle_be             = !narrowing_select_out_q ? 4'b0101 : 4'b1010;
          end
          EW32: begin
            narrowing_shuffled_result[63:32] = unit_out_result[31:0];
            narrowing_shuffled_result[31:0]  = unit_out_result[31:0];
            narrowing_shuffle_be             = !narrowing_select_out_q ? 4'b0011 : 4'b1100;
          end
          default: begin
            narrowing_shuffled_result[63:32] = unit_out_result[31:0];
            narrowing_shuffled_result[31:0]  = unit_out_result[31:0];
            narrowing_shuffle_be             = !narrowing_select_out_q ? 4'b0101 : 4'b1010;
          end
        endcase

        // Check if we have a valid result and we can add it to the result queue
        if (unit_out_valid && !result_queue_full) begin
          // How many elements have we processed?
          automatic logic [3:0] processed_element_cnt = (1 << (int'(EW64) - int'(vinsn_processing_q.vtype.vsew)));
          automatic logic [3:0] processed_element_cnt_narrow = (1 << (int'(EW64) - int'(vinsn_processing_q.vtype.vsew))) / 2;

          // Update the number of elements still to be processed
          if (processed_element_cnt > to_process_cnt_q)
            processed_element_cnt = to_process_cnt_q;
          if (processed_element_cnt_narrow > to_process_cnt_q)
            processed_element_cnt_narrow = to_process_cnt_q;

          // Update the number of elements still to be processed
          // If the instruction is a narrowing one, we have processed elements for one half of vtype.vsew
          to_process_cnt_d = (narrowing(vinsn_processing_q.cvt_resize)) ? (to_process_cnt_q - processed_element_cnt_narrow) : (to_process_cnt_q - processed_element_cnt);

          // Store the result in the result queue
          result_queue_d[result_queue_write_pnt_q].id    = vinsn_processing_q.id;
          result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_processing_q.vd, NrLanes) +
            ((vinsn_processing_q.vl - to_process_cnt_q) >> (int'(EW64) - vinsn_processing_q.vtype.vsew));
          // FP narrowing instructions pack the result in two different cycles, and only some 16-bit slices are active
          if (narrowing(vinsn_processing_q.cvt_resize)) begin
            for (int b = 0; b < 4; b++) begin
              if (narrowing_shuffle_be[b])
                result_queue_d[result_queue_write_pnt_q].wdata[b*16 +: 16] = narrowing_shuffled_result[b*16 +: 16];
            end
          end else begin
            result_queue_d[result_queue_write_pnt_q].wdata = unit_out_result;
          end
          if (!narrowing(vinsn_processing_q.cvt_resize) || !narrowing_select_out_q)
            result_queue_d[result_queue_write_pnt_q].be =
              be(processed_element_cnt, vinsn_processing_q.vtype.vsew) &
                (vinsn_processing_q.vm ? {StrbWidth{1'b1}} : unit_out_mask);

          result_queue_d[result_queue_write_pnt_q].mask  = vinsn_processing_q.vfu == VFU_MaskUnit;

          // Update the narrowing selector, validate the result, bump result queue pointers/counters
          if (narrowing(vinsn_processing_q.cvt_resize)) begin
            // Processed one half of the elements for the related narrowed result
            narrowing_select_out_d = ~narrowing_select_out_q;

            // Did we fill up a word?
            if (to_process_cnt_d == '0 || narrowing_select_out_q) begin
              result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

              // Bump pointers and counters of the result queue
              result_queue_cnt_d += 1;
              if (result_queue_write_pnt_q == ResultQueueDepth-1)
                result_queue_write_pnt_d = 0;
              else
                result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
            end
          end else begin
            result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

            // Bump pointers and counters of the result queue
            result_queue_cnt_d += 1;
            if (result_queue_write_pnt_q == ResultQueueDepth-1)
              result_queue_write_pnt_d = 0;
            else
              result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
          end

          // Finished issuing the micro-operations of this vector instruction
          if (to_process_cnt_d == '0) begin
            narrowing_select_out_d = 1'b0;

            vinsn_queue_d.processing_cnt -= 1;
            // Bump issue processing pointers
            if (vinsn_queue_q.processing_pnt == VInsnQueueDepth-1) vinsn_queue_d.processing_pnt = '0;
            else vinsn_queue_d.processing_pnt = vinsn_queue_q.processing_pnt + 1;

            if (vinsn_queue_d.processing_cnt != 0) to_process_cnt_d =
              vinsn_queue_q.vinsn[vinsn_queue_d.processing_pnt].vl;
          end
        end
      end
      INTRA_LANE_REDUCTION: begin
        // Update the element issue counter and the related issue_be signal for the divider
        // How many elements are we issuing?
        automatic logic [3:0] issue_element_cnt = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));

        // If the workload is unbalanced and some lanes already have commit_cnt == '0,
        // delay the commit until we are over with the inter-lanes phase
        prevent_commit = 1'b1;

        // Short Note:
        // 1. If the vector length for this lane is 0, the operand queue still gives one data
        // to make it compatible with the normal procedure
        // 2. Mask is processed in input stage

        // Update the number of elements still to be issued
        if (issue_element_cnt > issue_cnt_q) issue_element_cnt = issue_cnt_q;

        // Give the correct be signal to the divider/FPU
        issue_be = be(issue_element_cnt, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm ? {StrbWidth{1'b1}} : mask_i);

        // Stall only if this is the first operation for this reduction instruction and the result queue is full
        if (!(first_op_q && result_queue_full)) begin
          // =======================================================
          // Accumulate the result
          // =======================================================

          // Since operands may be result_queue_d, result processing should be placed before
          // the operation issuing.
          if (vfpu_out_valid && !result_queue_full) begin
            // How many elements have we processed?
            automatic logic [3:0] processed_element_cnt = (1 << (int'(EW64) - int'(vinsn_processing_q.vtype.vsew)));
            // Update the number of elements still to be processed
            if (processed_element_cnt > to_process_cnt_q)
              processed_element_cnt = to_process_cnt_q;

            if (vfpu_tag_out == strb_t'(2))
              to_process_cnt_d = to_process_cnt_q + (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
            else if (vfpu_tag_out == '0)
              to_process_cnt_d = to_process_cnt_q - processed_element_cnt;

            result_queue_d[result_queue_write_pnt_q].wdata = vfpu_processed_result;
            result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_processing_q.vd, NrLanes);
            result_queue_d[result_queue_write_pnt_q].id    = vinsn_processing_q.id;
            result_queue_d[result_queue_write_pnt_q].be    = be(1, vinsn_processing_q.vtype.vsew);
            result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

            first_result_op_valid_d = 1'b1;

            // Finished processing the micro-operations of this vector instruction
            if (to_process_cnt_d == '0) mfpu_state_d = INTER_LANES_REDUCTION;
          end else
            result_queue_valid_d[result_queue_write_pnt_q] = 1'b0;

          // =======================================================
          // Assign the corresponding input operands
          // =======================================================

          // Do we have all the operands necessary for this instruction?
          operand_a = processed_red_operand(mfpu_operand_i[1], ~vinsn_issue_q.vm, mask_i, issue_element_cnt, ntr_val);
          operand_c = processed_red_operand(mfpu_operand_i[2], ~vinsn_issue_q.vm, mask_i, issue_element_cnt, ntr_val);

          if (first_op_q) begin
            operand_b = vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0];
            if ((vinsn_issue_q.swap_vs2_vd_op ? mfpu_operand_valid_i[2] : mfpu_operand_valid_i[1]) &&
                (mask_valid_i || vinsn_issue_q.vm || (vinsn_issue_q.vl == '0)) && // Don't wait mask if vl is 0
                 mfpu_operand_valid_i[0]) begin
              operands_valid     = 1'b1;
              intra_op_rx_cnt_en = 1'b1;
            end else begin
              operands_valid = 1'b0;
            end
          end else if (ntr_filling_q) begin
            if (((vinsn_issue_q.swap_vs2_vd_op ? mfpu_operand_valid_i[2] : mfpu_operand_valid_i[1]) && intra_op_rx_cnt_q != vinsn_issue_q.vl) &&
                (mask_valid_i || vinsn_issue_q.vm)) begin
              intra_op_rx_cnt_en   = 1'b1;
              vfpu_tag_in          = strb_t'(1);
            end else begin
              // If there is no data from the operand queue, send two neutral values instead.
              operand_a            = ntr_val;
              operand_c            = ntr_val;
              vfpu_tag_in          = strb_t'(2);
            end
            operand_b = ntr_val;
            operands_valid = 1'b1;
          end else begin
            // The second operand is the result of the previous operation
            // In case there is no data from the operand queue, first check if there are two valid results,
            // if not, stop issuing.
            if (((vinsn_issue_q.swap_vs2_vd_op ? mfpu_operand_valid_i[2] : mfpu_operand_valid_i[1]) && intra_op_rx_cnt_q != vinsn_issue_q.vl) &&
               (mask_valid_i || vinsn_issue_q.vm)) begin
              // Take result_queue_q first
              if (first_result_op_valid_q) begin
                // First result data is used, if there is no new data, set first_result_op_valid to 0
                if (!result_queue_valid_d[result_queue_write_pnt_q])
                  first_result_op_valid_d = 1'b0;

                intra_op_rx_cnt_en = 1'b1;
                operand_b          = result_queue_q[result_queue_write_pnt_q].wdata;
                operands_valid     = 1'b1;
              end else if (result_queue_valid_d[result_queue_write_pnt_q]) begin
                // This result data is used, set valid to 0
                first_result_op_valid_d = 1'b0;
                intra_op_rx_cnt_en      = 1'b1;
                operand_b               = result_queue_d[result_queue_write_pnt_q].wdata;
                operands_valid          = 1'b1;
              end else begin
                operands_valid = 1'b0;
              end
            end else if (first_result_op_valid_q && result_queue_valid_d[result_queue_write_pnt_q]) begin
              operand_a               = result_queue_q[result_queue_write_pnt_q].wdata;
              operand_b               = result_queue_d[result_queue_write_pnt_q].wdata;
              operand_c               = result_queue_q[result_queue_write_pnt_q].wdata;
              operands_valid          = 1'b1;
              first_result_op_valid_d = 1'b0;
            end else begin
              operands_valid = 1'b0;
            end
          end

          // =======================================================
          // Issue the micro-operations
          // =======================================================

          if (operands_valid && vinsn_issue_valid) begin
            // Validate the inputs of FPU
            vfpu_in_valid = 1'b1;

            // Is FPU in use ready?
            if (vfpu_in_ready) begin
              automatic int unsigned latency = fpu_latency(vinsn_issue_q.vtype.vsew, vinsn_issue_q.op);

              if (vfpu_tag_in == strb_t'(2))
                issue_cnt_d = issue_cnt_q + (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
              else if (vfpu_tag_in == '0)
                issue_cnt_d = issue_cnt_q - issue_element_cnt;

              // The first operation of this instruction has just been done
              first_op_d = 1'b0;

              if (intra_op_rx_cnt_en) begin
                // Acknowledge the operands from the operand queue
                //mfpu_operand_ready_o = operands_ready;
                mfpu_operand_ready_o = vinsn_issue_q.swap_vs2_vd_op ? {2'b10, first_op_q} : {2'b01, first_op_q};
                // Acknowledge the mask operands
                mask_ready_o = ~vinsn_issue_q.vm;
                intra_op_rx_cnt_d = intra_op_rx_cnt_q + issue_element_cnt;
              end

              if (intra_issued_op_cnt_q != (latency - 1)) intra_issued_op_cnt_d = intra_issued_op_cnt_q + 1;

              // Start neutral value filling
              if (!first_op_d && first_op_q) ntr_filling_d = 1'b1;
              // Stop neutral value filling if the first result is available in the next cycle
              // or all elements in the operand queue have been issued
              if (intra_issued_op_cnt_q == (latency - 1) || intra_op_rx_cnt_d >= vinsn_issue_q.vl)
                ntr_filling_d = 1'b0;
            end
          end
        end
      end
      INTER_LANES_REDUCTION: begin
        // If the workload is unbalanced and some lanes already have commit_cnt == '0,
        // delay the commit until we are over with the inter-lanes phase
        prevent_commit = 1'b1;
        if (reduction_rx_cnt_q == '0) begin
          // Wait until the operand is valid in the result queue
          if (result_queue_valid_q[result_queue_write_pnt_q]) begin
            // This unit has finished processing data for this reduction instruction, send the partial result to the sliding unit
            mfpu_red_valid_o = 1'b1;
            // We can simply delay the ready since we will immediately change state,
            // so, no risk to re-sample alu_red_ready_i with side effects
            if (mfpu_red_ready_q) begin
              mfpu_state_d = WAIT_STATE;
              // Disable the used operand
              result_queue_valid_d[result_queue_write_pnt_q] = 1'b0;
            end
          end
        end else begin
          // This unit should still process data for the inter-lane reduction.
          // Ready to accept incoming operands from the slide unit.
          mfpu_red_valid_o = red_hs_synch_q;

          operand_a = sldu_operand_q;
          operand_b = result_queue_q[result_queue_write_pnt_q].wdata;
          operand_c = sldu_operand_q;
          // operand_b comes from the result_queue, operand_c comes from other lanes throught the slide unit
          operands_valid = result_queue_valid_q[result_queue_write_pnt_q] && sldu_mfpu_valid_q;

          if (operands_valid) begin
            // Issue the operation
            vfpu_in_valid = 1'b1;
            if (vfpu_in_ready) begin
              // Acknowledge operand_c from the slide unit
              sldu_mfpu_ready_d = 1'b1;
              // Disable the used operand
              result_queue_valid_d[result_queue_write_pnt_q] = 1'b0;
              reduction_rx_cnt_d = reduction_rx_cnt_q - 1;
            end
          end
        end

        // Count the successful transaction with the SLDU
        if (sldu_mfpu_valid_q && sldu_mfpu_ready_d) sldu_transactions_cnt_d = sldu_transactions_cnt_q - 1;
        if (mfpu_red_valid_o && mfpu_red_ready_i) red_hs_synch_d = 1'b0;
        if (sldu_mfpu_valid_q && sldu_mfpu_ready_d) red_hs_synch_d = 1'b1;

        // Accumulate the result
        if (vfpu_out_valid && !result_queue_full) begin
          result_queue_d[result_queue_write_pnt_q].wdata = vfpu_processed_result;
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
        end
      end
      WAIT_STATE: begin
        // If the workload is unbalanced and some lanes already have commit_cnt == '0,
        // delay the commit until we are over with the inter-lanes phase
        prevent_commit = 1'b1;
        // Acknowledge the sliding unit even if it is not forwarding anything useful
        sldu_mfpu_ready_d = sldu_mfpu_valid_q;
        mfpu_red_valid_o  = red_hs_synch_q;
        // If lane 0, wait for the inter-lane reduced operand, to perform a SIMD reduction
        if (lane_id_i == '0) begin
          if (sldu_mfpu_valid_q) begin
            if (sldu_transactions_cnt_q == 1) begin
              result_queue_d[result_queue_write_pnt_q].wdata = sldu_operand_q;
              result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
              unique case (vinsn_issue_q.vtype.vsew)
                  EW8 : simd_red_cnt_max_d = 2'd3;
                  EW16: simd_red_cnt_max_d = 2'd2;
                  EW32: simd_red_cnt_max_d = 2'd1;
                  EW64: simd_red_cnt_max_d = 2'd0;
              endcase
              simd_red_cnt_d = '0;
              mfpu_state_d = SIMD_REDUCTION;
            end
          end
        end else if (sldu_transactions_cnt_q == '0) begin
          // If not lane 0, wait for the completion of the reduction
          mfpu_state_d = MFPU_WAIT;

          // Give the done to the main sequencer
          commit_cnt_d = '0;
        end
        if (sldu_mfpu_valid_q && sldu_mfpu_ready_d) sldu_transactions_cnt_d = sldu_transactions_cnt_q - 1;
        if (mfpu_red_valid_o && mfpu_red_ready_i) red_hs_synch_d = 1'b0;
        if (sldu_mfpu_valid_q && sldu_mfpu_ready_d && sldu_transactions_cnt_d != '0) red_hs_synch_d = 1'b1;
      end
      SIMD_REDUCTION: begin // only lane 0 can enter this state
        unique case (simd_red_cnt_q)
          2'd0: simd_red_operand = {32'b0, result_queue_q[result_queue_write_pnt_q].wdata[63:32]};
          2'd1: simd_red_operand = {48'b0, result_queue_q[result_queue_write_pnt_q].wdata[31:16]};
          2'd2: simd_red_operand = {56'b0, result_queue_q[result_queue_write_pnt_q].wdata[15:8]};
          default:;
        endcase

        operand_a = simd_red_operand;
        operand_b = result_queue_q[result_queue_write_pnt_q].wdata;
        operand_c = simd_red_operand;
        // the operands in this state are simd_red_operand and result_queue.wdata
        operands_valid = result_queue_valid_q[result_queue_write_pnt_q];

        if (simd_red_cnt_q != simd_red_cnt_max_q) begin
          if (operands_valid) begin
            // Issue the operation
            vfpu_in_valid = 1'b1;
            if (vfpu_in_ready) begin
              // Acknowledge by updating the counter
              simd_red_cnt_d = simd_red_cnt_q + 1;

              // Disable the used operand
              result_queue_valid_d[result_queue_write_pnt_q] = 1'b0;
            end
          end
        end else if (result_queue_valid_q[result_queue_write_pnt_q]) begin
          mfpu_state_d = MFPU_WAIT;

          // Give the done to the main sequencer
          commit_cnt_d = '0;

          // Bump pointers and counters of the result queue
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
          result_queue_cnt_d += 1;
          if (result_queue_write_pnt_q == ResultQueueDepth-1)
            result_queue_write_pnt_d = 0;
          else
            result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
        end

        // Accumulate the result
        if (vfpu_out_valid && !result_queue_full) begin
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
          result_queue_d[result_queue_write_pnt_q].wdata = vfpu_processed_result;
        end
      end
      OSUM_REDUCTION: begin
        // Short Note: Only one lane is allowed to be active (only one lane has all operands valid)
        operand_c = processed_osum_operand(mfpu_operand_i[2], osum_issue_cnt_q, vinsn_issue_q.vtype.vsew, ~vinsn_issue_q.vm, mask_i, ntr_val);
        operand_b = (first_op_q && (lane_id_i == '0)) ?
                    (vinsn_issue_q.use_scalar_op ? scalar_op : mfpu_operand_i[0]) :
                    sldu_operand_q;

        if (mfpu_operand_valid_i[2] && (mask_valid_i || vinsn_issue_q.vm)) begin
          if (first_op_q) begin
            if (lane_id_i == '0)
              operands_valid = mfpu_operand_valid_i[0];
            else
              // Also check op_b, because it needs to be acknowledged
              operands_valid = mfpu_operand_valid_i[0] && sldu_mfpu_valid_q;
          end else begin
            operands_valid = sldu_mfpu_valid_q;
          end
        end else begin
          operands_valid = 1'b0;
        end

        // Ready to accept incoming operands from the slide unit.
        mfpu_red_valid_o = red_hs_synch_q;

        // Issue the uOp
        if (operands_valid && vinsn_issue_valid && issue_cnt_q != '0) begin
          vfpu_in_valid = 1'b1;
          if (vfpu_in_ready) begin
            // The number of elements to be issued in one 64-bit data
            automatic logic [3:0] num_element = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));

            osum_issue_cnt_d = osum_issue_cnt_q + 1;
            if (osum_issue_cnt_d == num_element || issue_cnt_q == 1) begin
              // All elements in one 64-bit data have been issued
              osum_issue_cnt_d = '0;
              // Ackownledge the operand_c, ready to receive the next
              // operand from operand queue
              //mfpu_operand_ready_o = operands_ready;
              mfpu_operand_ready_o[2] = 1'b1;
              // Acknowledge the mask operands
              mask_ready_o = ~vinsn_issue_q.vm;
            end

            // Acknowledge scalar operand_b
            if (first_op_q) mfpu_operand_ready_o[0] = 1'b1;

            // Acknowledge operand_c from the slide unit
            // Note: Also ack even if this is the first operation in lane 0
            sldu_mfpu_ready_d = 1'b1;

            // Give the correct be signal to the divider/FPU
            issue_be = be(1, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm ? {StrbWidth{1'b1}} : mask_i);
            issue_cnt_d = issue_cnt_q - 1;

            // The first operation of this instruction has just been done
            first_op_d = 1'b0;
          end
        end else if (mfpu_operand_valid_i[2] && mfpu_operand_valid_i[0] &&
                     first_op_q && (vinsn_issue_q.vl == '0)) begin
          // If vl = 0, just acknowledge the redundant data from operand_queue
          first_op_d = 1'b0;
          mfpu_operand_ready_o = 3'b101;
        end

        // Reduction instruction, accumulate the result
        // Only the active lane has the valid result
        if (vfpu_out_valid && !result_queue_full) begin
          to_process_cnt_d = to_process_cnt_q - 1;

          result_queue_d[result_queue_write_pnt_q].wdata = vfpu_processed_result;
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
        end

        // Slide unit has acknowledged the operand, set next valid to 0
        if (mfpu_red_valid_o && mfpu_red_ready_i) begin
          red_hs_synch_d = 1'b0;
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b0;
        end
        // Send valid result to the slide unit
        if (result_queue_valid_d[result_queue_write_pnt_q])
          red_hs_synch_d = 1'b1;

        // Finish this instruction if the last result is acknowledged
        // In the case of vl=0, wait until the redundant data is acknowledged
        if (!(lane_id_i == '0) && to_process_cnt_d == '0 && ((vinsn_processing_q.vl == '0) ? !first_op_q : red_hs_synch_q)) begin
          // Give the done to the main sequencer
          commit_cnt_d = '0;
          mfpu_state_d = MFPU_WAIT;
        end else if ((lane_id_i == '0) && sldu_mfpu_valid_q && to_process_cnt_d == '0) begin
          // Lane 0 should wait for the final result
          result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_processing_q.vd, NrLanes);
          result_queue_d[result_queue_write_pnt_q].id    = vinsn_processing_q.id;
          result_queue_d[result_queue_write_pnt_q].be    = be(1, vinsn_processing_q.vtype.vsew);
          result_queue_d[result_queue_write_pnt_q].mask  = vinsn_processing_q.vfu == VFU_MaskUnit;
          result_queue_d[result_queue_write_pnt_q].wdata = sldu_operand_q;

          // Bump pointers and counters of the result queue
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
          result_queue_cnt_d += 1;
          if (result_queue_write_pnt_q == ResultQueueDepth-1)
            result_queue_write_pnt_d = 0;
          else
            result_queue_write_pnt_d = result_queue_write_pnt_q + 1;

          sldu_mfpu_ready_d = 1'b1;
          commit_cnt_d = '0;
          mfpu_state_d = MFPU_WAIT;
        end
      end
      MFPU_WAIT: begin
        vinsn_queue_d.processing_cnt -= 1;
        // Bump issue processing pointers
        if (vinsn_queue_q.processing_pnt == VInsnQueueDepth-1) vinsn_queue_d.processing_pnt = '0;
        else vinsn_queue_d.processing_pnt = vinsn_queue_q.processing_pnt + 1;

        if (vinsn_queue_d.processing_cnt != 0) to_process_cnt_d =
          vinsn_queue_q.vinsn[vinsn_queue_d.processing_pnt].vl;

        // Bump issue counter and pointers
        vinsn_queue_d.issue_cnt -= 1;
        if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1) vinsn_queue_d.issue_pnt = '0;
        else vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

        if (vinsn_queue_d.issue_cnt != 0) issue_cnt_d =
          vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;

        mfpu_state_d = (vinsn_queue_d.issue_cnt != 0) ? next_mfpu_state(vinsn_issue_d.op) : NO_REDUCTION;

        // The next will be the first operation of this instruction
        // This information is useful for reduction operation
        first_op_d         = 1'b1;
        reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);
        sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
        // Allow the first valid
        red_hs_synch_d = !(vinsn_issue_d.op inside {VFREDOSUM, VFWREDOSUM}) & is_reduction(vinsn_issue_d.op);

        ntr_filling_d           = 1'b0;
        intra_issued_op_cnt_d   = '0;
        first_result_op_valid_d = 1'b0;
        intra_op_rx_cnt_d       = '0;
        osum_issue_cnt_d        = '0;
      end
      default:;
    endcase

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

    // Send result information to the VRF
    // Use mfpu_result_gnt register instead of mfpu_state, because the state could be changed
    if (mfpu_state_q inside {NO_REDUCTION, MFPU_WAIT} || ((lane_id_i == '0) && commit_cnt_d == '0))
      mfpu_result_req_o = (result_queue_valid_q[result_queue_read_pnt_q] && !result_queue_q[result_queue_read_pnt_q].mask) ? 1'b1 : 1'b0;
    else
      mfpu_result_req_o = 1'b0;

    mfpu_result_addr_o  = result_queue_q[result_queue_read_pnt_q].addr;
    mfpu_result_id_o    = result_queue_q[result_queue_read_pnt_q].id;
    mfpu_result_wdata_o = result_queue_q[result_queue_read_pnt_q].wdata;
    mfpu_result_be_o    = result_queue_q[result_queue_read_pnt_q].be;

    // Received a grant from the VRF, or the mask unit ate the result.
    // Deactivate the request.
    if (mfpu_result_gnt_i || mask_operand_gnt) begin
      // How many elements are we committing?
      automatic logic [3:0] commit_element_cnt =
        (1 << (int'(EW64) - int'(vinsn_commit.vtype.vsew)));

      result_queue_valid_d[result_queue_read_pnt_q] = 1'b0;
      result_queue_d[result_queue_read_pnt_q]       = '0;

      // Increment the read pointer
      if (result_queue_read_pnt_q == ResultQueueDepth-1) result_queue_read_pnt_d = 0;
      else result_queue_read_pnt_d = result_queue_read_pnt_q + 1;

      // Decrement the counter of results waiting to be written
      result_queue_cnt_d -= 1;

      // Decrement the counter of remaining vector elements waiting to be written
      // Don't do it in case of a reduction
      if (!is_reduction(vinsn_commit.op)) begin
        commit_cnt_d = commit_cnt_q - commit_element_cnt;
        if (commit_cnt_q < commit_element_cnt) commit_cnt_d = '0;
      end
    end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && (commit_cnt_d == '0) && !prevent_commit) begin
      // Mark the vector instruction as being done
      mfpu_vinsn_done_o[vinsn_commit.id] = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1) vinsn_queue_d.commit_pnt = '0;
      else vinsn_queue_d.commit_pnt += 1;

      // Update the commit counter for the next instruction
      if (vinsn_queue_d.commit_cnt != '0)
        commit_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl;

      // If we are reducing now, we will change state in MFPU_WAIT state during the next cycle
      if (mfpu_state_q == NO_REDUCTION) begin
        // Initialize counters and vmfpu state if needed by the next instruction
        // After a reduction, the next instructions starts after the reduction commits
        if (is_reduction(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op) && (vinsn_queue_d.issue_cnt != '0)) begin
          // The next will be the first operation of this instruction
          // This information is useful for reduction operation
          first_op_d         = 1'b1;
          reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);
          sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
          // Allow the first valid
          red_hs_synch_d = !(vinsn_issue_d.op inside {VFREDOSUM, VFWREDOSUM}) & is_reduction(vinsn_issue_d.op);

          ntr_filling_d           = 1'b0;
          intra_issued_op_cnt_d   = '0;
          first_result_op_valid_d = 1'b0;
          intra_op_rx_cnt_d       = '0;
          osum_issue_cnt_d        = '0;

          mfpu_state_d = next_mfpu_state(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op);
        end else begin
          mfpu_state_d = NO_REDUCTION;
        end
      end
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && vfu_operation_valid_i &&
      (vfu_operation_i.vfu == VFU_MFpu || vfu_operation_i.op inside {[VMFEQ:VMFGE]})) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = vfu_operation_i;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0 && !prevent_commit) begin
        mfpu_state_d = next_mfpu_state(vfu_operation_i.op);
        // The next will be the first operation of this instruction
        // This information is useful for reduction operation
        first_op_d              = 1'b1;
        reduction_rx_cnt_d      = reduction_rx_cnt_init(NrLanes, lane_id_i);
        sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
        // Allow the first valid
        red_hs_synch_d          = !(vfu_operation_i.op inside {VFREDOSUM, VFWREDOSUM}) & is_reduction(vfu_operation_i.op);
        ntr_filling_d           = 1'b0;
        intra_issued_op_cnt_d   = '0;
        first_result_op_valid_d = 1'b0;
        intra_op_rx_cnt_d       = '0;
        osum_issue_cnt_d        = '0;
      end
      if (vinsn_queue_d.processing_cnt == '0) to_process_cnt_d = vfu_operation_i.vl;
      if (vinsn_queue_d.commit_cnt == '0) commit_cnt_d = is_reduction(vfu_operation_i.op) ? 1 : vfu_operation_i.vl;
      if (vinsn_queue_d.issue_cnt == '0) issue_cnt_d = vfu_operation_i.vl;
      // Floating-Point re-encoding for widening operations
      // Enabled only for the supported formats
      if (FPUSupport != FPUSupportNone) begin
        if (vfu_operation_i.wide_fp_imm) begin
          unique casez ({vfu_operation_i.vtype.vsew,
            RVVH(FPUSupport),
            RVVF(FPUSupport),
            RVVD(FPUSupport)})
            {EW32, 1'b1, 1'b1, 1'b?}: begin
              for (int e = 0; e < 2; e++) begin
                automatic fp16_t fp16 =
                  vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op[15:0];
                automatic fp32_t fp32;
                fp32.s = fp16.s;
                fp32.e = (fp16.e - 15) + 127;
                fp32.m = {fp16.m, 13'b0};

                vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op[32*e +: 32] = fp32;
              end
            end
            {EW64, 1'b?, 1'b1, 1'b1}: begin
              automatic fp32_t fp32 = vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op[31:0];
              automatic fp64_t fp64;
              fp64.s = fp32.s;
              fp64.e = (fp32.e - 127) + 1023;
              fp64.m = {fp32.m, 29'b0};

              vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].scalar_op = fp64;
            end
            default:;
          endcase
        end
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.processing_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_vmfpu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_cnt_q             <= '0;
      to_process_cnt_q        <= '0;
      commit_cnt_q            <= '0;
      narrowing_select_in_q   <= 1'b0;
      narrowing_select_out_q  <= 1'b0;
      fflags_ex_valid_q       <= 1'b0;
      fflags_ex_q             <= '0;
      latency_problem_q       <= 1'b0;
      simd_red_cnt_q          <= '0;
      mfpu_state_q            <= NO_REDUCTION;
      reduction_rx_cnt_q      <= '0;
      first_op_q              <= 1'b0;
      sldu_transactions_cnt_q <= '0;
      red_hs_synch_q          <= 1'b0;
      simd_red_cnt_max_q      <= '0;
      mfpu_red_ready_q        <= 1'b0;
      ntr_filling_q           <= 1'b0;
      first_result_op_valid_q <= 1'b0;
      intra_issued_op_cnt_q   <= '0;
      intra_op_rx_cnt_q       <= '0;
      osum_issue_cnt_q        <= '0;
    end else begin
      issue_cnt_q             <= issue_cnt_d;
      to_process_cnt_q        <= to_process_cnt_d;
      commit_cnt_q            <= commit_cnt_d;
      narrowing_select_in_q   <= narrowing_select_in_d;
      narrowing_select_out_q  <= narrowing_select_out_d;
      fflags_ex_valid_q       <= fflags_ex_valid_d;
      fflags_ex_q             <= fflags_ex_d;
      latency_problem_q       <= latency_problem_d;
      simd_red_cnt_q          <= simd_red_cnt_d;
      mfpu_state_q            <= mfpu_state_d;
      reduction_rx_cnt_q      <= reduction_rx_cnt_d;
      first_op_q              <= first_op_d;
      sldu_transactions_cnt_q <= sldu_transactions_cnt_d;
      red_hs_synch_q          <= red_hs_synch_d;
      simd_red_cnt_max_q      <= simd_red_cnt_max_d;
      mfpu_red_ready_q        <= mfpu_red_ready_i;
      ntr_filling_q           <= ntr_filling_d;
      first_result_op_valid_q <= first_result_op_valid_d;
      intra_issued_op_cnt_q   <= intra_issued_op_cnt_d;
      intra_op_rx_cnt_q       <= intra_op_rx_cnt_d;
      osum_issue_cnt_q        <= osum_issue_cnt_d;
    end
  end

endmodule : vmfpu
