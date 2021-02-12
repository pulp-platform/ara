// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author:  Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
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
    output elen_t                        mask_operand_o,
    output logic                         mask_operand_valid_o,
    input  logic                         mask_operand_ready_i,
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

  // Is the vector instruction queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  vfu_operation_t vinsn_issue_d, vinsn_issue_q;
  logic           vinsn_issue_valid;
  assign vinsn_issue_d     = vinsn_queue_d.vinsn[vinsn_queue_d.issue_pnt];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

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

  /*******************
   *  Mask operands  *
   *******************/

  assign mask_operand_o       = result_queue_q[result_queue_read_pnt_q].wdata;
  assign mask_operand_valid_o = result_queue_q[result_queue_read_pnt_q].mask && result_queue_valid_q[result_queue_read_pnt_q];

  /********************
   *  Scalar operand  *
   ********************/

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

  /****************************
   *  Narrowing instructions  *
   ****************************/

  // This function returns 1'b1 if `op` is a narrowing instruction, i.e.,
  // it produces only EEW/2 per cycle.
  function automatic logic narrowing(ara_op_e op);
    narrowing = 1'b0;
    if (op inside {VNSRA, VNSRL})
      narrowing = 1'b1;
  endfunction: narrowing

  // If this is a narrowing instruction, point to which half of the
  // output EEW word we are producing.
  logic narrowing_select_d, narrowing_select_q;

  /*********************
   *  SIMD Vector ALU  *
   *********************/

  elen_t valu_result;
  logic  valu_valid;

  simd_valu i_simd_valu (
    .operand_a_i       (vinsn_issue_q.use_scalar_op ? scalar_op : alu_operand_i[0]    ),
    .operand_b_i       (alu_operand_i[1]                                              ),
    .valid_i           (valu_valid                                                    ),
    .vm_i              (vinsn_issue_q.vm                                              ),
    .mask_i            (mask_valid_i && !vinsn_issue_q.vm ? mask_i : {StrbWidth{1'b1}}),
    .narrowing_select_i(narrowing_select_q                                            ),
    .op_i              (vinsn_issue_q.op                                              ),
    .vew_i             (vinsn_issue_q.vtype.vsew                                      ),
    .result_o          (valu_result                                                   )
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

    narrowing_select_d = narrowing_select_q;

    // Do not issue any operations
    valu_valid = 1'b0;

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
      if ((alu_operand_valid_i[1] || !vinsn_issue_q.use_vs2) && (alu_operand_valid_i[0] || !vinsn_issue_q.use_vs1) && (mask_valid_i || vinsn_issue_q.vm || vinsn_issue_q.vfu == VFU_MaskUnit)) begin
        // How many elements are we committing with this word?
        automatic logic [3:0] element_cnt = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
        if (element_cnt > issue_cnt_q)
          element_cnt = issue_cnt_q;

        // Issue the operation
        valu_valid = 1'b1;

        // Acknowledge the operands of this instruction
        alu_operand_ready_o = {vinsn_issue_q.use_vs2, vinsn_issue_q.use_vs1};
        // Narrowing instructions might need an extra cycle before acknowledging the mask operands
        // If the results are being sent to the Mask Unit, it is up to it to acknowledge the operands.
        if (!narrowing(vinsn_issue_q.op) && vinsn_issue_q != VFU_MaskUnit)
          mask_ready_o = !vinsn_issue_q.vm;

        // Store the result in the result queue
        result_queue_d[result_queue_write_pnt_q].wdata = result_queue_q[result_queue_write_pnt_q].wdata | valu_result;
        result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_issue_q.vd, NrLanes) + ((vinsn_issue_q.vl - issue_cnt_q) >> (int'(EW64) - vinsn_issue_q.vtype.vsew));
        result_queue_d[result_queue_write_pnt_q].id    = vinsn_issue_q.id;
        result_queue_d[result_queue_write_pnt_q].mask  = vinsn_issue_q.vfu == VFU_MaskUnit;
        if (!narrowing(vinsn_issue_q.op) || !narrowing_select_q)
          result_queue_d[result_queue_write_pnt_q].be = be(element_cnt, vinsn_issue_q.vtype.vsew) & (vinsn_issue_q.vm || vinsn_issue_q.op inside {VMERGE, VADC, VSBC} ? {StrbWidth{1'b1}} : mask_i);

        // Is this a narrowing instruction?
        if (narrowing(vinsn_issue_q.op)) begin
          // How many elements did we calculate in this iteration?
          automatic logic [3:0] element_cnt_narrow = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew))) / 2;
          if (element_cnt_narrow > issue_cnt_q)
            element_cnt_narrow = issue_cnt_q;

          // Account for the issued operands
          issue_cnt_d = issue_cnt_q - element_cnt_narrow;

          // Write the next half of the results in the next cycle.
          narrowing_select_d = !narrowing_select_q;

          // Did we fill up a word?
          if (issue_cnt_d == '0 || !narrowing_select_d) begin
            result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;

            // Acknowledge the mask operand, if needed
            if (vinsn_issue_q != VFU_MaskUnit)
              mask_ready_o = !vinsn_issue_q.vm;

            // Bump pointers and counters of the result queue
            result_queue_cnt_d += 1;
            if (result_queue_write_pnt_q == ResultQueueDepth-1)
              result_queue_write_pnt_d = 0;
            else
              result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
          end
        end else begin // Normal behavior
          // Bump pointers and counters of the result queue
          result_queue_valid_d[result_queue_write_pnt_q] = 1'b1;
          result_queue_cnt_d += 1;
          if (result_queue_write_pnt_q == ResultQueueDepth-1)
            result_queue_write_pnt_d = 0;
          else
            result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
          issue_cnt_d = issue_cnt_q - element_cnt;
        end

        // Finished issuing the micro-operations of this vector instruction
        if (vinsn_issue_valid && issue_cnt_d == '0) begin
          // Reset the narrowing pointer
          narrowing_select_d = 1'b0;

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

    alu_result_req_o   = result_queue_valid_q[result_queue_read_pnt_q] && !result_queue_q[result_queue_read_pnt_q].mask;
    alu_result_addr_o  = result_queue_q[result_queue_read_pnt_q].addr;
    alu_result_id_o    = result_queue_q[result_queue_read_pnt_q].id;
    alu_result_wdata_o = result_queue_q[result_queue_read_pnt_q].wdata;
    alu_result_be_o    = result_queue_q[result_queue_read_pnt_q].be;

    // Received a grant from the VRF.
    // Deactivate the request.
    if (alu_result_gnt_i || mask_operand_ready_i) begin
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

    if (!vinsn_queue_full && vfu_operation_valid_i && vfu_operation_i.vfu inside {VFU_Alu, VFU_MaskUnit}) begin
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
      issue_cnt_q        <= '0;
      commit_cnt_q       <= '0;
      narrowing_select_q <= 1'b0;
    end else begin
      issue_cnt_q        <= issue_cnt_d;
      commit_cnt_q       <= commit_cnt_d;
      narrowing_select_q <= narrowing_select_d;
    end
  end

endmodule : valu


/***************
 *  SIMD VALU  *
 ***************/

// Description:
// Ara's SIMD ALU, operating on elements 64-bit wide, and generating 64 bits per cycle.

module simd_valu import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter int  unsigned StrbWidth = DataWidth/8,
    parameter type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  logic    valid_i,
    input  logic    vm_i,
    input  strb_t   mask_i,
    input  logic    narrowing_select_i,
    input  ara_op_e op_i,
    input  vew_e    vew_i,
    output elen_t   result_o
  );

  /*****************
   *  Definitions  *
   *****************/

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
  assign is_signed = op_i inside {VMAX, VMIN, VMSLT, VMSLE, VMSGT};
  // Compare operands.
  // For vew_i = EW8, all bits are valid.
  // For vew_i = EW16, bits 0, 2, 4, and 6 are valid.
  // For vew_i = EW32, bits 0 and 4 are valid.
  // For vew_i = EW64, only bit 0 indicates the result of the comparison.
  logic [7:0] less;
  logic [7:0] equal;

  always_comb begin: p_comparison
    // Default assignment
    less  = '0;
    equal = '0;

    if (valid_i) begin
      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) less[1*b] = $signed({is_signed & opb.w8 [b][ 7], opb.w8 [b]}) < $signed({is_signed & opa.w8 [b][ 7], opa.w8 [b]});
        EW16: for (int b = 0; b < 4; b++) less[2*b] = $signed({is_signed & opb.w16[b][15], opb.w16[b]}) < $signed({is_signed & opa.w16[b][15], opa.w16[b]});
        EW32: for (int b = 0; b < 2; b++) less[4*b] = $signed({is_signed & opb.w32[b][31], opb.w32[b]}) < $signed({is_signed & opa.w32[b][31], opa.w32[b]});
        EW64: for (int b = 0; b < 1; b++) less[8*b] = $signed({is_signed & opb.w64[b][63], opb.w64[b]}) < $signed({is_signed & opa.w64[b][63], opa.w64[b]});
        default:;
      endcase

      unique case (vew_i)
        EW8 : for (int b = 0; b < 8; b++) equal[1*b] = opa.w8 [b] == opb.w8 [b];
        EW16: for (int b = 0; b < 4; b++) equal[2*b] = opa.w16[b] == opb.w16[b];
        EW32: for (int b = 0; b < 2; b++) equal[4*b] = opa.w32[b] == opb.w32[b];
        EW64: for (int b = 0; b < 1; b++) equal[8*b] = opa.w64[b] == opb.w64[b];
        default:;
      endcase
    end
  end: p_comparison

  /*********
   *  ALU  *
   *********/

  always_comb begin: p_alu
    // Default assignment
    res = '0;

    if (valid_i)
      unique case (op_i)
        // Logical operations
        VAND: res = operand_a_i & operand_b_i;
        VOR : res = operand_a_i | operand_b_i;
        VXOR: res = operand_a_i ^ operand_b_i;

        // Mask logical operations
        VMAND   : res = operand_a_i & operand_b_i;
        VMANDNOT: res = ~operand_a_i & operand_b_i;
        VMNAND  : res = ~(operand_a_i & operand_b_i);
        VMOR    : res = operand_a_i | operand_b_i;
        VMNOR   : res = ~(operand_a_i | operand_b_i);
        VMORNOT : res = ~operand_a_i | operand_b_i;
        VMXOR   : res = operand_a_i ^ operand_b_i;
        VMXNOR  : res = ~(operand_a_i ^ operand_b_i);

        // Arithmetic instructions
        VADD, VADC, VMADC: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sum = opa.w8[b] + opb.w8[b] + logic'(op_i inside {VADC, VMADC} && mask_i[1*b] && vm_i);
                res.w8[b]                 = (op_i == VMADC) ? {7'b0, sum[8]} : sum[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sum = opa.w16[b] + opb.w16[b] + logic'(op_i inside {VADC, VMADC} && mask_i[2*b] && vm_i);
                res.w16[b]                 = (op_i == VMADC) ? {15'b0, sum[16]} : sum[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sum = opa.w32[b] + opb.w32[b] + logic'(op_i inside {VADC, VMADC} && mask_i[4*b] && vm_i);
                res.w32[b]                 = (op_i == VMADC) ? {31'b0, sum[32]} : sum[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sum = opa.w64[b] + opb.w64[b] + logic'(op_i inside {VADC, VMADC} && mask_i[8*b] && vm_i);
                res.w64[b]                 = (op_i == VMADC) ? {63'b0, sum[64]} : sum[63:0];
              end
            default:;
          endcase
        VSUB, VSBC, VMSBC: unique case (vew_i)
            EW8: for (int b = 0; b < 8; b++) begin
                automatic logic [8:0] sub = $signed(opb.w8[b]) - $signed(opa.w8[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[1*b] && vm_i));
                res.w8[b]                 = (op_i == VMSBC) ? {7'b0, sub[8]} : sub[7:0];
              end
            EW16: for (int b = 0; b < 4; b++) begin
                automatic logic [16:0] sub = $signed(opb.w16[b]) - $signed(opa.w16[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[2*b] && vm_i));
                res.w16[b]                 = (op_i == VMSBC) ? {15'b0, sub[16]} : sub[15:0];
              end
            EW32: for (int b = 0; b < 2; b++) begin
                automatic logic [32:0] sub = $signed(opb.w32[b]) - $signed(opa.w32[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[4*b] && vm_i));
                res.w32[b]                 = (op_i == VMSBC) ? {31'b0, sub[32]} : sub[31:0];
              end
            EW64: for (int b = 0; b < 1; b++) begin
                automatic logic [64:0] sub = $signed(opb.w64[b]) - $signed(opa.w64[b]) - $signed(logic'(op_i inside {VSBC, VMSBC} && mask_i[8*b] && vm_i));
                res.w64[b]                 = (op_i == VMSBC) ? {63'b0, sub[64]} : sub[63:0];
              end
            default:;
          endcase
        VRSUB: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opa.w8 [b] - opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opa.w16[b] - opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opa.w32[b] - opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opa.w64[b] - opb.w64[b];
            default:;
          endcase

        // Shift instructions
        VSLL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] << opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] << opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] << opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] << opa.w64[b][5:0];
            default:;
          endcase
        VSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = opb.w8 [b] >> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = opb.w16[b] >> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = opb.w32[b] >> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = opb.w64[b] >> opa.w64[b][5:0];
            default:;
          endcase
        VSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = $signed(opb.w8 [b]) >>> opa.w8 [b][2:0];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
            default:;
          endcase
        VNSRL: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] = opb.w16[b] >> opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] = opb.w32[b] >> opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] = opb.w64[b] >> opa.w64[b][5:0];
            default:;
          endcase
        VNSRA: unique case (vew_i)
            EW8 : for (int b = 0; b < 4; b++) res.w8 [2*b + narrowing_select_i] = $signed(opb.w16[b]) >>> opa.w16[b][3:0];
            EW16: for (int b = 0; b < 2; b++) res.w16[2*b + narrowing_select_i] = $signed(opb.w32[b]) >>> opa.w32[b][4:0];
            EW32: for (int b = 0; b < 1; b++) res.w32[2*b + narrowing_select_i] = $signed(opb.w64[b]) >>> opa.w64[b][5:0];
            default:;
          endcase

        // Merge instructions
        VMERGE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = mask_i[b] ? opa.w8 [b] : opb.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = mask_i[2*b] ? opa.w16[b] : opb.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = mask_i[4*b] ? opa.w32[b] : opb.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = mask_i[8*b] ? opa.w64[b] : opb.w64[b];
            default:;
          endcase

        // Comparison instructions
        VMIN, VMINU, VMAX, VMAXU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b] = (less[1*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w8 [b] : opa.w8 [b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b] = (less[2*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w16[b] : opa.w16[b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b] = (less[4*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w32[b] : opa.w32[b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b] = (less[8*b] ^ (op_i == VMAX || op_i == VMAXU)) ? opb.w64[b] : opa.w64[b];
            default:;
          endcase
        VMSEQ, VMSNE: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = equal[1*b] ^ (op_i == VMSNE);
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = equal[2*b] ^ (op_i == VMSNE);
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = equal[4*b] ^ (op_i == VMSNE);
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = equal[8*b] ^ (op_i == VMSNE);
            default:;
          endcase
        VMSLT, VMSLTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = less[1*b];
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = less[2*b];
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = less[4*b];
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = less[8*b];
            default:;
          endcase
        VMSLE, VMSLEU, VMSGT, VMSGTU: unique case (vew_i)
            EW8 : for (int b = 0; b < 8; b++) res.w8 [b][0] = (less[1*b] || equal[1*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW16: for (int b = 0; b < 4; b++) res.w16[b][0] = (less[2*b] || equal[2*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW32: for (int b = 0; b < 2; b++) res.w32[b][0] = (less[4*b] || equal[4*b]) ^ (op_i inside {VMSGT, VMSGTU});
            EW64: for (int b = 0; b < 1; b++) res.w64[b][0] = (less[8*b] || equal[8*b]) ^ (op_i inside {VMSGT, VMSGTU});
            default:;
          endcase

        default:;
      endcase
  end: p_alu

  /****************
   *  Assertions  *
   ****************/

  if (DataWidth != $bits(alu_operand_t))
    $error("[simd_valu] The SIMD vector ALU only works for a datapath 64-bit wide.");

endmodule : simd_valu
