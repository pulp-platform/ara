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
// File:   vmfpu.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Date:   12.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's integer multiplier and floating-point unit.

module vmfpu import ara_pkg::*; import rvv_pkg::*; #(
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

  // Is the vector instructoin queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  vfu_operation_t vinsn_issue;
  logic           vinsn_issue_valid;
  assign vinsn_issue       = vinsn_queue_q.vinsn[vinsn_queue_q.issue_pnt];
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
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
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
   *  Scalar operand  *
   ********************/

  elen_t scalar_op;

  // Replicate the scalar operand on the 64-bit word, depending
  // on the element width.
  always_comb begin
    // Default assignment
    scalar_op = '0;

    case (vinsn_issue.vtype.vsew)
      EW64: scalar_op = {1{vinsn_issue.scalar_op[63:0]}};
      EW32: scalar_op = {2{vinsn_issue.scalar_op[31:0]}};
      EW16: scalar_op = {4{vinsn_issue.scalar_op[15:0]}};
      EW8 : scalar_op = {8{vinsn_issue.scalar_op[ 7:0]}};
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
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                        ),
    .operand_c_i(mfpu_operand_i[2]                                        ),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .result_o   (vmul_simd_result[EW64]                                   ),
    .mask_o     (vmul_simd_mask[EW64]                                     ),
    .valid_i    (vmul_simd_in_valid[EW64]                                 ),
    .ready_o    (vmul_simd_in_ready[EW64]                                 ),
    .ready_i    (vmul_simd_out_ready[EW64]                                ),
    .valid_o    (vmul_simd_out_valid[EW64]                                )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW32),
    .ElementWidth(EW32             )
  ) i_simd_mul_ew32 (
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                        ),
    .operand_c_i(mfpu_operand_i[2]                                        ),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .result_o   (vmul_simd_result[EW32]                                   ),
    .mask_o     (vmul_simd_mask[EW32]                                     ),
    .valid_i    (vmul_simd_in_valid[EW32]                                 ),
    .ready_o    (vmul_simd_in_ready[EW32]                                 ),
    .ready_i    (vmul_simd_out_ready[EW32]                                ),
    .valid_o    (vmul_simd_out_valid[EW32]                                )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW16),
    .ElementWidth(EW16             )
  ) i_simd_mul_ew16 (
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                        ),
    .operand_c_i(mfpu_operand_i[2]                                        ),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .result_o   (vmul_simd_result[EW16]                                   ),
    .mask_o     (vmul_simd_mask[EW16]                                     ),
    .valid_i    (vmul_simd_in_valid[EW16]                                 ),
    .ready_o    (vmul_simd_in_ready[EW16]                                 ),
    .ready_i    (vmul_simd_out_ready[EW16]                                ),
    .valid_o    (vmul_simd_out_valid[EW16]                                )
  );

  simd_mul #(
    .NumPipeRegs (LatMultiplierEW8),
    .ElementWidth(EW8             )
  ) i_simd_mul_ew8 (
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                        ),
    .operand_c_i(mfpu_operand_i[2]                                        ),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .result_o   (vmul_simd_result[EW8]                                    ),
    .mask_o     (vmul_simd_mask[EW8]                                      ),
    .valid_i    (vmul_simd_in_valid[EW8]                                  ),
    .ready_o    (vmul_simd_in_ready[EW8]                                  ),
    .ready_i    (vmul_simd_out_ready[EW8]                                 ),
    .valid_o    (vmul_simd_out_valid[EW8]                                 )
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
    vmul_simd_in_valid                         = '0;
    vmul_simd_in_valid[vinsn_issue.vtype.vsew] = vmul_in_valid;
    vmul_in_ready                              = vmul_simd_in_ready[vinsn_issue.vtype.vsew];

    // We read the responses of a single SIMD Multipler
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
  strb_t vdiv_be;

  logic vdiv_in_valid;
  logic vdiv_out_valid;
  logic vdiv_in_ready;
  logic vdiv_out_ready;

  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the operand queues
  // Another choice would be to delay the mask grant when the vdiv_result is committed
  strb_t vdiv_mask;

  simd_div i_simd_div (
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(mfpu_operand_i[1]                                        ),
    .operand_b_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .be_i       (vdiv_be                                                  ),
    .vew_i      (vinsn_issue.vtype.vsew                                   ),
    .result_o   (vdiv_result                                              ),
    .mask_o     (vdiv_mask                                                ),
    .valid_i    (vdiv_in_valid                                            ),
    .ready_o    (vdiv_in_ready                                            ),
    .ready_i    (vdiv_out_ready                                           ),
    .valid_o    (vdiv_out_valid                                           )
  );

  /*************
   *  Control  *
   *************/

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

    // Valid of the unit in use (i.e., result queue input valid) is not asserted by default
    unit_out_valid  = 1'b0;
    unit_out_result = vmul_result;
    unit_out_mask   = vmul_mask;

    // Mask not granted by default
    mask_ready_o = 1'b0;

    // Short-circuit invalid elements divisions with a mask
    vdiv_be = '0;

    /***************************************
     *  Issue the instruction to the unit  *
     **************************************/

    // There is a vector instruction ready to be issued
    if (vinsn_issue_valid) begin
      // Do we have all the operands necessary for this instruction?
      if ((mfpu_operand_valid_i[2] || !vinsn_issue.use_vd_op) && (mfpu_operand_valid_i[1] || !vinsn_issue.use_vs2) && (mfpu_operand_valid_i[0] || !vinsn_issue.use_vs1) && (mask_valid_i || vinsn_issue.vm)) begin
        // Validate the inputs of the correct unit
        case (vinsn_issue.op) inside
          [VMUL:VNMSUB]: vmul_in_valid = 1'b1;
          [VDIVU:VREM] : vdiv_in_valid = 1'b1;
        endcase

        // Is the unit in use ready?
        if ((vinsn_issue.op inside {[VMUL:VNMSUB]} && vmul_in_ready) || (vinsn_issue.op inside {[VDIVU:VREM]} && vdiv_in_ready)) begin
          // Acknowledge the operands of this instruction
          mfpu_operand_ready_o = {vinsn_issue.use_vd_op, vinsn_issue.use_vs2, vinsn_issue.use_vs1};
          // Acknowledge the mask unit
          mask_ready_o         = ~vinsn_issue.vm;

          begin
            // How many elements are we issuing?
            automatic logic [3:0] issue_element_cnt = (1 << (int'(EW64) - int'(vinsn_issue.vtype.vsew)));
            // Update the number of elements still to be issued
            if (issue_element_cnt > issue_cnt_q)
              issue_element_cnt = issue_cnt_q;
            issue_cnt_d = issue_cnt_q - issue_element_cnt;

            // Give the divider the correct be signal
            vdiv_be = be(issue_element_cnt, vinsn_issue.vtype.vsew) & (vinsn_issue.vm ? {StrbWidth{1'b1}} : mask_i);
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

    // Select the correct valid, result, and mask, to write in the result queue
    case (vinsn_processing.op) inside
      [VMUL:VNMSUB]: begin
        unit_out_valid  = vmul_out_valid;
        unit_out_result = vmul_result;
        unit_out_mask   = vmul_mask;
      end
      [VDIVU:VREM] : begin
        unit_out_valid  = vdiv_out_valid;
        unit_out_result = vdiv_result;
        unit_out_mask   = vdiv_mask;
      end
    endcase

    // Check if we have a valid result and we can add it to the result queue
    if (unit_out_valid && !result_queue_full) begin
      // How many elements have we processed?
      automatic logic [3:0] processed_element_cnt = (1 << (int'(EW64) - int'(vinsn_processing.vtype.vsew)));
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

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.processing_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_vmfpu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_cnt_q      <= '0;
      to_process_cnt_q <= '0;
      commit_cnt_q     <= '0;
    end else begin
      issue_cnt_q      <= issue_cnt_d;
      to_process_cnt_q <= to_process_cnt_d;
      commit_cnt_q     <= commit_cnt_d;
    end
  end

endmodule : vmfpu

/*********************
 *  SIMD Multiplier  *
 ********************/

// Description:
// Ara's SIMD Multiplier, operating on elements 64-bit wide.
// The parametric number of pipeline register determines the intrinsic latency of the unit.
// Once the pipeline is full, the unit can generate 64 bits per cycle.

module simd_mul import ara_pkg::*; import rvv_pkg::*; #(
    parameter int   unsigned NumPipeRegs  = 0,
    parameter vew_e          ElementWidth = EW64,
    // Dependant parameters. DO NOT CHANGE!
    parameter int   unsigned DataWidth    = $bits(elen_t),
    parameter int   unsigned StrbWidth    = DataWidth/8,
    parameter type           strb_t       = logic [DataWidth/8-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  elen_t   operand_c_i,
    input  strb_t   mask_i,
    input  ara_op_e op_i,
    output elen_t   result_o,
    output strb_t   mask_o,
    input  logic    valid_i,
    output logic    ready_o,
    input  logic    ready_i,
    output logic    valid_o
  );

  /*****************
   *  Definitions  *
   *****************/

  `include "common_cells/registers.svh"

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } mul_operand_t;

  mul_operand_t opa, opb, opc;
  ara_op_e      op;

  /*********************
   *  Pipeline stages  *
   *********************/

  // Input signals for the next stage (= output signals of the previous stage)
  mul_operand_t [NumPipeRegs:0] opa_d, opb_d, opc_d;
  ara_op_e      [NumPipeRegs:0] op_d;
  strb_t        [NumPipeRegs:0] mask_d;
  logic         [NumPipeRegs:0] valid_d;
  // Ready signal is combinatorial for all stages
  logic         [NumPipeRegs:0] stage_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign opa_d[0]   = operand_a_i;
  assign opb_d[0]   = operand_b_i;
  assign opc_d[0]   = operand_c_i;
  assign op_d[0]    = op_i;
  assign mask_d[0]  = mask_i;
  assign valid_d[0] = valid_i;

  // Generate the pipeline stages in case they are needed
  if (NumPipeRegs > 0) begin : gen_pipeline
    // Pipelined versions of signals for later stages
    mul_operand_t [NumPipeRegs-1:0] opa_q, opb_q, opc_q;
    strb_t [NumPipeRegs-1:0] mask_q;
    ara_op_e [NumPipeRegs-1:0] op_q;
    logic [NumPipeRegs-1:0] valid_q;

    for (genvar i = 0; i < NumPipeRegs; i++) begin : pipeline_stages
      // Next state from previous register to form a shift register
      assign opa_d[i+1]   = opa_q[i];
      assign opb_d[i+1]   = opb_q[i];
      assign opc_d[i+1]   = opc_q[i];
      assign op_d[i+1]    = op_q[i];
      assign mask_d[i+1]  = mask_q[i];
      assign valid_d[i+1] = valid_q[i];

      // Determine the ready signal of the current stage - advance the pipeline:
      // 1. if the next stage is ready for our data
      // 2. if the next stage register only holds a bubble (not valid) -> we can pop it
      assign stage_ready[i] = stage_ready[i+1] | ~valid_q[i];

      // Enable register if pipleine ready
      logic reg_ena;
      assign reg_ena = stage_ready[i];

      // Generate the pipeline
      `FFL(valid_q[i], valid_d[i], reg_ena, '0)
      `FFL(opa_q[i], opa_d[i], reg_ena, '0)
      `FFL(opb_q[i], opb_d[i], reg_ena, '0)
      `FFL(opc_q[i], opc_d[i], reg_ena, '0)
      `FFL(op_q[i], op_d[i], reg_ena, ara_op_e'('0))
      `FFL(mask_q[i], mask_d[i], reg_ena, '0)
    end
  end

  // Input stage: Propagate ready signal from pipeline
  assign ready_o = stage_ready[0];

  // Output stage: bind last stage outputs to the pipeline output. Directly connects to input if no regs.
  assign opa     = opa_d[NumPipeRegs];
  assign opb     = opb_d[NumPipeRegs];
  assign opc     = opc_d[NumPipeRegs];
  assign op      = op_d[NumPipeRegs];
  assign mask_o  = mask_d[NumPipeRegs];
  assign valid_o = valid_d[NumPipeRegs];

  // Output stage: Ready travels backwards from output side
  assign stage_ready[NumPipeRegs] = ready_i;

  /****************
   *  Multiplier  *
   ****************/

  typedef union packed {
    logic [0:0][127:0] w128;
    logic [1:0][63:0] w64;
    logic [3:0][31:0] w32;
    logic [7:0][15:0] w16;
  } mul_result_t;
  mul_result_t mul_res;

  logic signed_a, signed_b;

  // Sign select MUX
  assign signed_a = op inside {VMULH};
  assign signed_b = op inside {VMULH, VMULHSU};

  if (ElementWidth == EW64) begin: gen_p_mul_ew64
    for (genvar l = 0; l < 1; l++) begin: gen_mul
      assign mul_res.w128[l] = $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
    end: gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 1; l++)
            result_o[64*l +: 64] = mul_res.w128[l][63:0];
        VMULH, VMULHU, VMULHSU: for (int l = 0; l < 1; l++)
            result_o[64*l +: 64] = mul_res.w128[l][127:64];

        // Single-Width integer multiply-add instructions
        VMACC, VMADD: for (int l = 0; l < 1; l++)
            result_o[64*l +: 64] = mul_res.w128[l][63:0] + opc.w64[l];
        VNMSAC, VNMSUB: for (int l = 0; l < 1; l++)
            result_o[64*l +: 64] = -mul_res.w128[l][63:0] + opc.w64[l];

        default: result_o = '0;
      endcase
    end
  end: gen_p_mul_ew64 else if (ElementWidth == EW32) begin: gen_p_mul_ew32
    for (genvar l = 0; l < 2; l++) begin: gen_mul
      assign mul_res.w64[l] = $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
    end: gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 2; l++)
            result_o[32*l +: 32] = mul_res.w64[l][31:0];
        VMULH, VMULHU, VMULHSU: for (int l = 0; l < 2; l++)
            result_o[32*l +: 32] = mul_res.w64[l][63:32];

        // Single-Width integer multiply-add instructions
        VMACC, VMADD: for (int l = 0; l < 2; l++)
            result_o[32*l +: 32] = mul_res.w64[l][31:0] + opc.w32[l];
        VNMSAC, VNMSUB: for (int l = 0; l < 2; l++)
            result_o[32*l +: 32] = -mul_res.w64[l][31:0] + opc.w32[l];

        default: result_o = '0;
      endcase
    end
  end: gen_p_mul_ew32 else if (ElementWidth == EW16) begin: gen_p_mul_ew16
    for (genvar l = 0; l < 4; l++) begin: gen_mul
      assign mul_res.w32[l] = $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l][15] & signed_b, opb.w16[l]});
    end: gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 4; l++)
            result_o[16*l +: 16] = mul_res.w32[l][15:0];
        VMULH, VMULHU, VMULHSU: for (int l = 0; l < 4; l++)
            result_o[16*l +: 16] = mul_res.w32[l][31:16];

        // Single-Width integer multiply-add instructions
        VMACC, VMADD: for (int l = 0; l < 4; l++)
            result_o[16*l +: 16] = mul_res.w32[l][15:0] + opc.w16[l];
        VNMSAC, VNMSUB: for (int l = 0; l < 4; l++)
            result_o[16*l +: 16] = -mul_res.w32[l][15:0] + opc.w16[l];

        default: result_o = '0;
      endcase
    end
  end: gen_p_mul_ew16 else if (ElementWidth == EW8) begin: gen_p_mul_ew8
    for (genvar l = 0; l < 8; l++) begin: gen_mul
      assign mul_res.w16[l] = $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
    end: gen_mul

    always_comb begin : p_mul
      unique case (op)
        // Single-Width integer multiply instructions
        VMUL: for (int l = 0; l < 8; l++)
            result_o[8*l +: 8] = mul_res.w16[l][7:0];
        VMULH, VMULHU, VMULHSU: for (int l = 0; l < 8; l++)
            result_o[8*l +: 8] = mul_res.w16[l][15:8];

        // Single-Width integer multiply-add instructions
        VMACC, VMADD: for (int l = 0; l < 8; l++)
            result_o[8*l +: 8] = mul_res.w16[l][7:0] + opc.w8[l];
        VNMSAC, VNMSUB: for (int l = 0; l < 8; l++)
            result_o[8*l +: 8] = -mul_res.w16[l][7:0] + opc.w8[l];

        default: result_o = '0;
      endcase
    end
  end: gen_p_mul_ew8 else begin: gen_p_mul_error
    $error("[simd_vmul] Invalid ElementWidth.");
  end: gen_p_mul_error

endmodule : simd_mul


/******************
 *  SIMD Divider  *
 *****************/

// Description:
// Ara's Serial Divider, operating on elements 64-bit wide.
// The unit serializes the whole computation, so it cannot parallelize sub-64-bit arithmetic.

module simd_div import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth   = $bits(elen_t),
    parameter int  unsigned StrbWidth   = DataWidth/8,
    parameter type          strb_t      = logic [DataWidth/8-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  strb_t   mask_i,
    input  ara_op_e op_i,
    input  strb_t   be_i,
    input  vew_e    vew_i,
    output elen_t   result_o,
    output strb_t   mask_o,
    input  logic    valid_i,
    output logic    ready_o,
    input  logic    ready_i,
    output logic    valid_o
  );

  /*****************
   *  Definitions  *
   *****************/

  // The input CU loads the number of elements to process into the issue counter and commit counter.
  // Then, it validates the inputs and waits until the last result is committed into the output
  // buffer, before returning IDLE
  typedef enum logic [2:0] {ISSUE_IDLE, LOAD, PROCESSING, ISSUE_SKIP, WAIT_DONE} issue_state_t;
  typedef enum logic [1:0] {COMMIT_IDLE, COMMIT_READY, COMMIT_SKIP, COMMIT_DONE} commit_state_t;

  issue_state_t  issue_state_d, issue_state_q;
  commit_state_t commit_state_d, commit_state_q;

  // Input registers, buffers for the input operands and information
  // Kept stable until the complete 64-bit result is formed
  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } operand_t;
  operand_t opa_d, opa_q, opb_d, opb_q, serdiv_result, serdiv_result_masked;
  vew_e     vew_d, vew_q;
  ara_op_e  op_d, op_q;
  strb_t    be_d, be_q;
  // Output buffer, directly linked to result_o
  elen_t result_d, result_q;
  assign result_o = result_q;
  // Mask buffer, directly linked to mask_o
  strb_t mask_d, mask_q;
  assign mask_o = mask_q;

  logic load_cnt, issue_cnt_en, commit_cnt_en;
  logic serdiv_out_ready, serdiv_out_valid, serdiv_in_valid, serdiv_in_ready;
  logic [2:0] cnt_init_val, issue_cnt_d, issue_cnt_q, commit_cnt_d, commit_cnt_q;

  elen_t opa_w8, opb_w8, opa_w16, opb_w16, opa_w32, opb_w32, opa_w64, opb_w64, serdiv_opa, serdiv_opb, shifted_result;

  logic [1:0] serdiv_opcode;

  /**********************
   *  In/Out registers  *
   **********************/

  // Input registers
  assign opa_d  = (valid_i && ready_o) ? operand_a_i : opa_q;
  assign opb_d  = (valid_i && ready_o) ? operand_b_i : opb_q;
  assign vew_d  = (valid_i && ready_o) ? vew_i       : vew_q;
  assign op_d   = (valid_i && ready_o) ? op_i        : op_q;
  assign be_d   = (valid_i && ready_o) ? be_i        : be_q;
  assign mask_d = (valid_i && ready_o) ? mask_i      : mask_q;

  /************
   *  Control  *
   ************/

  // Issue CU
  always_comb begin : issue_cu_p
    ready_o          = 1'b0;
    load_cnt         = 1'b0;
    serdiv_in_valid  = 1'b0;
    issue_cnt_en     = 1'b0;
    issue_state_d    = issue_state_q;

    case (issue_state_q)
      ISSUE_IDLE: begin
        // We can accept a new request from the external environment
        ready_o    = 1'b1;
        issue_state_d = valid_i ? LOAD : ISSUE_IDLE;
      end
      LOAD: begin
        // The request was accepted: load how many elements to process/commit
        load_cnt   = 1'b1;
        // Check if the next byte is valid or not. If not, skip it.
        issue_state_d = (be_q[cnt_init_val]) ? PROCESSING : ISSUE_SKIP;
      end
      PROCESSING: begin
        // The inputs are valid
        serdiv_in_valid = 1'b1;
        // Count down when these inputs are consumed by the serdiv
        issue_cnt_en    = (serdiv_in_valid && serdiv_in_ready) ? 1'b1 : 1'b0;
        // Change state only when the serdiv accepts the operands
        if (serdiv_in_valid && serdiv_in_ready) begin
          // If we are issuing the last operands, wait for the whole result to be completed
          if (issue_cnt_q == '0) begin
            issue_state_d = WAIT_DONE;
          // If we are not issuing the last operands, decide if to process or skip the next byte
          end else begin
            issue_state_d = (be_q[issue_cnt_d]) ? PROCESSING : ISSUE_SKIP;
          end
        end
      end
      ISSUE_SKIP: begin
        // Skip the invalid inputs
        issue_cnt_en  = 1'b1;
        // If we are issuing the last operands, wait for the whole result to be completed
        if (issue_cnt_q == '0) begin
          issue_state_d = WAIT_DONE;
        // If we are not issuing the last operands, decide if to process or skip the next byte
        end else begin
          issue_state_d = (be_q[issue_cnt_d]) ? PROCESSING : ISSUE_SKIP;
        end
      end
      WAIT_DONE: begin
        // Wait for the entire 64-bit result to be created
        // We need vew_q stable when serdiv_result is produced
        issue_state_d = valid_o ? ISSUE_IDLE : WAIT_DONE;
      end
      default: begin
        issue_state_d = ISSUE_IDLE;
      end
    endcase
  end

  // Commit CU
  always_comb begin : commit_cu_p
    valid_o          = 1'b0;
    serdiv_out_ready = 1'b0;
    commit_cnt_en    = 1'b0;
    commit_state_d      = commit_state_q;

  case (commit_state_q)
      COMMIT_IDLE: begin
        // Start if the issue CU has already started
        if (issue_state_q != ISSUE_IDLE) begin
          commit_state_d = (be_q[cnt_init_val]) ? COMMIT_READY : COMMIT_SKIP;
        end
      end
      COMMIT_READY: begin
        serdiv_out_ready = 1'b1;
        commit_cnt_en    = (serdiv_out_valid && serdiv_out_ready) ? 1'b1 : 1'b0;
        // Change state only when the serdiv produce a valid result
        if (serdiv_out_valid && serdiv_out_ready) begin
          // If we are committing the last result, complete the execution
          if (commit_cnt_q == '0) begin
            commit_state_d = COMMIT_DONE;
          // If we are not committing the last result, decide if to process or skip the next one
          end else begin
            commit_state_d = (be_q[commit_cnt_d]) ? COMMIT_READY : COMMIT_SKIP;
          end
        end
      end
      COMMIT_SKIP: begin
        serdiv_out_ready = 1'b1;
        commit_cnt_en    = 1'b1;
        // If we are skipping the last result, complete the execution
        if (commit_cnt_q == '0) begin
          commit_state_d = COMMIT_DONE;
        // If we are not committing the last result, decide if to process or skip the next one
        end else begin
          commit_state_d = (be_q[commit_cnt_d]) ? COMMIT_READY : COMMIT_SKIP;
        end
      end
      COMMIT_DONE: begin
        // The 64-bit result is complete, validate it
        valid_o     = 1'b1;
        commit_state_d = ready_i ? COMMIT_IDLE : COMMIT_DONE;
      end
      default: begin
        commit_state_d = COMMIT_IDLE;
      end
    endcase
  end

  // Counters
  // issue_cnt  counts how many elements should still be issued, and controls the first wall of MUXes
  // commit_cnt counts how many elements should still be committed
  always_comb begin
    issue_cnt_d  = issue_cnt_q;
    commit_cnt_d = commit_cnt_q;
    cnt_init_val = '0;

    // Track how many elements we should process (load #elements-1)
    case (vew_q)
      EW8:  cnt_init_val = 3'h7;
      EW16: cnt_init_val = 3'h3;
      EW32: cnt_init_val = 3'h1;
      EW64: cnt_init_val = 3'h0;
    endcase
    // Load the initial number of elements to process (i.e., also the number of results to collect)
    if (load_cnt) begin
      issue_cnt_d  = cnt_init_val;
      commit_cnt_d = cnt_init_val;
    end

    // Count down when serdiv accepts one couple of operands or when they are invalid
    if (issue_cnt_en)  issue_cnt_d  -= 1;
    // Count down when serdiv produce one result or when it is invalid
    if (commit_cnt_en) commit_cnt_d -= 1;
  end

  // Opcode selection
  always_comb begin
    case (op_q)
      VDIVU:   serdiv_opcode = 2'b00;
      VDIV:    serdiv_opcode = 2'b01;
      VREMU:   serdiv_opcode = 2'b10;
      VREM:    serdiv_opcode = 2'b11;
      default: serdiv_opcode = 2'b00;
    endcase
  end

  /**************
   *  Datapath  *
   **************/

  // serdiv input MUXes
  always_comb begin
    // First wall of MUXes: select one byte/halfword/word/dword from the inputs and fill it with zeroes/sign extend it
    opa_w8  = op_q inside {VDIV, VREM} ? {{56{opa_q.w8[issue_cnt_q[2:0]][7]  }}, opa_q.w8[issue_cnt_q[2:0]] } : {56'b0, opa_q.w8[issue_cnt_q[2:0]] };
    opb_w8  = op_q inside {VDIV, VREM} ? {{56{opb_q.w8[issue_cnt_q[2:0]][7]  }}, opb_q.w8[issue_cnt_q[2:0]] } : {56'b0, opb_q.w8[issue_cnt_q[2:0]] };
    opa_w16 = op_q inside {VDIV, VREM} ? {{48{opa_q.w16[issue_cnt_q[1:0]][15]}}, opa_q.w16[issue_cnt_q[1:0]]} : {48'b0, opa_q.w16[issue_cnt_q[1:0]]};
    opb_w16 = op_q inside {VDIV, VREM} ? {{48{opb_q.w16[issue_cnt_q[1:0]][15]}}, opb_q.w16[issue_cnt_q[1:0]]} : {48'b0, opb_q.w16[issue_cnt_q[1:0]]};
    opa_w32 = op_q inside {VDIV, VREM} ? {{32{opa_q.w32[issue_cnt_q[0]][31]  }}, opa_q.w32[issue_cnt_q[0]]  } : {32'b0, opa_q.w32[issue_cnt_q[0]]  };
    opb_w32 = op_q inside {VDIV, VREM} ? {{32{opb_q.w32[issue_cnt_q[0]][31]  }}, opb_q.w32[issue_cnt_q[0]]  } : {32'b0, opb_q.w32[issue_cnt_q[0]]  };
    opa_w64 = opa_q.w64;
    opb_w64 = opb_q.w64;

    // Last 64-bit wide selection MUX
    case (vew_q)
      EW8: begin
        serdiv_opa = opa_w8;
        serdiv_opb = opb_w8;
      end
      EW16: begin
        serdiv_opa = opa_w16;
        serdiv_opb = opb_w16;
      end
      EW32: begin
        serdiv_opa = opa_w32;
        serdiv_opb = opb_w32;
      end
      EW64: begin
        serdiv_opa = opa_w64;
        serdiv_opb = opb_w64;
      end
      default: begin
        serdiv_opa = opa_w64;
        serdiv_opb = opb_w64;
      end
    endcase
  end

  // Serial divider
  serdiv_mod #(
    .WIDTH(ELEN)
  ) i_serdiv_mod (
    .clk_i    (clk_i            ),
    .rst_ni   (rst_ni           ),
    .id_i     ('0               ),
    .op_a_i   (serdiv_opa       ),
    .op_b_i   (serdiv_opb       ),
    .opcode_i (serdiv_opcode    ),
    .in_vld_i (serdiv_in_valid  ),
    .in_rdy_o (serdiv_in_ready  ),
    .flush_i  (1'b0             ),
    .out_vld_o(serdiv_out_valid ),
    .out_rdy_i(serdiv_out_ready ),
    .id_o     (/* unconnected */),
    .res_o    (serdiv_result    )
  );

  // Output buffer
  // Shift the partial result and update the output buffer with the new masked byte/halfword/word
  // If we are skipping a byte, just shift
  always_comb begin
    if (commit_state_q == COMMIT_SKIP) begin
      shifted_result       = result_q << 8;
      serdiv_result_masked = '0;
    end else begin
      case (vew_q)
        EW8: begin
          shifted_result       = result_q << 8;
          serdiv_result_masked = {56'b0, serdiv_result.w8[0]};
        end
        EW16: begin
          shifted_result       = result_q << 16;
          serdiv_result_masked = {48'b0, serdiv_result.w16[0]};
        end
        EW32: begin
          shifted_result       = result_q << 32;
          serdiv_result_masked = {32'b0, serdiv_result.w32[0]};
        end
        default: begin
          shifted_result       = '0;
          serdiv_result_masked = serdiv_result;
        end
      endcase
    end
  end
  assign result_d = (commit_cnt_en) ? (shifted_result | serdiv_result_masked) : result_q;

  /****************************
   *  Sequential assignments  *
   ****************************/

  // In/Out CUs sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_state_q   <= ISSUE_IDLE;
      commit_state_q  <= COMMIT_IDLE;

      opa_q        <= '0;
      opb_q        <= '0;
      vew_q        <= EW8;
      op_q         <= VDIV;
      be_q         <= '0;
      mask_q       <= '0;
      result_q     <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      issue_state_q   <= issue_state_d;
      commit_state_q  <= commit_state_d;

      opa_q        <= opa_d;
      opb_q        <= opb_d;
      vew_q        <= vew_d;
      op_q         <= op_d;
      be_q         <= be_d;
      mask_q       <= mask_d;
      result_q     <= result_d;

      issue_cnt_q  <= issue_cnt_d;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : simd_div

// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
//         Andreas Traber    <traber@iis.ee.ethz.ch>, ETH Zurich
//
// Date: 18.10.2018
// Description: simple 64bit serial divider
// MODIFICATION: the ready is kept asserted during handshake

module serdiv_mod import ariane_pkg::*; #(
  parameter WIDTH       = 64
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,
  // input IF
  input  logic [TRANS_ID_BITS-1:0]  id_i,
  input  logic [WIDTH-1:0]          op_a_i,
  input  logic [WIDTH-1:0]          op_b_i,
  input  logic [1:0]                opcode_i, // 0: udiv, 2: urem, 1: div, 3: rem
  // handshake
  input  logic                      in_vld_i, // there is a cycle delay from in_rdy_o->in_vld_i, see issue_read_operands.sv stage
  output logic                      in_rdy_o,
  input  logic                      flush_i,
  // output IF
  output logic                      out_vld_o,
  input  logic                      out_rdy_i,
  output logic [TRANS_ID_BITS-1:0]  id_o,
  output logic [WIDTH-1:0]          res_o
);

/////////////////////////////////////
// signal declarations
/////////////////////////////////////

  enum logic [1:0] {IDLE, DIVIDE, FINISH} state_d, state_q;

  logic [WIDTH-1:0]       res_q, res_d;
  logic [WIDTH-1:0]       op_a_q, op_a_d;
  logic [WIDTH-1:0]       op_b_q, op_b_d;
  logic                   op_a_sign, op_b_sign;
  logic                   op_b_zero, op_b_zero_q, op_b_zero_d;

  logic [TRANS_ID_BITS-1:0] id_q, id_d;

  logic rem_sel_d, rem_sel_q;
  logic comp_inv_d, comp_inv_q;
  logic res_inv_d, res_inv_q;

  logic [WIDTH-1:0] add_mux;
  logic [WIDTH-1:0] add_out;
  logic [WIDTH-1:0] add_tmp;
  logic [WIDTH-1:0] b_mux;
  logic [WIDTH-1:0] out_mux;

  logic [$clog2(WIDTH+1)-1:0] cnt_q, cnt_d;
  logic cnt_zero;

  logic [WIDTH-1:0] lzc_a_input, lzc_b_input, op_b;
  logic [$clog2(WIDTH)-1:0] lzc_a_result, lzc_b_result;
  logic [$clog2(WIDTH+1)-1:0] shift_a;
  logic [$clog2(WIDTH+1):0] div_shift;

  logic a_reg_en, b_reg_en, res_reg_en, ab_comp, pm_sel, load_en;
  logic lzc_a_no_one, lzc_b_no_one;
  logic div_res_zero_d, div_res_zero_q;


/////////////////////////////////////
// align the input operands
// for faster division
/////////////////////////////////////

  assign op_b_zero = (op_b_i == 0);
  assign op_a_sign = op_a_i[$high(op_a_i)];
  assign op_b_sign = op_b_i[$high(op_b_i)];

  assign lzc_a_input = (opcode_i[0] & op_a_sign) ? {~op_a_i, 1'b0} : op_a_i;
  assign lzc_b_input = (opcode_i[0] & op_b_sign) ? ~op_b_i         : op_b_i;

  lzc #(
    .MODE    ( 1          ), // count leading zeros
    .WIDTH   ( WIDTH      )
  ) i_lzc_a (
    .in_i    ( lzc_a_input  ),
    .cnt_o   ( lzc_a_result ),
    .empty_o ( lzc_a_no_one )
  );

  lzc #(
    .MODE    ( 1          ), // count leading zeros
    .WIDTH   ( WIDTH      )
  ) i_lzc_b (
    .in_i    ( lzc_b_input  ),
    .cnt_o   ( lzc_b_result ),
    .empty_o ( lzc_b_no_one )
  );

  assign shift_a      = (lzc_a_no_one) ? WIDTH : lzc_a_result;
  assign div_shift    = (lzc_b_no_one) ? WIDTH : lzc_b_result-shift_a;

  assign op_b         = op_b_i <<< $unsigned(div_shift);

  // the division is zero if |opB| > |opA| and can be terminated
  assign div_res_zero_d = (load_en) ? ($signed(div_shift) < 0) : div_res_zero_q;

/////////////////////////////////////
// Datapath
/////////////////////////////////////

  assign pm_sel      = load_en & ~(opcode_i[0] & (op_a_sign ^ op_b_sign));

  // muxes
  assign add_mux     = (load_en)   ? op_a_i  : op_b_q;

  // attention: logical shift by one in case of negative operand B!
  assign b_mux       = (load_en)   ? op_b : {comp_inv_q, (op_b_q[$high(op_b_q):1])};

  // in case of bad timing, we could output from regs -> needs a cycle more in the FSM
  assign out_mux     = (rem_sel_q) ? op_a_q : res_q;
  // assign out_mux     = (rem_sel_q) ? op_a_d : res_d;

  // invert if necessary
  assign res_o       = (res_inv_q) ? -$signed(out_mux) : out_mux;

  // main comparator
  assign ab_comp     = ((op_a_q == op_b_q) | ((op_a_q > op_b_q) ^ comp_inv_q)) & ((|op_a_q) | op_b_zero_q);

  // main adder
  assign add_tmp     = (load_en) ? 0 : op_a_q;
  assign add_out     = (pm_sel)  ? add_tmp + add_mux : add_tmp - $signed(add_mux);

/////////////////////////////////////
// FSM, counter
/////////////////////////////////////

  assign cnt_zero = (cnt_q == 0);
  assign cnt_d    = (load_en)   ? div_shift  :
                    (~cnt_zero) ? cnt_q - 1  : cnt_q;

  always_comb begin : p_fsm
    // default
    state_d        = state_q;
    in_rdy_o       = 1'b0;
    out_vld_o      = 1'b0;
    load_en        = 1'b0;
    a_reg_en       = 1'b0;
    b_reg_en       = 1'b0;
    res_reg_en     = 1'b0;

    unique case (state_q)
      IDLE: begin
        in_rdy_o    = 1'b1;

        if (in_vld_i) begin
//          in_rdy_o  = 1'b0;// there is a cycle delay until the valid signal is asserted by the id stage
          a_reg_en  = 1'b1;
          b_reg_en  = 1'b1;
          load_en   = 1'b1;
          state_d   = DIVIDE;
        end
      end
      DIVIDE: begin
        if(~div_res_zero_q) begin
          a_reg_en     = ab_comp;
          b_reg_en     = 1'b1;
          res_reg_en   = 1'b1;
        end
        // can end the division now if the result is clearly 0
        if(div_res_zero_q) begin
          out_vld_o = 1'b1;
          state_d   = FINISH;
          if(out_rdy_i) begin
            // in_rdy_o = 1'b1;// there is a cycle delay until the valid signal is asserted by the id stage
            state_d  = IDLE;
          end
        end else if (cnt_zero) begin
          state_d   = FINISH;
        end
      end
      FINISH: begin
        out_vld_o = 1'b1;

        if (out_rdy_i) begin
          // in_rdy_o = 1'b1;// there is a cycle delay until the valid signal is asserted by the id stage
          state_d  = IDLE;
        end
      end
      default : state_d = IDLE;
    endcase

    if (flush_i) begin
        in_rdy_o   = 1'b0;
        out_vld_o  = 1'b0;
        a_reg_en   = 1'b0;
        b_reg_en   = 1'b0;
        load_en    = 1'b0;
        state_d    = IDLE;
    end
  end

/////////////////////////////////////
// regs, flags
/////////////////////////////////////

  // get flags
  assign rem_sel_d    = (load_en) ? opcode_i[1]               : rem_sel_q;
  assign comp_inv_d   = (load_en) ? opcode_i[0] & op_b_sign   : comp_inv_q;
  assign op_b_zero_d  = (load_en) ? op_b_zero                 : op_b_zero_q;
  assign res_inv_d    = (load_en) ? (~op_b_zero | opcode_i[1]) & opcode_i[0] & (op_a_sign ^ op_b_sign) : res_inv_q;

  // transaction id
  assign id_d = (load_en) ? id_i : id_q;
  assign id_o = id_q;

  assign op_a_d   = (a_reg_en)   ? add_out : op_a_q;
  assign op_b_d   = (b_reg_en)   ? b_mux   : op_b_q;
  assign res_d    = (load_en)   ? '0       :
                    (res_reg_en) ? {res_q[$high(res_q)-1:0], ab_comp} : res_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (~rst_ni) begin
      state_q        <= IDLE;
      op_a_q         <= '0;
      op_b_q         <= '0;
      res_q          <= '0;
      cnt_q          <= '0;
      id_q           <= '0;
      rem_sel_q      <= 1'b0;
      comp_inv_q     <= 1'b0;
      res_inv_q      <= 1'b0;
      op_b_zero_q    <= 1'b0;
      div_res_zero_q <= 1'b0;
    end else begin
      state_q        <= state_d;
      op_a_q         <= op_a_d;
      op_b_q         <= op_b_d;
      res_q          <= res_d;
      cnt_q          <= cnt_d;
      id_q           <= id_d;
      rem_sel_q      <= rem_sel_d;
      comp_inv_q     <= comp_inv_d;
      res_inv_q      <= res_inv_d;
      op_b_zero_q    <= op_b_zero_d;
      div_res_zero_q <= div_res_zero_d;
    end
  end

endmodule
