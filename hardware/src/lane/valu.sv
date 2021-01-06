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
// File:    valu.sv
// Author:  Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created: 04.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is Ara's vector ALU. It is capable of executing integer operations
// in a SIMD fashion, always operating on 64 bits.

module valu import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes   = 0,
    // Type used to address vector register file elements
    parameter type          vaddr_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter int  unsigned StrbWidth = DataWidth/8,
    parameter type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Interface with the lane sequencer
    input  vfu_operation_t               vfu_operation_i,
    input  logic                         vfu_operation_valid_i,
    output logic                         alu_ready_o,
    output logic           [NrVInsn-1:0] alu_vinsn_done_o,
    // Interface with the operand queues
    input  elen_t          [1:0]         alu_operand_i,
    input  logic           [1:0]         alu_operand_valid_i,
    output logic           [1:0]         alu_operand_ready_o,
    // Interface with the vector register file
    output logic                         alu_result_req_o,
    output vid_t                         alu_result_id_o,
    output vaddr_t                       alu_result_addr_o,
    output elen_t                        alu_result_wdata_o,
    output strb_t                        alu_result_be_o,
    input  logic                         alu_result_gnt_i,
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
    // - Being issued (i.e., its micro-operations are currently being issued
    //   to the corresponding functional units).
    // - Being committed (i.e., its results are being written to the vector
    //   register file).
    // We need pointers to index which instruction is at each execution phase
    // between the VInsnQueueDepth instructions in memory.
    logic [idx_width(VInsnQueueDepth)-1:0] accept_pnt;
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

  /*********************
   *  SIMD Vector ALU  *
   *********************/

  elen_t valu_result;

  simd_valu i_simd_valu (
    .operand_a_i(vinsn_issue.use_scalar_op ? scalar_op : alu_operand_i[0]),
    .operand_b_i(alu_operand_i[1]                                        ),
    .op_i       (vinsn_issue.op                                          ),
    .vew_i      (vinsn_issue.vtype.vsew                                  ),
    .result_o   (valu_result                                             )
  );

  /*************
   *  Control  *
   *************/

  // Remaining elements of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining elements of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  always_comb begin: p_valu
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    issue_cnt_d   = issue_cnt_q;
    commit_cnt_d  = commit_cnt_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    // Inform our status to the lane controller
    alu_ready_o      = !vinsn_queue_full;
    alu_vinsn_done_o = '0;

    // Do not acknowledge any operands
    alu_operand_ready_o = '0;
    mask_ready_o        = '0;

    /**************************************
     *  Write data into the result queue  *
     **************************************/

    // There is a vector instruction ready to be issued
    if (vinsn_issue_valid && !result_queue_full) begin
      // Do we have all the operands necessary for this instruction?
      if ((alu_operand_valid_i[1] || !vinsn_issue.use_vs2) && (alu_operand_valid_i[0] || !vinsn_issue.use_vs1) && (mask_valid_i || vinsn_issue.vm)) begin
        // How many elements are we committing with this word?
        automatic logic [3:0] element_cnt = (1 << (int'(EW64) - int'(vinsn_issue.vtype.vsew)));
        if (element_cnt > issue_cnt_q)
          element_cnt = issue_cnt_q;

        // Acknowledge the operands of this instruction
        alu_operand_ready_o = {vinsn_issue.use_vs2, vinsn_issue.use_vs1};
        mask_ready_o        = !vinsn_issue.vm;

        // Store the result in the result queue
        result_queue_d[result_queue_write_pnt_q] = '{
          wdata: valu_result,
          be   : be(element_cnt, vinsn_issue.vtype.vsew) & (vinsn_issue.vm ? {StrbWidth{1'b1}} : mask_i),
          addr : vaddr(vinsn_issue.vd, NrLanes) + ((vinsn_issue.vl - issue_cnt_q) >> (int'(EW64) - vinsn_issue.vtype.vsew)),
          id   : vinsn_issue.id
        };
        result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

        // Bump pointers and counters of the result queue
        result_queue_cnt_d += 1;
        if (result_queue_write_pnt_q == ResultQueueDepth-1)
          result_queue_write_pnt_d = 0;
        else
          result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
        issue_cnt_d = issue_cnt_q - element_cnt;

        // Finished issuing the micro-operations of this vector instruction
        if (vinsn_issue_valid && issue_cnt_d == '0) begin
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

    /********************************
     *  Write results into the VRF  *
     ********************************/

    alu_result_req_o   = result_queue_valid_q[result_queue_read_pnt_q];
    alu_result_addr_o  = result_queue_q[result_queue_read_pnt_q].addr;
    alu_result_id_o    = result_queue_q[result_queue_read_pnt_q].id;
    alu_result_wdata_o = result_queue_q[result_queue_read_pnt_q].wdata;
    alu_result_be_o    = result_queue_q[result_queue_read_pnt_q].be;

    // Received a grant from the VRF.
    // Deactivate the request.
    if (alu_result_gnt_i) begin
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
      commit_cnt_d = commit_cnt_q - (1 << (int'(EW64) - vinsn_commit.vtype.vsew));
      if (commit_cnt_q < (1 << (int'(EW64) - vinsn_commit.vtype.vsew)))
        commit_cnt_d = '0;
    end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && commit_cnt_d == '0) begin
      // Mark the vector instruction as being done
      alu_vinsn_done_o[vinsn_commit.id] = 1'b1;

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

    if (!vinsn_queue_full && vfu_operation_valid_i && vfu_operation_i.vfu == VFU_Alu) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = vfu_operation_i;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0)
        issue_cnt_d = vfu_operation_i.vl;
      if (vinsn_queue_d.commit_cnt == '0)
        commit_cnt_d = vfu_operation_i.vl;

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end: p_valu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      issue_cnt_q  <= issue_cnt_d;
      commit_cnt_q <= commit_cnt_d;
    end
  end

endmodule : valu


/***************
 *  SIMD VALU  *
 ***************/

// Description:
// Ara's SIMD ALU, operating on elements 64-bit wide, and generating 64 bits per cycle.

module simd_valu import ara_pkg::*; import rvv_pkg::*; (
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  ara_op_e op_i,
    input  vew_e    vew_i,
    output elen_t   result_o
  );

  /*****************
   *  Definitions  *
   *****************/

  localparam DataWidth = $bits(elen_t);

  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } alu_operand_t;

  alu_operand_t opa, opb, res;
  assign opa      = operand_a_i;
  assign opb      = operand_b_i;
  assign result_o = res;

  /*****************
   *  Comparisons  *
   *****************/

  // Comparison instructions that use signed operands
  logic is_signed;
  assign is_signed = op_i inside {VMAX, VMIN};
  // Compare operands.
  // For vew_i = EW8, all bits are valid.
  // For vew_i = EW16, bits 0, 2, 4, and 6 are valid.
  // For vew_i = EW32, bits 0 and 4 are valid.
  // For vew_i = EW64, only bit 0 indicates the result of the comparison.
  logic [7:0] less;

  always_comb begin: p_comparison
    // Default assignment
    less = '0;

    unique case (vew_i)
      EW8 : for (int b = 0; b < 8; b++) less[1*b] = $signed({is_signed & opa.w8 [b][ 7], opa.w8 [b]}) < $signed({is_signed & opb.w8 [b][ 7], opb.w8 [b]});
      EW16: for (int b = 0; b < 4; b++) less[2*b] = $signed({is_signed & opa.w16[b][15], opa.w16[b]}) < $signed({is_signed & opb.w16[b][15], opb.w16[b]});
      EW32: for (int b = 0; b < 2; b++) less[4*b] = $signed({is_signed & opa.w32[b][31], opa.w32[b]}) < $signed({is_signed & opb.w32[b][31], opb.w32[b]});
      EW64: for (int b = 0; b < 1; b++) less[8*b] = $signed({is_signed & opa.w64[b][63], opa.w64[b]}) < $signed({is_signed & opb.w64[b][63], opb.w64[b]});
    endcase
  end: p_comparison

  /*********
   *  ALU  *
   *********/

  always_comb begin: p_alu
    // Default assignment
    res = '0;

    case (op_i)
      // Logical operations
      VAND: res = operand_a_i & operand_b_i;
      VOR : res = operand_a_i | operand_b_i;
      VXOR: res = operand_a_i ^ operand_b_i;

      // Arithmetic instructions
      VADD: unique case (vew_i)
          EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opa.w8 [b] + opb.w8 [b];
          EW16: for (int b = 0; b < 4; b++) res.w16[b] = opa.w16[b] + opb.w16[b];
          EW32: for (int b = 0; b < 2; b++) res.w32[b] = opa.w32[b] + opb.w32[b];
          EW64: for (int b = 0; b < 1; b++) res.w64[b] = opa.w64[b] + opb.w64[b];
        endcase
      VSUB: unique case (vew_i)
          EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] - opa.w8 [b];
          EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] - opa.w16[b];
          EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] - opa.w32[b];
          EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] - opa.w64[b];
        endcase
      VRSUB: unique case (vew_i)
          EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opa.w8 [b] - opb.w8 [b];
          EW16: for (int b = 0; b < 4; b++) res.w16[b] = opa.w16[b] - opb.w16[b];
          EW32: for (int b = 0; b < 2; b++) res.w32[b] = opa.w32[b] - opb.w32[b];
          EW64: for (int b = 0; b < 1; b++) res.w64[b] = opa.w64[b] - opb.w64[b];
        endcase

      // Shift instructions
      VSLL: unique case (vew_i)
          EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] << opa.w8 [b][2:0];
          EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] << opa.w16[b][3:0];
          EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] << opa.w32[b][4:0];
          EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] << opa.w64[b][5:0];
        endcase

      // Comparison instructions
      VMIN, VMINU, VMAX, VMAXU: unique case (vew_i)
          EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = (less[1*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opa.w8 [b] : opb.w8 [b];
          EW16: for (int b = 0; b < 4; b++) res.w16[b] = (less[2*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opa.w16[b] : opb.w16[b];
          EW32: for (int b = 0; b < 2; b++) res.w32[b] = (less[4*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opa.w32[b] : opb.w32[b];
          EW64: for (int b = 0; b < 1; b++) res.w64[b] = (less[8*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opa.w64[b] : opb.w64[b];
        endcase
    endcase
  end: p_alu

  /****************
   *  Assertions  *
   ****************/

  if (DataWidth != $bits(alu_operand_t))
    $error("[simd_valu] The SIMD vector ALU only works for a datapath 64-bit wide.");

endmodule : simd_valu
