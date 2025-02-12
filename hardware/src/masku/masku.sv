// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// This is Ara's mask unit. It fetches operands from any one the lanes, and
// then sends back to them whether the elements are predicated or not.
// This unit is shared between all the functional units who can execute
// predicated instructions.

module masku import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes   = 0,
    parameter  int  unsigned VLEN      = 0,
    parameter  type          vaddr_t   = logic, // Type used to address vector register file elements
    parameter  type          pe_req_t  = logic,
    parameter  type          pe_resp_t = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t), // Width of the lane datapath
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0], // Byte-strobe type
    localparam type          vlen_t    = logic[$clog2(VLEN+1)-1:0]
  ) (
    input  logic                                       clk_i,
    input  logic                                       rst_ni,
    // Interface with the main sequencer
    input  pe_req_t                                    pe_req_i,
    input  logic                                       pe_req_valid_i,
    input  logic     [NrVInsn-1:0]                     pe_vinsn_running_i,
    output logic                                       pe_req_ready_o,
    output pe_resp_t                                   pe_resp_o,
    output elen_t                                      result_scalar_o,
    output logic                                       result_scalar_valid_o,
    // Interface with the lanes
    input  elen_t    [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_i,
    input  logic     [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_valid_i,
    output logic     [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_ready_o,
    output logic     [NrLanes-1:0]                     masku_result_req_o,
    output vid_t     [NrLanes-1:0]                     masku_result_id_o,
    output vaddr_t   [NrLanes-1:0]                     masku_result_addr_o,
    output elen_t    [NrLanes-1:0]                     masku_result_wdata_o,
    output strb_t    [NrLanes-1:0]                     masku_result_be_o,
    input  logic     [NrLanes-1:0]                     masku_result_gnt_i,
    input  logic     [NrLanes-1:0]                     masku_result_final_gnt_i,
    output logic     [NrLanes-1:0]                     masku_vrgat_req_valid_o,
    input  logic     [NrLanes-1:0]                     masku_vrgat_req_ready_i,
    output vrgat_req_t                                 masku_vrgat_req_o,
    // Interface with the VFUs
    output strb_t    [NrLanes-1:0]                     mask_o,
    output logic     [NrLanes-1:0]                     mask_valid_o,
    output logic                                       mask_valid_lane_o,
    input  logic     [NrLanes-1:0]                     lane_mask_ready_i,
    input  logic                                       vldu_mask_ready_i,
    input  logic                                       vstu_mask_ready_i,
    input  logic                                       sldu_mask_ready_i
  );

  import cf_math_pkg::idx_width;

  // Pointers
  //
  // We need a pointer to which bit on the full VRF word we are reading mask operands from.
  logic [idx_width(DataWidth*NrLanes):0] mask_pnt_d, mask_pnt_q;
  // We need a pointer to which bit on the full VRF word we are writing results to.
  logic [idx_width(DataWidth*NrLanes):0] vrf_pnt_d, vrf_pnt_q;

  // Remaining elements of the current instruction in the read operand phase
  vlen_t read_cnt_d, read_cnt_q;
  // Remaining elements of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining elements of the current instruction to be validated in the result queue
  vlen_t processing_cnt_d, processing_cnt_q;
  // Remaining elements of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;

  ////////////////
  //  Operands  //
  ////////////////

  // Information about which is the target FU of the request
  masku_fu_e masku_operand_fu;

  // ALU/FPU result (shuffled)
  elen_t [NrLanes-1:0] masku_operand_alu;
  logic  [NrLanes-1:0] masku_operand_alu_valid;
  logic  [NrLanes-1:0] masku_operand_alu_ready;

  // ALU/FPU result (deshuffled)
  logic  [NrLanes*DataWidth-1:0] masku_operand_alu_seq;

  // vd (shuffled)
  elen_t [NrLanes-1:0] masku_operand_vd;
  logic  [NrLanes-1:0] masku_operand_vd_valid;
  logic  [NrLanes-1:0] masku_operand_vd_ready;

  // vd (deshuffled)
  logic  [NrLanes*DataWidth-1:0] masku_operand_vd_seq;
  logic  [     NrLanes-1:0] masku_operand_vd_seq_valid;

  // Mask
  elen_t [NrLanes-1:0] masku_operand_m;
  logic  [NrLanes-1:0] masku_operand_m_valid;
  logic  [NrLanes-1:0] masku_operand_m_ready;

  // Mask deshuffled
  logic  [NrLanes*DataWidth-1:0] masku_operand_m_seq;

  // Insn-queue related signal
  pe_req_t vinsn_issue;

  logic  [NrLanes*DataWidth-1:0] bit_enable_mask;
  logic  [NrLanes*DataWidth-1:0] alu_result_compressed_seq;

  // Performs all shuffling and deshuffling of mask operands (including masks for mask instructions)
  // Furthermore, it buffers certain operands that would create long critical paths
  masku_operands #(
    .NrLanes  ( NrLanes   ),
    .pe_req_t ( pe_req_t  ),
    .pe_resp_t( pe_resp_t )
  ) i_masku_operands (
    .clk_i                         (                       clk_i ),
    .rst_ni                        (                      rst_ni ),
    // Control logic
    .masku_fu_i                    (            masku_operand_fu ),
    .vinsn_issue_i                 (                 vinsn_issue ),
    .vrf_pnt_i                     (                   vrf_pnt_q ),
    // Operands coming from lanes
    .masku_operand_valid_i         (       masku_operand_valid_i ),
    .masku_operand_ready_o         (       masku_operand_ready_o ),
    .masku_operands_i              (             masku_operand_i ),
    // Operands prepared for mask unit execution
    .masku_operand_alu_o           (           masku_operand_alu ),
    .masku_operand_alu_valid_o     (     masku_operand_alu_valid ),
    .masku_operand_alu_ready_i     (     masku_operand_alu_ready ),
    .masku_operand_alu_seq_o       (       masku_operand_alu_seq ),
    .masku_operand_alu_seq_valid_o (                             ),
    .masku_operand_alu_seq_ready_i (                          '0 ),
    .masku_operand_vd_o            (            masku_operand_vd ),
    .masku_operand_vd_valid_o      (      masku_operand_vd_valid ),
    .masku_operand_vd_ready_i      (      masku_operand_vd_ready ),
    .masku_operand_vd_seq_o        (        masku_operand_vd_seq ),
    .masku_operand_vd_seq_valid_o  (  masku_operand_vd_seq_valid ),
    .masku_operand_vd_seq_ready_i  (                          '0 ),
    .masku_operand_m_o             (             masku_operand_m ),
    .masku_operand_m_valid_o       (       masku_operand_m_valid ),
    .masku_operand_m_ready_i       (       masku_operand_m_ready ),
    .masku_operand_m_seq_o         (         masku_operand_m_seq ),
    .masku_operand_m_seq_valid_o   (                             ),
    .masku_operand_m_seq_ready_i   (                          '0 ),
    .bit_enable_mask_o             (             bit_enable_mask ),
    .alu_result_compressed_seq_o   (   alu_result_compressed_seq )
  );

  // Local Parameter for mask logical instructions
  //
  // Don't change this parameter!
  localparam integer unsigned VrgatherParallelism = 1;

  // Local Parameter for mask logical instructions
  //
  // Don't change this parameter!
  localparam integer unsigned VmLogicalParallelism = NrLanes*DataWidth;

  // Local Parameter VMSBF, VMSIF, VMSOF
  //
  localparam integer unsigned VmsxfParallelism = NrLanes < 4 ? 2 : NrLanes/2;
  // Ancillary signals
  logic [VmsxfParallelism-1:0] vmsbf_buffer;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsif_vm;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsbf_vm;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsof_vm;

  // Local Parameter VIOTA, VID
  //
  // How many output results are computed in parallel by VIOTA
  localparam integer unsigned ViotaParallelism = NrLanes < 4 ? 2 : NrLanes/2;
  // Check if parameters are within range
  if (ViotaParallelism > NrLanes || ViotaParallelism % 2 != 0) begin
    $fatal(1, "Parameter ViotaParallelism cannot be higher than NrLanes and should be a power of 2.");
  end
  // VLENMAX can be 64Ki elements at most - 16 bit per adder are enough
  logic [ViotaParallelism-1:0] [idx_width(RISCV_MAX_VLEN)-1:0] viota_res;
  logic [idx_width(RISCV_MAX_VLEN)-1:0] viota_acc, viota_acc_d, viota_acc_q;
  // Ancillary signal to tweak the VRF byte-enable, accounting for an unbalanced write,
  // i.e., when the number of elements does not perfectly divide NrLanes
  logic [3:0] elm_per_lane; // From 0 to 8 elements per lane
  logic [NrLanes-1:0] additional_elm; // There can be an additional element for some lanes
  // BE signals for VIOTA
  logic [NrLanes*DataWidth/8-1:0] be_viota_seq_d, be_viota_seq_q, be_vrgat_seq_d, be_vrgat_seq_q;
  logic [NrLanes*DataWidth/8-1:0] be_masku_alu_shuf;

  // Local Parameter VcpopParallelism and VfirstParallelism
  //
  // Description: Parameters VcpopParallelism and VfirstParallelism enable time multiplexing of vcpop.m and vfirst.m instruction.
  //
  // Legal range VcpopParallelism:   {16, 32, 64, 128, ... , DataWidth*NrLanes} // DataWidth = 64
  // Legal range VfirstParallelism: {16, 32, 64, 128, ... , DataWidth*NrLanes} // DataWidth = 64
  //
  // Execution time example for vcpop.m (similar for vfirst.m):
  // VcpopParallelism = 64; VLEN = 1024; vl = 1024
  // t_vcpop.m = VLEN/VcpopParallelism = 8 [Cycles]
  localparam int VcpopParallelism   = 16;
  localparam int VfirstParallelism = 16;
  // derived parameters
  localparam int MAX_VcpopParallelism_VFIRST = (VcpopParallelism > VfirstParallelism) ? VcpopParallelism : VfirstParallelism;
  localparam int N_SLICES_CPOP   = NrLanes * DataWidth / VcpopParallelism;
  localparam int N_SLICES_VFIRST = NrLanes * DataWidth / VfirstParallelism;
  // Check if parameters are within range
  if (((VcpopParallelism & (VcpopParallelism - 1)) != 0) || (VcpopParallelism < 8)) begin
    $fatal(1, "Parameter VcpopParallelism must be power of 2.");
  end else if (((VfirstParallelism & (VfirstParallelism - 1)) != 0) || (VfirstParallelism < 8)) begin
    $fatal(1, "Parameter VfirstParallelism must be power of 2.");
  end

  // VFIRST and VCPOP Signals
  logic  [NrLanes*DataWidth-1:0]              vcpop_operand;
  logic  [$clog2(VcpopParallelism):0]              popcount;
  logic  [$clog2(VLEN):0]                popcount_d, popcount_q;
  logic  [$clog2(VfirstParallelism)-1:0]          vfirst_count;
  logic  [$clog2(VLEN)-1:0]              vfirst_count_d, vfirst_count_q;
  logic                                  vfirst_empty;
  // counter to keep track of how many slices of the vcpop_operand have been processed
  logic [VcpopParallelism-1:0]                    vcpop_slice;
  logic [VfirstParallelism-1:0]                  vfirst_slice;

  // vmsbf, vmsif, vmsof, viota, vid, vcpop, vfirst variables
  logic  [NrLanes*DataWidth-1:0] masku_operand_alu_seq_m;
  logic  [NrLanes*DataWidth-1:0] alu_result_vm, alu_result_vm_m, alu_result_vm_shuf;
  logic                          found_one, found_one_d, found_one_q;

  // How many elements we are processing per cycle
  logic [idx_width(NrLanes*DataWidth):0] delta_elm_d, delta_elm_q;

  // MASKU Alu: is a VRF word result or a scalar result fully valid?
  logic out_vrf_word_valid, out_scalar_valid;

  ////////////////////////////////
  //  Vector instruction queue  //
  ////////////////////////////////

  // We store a certain number of in-flight vector instructions.
  // To avoid any hazards between masked vector instructions, the mask
  // unit is only capable of handling one vector instruction at a time.
  // Optimizing this unit is left as future work.

  localparam VInsnQueueDepth = MaskuInsnQueueDepth;

  struct packed {
    pe_req_t [VInsnQueueDepth-1:0] vinsn;

    // We also need to count how many instructions are queueing to be
    // issued/committed, to avoid accepting more instructions than
    // we can handle.
    logic [idx_width(VInsnQueueDepth)-1:0] issue_cnt;
    logic [idx_width(VInsnQueueDepth)-1:0] commit_cnt;
  } vinsn_queue_d, vinsn_queue_q;

  // Is the vector instruction queue full?
  logic vinsn_queue_full;
  assign vinsn_queue_full = (vinsn_queue_q.commit_cnt == VInsnQueueDepth);

  // Do we have a vector instruction ready to be issued?
  logic    vinsn_issue_valid;
  assign vinsn_issue       = vinsn_queue_q.vinsn[0];
  assign vinsn_issue_valid = (vinsn_queue_q.issue_cnt != '0);

  // Do we have a vector instruction with results being committed?
  pe_req_t vinsn_commit;
  logic    vinsn_commit_valid;
  assign vinsn_commit       = vinsn_queue_q.vinsn[0];
  assign vinsn_commit_valid = (vinsn_queue_q.commit_cnt != '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_queue_q <= '0;
    end else begin
      vinsn_queue_q <= vinsn_queue_d;
    end
  end

  ///////////////////
  //  Mask queues  //
  ///////////////////

  localparam int unsigned MaskQueueDepth = 2;

  // There is a mask queue per lane, holding the operands that were not
  // yet used by the corresponding lane.

  // Mask queue
  strb_t [MaskQueueDepth-1:0][NrLanes-1:0] mask_queue_d, mask_queue_q;
  logic  [MaskQueueDepth-1:0][NrLanes-1:0] mask_queue_valid_d, mask_queue_valid_q;
  // We need two pointers in the mask queue. One pointer to
  // indicate with `strb_t` we are currently writing into (write_pnt),
  // and one pointer to indicate which `strb_t` we are currently
  // reading from and writing into the lanes (read_pnt).
  logic  [idx_width(MaskQueueDepth)-1:0]   mask_queue_write_pnt_d, mask_queue_write_pnt_q;
  logic  [idx_width(MaskQueueDepth)-1:0]   mask_queue_read_pnt_d, mask_queue_read_pnt_q;
  // We need to count how many valid elements are there in this mask queue.
  logic  [idx_width(MaskQueueDepth):0]     mask_queue_cnt_d, mask_queue_cnt_q;

  // Is the mask queue full?
  logic mask_queue_full;
  assign mask_queue_full = (mask_queue_cnt_q == MaskQueueDepth);
  // Is the mask queue empty?
  logic mask_queue_empty;
  assign mask_queue_empty = (mask_queue_cnt_q == '0);

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_mask_queue_ff
    if (!rst_ni) begin
      mask_queue_q           <= '0;
      mask_queue_valid_q     <= '0;
      mask_queue_write_pnt_q <= '0;
      mask_queue_read_pnt_q  <= '0;
      mask_queue_cnt_q       <= '0;
    end else begin
      mask_queue_q           <= mask_queue_d;
      mask_queue_valid_q     <= mask_queue_valid_d;
      mask_queue_write_pnt_q <= mask_queue_write_pnt_d;
      mask_queue_read_pnt_q  <= mask_queue_read_pnt_d;
      mask_queue_cnt_q       <= mask_queue_cnt_d;
    end
  end

  /////////////////////
  //  Result queues  //
  /////////////////////

  localparam int unsigned ResultQueueDepth = 2;

  // There is a result queue per lane, holding the results that were not
  // yet accepted by the corresponding lane.
  typedef struct packed {
    vid_t id;
    vaddr_t addr;
    elen_t wdata;
    strb_t be;
  } payload_t;

  // Result queue
  payload_t [ResultQueueDepth-1:0][NrLanes-1:0] result_queue_d, result_queue_q;
  logic     [ResultQueueDepth-1:0][NrLanes-1:0] result_queue_valid_d, result_queue_valid_q;
  // We need two pointers in the result queue. One pointer to
  // indicate with `payload_t` we are currently writing into (write_pnt),
  // and one pointer to indicate which `payload_t` we are currently
  // reading from and writing into the lanes (read_pnt).
  logic     [idx_width(ResultQueueDepth)-1:0]   result_queue_write_pnt_d, result_queue_write_pnt_q;
  logic     [idx_width(ResultQueueDepth)-1:0]   result_queue_read_pnt_d, result_queue_read_pnt_q;
  // We need to count how many valid elements are there in this result queue.
  logic     [idx_width(ResultQueueDepth):0]     result_queue_cnt_d, result_queue_cnt_q;
  // Vector to register the final grants from the operand requesters, which indicate
  // that the result was actually written in the VRF (while the normal grant just says
  // that the result was accepted by the operand requester stage
  logic     [NrLanes-1:0]                       result_final_gnt_d, result_final_gnt_q;

  // Result queue
  elen_t [NrLanes-1:0] result_queue_background_data;
  elen_t [NrLanes-1:0] result_queue_mask_seq;
  logic  [NrLanes*DataWidth-1:0] background_data_init_seq, background_data_init_shuf;

  // Is the result queue full?
  logic result_queue_full;
  assign result_queue_full = (result_queue_cnt_q == ResultQueueDepth);
  // Is the result queue empty?
  logic result_queue_empty;
  assign result_queue_empty = (result_queue_cnt_q == '0);

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

  ////////////////////
  //  ALU counters  //
  ////////////////////

  // What is the minimum supported parallelism?
  localparam int unsigned MIN_MASKU_ALU_WIDTH = 1; // VrgatherParallelism

  localparam int unsigned IN_READY_CNT_WIDTH = idx_width(NrLanes * DataWidth / MIN_MASKU_ALU_WIDTH);
  typedef logic [IN_READY_CNT_WIDTH-1:0] in_ready_cnt_t;
  logic in_ready_cnt_en, in_ready_cnt_clr;
  in_ready_cnt_t in_ready_cnt_delta_q, in_ready_cnt_q;
  in_ready_cnt_t in_ready_threshold_d, in_ready_threshold_q;

  assign in_ready_cnt_delta_q = 1;

  // Counter to trigger the input ready.
  // Ready triggered when all the slices of the VRF word have been consumed.
  delta_counter #(
    .WIDTH(IN_READY_CNT_WIDTH)
  ) i_in_ready_cnt (
    .clk_i,
    .rst_ni,
    .clear_i(in_ready_cnt_clr    ),
    .en_i   (in_ready_cnt_en     ),
    .load_i (1'b0                ),
    .down_i (1'b0                ),
    .delta_i(in_ready_cnt_delta_q),
    .d_i    ('0                  ),
    .q_o    (in_ready_cnt_q      ),
    .overflow_o(/* Unused */)
  );

  localparam int unsigned IN_M_READY_CNT_WIDTH = idx_width(NrLanes * DataWidth / MIN_MASKU_ALU_WIDTH);
  typedef logic [IN_M_READY_CNT_WIDTH-1:0] in_m_ready_cnt_t;
  logic in_m_ready_cnt_en, in_m_ready_cnt_clr;
  in_m_ready_cnt_t in_m_ready_cnt_q, in_m_ready_cnt_delta_q;
  in_ready_cnt_t in_m_ready_threshold_d, in_m_ready_threshold_q;

  assign in_m_ready_cnt_delta_q = 1;

  // Counter to trigger the input ready.
  // Ready triggered when all the slices of the VRF word have been consumed.
  delta_counter #(
    .WIDTH(IN_M_READY_CNT_WIDTH)
  ) i_in_m_ready_cnt (
    .clk_i,
    .rst_ni,
    .clear_i(in_m_ready_cnt_clr    ),
    .en_i   (in_m_ready_cnt_en     ),
    .load_i (1'b0                  ),
    .down_i (1'b0                  ),
    .delta_i(in_m_ready_cnt_delta_q),
    .d_i    ('0                    ),
    .q_o    (in_m_ready_cnt_q      ),
    .overflow_o(/* Unused */)
  );

  localparam int unsigned OUT_VALID_CNT_WIDTH = idx_width(NrLanes * DataWidth / MIN_MASKU_ALU_WIDTH);
  typedef logic [OUT_VALID_CNT_WIDTH-1:0] out_valid_cnt_t;
  logic out_valid_cnt_en, out_valid_cnt_clr;
  out_valid_cnt_t out_valid_cnt_q, out_valid_cnt_delta_q;
  out_valid_cnt_t out_valid_threshold_d, out_valid_threshold_q;

  assign out_valid_cnt_delta_q = 1;

  // Counter to trigger the output valid.
  // Valid triggered when all the slices of the VRF word have been consumed.
  delta_counter #(
    .WIDTH(OUT_VALID_CNT_WIDTH)
  ) i_out_valid_cnt (
    .clk_i,
    .rst_ni,
    .clear_i(out_valid_cnt_clr    ),
    .en_i   (out_valid_cnt_en     ),
    .load_i (1'b0                 ),
    .down_i (1'b0                 ),
    .delta_i(out_valid_cnt_delta_q),
    .d_i    ('0                   ),
    .q_o    (out_valid_cnt_q      ),
    .overflow_o(/* Unused */)
  );

  // How many (64*NrLanes)-bit VRF words we can get, maximum?
  localparam int unsigned MAX_NUM_VRF_WORDS = VLEN / NrLanes / 8;
  logic iteration_cnt_clr;
  logic [idx_width(MAX_NUM_VRF_WORDS)-1:0] iteration_cnt_q, iteration_cnt_delta_q;

  assign iteration_cnt_delta_q = 1;

  // Iteration count for masked instructions
  // One iteration == One full output slice processed
  delta_counter #(
    .WIDTH(idx_width(MAX_NUM_VRF_WORDS))
  ) i_iteration_cnt (
    .clk_i,
    .rst_ni,
    .clear_i(iteration_cnt_clr    ),
    .en_i   (out_valid_cnt_clr    ),
    .load_i (1'b0                 ),
    .down_i (1'b0                 ),
    .delta_i(iteration_cnt_delta_q),
    .d_i    ('0                   ),
    .q_o    (iteration_cnt_q      ),
    .overflow_o(/* Unused */)
  );

  ///////////////////////////////
  //// VRGATHER / VCOMPRESS  ////
  ///////////////////////////////

  // How deep are the VRGATHER/VCOMPRESS address/index FIFOs?
  localparam int unsigned VrgatFifoDepth = 3;

  // Mask bit sequentially selected by the m-operand delta counter
  // VRGATHER: used as a mask bit by the MASKU ALU (write-back phase of VRGATHER)
  // VCOMPRESS: used as an index bit to build the next index for address generation (first phase of VCOMPRESS)
  logic vrgat_m_seq_bit;

  // Sequential indicator to track that end of the vcompress issue phase
  logic vcompress_issue_end_d, vcompress_issue_end_q;

  // How many elements will the current vcompress write?
  vlen_t vcompress_cnt_d, vcompress_cnt_q;

  vlen_t effective_elm_cnt;

  // Sequential counter for vcompress
  vlen_t vrgat_cnt_d, vrgat_cnt_q;
  logic vcompress_bit;

  // FIFO-related signals
  logic vrgat_req_fifo_empty, vrgat_req_fifo_full, vrgat_req_fifo_push, vrgat_req_fifo_pop;
  logic vrgat_idx_fifo_empty, vrgat_idx_fifo_full, vrgat_idx_fifo_push, vrgat_idx_fifo_pop;

  max_vlen_t vrgat_req_idx_d, vrgat_req_idx_q;
  vrgat_req_t vrgat_req_d, vrgat_req_q;

  vew_e vrgat_req_eew_d;
  logic [4:0] vrgat_req_vs_d;
  logic vrgat_req_is_last_req_d;

  // If VRGATHEREI16, vsew == EW16 -> shift-by-1
  logic [1:0] vrgat_eff_vsew;
  assign vrgat_eff_vsew = (pe_req_i.op == VRGATHEREI16) ? 2'b1 : unsigned'(pe_req_i.vtype.vsew);

  assign vrgat_req_eew_d = vinsn_issue.vtype.vsew;
  assign vrgat_req_vs_d  = vinsn_issue.vs2;

  // Build the address from the index
  assign vrgat_req_d = {
    vrgat_req_idx_d / NrLanes,
    vrgat_req_eew_d,
    vrgat_req_vs_d,
    vrgat_req_is_last_req_d
  };

  // Broadcast the address request to all the lanes
  assign masku_vrgat_req_o = vrgat_req_q;

  // A mask for the valid to keep up only the unshaked ones and hide the others
  logic [NrLanes-1:0] vrgat_req_valid_mask_d, vrgat_req_valid_mask_q;

  // Synchronize the handshake between MASKU and lanes since we are making a single request
  // to all the lanes, which can also answer individually
  always_comb begin
    // Don't do anything by default
    vrgat_req_fifo_pop = 1'b0;

    // Don't hide the valids by defaults
    vrgat_req_valid_mask_d = vrgat_req_valid_mask_q;

    for (int lane = 0; lane < NrLanes; lane++) begin
      // Valid address request if the address fifo is not empty and if the valid is not masked
      masku_vrgat_req_valid_o[lane] = ~vrgat_req_fifo_empty & ~vrgat_req_valid_mask_q[lane];
      // Mask the next valid on this lane if the lane is handshaking
      vrgat_req_valid_mask_d[lane] = masku_vrgat_req_ready_i[lane];
    end

    // Don't mask if all the lanes have handshaked
    if (&masku_vrgat_req_ready_i) vrgat_req_valid_mask_d = '0;

    // Pop the current address if all the lanes have handshaked it
    if (&(masku_vrgat_req_ready_i | vrgat_req_valid_mask_q) && ~vrgat_req_fifo_empty) vrgat_req_fifo_pop = 1'b1;
  end

  // Overflow after 16-bits
  logic vrgat_idx_overflow;
  // Out-of-range (oor) indicators
  logic vrgat_idx_oor_d, vrgat_idx_oor_q;
  // Last vcompress index
  logic vcompress_last_idx_d, vcompress_last_idx_q;

  // Save the indices into the MASKU ALU vrgather/vcompress queue for later use
  // Also, save if one of the indices is out of range and if this is the last VCOMPRESS index
  fifo_v3 #(
    .DATA_WIDTH($clog2(RISCV_MAX_VLEN) + 2),
    .DEPTH     (VrgatFifoDepth            )
  ) i_fifo_vrgat_idx (
    .clk_i,
    .rst_ni,
    .flush_i   (1'b0),
    .testmode_i(1'b0),
    .full_o    (vrgat_idx_fifo_full           ),
    .empty_o   (vrgat_idx_fifo_empty          ),
    .usage_o   (/* unused */                  ),
    .data_i    ({vcompress_last_idx_d, vrgat_idx_oor_d, vrgat_req_idx_d}),
    .push_i    (vrgat_idx_fifo_push           ),
    .data_o    ({vcompress_last_idx_q, vrgat_idx_oor_q, vrgat_req_idx_q}),
    .pop_i     (vrgat_idx_fifo_pop            )
  );

  // Send the address request to the lanes
  fifo_v3 #(
    .dtype(vrgat_req_t   ),
    .DEPTH(VrgatFifoDepth)
  ) i_fifo_vrgat_req (
    .clk_i,
    .rst_ni,
    .flush_i   (1'b0),
    .testmode_i(1'b0),
    .full_o    (vrgat_req_fifo_full ),
    .empty_o   (vrgat_req_fifo_empty),
    .usage_o   (/* unused */         ),
    .data_i    (vrgat_req_d         ),
    .push_i    (vrgat_req_fifo_push ),
    .data_o    (vrgat_req_q         ),
    .pop_i     (vrgat_req_fifo_pop  )
  );

  ////////////////////////////
  //// Scalar result reg  ////
  ////////////////////////////

  elen_t result_scalar_d;
  logic  result_scalar_valid_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      result_scalar_o       <= '0;
      result_scalar_valid_o <= '0;
    end else begin
      result_scalar_o       <= result_scalar_d;
      result_scalar_valid_o <= result_scalar_valid_d;
    end
  end

  ////////////////
  //  Mask ALU  //
  ////////////////

  elen_t [NrLanes-1:0] alu_result;

  // assign operand slices to be processed by popcount and lzc
  assign vcpop_slice  = vcpop_operand[(in_ready_cnt_q[idx_width(N_SLICES_CPOP)-1:0] * VcpopParallelism) +: VcpopParallelism];
  assign vfirst_slice = vcpop_operand[(in_ready_cnt_q[idx_width(N_SLICES_VFIRST)-1:0] * VfirstParallelism) +: VfirstParallelism];

  // Population count for vcpop.m instruction
  popcount #(
    .INPUT_WIDTH (VcpopParallelism)
  ) i_popcount (
    .data_i    (vcpop_slice),
    .popcount_o(popcount     )
  );

  // Trailing zero counter
  lzc #(
    .WIDTH(VfirstParallelism),
    .MODE (0)
  ) i_clz (
    .in_i    (vfirst_slice ),
    .cnt_o   (vfirst_count ),
    .empty_o (vfirst_empty )
  );

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // Effective MASKU stride in case of VSLIDEUP
  // MASKU receives chunks of 64 * NrLanes mask bits from the lanes
  // VSLIDEUP only needs the bits whose index >= than its stride
  // So, the operand requester does not send vl mask bits to MASKU
  // and trims all the unused 64 * NrLanes mask bits chunks
  // Therefore, the stride needs to be trimmed, too
  elen_t trimmed_stride;

  // Information about which is the target FU of the request
  assign masku_operand_fu = (vinsn_issue.op inside {[VMFEQ:VMFGE]}) ? MaskFUMFpu : MaskFUAlu;

  always_comb begin
    // Tail-agnostic bus
    alu_result          = '1;
    alu_result_vm       = '1;
    alu_result_vm_m     = '1;
    alu_result_vm_shuf  = '1;
    alu_result_vmsif_vm = '1;
    alu_result_vmsbf_vm = '1;
    alu_result_vmsof_vm = '1;
    alu_result_vm       = '1;

    vcpop_operand = '0;

    vrgat_m_seq_bit = 1'b0;

    // The result mask should be created here since the output is a non-mask vector
    be_viota_seq_d = be_viota_seq_q;

    // Create a bit-masked ALU sequential vector
    masku_operand_alu_seq_m = masku_operand_alu_seq
                            & (masku_operand_m_seq | {NrLanes*DataWidth{vinsn_issue.vm}});

    // VMSBF, VMSIF, VMSOF default assignments
    found_one           = found_one_q;
    found_one_d         = found_one_q;
    vmsbf_buffer        = '0;
    // VIOTA default assignments
    viota_acc   = viota_acc_q;
    viota_acc_d = viota_acc_q;
    for (int i = 0; i < ViotaParallelism; i++) viota_res[i] = '0;

    be_vrgat_seq_d = be_vrgat_seq_q;

    if (vinsn_issue_valid) begin
      // Evaluate the instruction
      unique case (vinsn_issue.op) inside
        // Mask logical: pass through the result already computed in the ALU
        // This operation is never masked
        // This operation always writes to multiple of VRF words, and it does not need vd
        // This operation can overwrite the destination register without constraints on tail elements
        [VMANDNOT:VMXNOR]: alu_result_vm_m = masku_operand_alu_seq;
        // Comparisons: mask out the masked out bits of this pre-computed slice
        [VMFEQ:VMSGT]: alu_result_vm_m = alu_result_compressed_seq
                                  | ~(masku_operand_m_seq | {NrLanes*DataWidth{vinsn_issue.vm}});
        // Add/sub-with-carry/borrow: the masks are all 1 since these operations are NOT masked
        [VMADC:VMSBC]: alu_result_vm_m = alu_result_compressed_seq;
        // VMSBF, VMSOF, VMSIF: compute a slice of the output and mask out the masked out bits
        [VMSBF:VMSIF] : begin
          vmsbf_buffer[0] = ~(masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism] | found_one_q);
          for (int i = 1; i < VmsxfParallelism; i++) begin
            vmsbf_buffer[i] = ~((masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism + i]) | ~vmsbf_buffer[i-1]);
          end
          // Have we found a 1 in the current slice?
          found_one = |(masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism]) | found_one_q;

          alu_result_vmsbf_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = vmsbf_buffer;
          alu_result_vmsif_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = {vmsbf_buffer[VmsxfParallelism-2:0], ~found_one_q};
          alu_result_vmsof_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = ~vmsbf_buffer & {vmsbf_buffer[VmsxfParallelism-2:0], ~found_one_q};

          unique case (vinsn_issue.op)
            VMSBF: alu_result_vm = alu_result_vmsbf_vm;
            VMSIF: alu_result_vm = alu_result_vmsif_vm;
            // VMSOF
            default: alu_result_vm = alu_result_vmsof_vm;
          endcase

          // Mask the result
          alu_result_vm_m = (!vinsn_issue.vm) || (vinsn_issue.op inside {[VMADC:VMSBC]}) ? alu_result_vm | ~masku_operand_m_seq : alu_result_vm;
        end
        // VIOTA, VID: compute a slice of the output and mask out the masked elements
        // VID re-uses the VIOTA datapath
        VIOTA, VID: begin
          // Mask the input vector
          // VID uses the same datapath of VIOTA, but with implicit input vector at '1
          masku_operand_alu_seq_m = (vinsn_issue.op == VID)
                                  ? '1 // VID mask does NOT modify the count
                                  : masku_operand_alu_seq
                                    & (masku_operand_m_seq | {NrLanes*DataWidth{vinsn_issue.vm}}); // VIOTA mask DOES modify the count

          // Compute output results on `ViotaParallelism 16-bit adders
          viota_res[0] = viota_acc_q;
          for (int i = 0; i < ViotaParallelism - 1; i++) begin
            viota_res[i+1] = viota_res[i] + masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i];
          end
          viota_acc = viota_res[ViotaParallelism-1] + masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + ViotaParallelism - 1];

          // This datapath should be relativeley simple:
          // `ViotaParallelism bytes connected, in line, to output byte chunks
          // Multiple limited-width counters should help the synthesizer reduce wiring
          unique case (vinsn_issue.vtype.vsew)
            EW8: for (int i = 0; i < ViotaParallelism; i++) begin
              alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8/ViotaParallelism)-1:0]  * ViotaParallelism * 8  + i*8  +: 8]  = viota_res[i][7:0];
            end
            EW16: for (int i = 0; i < ViotaParallelism; i++) begin
              alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16/ViotaParallelism)-1:0] * ViotaParallelism * 16 + i*16 +: 16] = viota_res[i];
            end
            EW32: for (int i = 0; i < ViotaParallelism; i++) begin
              alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32/ViotaParallelism)-1:0] * ViotaParallelism * 32 + i*32 +: 32] = {{32{1'b0}}, viota_res[i]};
            end
            default: for (int i = 0; i < ViotaParallelism; i++) begin // EW64
              alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64/ViotaParallelism)-1:0] * ViotaParallelism * 64 + i*64 +: 64] = {{48{1'b0}}, viota_res[i]};
            end
          endcase

          // BE signal for VIOTA,VID
          unique case (vinsn_issue.vtype.vsew)
            EW8: for (int i = 0; i < ViotaParallelism; i++) begin
              be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8/ViotaParallelism)-1:0] * ViotaParallelism * 1 + 1*i +: 1] =
                {1{vinsn_issue.vm}} | {1{masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
            end
            EW16: for (int i = 0; i < ViotaParallelism; i++) begin
              be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16/ViotaParallelism)-1:0] * ViotaParallelism * 2 + 2*i +: 2] =
                {2{vinsn_issue.vm}} | {2{masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
            end
            EW32: for (int i = 0; i < ViotaParallelism; i++) begin
              be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32/ViotaParallelism)-1:0] * ViotaParallelism * 4 + 4*i +: 4] =
                {4{vinsn_issue.vm}} | {4{masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
            end
            default: for (int i = 0; i < ViotaParallelism; i++) begin // EW64
              be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64/ViotaParallelism)-1:0] * ViotaParallelism * 8 + 8*i +: 8] =
                {8{vinsn_issue.vm}} | {8{masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
            end
          endcase
        end
        // VRGATHER, VRGATHEREI16, VCOMPRESS get elements from the vd operand queue (not to complicate the ALU control)
        // Then, they just shuffle the operand in the correct place
        // This operation writes vsew-bit elements with vtype.vsew encoding
        // The vd source can have a different encoding (it gets deshuffled in the masku_operand stage)
        [VRGATHER:VCOMPRESS]: begin
          // Buffer for the current element
          logic [NrLanes*DataWidth-1:0] vrgat_res;
          // Buffer for the current element
          logic [DataWidth-1:0] vrgat_buf;

          // Extract the correct elements
          vrgat_res = '1; // Default assignment
          vrgat_buf = masku_operand_vd_seq[vrgat_req_idx_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64]; // Default assignment
          unique case (vinsn_issue.vtype.vsew)
            EW8: begin
              vrgat_buf[0 +: 8] = masku_operand_vd_seq[vrgat_req_idx_q[idx_width(NrLanes*ELENB/1)-1:0] * 8 +: 8];
              vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/1)-1:0] * 8 +: 8] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 8];
            end
            EW16: begin
              vrgat_buf[0 +: 16] = masku_operand_vd_seq[vrgat_req_idx_q[idx_width(NrLanes*ELENB/2)-1:0] * 16 +: 16];
              vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/2)-1:0] * 16 +: 16] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 16];
            end
            EW32: begin
              vrgat_buf[0 +: 32] = masku_operand_vd_seq[vrgat_req_idx_q[idx_width(NrLanes*ELENB/4)-1:0] * 32 +: 32];
              vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/4)-1:0] * 32 +: 32] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 32];
            end
            default: begin // EW64
              vrgat_buf[0 +: 64] = masku_operand_vd_seq[vrgat_req_idx_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64];
              vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 64];
            end
          endcase

          // BE signal for VRGATHER
		  unique case (vinsn_issue.vtype.vsew)
            EW8: begin
              vrgat_m_seq_bit = masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
              be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8)-1:0] * 1 +: 1] =
                {1{vinsn_issue.vm}} | {1{vrgat_m_seq_bit}};
            end
            EW16: begin
              vrgat_m_seq_bit = masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
              be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16)-1:0] * 2 +: 2] =
                {2{vinsn_issue.vm}} | {2{vrgat_m_seq_bit}};
            end
            EW32: begin
              vrgat_m_seq_bit = masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
              be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32)-1:0] * 4 +: 4] =
                {4{vinsn_issue.vm}} | {4{vrgat_m_seq_bit}};
            end
            default: begin // EW64
              vrgat_m_seq_bit = masku_operand_m_seq[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
              be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64)-1:0] * 8 +: 8] =
                {8{vinsn_issue.vm}} | {8{vrgat_m_seq_bit}};
            end
          endcase

          alu_result_vm_m = vrgat_res;
        end
        // VCPOP, VFIRST: mask the current slice and feed the popc or lzc unit
        [VCPOP:VFIRST] : begin
          vcpop_operand = (!vinsn_issue.vm) ? masku_operand_alu_seq & masku_operand_m_seq : masku_operand_alu_seq;
        end
        default:;
      endcase
    end

    // Shuffle the sequential result with vtype.vsew encoding
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte              = shuffle_index(b, NrLanes, vinsn_issue.vtype.vsew);
      alu_result_vm_shuf[8*shuffle_byte +: 8] = alu_result_vm_m[8*b +: 8];
    end

    // Shuffle the VIOTA, VID, VRGATHER, VCOMPRESS byte enable signal
    be_masku_alu_shuf = '0;
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte  = shuffle_index(b, NrLanes, vinsn_issue.vtype.vsew);
      be_masku_alu_shuf[shuffle_byte] = vinsn_issue.op inside {VRGATHER,VRGATHEREI16} ? be_vrgat_seq_d[b] : be_viota_seq_d[b];
    end

    // Simplify layout handling
    alu_result = alu_result_vm_shuf;

    // Prepare the background data with vtype.vsew encoding
    result_queue_mask_seq = vinsn_issue.op inside {[VIOTA:VID], [VRGATHER:VCOMPRESS]} ? '0 : masku_operand_m_seq | {NrLanes*DataWidth{vinsn_issue.vm}} | {NrLanes*DataWidth{vinsn_issue.op inside {[VMADC:VMSBC]}}};
    background_data_init_seq = masku_operand_vd_seq | result_queue_mask_seq;
    background_data_init_shuf = '0;
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte                     = shuffle_index(b, NrLanes, vinsn_issue.vtype.vsew);
      background_data_init_shuf[8*shuffle_byte +: 8] = background_data_init_seq[8*b +: 8];
    end

  /////////////////
  //  Mask unit  //
  /////////////////

    // Maintain state
    vinsn_queue_d    = vinsn_queue_q;
    read_cnt_d       = read_cnt_q;
    issue_cnt_d      = issue_cnt_q;
    processing_cnt_d = processing_cnt_q;
    commit_cnt_d     = commit_cnt_q;

    mask_pnt_d     = mask_pnt_q;
    vrf_pnt_d      = vrf_pnt_q;

    popcount_d        = popcount_q;
    vfirst_count_d    = vfirst_count_q;

    mask_queue_d           = mask_queue_q;
    mask_queue_valid_d     = mask_queue_valid_q;
    mask_queue_write_pnt_d = mask_queue_write_pnt_q;
    mask_queue_read_pnt_d  = mask_queue_read_pnt_q;
    mask_queue_cnt_d       = mask_queue_cnt_q;

    result_queue_d           = result_queue_q;
    result_queue_valid_d     = result_queue_valid_q;
    result_queue_write_pnt_d = result_queue_write_pnt_q;
    result_queue_read_pnt_d  = result_queue_read_pnt_q;
    result_queue_cnt_d       = result_queue_cnt_q;

    result_final_gnt_d = result_final_gnt_q;

    trimmed_stride = pe_req_i.stride;

    out_vrf_word_valid = 1'b0;
    out_scalar_valid   = 1'b0;

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // Mask the response, by default
    pe_resp = '0;

    // We are not ready, by default
    masku_operand_alu_ready    = '0;
    masku_operand_m_ready      = '0;
    masku_operand_vd_ready     = '0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    // scalar path signals
    result_scalar_d       = result_scalar_o;
    result_scalar_valid_d = result_scalar_valid_o;

    // Don't handshake the inputs
    in_ready_cnt_en   = 1'b0;
    in_m_ready_cnt_en = 1'b0;
    out_valid_cnt_en  = 1'b0;

    // Result queue background data
    for (int unsigned lane = 0; lane < NrLanes; lane++)
      result_queue_background_data[lane] = result_queue_q[result_queue_write_pnt_q][lane].wdata;

    // Maintain state
    delta_elm_d = delta_elm_q;
    in_ready_threshold_d   = in_ready_threshold_q;
    in_m_ready_threshold_d = in_m_ready_threshold_q;
    out_valid_threshold_d  = out_valid_threshold_q;

    in_ready_cnt_clr   = 1'b0;
    in_m_ready_cnt_clr = 1'b0;
    out_valid_cnt_clr  = 1'b0;
    iteration_cnt_clr  = 1'b0;

    ////////////////////////////
    //  Predicated execution  //
    ////////////////////////////

    // Instructions that run in other units, but need mask strobes for predicated execution

    // Is there space in the result queue?
    if (!mask_queue_full) begin
      // Copy data from the mask operands into the mask queue
      for (int vrf_seq_byte = 0; vrf_seq_byte < NrLanes*StrbWidth; vrf_seq_byte++) begin
        // Map vrf_seq_byte to the corresponding byte in the VRF word.
        automatic int vrf_byte = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue.vtype.vsew);

        // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
        // NOTE: This does not work if the number of lanes is not a power of two.
        // If that is needed, the following two lines must be changed accordingly.
        automatic int vrf_lane   = vrf_byte >> $clog2(StrbWidth);
        automatic int vrf_offset = vrf_byte[idx_width(StrbWidth)-1:0];

        // The VRF pointer can be broken into a byte offset, and a bit offset
        automatic int vrf_pnt_byte_offset = mask_pnt_q >> $clog2(StrbWidth);
        automatic int vrf_pnt_bit_offset  = mask_pnt_q[idx_width(StrbWidth)-1:0];

        // A single bit from the mask operands can be used several times, depending on the eew.
        automatic int mask_seq_bit  = vrf_seq_byte >> int'(vinsn_issue.vtype.vsew);
        automatic int mask_seq_byte = (mask_seq_bit >> $clog2(StrbWidth)) + vrf_pnt_byte_offset;
        // Shuffle this source byte
        automatic int mask_byte     = shuffle_index(mask_seq_byte, NrLanes, vinsn_issue.eew_vmask);
        // Account for the bit offset
        automatic int mask_bit = (mask_byte << $clog2(StrbWidth)) +
          mask_seq_bit[idx_width(StrbWidth)-1:0] + vrf_pnt_bit_offset;

        // At which lane, and what is the bit offset in that lane, of the mask operand from
        // mask_seq_bit?
        automatic int mask_lane   = mask_bit >> idx_width(DataWidth);
        automatic int mask_offset = mask_bit[idx_width(DataWidth)-1:0];

        // Copy the mask operand
        mask_queue_d[mask_queue_write_pnt_q][vrf_lane][vrf_offset] =
          masku_operand_m[mask_lane][mask_offset];
      end

      // Is there an instruction ready to be issued?
      if (vinsn_issue_valid && ((vinsn_issue.vfu != VFU_MaskUnit) || (vinsn_issue.op inside {[VMADC:VMSBC]}))) begin
        // Is there place in the mask queue to write the mask operands?
        // Did we receive the mask bits on the MaskM channel?
        if (!vinsn_issue.vm && &masku_operand_m_valid) begin
          // Account for the used operands
          mask_pnt_d += NrLanes * (1 << (int'(EW64) - vinsn_issue.vtype.vsew));

          // Increment result queue pointers and counters
          mask_queue_cnt_d += 1;
          if (mask_queue_write_pnt_q == MaskQueueDepth-1)
            mask_queue_write_pnt_d = '0;
          else
            mask_queue_write_pnt_d = mask_queue_write_pnt_q + 1;

          // Account for the operands that were issued
          read_cnt_d = read_cnt_q - NrLanes * (1 << (int'(EW64) - vinsn_issue.vtype.vsew));
          if (read_cnt_q < NrLanes * (1 << (int'(EW64) - vinsn_issue.vtype.vsew)))
            read_cnt_d = '0;

          // Trigger the request signal
          mask_queue_valid_d[mask_queue_write_pnt_q] = {NrLanes{1'b1}};

          // Are there lanes with no valid elements?
          // If so, mute their request signal
          if (read_cnt_q < NrLanes)
            mask_queue_valid_d[mask_queue_write_pnt_q] = (1 << read_cnt_q) - 1;

          // Consumed all valid bytes from the lane operands
          if (mask_pnt_d == NrLanes*DataWidth || read_cnt_d == '0) begin
            // Request another beat
            masku_operand_m_ready = '1;
            // Reset the pointer
            mask_pnt_d = '0;
          end
        end
      end
    end

    // Send Mask Operands to the VFUs
    for (int lane = 0; lane < NrLanes; lane++) begin: send_operand
      mask_valid_o[lane] = mask_queue_valid_q[mask_queue_read_pnt_q][lane];
      mask_o[lane]       = mask_queue_q[mask_queue_read_pnt_q][lane];
      // Received a grant from the VFUs.
      // The VLDU and the VSTU acknowledge all the operands at once.
      // Only accept the acknowledgement from the lanes if the current instruction is executing there.
      // Deactivate the request, but do not bump the pointers for now.
      if ((lane_mask_ready_i[lane] && mask_valid_o[lane] && (vinsn_issue.vfu inside {VFU_Alu, VFU_MFpu} || vinsn_issue.op inside {[VMADC:VMSBC]})) ||
           vldu_mask_ready_i || vstu_mask_ready_i || sldu_mask_ready_i) begin
        mask_queue_valid_d[mask_queue_read_pnt_q][lane] = 1'b0;
        mask_queue_d[mask_queue_read_pnt_q][lane]       = '0;
      end
    end: send_operand

    // Is this operand going to the lanes?
    mask_valid_lane_o = vinsn_issue.vfu inside {VFU_Alu, VFU_MFpu, VFU_MaskUnit};

    // All lanes accepted the VRF request
    if (!(|mask_queue_valid_d[mask_queue_read_pnt_q])) begin
      // There is something waiting to be written
      if (!mask_queue_empty) begin
        // Increment the read pointer
        if (mask_queue_read_pnt_q == MaskQueueDepth-1)
          mask_queue_read_pnt_d = 0;
        else
          mask_queue_read_pnt_d = mask_queue_read_pnt_q + 1;

        // Reset the queue
        mask_queue_d[mask_queue_read_pnt_q] = '0;

        // Decrement the counter of mask operands waiting to be used
        mask_queue_cnt_d -= 1;

        // Decrement the counter of remaining vector elements waiting to be used
        if (vldu_mask_ready_i || vstu_mask_ready_i || sldu_mask_ready_i || vinsn_issue.vm || (vinsn_issue.vfu != VFU_MaskUnit)) begin
          commit_cnt_d = commit_cnt_q - NrLanes * (1 << (int'(EW64) - vinsn_commit.vtype.vsew));
          if (commit_cnt_q < (NrLanes * (1 << (int'(EW64) - vinsn_commit.vtype.vsew))))
            commit_cnt_d = '0;
        end
      end
    end

    ////////////////////////
    //  Index generation  //
    ////////////////////////

    // VRGATHER, VCOMPRESS require index generation and ad-hoc operand requesters
    // The indices come from the VALU, while the operands will pass through the Vd operand queue (MaskB)
    // This implementation is simple and unoptimized:
    // We ask all the lanes in parallel for a precise index, and we will get a balanced payload from them.
    // Only one element of the payload is important, the rest is discarded.
    // This can be easily optimized by asking only the correct lane and by handling unbalanced payloads.

    vrgat_cnt_d = vrgat_cnt_q;

    vrgat_req_idx_d = '0;
    vrgat_idx_fifo_push = 1'b0;
    vrgat_req_fifo_push = 1'b0;

    // Track if an index overflow occurred past the 16 sampled bits
    vrgat_idx_overflow = 1'b0;

    // Track if the index is out of range
    vrgat_idx_oor_d = 1'b0;

    vcompress_bit = 1'b0;

    vrgat_req_is_last_req_d = 1'b0;

    vcompress_last_idx_d = 1'b0;

    vcompress_issue_end_d = vcompress_issue_end_q;

    vcompress_cnt_d = vcompress_cnt_q;

    // Control counters in the pre-issue phase
    if (vinsn_issue_valid) begin
      unique case (vinsn_issue.op)
        VCOMPRESS: begin
          // Select the current enable bit
          vcompress_bit = masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
          // Select the current index
          vrgat_req_idx_d = vrgat_cnt_q;
          if (&masku_operand_alu_valid && ~vrgat_idx_fifo_full && ~vrgat_req_fifo_full) begin
            // Check vrgat_m_seq_bit: we can use this since VRGATHER and VCOMPRESS are mutually exclusive
            // and the masku_operand_m is used in different ways
            if (vcompress_bit) begin
              // Push this index and address if the fifos are free and if the mask bit is set
              vrgat_idx_fifo_push = 1'b1;
              vrgat_req_fifo_push = 1'b1;
              // Increase the number of elements to write
              vcompress_cnt_d = vcompress_cnt_q + 1;
            end
          end
        end
        VRGATHER,
        VRGATHEREI16: begin
          // Find the maximum vector length. VLMAX = LMUL * VLEN / SEW.
          automatic int unsigned vlmax = (VLEN/8) >> vinsn_issue.vtype.vsew;
          unique case (vinsn_issue.vtype.vlmul)
            LMUL_1  : vlmax <<= 0;
            LMUL_2  : vlmax <<= 1;
            LMUL_4  : vlmax <<= 2;
            LMUL_8  : vlmax <<= 3;
            // Fractional LMUL
            LMUL_1_2: vlmax >>= 1;
            LMUL_1_4: vlmax >>= 2;
            LMUL_1_8: vlmax >>= 3;
            default:;
          endcase

          // VRGATHER: treat the index as a vtype.vsew-bit number
          if (vinsn_issue.op == VRGATHER) begin
            unique case (vinsn_issue.vtype.vsew)
              EW8: begin
                vrgat_req_idx_d = {8'b0, masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/8)-1:0] * 8 +: 8]};
              end
              EW16: begin
                vrgat_req_idx_d = masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/16)-1:0] * 16 +: 16];
              end
              EW32: begin
                vrgat_req_idx_d = masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/32)-1:0] * 32 +: 16];
                vrgat_idx_overflow = |masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/32)-1:0] * 32 + 16 +: 32 - 16];
              end
              default: begin // EW64
                vrgat_req_idx_d = masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/64)-1:0] * 64 +: 16];
                vrgat_idx_overflow = |masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/64)-1:0] * 64 + 16 +: 64 - 16];
              end
            endcase
          end else begin
            // VRGATHEREI16: treat the index as a 16-bit number
            vrgat_req_idx_d = masku_operand_alu_seq[vrgat_cnt_q[idx_width(NrLanes*DataWidth/16)-1:0] * 16 +: 16];
          end

          // VRGATHER.v[x|i] splats one scalar into Vd. The scalar is not truncated
          if (vinsn_issue.use_scalar_op) begin
            vrgat_req_idx_d = vinsn_issue.scalar_op[15:0];
            vrgat_idx_overflow = |vinsn_issue.scalar_op[16 +: ELEN - 16];
          end

          vrgat_idx_oor_d = (vrgat_req_idx_d >= vlmax) | vrgat_idx_overflow;

          // Proceed if the FIFOs are not full
          if (&masku_operand_alu_valid && ~vrgat_idx_fifo_full && ~vrgat_req_fifo_full) begin
            // Push the index no matter what
            vrgat_idx_fifo_push = 1'b1;
            // Request to the lanes only if the index is within range
            if (!vrgat_idx_oor_d) begin
              vrgat_req_fifo_push = 1'b1;
            end
          end
        end
        default:;
      endcase
    end

    // Handle the counters
    if (vinsn_issue.op inside {[VRGATHER:VCOMPRESS]} && &masku_operand_alu_valid && (vrgat_idx_fifo_push || (~vrgat_idx_fifo_full && ~vrgat_req_fifo_full && (vinsn_issue.op == VCOMPRESS)))) begin
      // Count up if we could process the current input chunk
      vrgat_cnt_d = vrgat_cnt_q + 1;
      in_ready_cnt_en = 1'b1;

      // We either finished or we need to ask a new idx operand
      if ((in_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0] == in_ready_threshold_q) || (vrgat_cnt_q == (vinsn_issue.vl - 1))) begin
        in_ready_cnt_clr = 1'b1;
        masku_operand_alu_ready = '1;
        // Check if we are over
        if (vrgat_cnt_q == (vinsn_issue.vl - 1)) begin
          vrgat_cnt_d = '0;
          vcompress_last_idx_d = (vinsn_issue.op == VCOMPRESS);
          // End of the pre-issue phase
          vrgat_req_is_last_req_d = 1'b1;
        end
      end
    end

    ///////////////////////
    // MASKU ALU Control //
    ///////////////////////

    // Instructions that natively run in the MASKU

    // The main data packets come from the lanes' ALUs.
    // Also, mask- and tail-undisturbed policies are implemented by fetching the destination register,
    // which is the default value of the result queue.

    // Almost all the operations are time multiplexed. Moreover, some operations (e.g., VIOTA) work on
    // different input and output data widths, meaning that the input ready and the final output valid
    // are not always synchronized.

    vrgat_idx_fifo_pop = 1'b0;

    // How many elements {VIOTA|VID|VRGATHER|VRGATHEREI16} are writing to each lane
    // VCOMPRESS follows its own counter
    effective_elm_cnt = vinsn_issue.op == VCOMPRESS ? vcompress_cnt_q : processing_cnt_q;
    elm_per_lane = effective_elm_cnt / NrLanes;
    if ((effective_elm_cnt / NrLanes) > 4'b1000)
      elm_per_lane = 4'b1000;
    for (int l = 0; l < NrLanes; l++) additional_elm[l] = effective_elm_cnt[idx_width(NrLanes)-1:0] > l;

    // Default operand queue assignment
    for (int unsigned lane = 0; lane < NrLanes; lane++) begin
      result_queue_d[result_queue_write_pnt_q][lane] = '{
        wdata: result_queue_q[result_queue_write_pnt_q][lane].wdata, // Retain the last-cycle's data
		// VIOTA, VID generate a non-mask vector and should comply with undisturbed policy
        // This means that we can use the byte-enable signal
        be   : vinsn_issue.op inside {[VIOTA:VID],[VRGATHER:VCOMPRESS]}
               ? be(elm_per_lane + additional_elm[lane], vinsn_issue.vtype.vsew) & be_masku_alu_shuf[lane*StrbWidth +: StrbWidth]
               : '1,
        addr : vaddr(vinsn_issue.vd, NrLanes, VLEN) + iteration_cnt_q,
        id   : vinsn_issue.id
      };
    end

    // Is there an instruction ready to be issued?
    if (vinsn_issue_valid && vinsn_issue.op inside {[VMFEQ:VCOMPRESS]}) begin
      // Compute one slice if we can write and the necessary inputs are valid
      // VID does not require any operand, while VRGATHER/VCOMPRESS's ALU operand is just preprocessed to get the indices.
      // Therefore, VRGATHER/VCOMPRESS's operand are special. Only the vd operand works in the MASKU ALU.
      if (!result_queue_full && (&masku_operand_alu_valid || vinsn_issue.op inside {VID,[VRGATHER:VCOMPRESS]})
                             && (&masku_operand_vd_valid  || (!vinsn_issue.use_vd_op && !(vinsn_issue.op inside {[VRGATHER:VCOMPRESS]})))
                             && (&masku_operand_m_valid   || vinsn_issue.vm || vinsn_issue.op inside {[VMADC:VMSBC]})
                             && (!vrgat_idx_fifo_empty    || !(vinsn_issue.op inside {[VRGATHER:VCOMPRESS]}))) begin

        // Write the result queue on the background data - either vd or the previous result
        // The mask vector writes at 1 (tail-agnostic ok value) both the background body
        // elements that will be written by the MASKU ALU and the tail elements.
        for (int unsigned lane = 0; lane < NrLanes; lane++) begin
          result_queue_background_data[lane] = (out_valid_cnt_q != '0)
                                             ? result_queue_q[result_queue_write_pnt_q][lane].wdata
                                             : vinsn_issue.op inside {[VIOTA:VID], [VRGATHER:VCOMPRESS]} ? '1 : background_data_init_shuf[lane*DataWidth +: DataWidth];
        end
        for (int unsigned lane = 0; lane < NrLanes; lane++) begin
          // The alu_result has all the bits at 1 except for the portion of bits to write.
          // The masking is already applied in the MASKU ALU.
          result_queue_d[result_queue_write_pnt_q][lane].wdata = result_queue_background_data[lane] & alu_result[lane];
        end
        // Write the scalar accumulator
        popcount_d = popcount_q + popcount;
        vfirst_count_d = vfirst_count_q + vfirst_count;

        // Bump MASKU ALU state
        found_one_d = found_one;
        viota_acc_d = viota_acc;
        vrf_pnt_d   = vrf_pnt_q + delta_elm_q;
        if (vinsn_issue.op inside {[VRGATHER:VCOMPRESS]}) vrgat_idx_fifo_pop = 1'b1;

        // Increment the input, input-mask, and output slice counters
        if (!(vinsn_issue.op inside {[VRGATHER:VCOMPRESS]})) in_ready_cnt_en = 1'b1;
        if (!(vinsn_issue.op inside {[VMADC:VMSBC]})) in_m_ready_cnt_en = 1'b1;
        out_valid_cnt_en  = 1'b1;

        // Account for the elements that have been processed
        issue_cnt_d = issue_cnt_q - delta_elm_q;
        if (issue_cnt_q < delta_elm_q)
          issue_cnt_d = '0;

        // Request new input (by completing ready-valid handshake) once all slices have been processed
        // Alu input is accessed in different widths
        // VRGATHER and VCOMPRESS handle the ALU operand for the index generation before the MASKU ALU gets the operands
        if ((((in_ready_cnt_q == in_ready_threshold_q) || (issue_cnt_d == '0)) && !(vinsn_issue.op inside {[VRGATHER:VCOMPRESS]})) || (!vfirst_empty && (vinsn_issue.op == VFIRST))) begin
          in_ready_cnt_clr = 1'b1;
          if (vinsn_issue.op != VID) begin
            masku_operand_alu_ready = '1;
          end
        end
        // Mask is always accessed at bit level
        // VMADC, VMSBC handle masks in the mask queue
        if ((((in_m_ready_cnt_q == in_m_ready_threshold_q) || (issue_cnt_d == '0)) && !(vinsn_issue.op inside {[VMADC:VMSBC]})) || (!vfirst_empty && (vinsn_issue.op == VFIRST))) begin
          in_m_ready_cnt_clr = 1'b1;
          if (!vinsn_issue.vm) begin
            masku_operand_m_ready = '1;
          end
        end

        // This vcompress has written less than vl elements
        vcompress_issue_end_d = vcompress_last_idx_q;
        // Write to the result queue if the entry is full or if this is the last output
        // if this is the last output slice of the vector.
        // Also, handshake the vd input, which follows the output.
        if (vinsn_issue.op inside {[VRGATHER:VCOMPRESS]}) masku_operand_vd_ready = '1;
        if ((out_valid_cnt_q == out_valid_threshold_q) || (issue_cnt_d == '0) || vcompress_last_idx_q) begin
          out_valid_cnt_clr = 1'b1;
          // Handshake vd input
          if (vinsn_issue.use_vd_op) begin
            masku_operand_vd_ready = '1;
          end
          // Assert valid result queue output
          out_vrf_word_valid = !vd_scalar(vinsn_issue.op);
        end

        // The scalar result is valid for write back at the end of the operation.
        // VFIRST can also interrupt the operation in advance when the 1 is found.
        if (issue_cnt_d == '0 || (!vfirst_empty && (vinsn_issue.op == VFIRST))) begin
          // Assert valid scalar output
          out_scalar_valid = vd_scalar(vinsn_issue.op);
        end

        // Have we finished insn execution? Clear MASKU ALU state
        if (issue_cnt_d == '0) begin
          be_viota_seq_d = '1; // Default: write
          be_vrgat_seq_d = '1; // Default: write
          viota_acc_d    = '0;
          found_one_d    = '0;
        end
      end
    end

    // Write VRF words to the result queue
    if (out_vrf_word_valid) begin
      // Write to the lanes
      result_queue_valid_d[result_queue_write_pnt_q] = {NrLanes{1'b1}};

      // Increment result queue pointers and counters
      result_queue_cnt_d += 1;
      result_queue_write_pnt_d = result_queue_write_pnt_q + 1;
      if (result_queue_write_pnt_q == ResultQueueDepth-1) begin
        result_queue_write_pnt_d = '0;
      end

      // Clear MASKU ALU state
      be_viota_seq_d = '1;
      be_vrgat_seq_d = '1;

      // Account for the written results
      // VIOTA and VID do not write bits!
      processing_cnt_d = vinsn_issue.op inside {[VIOTA:VID], [VRGATHER:VRGATHEREI16]} ? processing_cnt_q - ((NrLanes * DataWidth / 8) >> vinsn_issue.vtype.vsew) : processing_cnt_q - NrLanes * DataWidth;
      // Account for the written results by VCOMPRESS
      if (vinsn_issue.op == VCOMPRESS) begin
        vcompress_cnt_d = vcompress_cnt_d - ((NrLanes * DataWidth / 8) >> vinsn_issue.vtype.vsew);
      end
    end

    // The scalar result has been sent to and acknowledged by the dispatcher
    if (out_scalar_valid) begin
      result_scalar_d = (vinsn_issue.op == VCPOP) ? popcount_d : ((vfirst_empty) ? -1 : vfirst_count_d);
      result_scalar_valid_d = '1;

      // The instruction is over
      issue_cnt_d       = '0;
      processing_cnt_d  = '0;
      commit_cnt_d      = '0;
    end

    // Finished issuing results
    if (vinsn_issue_valid && (
          ( (vinsn_issue.vm || vinsn_issue.vfu == VFU_MaskUnit) && issue_cnt_d == '0) || vcompress_issue_end_q ||
          (!(vinsn_issue.vm || vinsn_issue.vfu == VFU_MaskUnit) && read_cnt_d  == '0))) begin
      // The instruction finished its issue phase
      vinsn_queue_d.issue_cnt -= 1;
    end

    //////////////
    //  Commit  //
    //////////////

    for (int lane = 0; lane < NrLanes; lane++) begin: result_write
      masku_result_req_o[lane]   = result_queue_valid_q[result_queue_read_pnt_q][lane];
      masku_result_addr_o[lane]  = result_queue_q[result_queue_read_pnt_q][lane].addr;
      masku_result_id_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].id;
      masku_result_wdata_o[lane] = result_queue_q[result_queue_read_pnt_q][lane].wdata;
      masku_result_be_o[lane]    = result_queue_q[result_queue_read_pnt_q][lane].be;

      // Update the final gnt vector
      result_final_gnt_d[lane] |= masku_result_final_gnt_i[lane];

      // Received a grant from the VRF.
      // Deactivate the request, but do not bump the pointers for now.
      if (masku_result_req_o[lane] && masku_result_gnt_i[lane]) begin
        result_queue_valid_d[result_queue_read_pnt_q][lane] = 1'b0;
        result_queue_d[result_queue_read_pnt_q][lane]       = '0;
        // Reset the final gnt vector since we are now waiting for another final gnt
        result_final_gnt_d[lane] = 1'b0;
      end
    end: result_write

    // All lanes accepted the VRF request
    if (!(|result_queue_valid_d[result_queue_read_pnt_q]) &&
      (&result_final_gnt_d || (commit_cnt_q > (NrLanes * DataWidth)))) begin
      // There is something waiting to be written
      if (!result_queue_empty) begin
        // Increment the read pointer
        if (result_queue_read_pnt_q == ResultQueueDepth-1)
          result_queue_read_pnt_d = 0;
        else
          result_queue_read_pnt_d = result_queue_read_pnt_q + 1;

        // Decrement the counter of results waiting to be written
        result_queue_cnt_d -= 1;

        // Reset the queue
        result_queue_d[result_queue_read_pnt_q] = '0;

        // Decrement the counter of remaining vector elements waiting to be written
        if (!(vinsn_commit.op inside {VSE})) begin
          if (vinsn_commit.op inside {[VIOTA:VID],[VRGATHER:VCOMPRESS]}) begin
            commit_cnt_d = commit_cnt_q - ((NrLanes * DataWidth / 8) >> unsigned'(vinsn_commit.vtype.vsew));
            if (commit_cnt_q < ((NrLanes * DataWidth / 8) >> unsigned'(vinsn_commit.vtype.vsew)))
              commit_cnt_d = '0;
          end else begin
            commit_cnt_d = commit_cnt_q - NrLanes * DataWidth;
            if (commit_cnt_q < (NrLanes * DataWidth))
              commit_cnt_d = '0;
          end
        end
      end
    end

    // Finished committing the results of a vector instruction
    if (vinsn_commit_valid && ((commit_cnt_d == '0) || (!(|result_queue_valid_q[result_queue_read_pnt_q]) && vcompress_issue_end_q))) begin
      // Clear the iteration counter
      out_valid_cnt_clr = 1'b1;

      // Clear the vrf pointer for comparisons
      vrf_pnt_d = '0;

      // Clear the vcompress issue-end indicator
      vcompress_cnt_d = '0;

      // Clear the iteration counter
      iteration_cnt_clr = 1'b1;

      if(&result_final_gnt_d || vd_scalar(vinsn_commit.op) || vinsn_commit.vfu != VFU_MaskUnit) begin
        // Mark the vector instruction as being done
        pe_resp.vinsn_done[vinsn_commit.id] = 1'b1;

        // Clear the vcompress end indicator
        vcompress_issue_end_d = 1'b0;

        // Update the commit counters and pointers
        vinsn_queue_d.commit_cnt -= 1;
      end
    end

    ///////////////////////////
    // Commit scalar results //
    ///////////////////////////

    // This is one cycle after asserting out_scalar_valid
    // Ara's frontend is always ready to accept the scalar result
    if (result_scalar_valid_o) begin
      // Reset result_scalar
      result_scalar_d       = '0;
      result_scalar_valid_d = '0;

      // Clear the iteration counter
      iteration_cnt_clr = 1'b1;

      // Reset the popcount and vfirst_count
      popcount_d     = '0;
      vfirst_count_d = '0;
    end

    //////////////////////////////
    //  Accept new instruction  //
    //////////////////////////////

    // Trim the slide stride if it is higher than NrLanes * 64
    // and we have a VSLIDEUP, as the mask bits with index lower than
    // this stride are not used and therefore not sent to the MASKU
    if (pe_req_i.stride >= NrLanes * 64)
      trimmed_stride = pe_req_i.stride - ((pe_req_i.stride >> NrLanes * 64) << NrLanes * 64);

    if (!vinsn_queue_full && pe_req_valid_i && !vinsn_running_q[pe_req_i.id] &&
        (!pe_req_i.vm || pe_req_i.vfu == VFU_MaskUnit)) begin
      vinsn_queue_d.vinsn[0]       = pe_req_i;
      vinsn_running_d[pe_req_i.id] = 1'b1;

      // Initialize counters
      if (vinsn_queue_d.issue_cnt == '0) begin
        issue_cnt_d      = pe_req_i.vl;
        processing_cnt_d = pe_req_i.vl;
        read_cnt_d       = pe_req_i.vl;

        // Trim skipped words
        if (pe_req_i.op == VSLIDEUP) begin
          issue_cnt_d      -= vlen_t'(trimmed_stride);
          processing_cnt_d -= vlen_t'(trimmed_stride);
          case (pe_req_i.vtype.vsew)
            EW8:  begin
              read_cnt_d -= (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 3)) << $clog2(NrLanes << 3);
              mask_pnt_d  = (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 3)) << $clog2(NrLanes << 3);
            end
            EW16: begin
              read_cnt_d -= (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 2)) << $clog2(NrLanes << 2);
              mask_pnt_d  = (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 2)) << $clog2(NrLanes << 2);
            end
            EW32: begin
              read_cnt_d -= (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 1)) << $clog2(NrLanes << 1);
              mask_pnt_d  = (vlen_t'(trimmed_stride) >> $clog2(NrLanes << 1)) << $clog2(NrLanes << 1);
            end
            EW64: begin
              read_cnt_d -= (vlen_t'(trimmed_stride) >> $clog2(NrLanes)) << $clog2(NrLanes);
              mask_pnt_d  = (vlen_t'(trimmed_stride) >> $clog2(NrLanes)) << $clog2(NrLanes);
            end
            default:;
          endcase
        end

        // Initialize ALU MASKU counters and pointers
        unique case (pe_req_i.op) inside
          [VMFEQ:VMSGT]: begin
            // Mask to mask - encoded
            delta_elm_d = NrLanes << (EW64 - pe_req_i.eew_vs2[1:0]);

            in_ready_threshold_d   = 0;
            in_m_ready_threshold_d = (DataWidth >> (EW64 - pe_req_i.eew_vs2[1:0]))-1;
            out_valid_threshold_d  = (DataWidth >> (EW64 - pe_req_i.eew_vs2[1:0]))-1;
          end
          [VMADC:VMSBC]: begin
            // Mask to mask - encoded
            delta_elm_d = NrLanes << (EW64 - pe_req_i.eew_vs2[1:0]);

            in_ready_threshold_d   = 0;
            in_m_ready_threshold_d = (DataWidth >> (EW64 - pe_req_i.eew_vs2[1:0]))-1;
            out_valid_threshold_d  = (DataWidth >> (EW64 - pe_req_i.eew_vs2[1:0]))-1;
          end
          [VMANDNOT:VMXNOR]: begin
            // Mask to mask
            delta_elm_d = VmLogicalParallelism;

            in_ready_threshold_d   = NrLanes*DataWidth/VmLogicalParallelism-1;
            in_m_ready_threshold_d = NrLanes*DataWidth/VmLogicalParallelism-1;
            out_valid_threshold_d  = NrLanes*DataWidth/VmLogicalParallelism-1;
          end
          [VMSBF:VMSIF]: begin
            // Mask to mask
            delta_elm_d = VmsxfParallelism;

            in_ready_threshold_d   = NrLanes*DataWidth/VmsxfParallelism-1;
            in_m_ready_threshold_d = NrLanes*DataWidth/VmsxfParallelism-1;
            out_valid_threshold_d  = NrLanes*DataWidth/VmsxfParallelism-1;
          end
          [VIOTA:VID]: begin
            // Mask to non-mask
            delta_elm_d = ViotaParallelism;

            in_ready_threshold_d   = NrLanes*DataWidth/ViotaParallelism-1;
            in_m_ready_threshold_d = NrLanes*DataWidth/ViotaParallelism-1;
            out_valid_threshold_d  = ((NrLanes*DataWidth/8/ViotaParallelism) >> pe_req_i.vtype.vsew[1:0])-1;
          end
          VCPOP: begin
            popcount_d = '0;

            // Mask to scalar
            delta_elm_d = VcpopParallelism;

            in_ready_threshold_d   = NrLanes*DataWidth/VcpopParallelism-1;
            in_m_ready_threshold_d = NrLanes*DataWidth/VcpopParallelism-1;
            out_valid_threshold_d  = '0;
          end
          VFIRST: begin
            vfirst_count_d = '0;

            // Mask to scalar
            delta_elm_d = VfirstParallelism;

            in_ready_threshold_d   = NrLanes*DataWidth/VfirstParallelism-1;
            in_m_ready_threshold_d = NrLanes*DataWidth/VfirstParallelism-1;
            out_valid_threshold_d  = '0;
          end
          default: begin // VRGATHER, VRGATHEREI16, VCOMPRESS
            delta_elm_d = 1;

            in_ready_threshold_d   = pe_req_i.op == VCOMPRESS ? NrLanes*DataWidth-1 : ((NrLanes*DataWidth/8) >> vrgat_eff_vsew)-1;
            in_m_ready_threshold_d = NrLanes*DataWidth-1;
            out_valid_threshold_d  = ((NrLanes*DataWidth/8) >> pe_req_i.vtype.vsew[1:0])-1;

            vrgat_cnt_d = '0;
          end
        endcase

        // Reset the final grant vector
        // Be aware: this works only if the insn queue length is 1
        result_final_gnt_d = '0;
      end
      if (vinsn_queue_d.commit_cnt == '0) begin
        commit_cnt_d = pe_req_i.vl;
        // Trim skipped words
        if (pe_req_i.op == VSLIDEUP)
          commit_cnt_d -= vlen_t'(trimmed_stride);
      end

      // Bump pointers and counters of the vector instruction queue
      vinsn_queue_d.issue_cnt += 1;
      vinsn_queue_d.commit_cnt += 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q         <= '0;
      read_cnt_q              <= '0;
      issue_cnt_q             <= '0;
      processing_cnt_q        <= '0;
      commit_cnt_q            <= '0;
      vrf_pnt_q               <= '0;
      mask_pnt_q              <= '0;
      pe_resp_o               <= '0;
      result_final_gnt_q      <= '0;
      popcount_q              <= '0;
      vfirst_count_q          <= '0;
      delta_elm_q             <= '0;
      in_ready_threshold_q    <= '0;
      in_m_ready_threshold_q  <= '0;
      out_valid_threshold_q   <= '0;
      viota_acc_q             <= '0;
      found_one_q             <= '0;
      be_viota_seq_q          <= '1; // Default: write
      be_vrgat_seq_q          <= '1; // Default: write
      vrgat_req_valid_mask_q  <= '0;
      vrgat_cnt_q             <= '0;
      vcompress_issue_end_q   <= '0;
      vcompress_cnt_q         <= '0;
    end else begin
      vinsn_running_q         <= vinsn_running_d;
      read_cnt_q              <= read_cnt_d;
      issue_cnt_q             <= issue_cnt_d;
      processing_cnt_q        <= processing_cnt_d;
      commit_cnt_q            <= commit_cnt_d;
      vrf_pnt_q               <= vrf_pnt_d;
      mask_pnt_q              <= mask_pnt_d;
      pe_resp_o               <= pe_resp;
      result_final_gnt_q      <= result_final_gnt_d;
      popcount_q              <= popcount_d;
      vfirst_count_q          <= vfirst_count_d;
      delta_elm_q             <= delta_elm_d;
      in_ready_threshold_q    <= in_ready_threshold_d;
      in_m_ready_threshold_q  <= in_m_ready_threshold_d;
      out_valid_threshold_q   <= out_valid_threshold_d;
      viota_acc_q             <= viota_acc_d;
      found_one_q             <= found_one_d;
      be_viota_seq_q          <= be_viota_seq_d;
      be_vrgat_seq_q          <= be_vrgat_seq_d;
      vrgat_req_valid_mask_q  <= vrgat_req_valid_mask_d;
      vrgat_cnt_q             <= vrgat_cnt_d;
      vcompress_issue_end_q   <= vcompress_issue_end_d;
      vcompress_cnt_q         <= vcompress_cnt_d;
    end
  end

endmodule : masku
