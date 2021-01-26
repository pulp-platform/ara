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
  logic           vinsn_processing_valid;
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
    endcase
  end

  /****************
   *  Multiplier  *
   ****************/

  elen_t vmul_result;

  logic vmul_in_valid;
  logic vmul_out_valid;
  logic vmul_in_ready;
  logic vmul_out_ready;

  // We let the mask percolate throughout the pipeline to have the mask unit synchronized with the operand queues
  // Another choice would be to delay the mask grant when the vmul_result is committed
  strb_t vmul_mask;

  simd_mul #(
    .NumPipeRegs(LatMultiplier)
  ) i_simd_mul (
    .clk_i      (clk_i                                                    ),
    .rst_ni     (rst_ni                                                   ),
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : mfpu_operand_i[0]),
    .operand_b_i(mfpu_operand_i[1]                                        ),
    .operand_c_i(mfpu_operand_i[2]                                        ),
    .mask_i     (mask_i                                                   ),
    .op_i       (vinsn_issue.op                                           ),
    .vew_i      (vinsn_issue.vtype.vsew                                   ),
    .result_o   (vmul_result                                              ),
    .mask_o     (vmul_mask                                                ),
    .valid_i    (vmul_in_valid                                            ),
    .ready_o    (vmul_in_ready                                            ),
    .ready_i    (vmul_out_ready                                           ),
    .valid_o    (vmul_out_valid                                           )
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

    // vmul input not valid by default
    vmul_in_valid = 1'b0;

    // Mask not granted by default
    mask_ready_o = 1'b0;

    /***************************************
     *  Issue the instruction to the unit  *
     **************************************/

    // There is a vector instruction ready to be issued
    if (vinsn_issue_valid) begin
      // Do we have all the operands necessary for this instruction?
      if ((mfpu_operand_valid_i[2] || !vinsn_issue.use_vd_op) && (mfpu_operand_valid_i[1] || !vinsn_issue.use_vs2) && (mfpu_operand_valid_i[0] || !vinsn_issue.use_vs1) && (mask_valid_i || vinsn_issue.vm)) begin
        // Validate multiplier inputs
        vmul_in_valid = 1'b1;

        // Is the multiplier ready?
        if (vmul_in_ready) begin
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
          end
          // Finished issuing the micro-operations of this vector instruction
          if (issue_cnt_d == '0) begin
            // Bump issue counter and pointers
            vinsn_queue_d.issue_cnt -= 1;
            if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1)
              vinsn_queue_d.issue_pnt = '0;
            else
              vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

            if (vinsn_queue_d.issue_pnt != 0)
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

    // Check if we have a valid result and we can add it to the result queue
    if (vmul_out_valid && !result_queue_full) begin
      // How many elements have we processed?
      automatic logic [3:0] processed_element_cnt    = (1 << (int'(EW64) - int'(vinsn_processing.vtype.vsew)));
      // Store the result in the result queue
      result_queue_d[result_queue_write_pnt_q].id    = vinsn_processing.id;
      result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_processing.vd, NrLanes) + ((vinsn_processing.vl - to_process_cnt_q) >> (int'(EW64) - vinsn_processing.vtype.vsew));
      result_queue_d[result_queue_write_pnt_q].wdata = vmul_result;
      result_queue_d[result_queue_write_pnt_q].be    = be(processed_element_cnt, vinsn_processing.vtype.vsew) & (vinsn_processing.vm ? {StrbWidth{1'b1}} : vmul_mask);
      result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

      // Update the number of elements still to be processed
      if (processed_element_cnt > to_process_cnt_q)
        processed_element_cnt = to_process_cnt_q;
      to_process_cnt_d = to_process_cnt_q - processed_element_cnt;

      // Finished issuing the micro-operations of this vector instruction
      if (to_process_cnt_d == '0) begin
        // Bump issue processing pointers
        if (vinsn_queue_q.processing_pnt == VInsnQueueDepth-1)
          vinsn_queue_d.processing_pnt = '0;
        else
          vinsn_queue_d.processing_pnt = vinsn_queue_q.processing_pnt + 1;

        if (vinsn_queue_d.processing_pnt != 0)
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
      if (vinsn_queue_d.issue_cnt == '0) begin
        issue_cnt_d = vfu_operation_i.vl;
        to_process_cnt_d = vfu_operation_i.vl;
      end
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = vfu_operation_i.vl;

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
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
    parameter int  unsigned NumPipeRegs = 0,
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth   = $bits(elen_t),
    parameter int  unsigned StrbWidth   = DataWidth/8,
    parameter type          strb_t      = logic [DataWidth/8-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  elen_t   operand_c_i,
    input  strb_t   mask_i,
    input  ara_op_e op_i,
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

  `include "common_cells/registers.svh"

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } mul_operand_t;

  typedef union packed {
    logic [0:0][127:0] w128;
    logic [1:0][63:0] w64;
    logic [3:0][31:0] w32;
    logic [7:0][15:0] w16;
  } mul_wide_result_t;

  mul_operand_t     opa, opb, opc, res;
  mul_wide_result_t mul_wide_res;
  assign opa = operand_a_i;
  assign opb = operand_b_i;
  assign opc = operand_c_i;

  /****************
   *  Multiplier  *
   ****************/

  logic signed_a, signed_b;

  // Sign select MUX
  assign signed_a = op_i inside {VMULH};
  assign signed_b = op_i inside {VMULH, VMULHSU};

  always_comb begin : p_mul
    // Default assignments
    mul_wide_res = '0;
    res          = '0;

    case (op_i)
      // Single-Width integer multiply instructions
      VMUL: unique case (vew_i)
          EW8: for (int l = 0; l < 8; l++) begin
              mul_wide_res.w16[l] = $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
              res.w8[l]           = mul_wide_res.w16[l][7:0];
            end
          EW16: for (int l = 0; l < 4; l++) begin
              mul_wide_res.w32[l] = $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l][15] & signed_b, opb.w16[l]});
              res.w16[l]          = mul_wide_res.w32[l][15:0];
            end
          EW32: for (int l = 0; l < 2; l++) begin
              mul_wide_res.w64[l] = $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
              res.w32[l]          = mul_wide_res.w64[l][31:0];
            end
          EW64: for (int l = 0; l < 1; l++) begin
              mul_wide_res.w128[l] = $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
              res.w64[l]           = mul_wide_res.w128[l][63:0];
            end
        endcase

      VMULH,
      VMULHU,
      VMULHSU: unique case (vew_i)
          EW8: for (int l = 0; l < 8; l++) begin
              mul_wide_res.w16[l] = $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
              res.w8[l]           = mul_wide_res.w16[l][15:8];
            end
          EW16: for (int l = 0; l < 4; l++) begin
              mul_wide_res.w32[l] = $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l][15] & signed_b, opb.w16[l]});
              res.w16[l]          = mul_wide_res.w32[l][31:16];
            end
          EW32: for (int l = 0; l < 2; l++) begin
              mul_wide_res.w64[l] = $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
              res.w32[l]          = mul_wide_res.w64[l][63:32];
            end
          EW64: for (int l = 0; l < 1; l++) begin
              mul_wide_res.w128[l] = $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
              res.w64[l]           = mul_wide_res.w128[l][127:64];
            end
        endcase

      // Single-Width integer multiply-add instructions
      VMACC,
      VMADD: unique case (vew_i)
          EW8: for (int l = 0; l < 8; l++) begin
              mul_wide_res.w16[l] = $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
              res.w8[l]           = mul_wide_res.w16[l][7:0] + opc.w8[l];
            end
          EW16: for (int l = 0; l < 4; l++) begin
              mul_wide_res.w32[l] = $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l][15] & signed_b, opb.w16[l]});
              res.w16[l]          = mul_wide_res.w32[l][15:0] + opc.w16[l];
            end
          EW32: for (int l = 0; l < 2; l++) begin
              mul_wide_res.w64[l] = $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
              res.w32[l]          = mul_wide_res.w64[l][31:0] + opc.w32[l];
            end
          EW64: for (int l = 0; l < 1; l++) begin
              mul_wide_res.w128[l] = $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
              res.w64[l]           = mul_wide_res.w128[l][63:0] + opc.w64[l];
            end
        endcase

      VNMSAC,
      VNMSUB: unique case (vew_i)
          EW8: for (int l = 0; l < 8; l++) begin
              mul_wide_res.w16[l] = $signed({opa.w8[l][7] & signed_a, opa.w8[l]}) * $signed({opb.w8[l][7] & signed_b, opb.w8[l]});
              res.w8[l]           = -mul_wide_res.w16[l][7:0] + opc.w8[l];
            end
          EW16: for (int l = 0; l < 4; l++) begin
              mul_wide_res.w32[l] = $signed({opa.w16[l][15] & signed_a, opa.w16[l]}) * $signed({opb.w16[l][15] & signed_b, opb.w16[l]});
              res.w16[l]          = -mul_wide_res.w32[l][15:0] + opc.w16[l];
            end
          EW32: for (int l = 0; l < 2; l++) begin
              mul_wide_res.w64[l] = $signed({opa.w32[l][31] & signed_a, opa.w32[l]}) * $signed({opb.w32[l][31] & signed_b, opb.w32[l]});
              res.w32[l]          = -mul_wide_res.w64[l][31:0] + opc.w32[l];
            end
          EW64: for (int l = 0; l < 1; l++) begin
              mul_wide_res.w128[l] = $signed({opa.w64[l][63] & signed_a, opa.w64[l]}) * $signed({opb.w64[l][63] & signed_b, opb.w64[l]});
              res.w64[l]           = -mul_wide_res.w128[l][63:0] + opc.w64[l];
            end
        endcase
    endcase
  end

  /*********************
   *  Pipeline stages  *
   *********************/

  // Input signals for the next stage (= output signals of the previous stage)
  logic  [NumPipeRegs:0][63:0] result_d;
  strb_t [NumPipeRegs:0]       mask_d;
  logic  [NumPipeRegs:0]       valid_d;
  // Ready signal is combinatorial for all stages
  logic  [NumPipeRegs:0]       stage_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign result_d[0] = res;
  assign mask_d[0]   = mask_i;
  assign valid_d[0]  = valid_i;

  // Generate the pipeline stages in case they are needed
  if (NumPipeRegs > 0) begin : gen_pipeline
    // Pipelined versions of signals for later stages
    logic  [NumPipeRegs-1:0][63:0] result_q;
    logic  [NumPipeRegs-1:0][7:0]  operand_m_q;
    strb_t [NumPipeRegs-1:0]       mask_q;
    logic  [NumPipeRegs-1:0]       valid_q;

    for (genvar i = 0; i < NumPipeRegs; i++) begin : pipeline_stages
      // Next state from previous register to form a shift register
      assign result_d[i+1] = result_q[i];
      assign mask_d[i+1]   = mask_q[i];
      assign valid_d[i+1]  = valid_q[i];

      // Determine the ready signal of the current stage - advance the pipeline:
      // 1. if the next stage is ready for our data
      // 2. if the next stage register only holds a bubble (not valid) -> we can pop it
      assign stage_ready[i] = stage_ready[i+1] | ~valid_q[i];

      // Enable register if pipleine ready
      logic reg_ena;
      assign reg_ena = stage_ready[i];

      // Generate the pipeline
      `FFL(valid_q[i], valid_d[i], reg_ena, '0)
      `FFL(result_q[i], result_d[i], reg_ena, '0)
      `FFL(mask_q[i], mask_d[i], reg_ena, '0)
    end
  end

  // Input stage: Propagate ready signal from pipeline
  assign ready_o = stage_ready[0];

  // Output stage: bind last stage outputs to module output. Directly connects to input if no regs.
  assign result_o = result_d[NumPipeRegs];
  assign mask_o   = mask_d[NumPipeRegs];
  assign valid_o  = valid_d[NumPipeRegs];

  // Output stage: Ready travels backwards from output side
  assign stage_ready[NumPipeRegs] = ready_i;

endmodule : simd_mul
