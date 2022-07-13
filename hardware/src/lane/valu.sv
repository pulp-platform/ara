// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author:  Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's vector ALU. It is capable of executing integer operations
// in a SIMD fashion, always operating on 64 bits.

module valu import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter  int  unsigned NrLanes   = 0,
    // Type used to address vector register file elements
    parameter  type          vaddr_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t),
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic[idx_width(NrLanes)-1:0] lane_id_i,
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
    // Interface with the Slide Unit
    output logic                         alu_red_valid_o,
    input  logic                         alu_red_ready_i,
    input  elen_t                        sldu_operand_i,
    input  logic                         sldu_alu_valid_i,
    output logic                         sldu_alu_ready_o,
    // Interface with the Mask unit
    output elen_t                        mask_operand_o,
    output logic                         mask_operand_valid_o,
    input  logic                         mask_operand_ready_i,
    input  strb_t                        mask_i,
    input  logic                         mask_valid_i,
    output logic                         mask_ready_o
  );

  import cf_math_pkg::idx_width;

  /////////////
  // Lane ID //
  /////////////

  // Lane 0 has different logic than Lanes != 0
  // A parameter would be perfect to save HW, but our hierarchical
  // synth/pnr flow needs that all lanes are the same

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions
  localparam VInsnQueueDepth = ValuInsnQueueDepth;

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
  // We need two pointers in the result queue. One pointer to indicate with `payload_t` we are
  // currently writing into (write_pnt), and one pointer to indicate which `payload_t` we are
  // currently reading from and writing into the lanes (read_pnt).
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

  //////////////////////////////
  //  Narrowing instructions  //
  //////////////////////////////

  // This function returns 1'b1 if `op` is a narrowing instruction, i.e.,
  // it produces only EEW/2 per cycle.
  function automatic logic narrowing(ara_op_e op);
    narrowing = 1'b0;
    if (op inside {VNSRA, VNSRL})
      narrowing = 1'b1;
  endfunction : narrowing

  // If this is a narrowing instruction, point to which half of the
  // output EEW word we are producing.
  logic narrowing_select_d, narrowing_select_q;

  //////////////////
  //  Reductions  //
  //////////////////

  // Cut the path between the SLDU and the ALU. This increase latency
  // but does has negligible impact on long vectors
  elen_t sldu_operand_q;
  logic  sldu_alu_valid_q, sldu_alu_ready_d;
  spill_register #(
    .T(elen_t)
  ) i_alu_reduction_spill_register (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .valid_i(sldu_alu_valid_i),
    .ready_o(sldu_alu_ready_o),
    .data_i (sldu_operand_i  ),
    .valid_o(sldu_alu_valid_q),
    .ready_i(sldu_alu_ready_d),
    .data_o (sldu_operand_q  )
  );

  // This function returns 1'b1 if `op` is a reduction instruction, i.e.,
  // it must accumulate the result (intra-lane reduction) before sending it to the
  // sliding unit (inter-lane and SIMD reduction).
  function automatic logic is_reduction(ara_op_e op);
    is_reduction = 1'b0;
    if (op inside {[VREDSUM:VWREDSUM]})
      is_reduction = 1'b1;
  endfunction: is_reduction

  // During an inter-lane reduction (after the intra-lane reduction), the NrLanes partial results
  // must be reduced to only one. The first reduction is done by NrLanes/2 FUs, then NrLanes/4, and
  // so on. In the end, the result is collected in Lane 0 and the last SIMD reduction is performed.
  // The following function determines how many partial results this lane must process during the
  // inter-lane reduction.
  typedef logic [idx_width(NrLanes/2):0] reduction_rx_cnt_t;
  reduction_rx_cnt_t reduction_rx_cnt_d, reduction_rx_cnt_q;
  reduction_rx_cnt_t simd_red_cnt_max_d, simd_red_cnt_max_q;

  // Use this function to assign a counter value to each lane if you can use in-lane parameters with your flow
  //  function automatic reduction_rx_cnt_t reduction_rx_cnt_init(int unsigned NrLanes, int unsigned LaneIdx);
  //    // The even lanes do not receive intermediate results. Only Lane 0 will receive the final result, but this is not checked here.
  //    int adjusted_idx = LaneIdx + 1;
  //    reduction_rx_cnt_init = '0;
  //    for (int i = 2; i <= NrLanes; i *= 2) if (!(adjusted_idx % i)) reduction_rx_cnt_init++;
  //  endfunction: reduction_rx_cnt_init
  // Otherwise, use the following function (okay until 16 lanes)
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
  logic first_op_d, first_op_q;

  // Signal to indicate the state of the ALU
  typedef enum logic [2:0] {NO_REDUCTION, INTRA_LANE_REDUCTION, INTER_LANES_REDUCTION, WAIT_STATE, SIMD_REDUCTION} alu_state_e;
  alu_state_e alu_state_d, alu_state_q;

  // This signal is used to cut a in2reg bad path
  // This works since the signal is never checked
  // twice in two consecutive cycles
  logic  alu_red_ready_q;

  // Input multiplexers.
  elen_t simd_red_operand;
  strb_t red_mask;
  // During the first cycle, the reduction adds a scalar value kept into a
  // vector register to the first group of vector elements. Then, one of the operand is always
  // the accumulator.
  // For lane[0], the scalar value is actually a value. For the other lanes the value is a neutral one.
  elen_t alu_operand_a;
  elen_t alu_operand_b;

  // Main Alu input MUXes
  // Operands can come from the input queues, from the other lanes, or from the reduction accumulator
  assign alu_operand_a  = (alu_state_q inside {INTER_LANES_REDUCTION, SIMD_REDUCTION, INTRA_LANE_REDUCTION} && !first_op_q)
                        ? result_queue_q[result_queue_write_pnt_q].wdata
                        : vinsn_issue_q.use_scalar_op ? scalar_op : alu_operand_i[0];
  assign alu_operand_b  = (alu_state_q inside {INTER_LANES_REDUCTION, SIMD_REDUCTION})
                        ? alu_state_q == SIMD_REDUCTION ? simd_red_operand : sldu_operand_q
                        : alu_operand_i[1];

  ///////////////////////
  //  SIMD Vector ALU  //
  ///////////////////////

  elen_t valu_result;
  logic  valu_valid;

  simd_alu i_simd_alu (
    .operand_a_i       (alu_operand_a                                                   ),
    .operand_b_i       (alu_operand_b                                                   ),
    .valid_i           (valu_valid                                                      ),
    .vm_i              (vinsn_issue_q.vm                                                ),
    .mask_i            ((mask_valid_i && !vinsn_issue_q.vm) ? mask_i : {StrbWidth{1'b1}}),
    .narrowing_select_i(narrowing_select_q                                              ),
    .op_i              (vinsn_issue_q.op                                                ),
    .vew_i             (vinsn_issue_q.vtype.vsew                                        ),
    .result_o          (valu_result                                                     )
  );

  ///////////////
  //  Control  //
  ///////////////

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

    first_op_d              = first_op_q;
    simd_red_cnt_d          = simd_red_cnt_q;
    reduction_rx_cnt_d      = reduction_rx_cnt_q;
    sldu_transactions_cnt_d = sldu_transactions_cnt_q;
    red_hs_synch_d          = red_hs_synch_q;
    alu_red_valid_o         = 1'b0;
    sldu_alu_ready_d        = 1'b0;
    simd_red_cnt_max_d      = simd_red_cnt_max_q;
    simd_red_operand        = '0;
    red_mask                = '0;

    // Do not issue any operations
    valu_valid  = 1'b0;
    alu_state_d = alu_state_q;

    // Inform our status to the lane controller
    alu_ready_o      = !vinsn_queue_full;
    alu_vinsn_done_o = '0;

    // Do not acknowledge any operands
    alu_operand_ready_o = '0;
    mask_ready_o        = '0;

    ////////////////////////////////////////
    //  Write data into the result queue  //
    ////////////////////////////////////////

    if (vinsn_issue_valid || alu_state_q != NO_REDUCTION) begin
      case (alu_state_q)
        NO_REDUCTION: begin
          // Do not accept operands if the result queue is full!
          // Do not accept operands from this state if the current instruction is a reduction
          if (!result_queue_full && !is_reduction(vinsn_issue_q.op)) begin
            // Do we have all the operands necessary for this instruction?
            if ((alu_operand_valid_i[1] || !vinsn_issue_q.use_vs2) &&
                (alu_operand_valid_i[0] || !vinsn_issue_q.use_vs1) &&
                (mask_valid_i || vinsn_issue_q.vm)) begin
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
              if (!narrowing(vinsn_issue_q.op))
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
                  if (!(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op inside {[VMANDNOT:VMXNOR]}))
                    issue_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
                  else begin
                    // Operations between mask vectors operate on bits
                    issue_cnt_d = (vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl / 8) >>
                      vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew;
                    issue_cnt_d += |vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl[2:0];
                  end
              end
            end
          end
        end
        INTRA_LANE_REDUCTION: begin
          // Stall only if this is the first operation for this reduction instruction and the result queue is full
          if (!(first_op_q && result_queue_full)) begin
            // Do we have all the operands necessary for this instruction?
            // The second operand is needed only during the first operation of a reduction instruction
            if ((alu_operand_valid_i[1] || !vinsn_issue_q.use_vs2) &&
                (alu_operand_valid_i[0] || !vinsn_issue_q.use_vs1 || !first_op_q) &&
                (mask_valid_i || vinsn_issue_q.vm)) begin
              // How many elements are we committing with this word?
              automatic logic [3:0] element_cnt = (1 << (int'(EW64) - int'(vinsn_issue_q.vtype.vsew)));
              if (element_cnt > issue_cnt_q)
                element_cnt = issue_cnt_q;

              // Mask the inactive elements
              red_mask = be(element_cnt, vinsn_issue_q.vtype.vsew) & ({StrbWidth{vinsn_issue_q.vm}} | mask_i);

              // Issue the operation
              valu_valid = 1'b1;

              // Acknowledge the operands of this instruction
              alu_operand_ready_o = {vinsn_issue_q.use_vs2, vinsn_issue_q.use_vs1 & first_op_q};
              // Acknowledge the mask operands
              mask_ready_o = ~vinsn_issue_q.vm;

              // Reduction instruction, accumulate the result
              for (int b = 0; b < 8; b++) begin
                result_queue_d[result_queue_write_pnt_q].wdata[8*b +: 8] =
                    red_mask[b]            ?
                    valu_result[8*b +: 8]  :
                    alu_operand_a[8*b +: 8];
              end
              result_queue_d[result_queue_write_pnt_q].addr  = vaddr(vinsn_issue_q.vd, NrLanes);
              result_queue_d[result_queue_write_pnt_q].id    = vinsn_issue_q.id;
              result_queue_d[result_queue_write_pnt_q].be    = be(1, vinsn_issue_q.vtype.vsew);

              // The first operation of this instruction has just been done
              first_op_d = 1'b0;

              issue_cnt_d = issue_cnt_q - element_cnt;

              // Finished issuing the micro-operations of this vector instruction
              if (vinsn_issue_valid && issue_cnt_d == '0) begin
                // We can start the inter-lanes reduction
                alu_state_d = INTER_LANES_REDUCTION;
              end
            end
          end
        end
        INTER_LANES_REDUCTION: begin
          if (reduction_rx_cnt_q == '0) begin
            // This unit has finished processing data for this reduction instruction, send the partial result to the sliding unit
            alu_red_valid_o = 1'b1;
            // We can simply delay the ready since we will immediately change state,
            // so, no risk to re-sample alu_red_ready_i with side effects
            if (alu_red_ready_q) begin
              alu_state_d = WAIT_STATE;
                if (lane_id_i != '0) begin
                // Bump issue counter and pointers
                vinsn_queue_d.issue_cnt -= 1;
                if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1)
                  vinsn_queue_d.issue_pnt = '0;
                else
                  vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

                if (vinsn_queue_d.issue_cnt != 0)
                  if (!(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op inside {[VMANDNOT:VMXNOR]}))
                    issue_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
                  else begin
                    issue_cnt_d = (vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl / 8) >>
                      vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew;
                    issue_cnt_d += |vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl[2:0];
                  end
              end
            end
          end else begin
            // This unit should still process data for the inter-lane reduction.
            // Ready to accept incoming operands from the slide unit.
            alu_red_valid_o = red_hs_synch_q;
            if (sldu_alu_valid_q) begin
              // Issue the operation
              valu_valid = 1'b1;
              sldu_alu_ready_d = 1'b1;
              reduction_rx_cnt_d = reduction_rx_cnt_q - 1;
              result_queue_d[result_queue_write_pnt_q].wdata = valu_result;
            end
          end
          // Count the successful transaction with the SLDU
          if (sldu_alu_valid_q && sldu_alu_ready_d) begin
            sldu_transactions_cnt_d = sldu_transactions_cnt_q - 1;
          end
          if (alu_red_valid_o && alu_red_ready_i) red_hs_synch_d = 1'b0;
          if (sldu_alu_valid_q && sldu_alu_ready_d) red_hs_synch_d = 1'b1;
        end
        WAIT_STATE: begin
          // Acknowledge the sliding unit even if it is not forwarding anything useful
          sldu_alu_ready_d = sldu_alu_valid_q;
          alu_red_valid_o  = red_hs_synch_q;
          // If lane 0, wait for the inter-lane reduced operand, to perform a SIMD reduction
          if (lane_id_i == '0) begin
            if (sldu_alu_valid_q) begin
              if (sldu_transactions_cnt_q == 1) begin
                result_queue_d[result_queue_write_pnt_q].wdata = sldu_operand_q;
                unique case (vinsn_issue_q.vtype.vsew)
                  EW8 : simd_red_cnt_max_d = 2'd3;
                  EW16: simd_red_cnt_max_d = 2'd2;
                  EW32: simd_red_cnt_max_d = 2'd1;
                  EW64: simd_red_cnt_max_d = 2'd0;
                endcase
                simd_red_cnt_d = '0;
                alu_state_d = SIMD_REDUCTION;
              end
            end
          end else if (sldu_transactions_cnt_q == '0) begin
            // If not lane 0, wait for the completion of the reduction
            alu_state_d = is_reduction(vinsn_issue_q.op) && vinsn_issue_valid ? INTRA_LANE_REDUCTION : NO_REDUCTION;
            // The next will be the first operation of this instruction
            // This information is useful for reduction operation
            first_op_d         = 1'b1;
            reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);
            sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
            // Allow the first valid
            red_hs_synch_d = 1'b1;
            // Give the done to the main sequencer
            commit_cnt_d = '0;
          end
          if (sldu_alu_valid_q && sldu_alu_ready_d) begin
            sldu_transactions_cnt_d = sldu_transactions_cnt_q - 1;
          end
          if (alu_red_valid_o && alu_red_ready_i) red_hs_synch_d = 1'b0;
          if (sldu_alu_valid_q && sldu_alu_ready_d) red_hs_synch_d = 1'b1;
        end
        SIMD_REDUCTION: begin
          if (lane_id_i == '0) begin
            valu_valid = (simd_red_cnt_q != simd_red_cnt_max_q);

            unique case (simd_red_cnt_q)
              2'd0: simd_red_operand = {32'b0, result_queue_q[result_queue_write_pnt_q].wdata[63:32]};
              2'd1: simd_red_operand = {48'b0, result_queue_q[result_queue_write_pnt_q].wdata[31:16]};
              2'd2: simd_red_operand = {56'b0, result_queue_q[result_queue_write_pnt_q].wdata[15:8]};
              default:;
            endcase

            if (simd_red_cnt_q != simd_red_cnt_max_q) begin
              simd_red_cnt_d = simd_red_cnt_q + 1;
              result_queue_d[result_queue_write_pnt_q].wdata = valu_result;
            end else begin
              // Bump issue counter and pointers
              vinsn_queue_d.issue_cnt -= 1;
              if (vinsn_queue_q.issue_pnt == VInsnQueueDepth-1)
                vinsn_queue_d.issue_pnt = '0;
              else
                vinsn_queue_d.issue_pnt = vinsn_queue_q.issue_pnt + 1;

              if (vinsn_queue_d.issue_cnt != 0)
                if (!(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op inside {[VMANDNOT:VMXNOR]}))
                  issue_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
                else begin
                  issue_cnt_d = (vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl / 8) >>
                    vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vtype.vsew;;
                  issue_cnt_d += |vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl[2:0];
                end

              alu_state_d = is_reduction(vinsn_issue_d.op) && (vinsn_queue_d.issue_cnt != 0) ? INTRA_LANE_REDUCTION : NO_REDUCTION;
              // The next will be the first operation of this instruction
              // This information is useful for reduction operation
              first_op_d         = 1'b1;
              reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);
              sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
              // Allow the first valid
              red_hs_synch_d = 1'b1;
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
          end
        end
        default:;
      endcase
    end

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

    alu_result_wdata_o = result_queue_q[result_queue_read_pnt_q].wdata;
    if (alu_state_q == NO_REDUCTION || (alu_state_q == SIMD_REDUCTION && simd_red_cnt_q == simd_red_cnt_max_q)) begin
      alu_result_req_o = result_queue_valid_q[result_queue_read_pnt_q] & ((alu_state_q == SIMD_REDUCTION) || !result_queue_q[result_queue_read_pnt_q].mask);
    end else begin
      alu_result_req_o = 1'b0;
    end
    alu_result_addr_o = result_queue_q[result_queue_read_pnt_q].addr;
    alu_result_id_o   = result_queue_q[result_queue_read_pnt_q].id;
    alu_result_be_o   = result_queue_q[result_queue_read_pnt_q].be;

    // Clear the accumulator after a partial reduction
    if (alu_state_q == WAIT_STATE && alu_state_d == NO_REDUCTION)
      result_queue_d[result_queue_read_pnt_q] = '0;

    // Received a grant from the VRF.
    // Deactivate the request.
    if (alu_result_gnt_i || mask_operand_gnt) begin
      result_queue_valid_d[result_queue_read_pnt_q] = 1'b0;
      result_queue_d[result_queue_read_pnt_q]       = '0;

      // Increment the read pointer
      if (result_queue_read_pnt_q == ResultQueueDepth-1) result_queue_read_pnt_d = 0;
      else result_queue_read_pnt_d = result_queue_read_pnt_q + 1;

      // Decrement the counter of results waiting to be written
      result_queue_cnt_d -= 1;

      // Decrement the counter of remaining vector elements waiting to be written
      // Don't do it in case of a reduction
      if (!is_reduction(vinsn_commit.op))
        commit_cnt_d = commit_cnt_q - (1 << (int'(EW64) - vinsn_commit.vtype.vsew));
      if (commit_cnt_q < (1 << (int'(EW64) - vinsn_commit.vtype.vsew))) commit_cnt_d = '0;
    end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && commit_cnt_d == '0) begin
      // Mark the vector instruction as being done
      alu_vinsn_done_o[vinsn_commit.id] = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
      if (vinsn_queue_d.commit_pnt == VInsnQueueDepth-1) vinsn_queue_d.commit_pnt = '0;
      else vinsn_queue_d.commit_pnt += 1;

      // Update the commit counter for the next instruction
      if (vinsn_queue_d.commit_cnt != '0)
        if (!(vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].op inside {[VMANDNOT:VMXNOR]}))
          commit_cnt_d = vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl;
        else begin
          // We are asking for bits, and we want at least one chunk of bits if
          // vl > 0. Therefore, commit_cnt = ceil((vl / 8) >> sew)
          commit_cnt_d = (vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl / 8) >>
            vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vtype.vsew;
          commit_cnt_d += |vinsn_queue_q.vinsn[vinsn_queue_d.commit_pnt].vl[2:0];
        end

      // Initialize counters and alu state if needed by the next instruction
      // After a reduction, the next instructions starts after the reduction commits
      if (is_reduction(vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].op) && (vinsn_queue_d.issue_cnt != '0)) begin
        alu_state_d = INTRA_LANE_REDUCTION;
        // The next will be the first operation of this instruction
        // This information is useful for reduction operation
        first_op_d         = 1'b1;
        reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);

        sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
        // Allow the first valid
        red_hs_synch_d = 1'b1;
        issue_cnt_d    = vinsn_queue_q.vinsn[vinsn_queue_d.issue_pnt].vl;
      end
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    if (!vinsn_queue_full && vfu_operation_valid_i &&
      (vfu_operation_i.vfu == VFU_Alu || vfu_operation_i.op inside {[VMSEQ:VMXNOR]})) begin
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt] = vfu_operation_i;
      // Do not wait for masks if, during a reduction, this lane is just a pass-through
      // The only valid instructions here with vl == '0 are reductions
      vinsn_queue_d.vinsn[vinsn_queue_q.accept_pnt].vm = vfu_operation_i.vm | (vfu_operation_i.vl == '0);

      // Initialize counters and alu state if this is the instruction queue was empty
      if (vinsn_queue_d.issue_cnt == '0) begin
        alu_state_d = is_reduction(vfu_operation_i.op) ? INTRA_LANE_REDUCTION : NO_REDUCTION;
        // The next will be the first operation of this instruction
        // This information is useful for reduction operation
        first_op_d         = 1'b1;
        reduction_rx_cnt_d = reduction_rx_cnt_init(NrLanes, lane_id_i);

        sldu_transactions_cnt_d = $clog2(NrLanes) + 1;
        // Allow the first valid
        red_hs_synch_d = 1'b1;
        issue_cnt_d    = vfu_operation_i.vl;
      end
      if (vinsn_queue_d.commit_cnt == '0)
        if (!(vfu_operation_i.op inside {[VMANDNOT:VMXNOR]}))
          commit_cnt_d = vfu_operation_i.vl;
        else begin
          // Operations between mask vectors operate on bits
          commit_cnt_d  = (vfu_operation_i.vl / 8) >> vfu_operation_i.vtype.vsew;
          commit_cnt_d += |vfu_operation_i.vl[2:0];
        end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.accept_pnt += 1;
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end : p_valu

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_cnt_q             <= '0;
      commit_cnt_q            <= '0;
      narrowing_select_q      <= 1'b0;
      simd_red_cnt_q          <= '0;
      alu_state_q             <= NO_REDUCTION;
      reduction_rx_cnt_q      <= '0;
      first_op_q              <= 1'b0;
      sldu_transactions_cnt_q <= '0;
      red_hs_synch_q          <= 1'b0;
      simd_red_cnt_max_q      <= '0;
      alu_red_ready_q         <= 1'b0;
    end else begin
      issue_cnt_q             <= issue_cnt_d;
      commit_cnt_q            <= commit_cnt_d;
      narrowing_select_q      <= narrowing_select_d;
      simd_red_cnt_q          <= simd_red_cnt_d;
      alu_state_q             <= alu_state_d;
      reduction_rx_cnt_q      <= reduction_rx_cnt_d;
      first_op_q              <= first_op_d;
      sldu_transactions_cnt_q <= sldu_transactions_cnt_d;
      red_hs_synch_q          <= red_hs_synch_d;
      simd_red_cnt_max_q      <= simd_red_cnt_max_d;
      alu_red_ready_q         <= alu_red_ready_i;
    end
  end

endmodule : valu
