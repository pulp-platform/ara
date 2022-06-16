// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's mask unit. It fetches operands from any one the lanes, and
// then sends back to them whether the elements are predicated or not.
// This unit is shared between all the functional units who can execute
// predicated instructions.

module masku import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes = 0,
    parameter  type          vaddr_t = logic, // Type used to address vector register file elements
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t), // Width of the lane datapath
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [StrbWidth-1:0] // Byte-strobe type
  ) (
    input  logic                                       clk_i,
    input  logic                                       rst_ni,
    // Interface with the main sequencer
    input  pe_req_t                                    pe_req_i,
    input  logic                                       pe_req_valid_i,
    input  logic     [NrVInsn-1:0]                     pe_vinsn_running_i,
    output logic                                       pe_req_ready_o,
    output pe_resp_t                                   pe_resp_o,
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

  ////////////////
  //  Operands  //
  ////////////////

  // Information about which is the target FU of the request
  masku_fu_e masku_operand_fu;

  // ALU/FPU result
  elen_t [NrLanes-1:0] masku_operand_a_i;
  logic  [NrLanes-1:0] masku_operand_a_valid_i;
  logic  [NrLanes-1:0] masku_operand_a_ready_o;

  // Previous value of the destination vector register
  elen_t [NrLanes-1:0] masku_operand_b_i;
  logic  [NrLanes-1:0] masku_operand_b_valid_i;
  logic  [NrLanes-1:0] masku_operand_b_ready_o;

  // Mask
  elen_t [NrLanes-1:0] masku_operand_m_i;
  logic  [NrLanes-1:0] masku_operand_m_valid_i;
  logic  [NrLanes-1:0] masku_operand_m_ready_o;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_unpack_masku_operands
    assign masku_operand_a_i[lane]       = masku_operand_i[lane][2 + masku_operand_fu];
    assign masku_operand_a_valid_i[lane] = masku_operand_valid_i[lane][2 + masku_operand_fu];
    for (genvar operand_fu = 0; operand_fu < NrMaskFUnits; operand_fu++) begin: gen_masku_operand_ready
      assign masku_operand_ready_o[lane][2 + operand_fu] = (masku_fu_e'(operand_fu) == masku_operand_fu) && masku_operand_a_ready_o[lane];
    end: gen_masku_operand_ready

    assign masku_operand_b_i[lane]        = masku_operand_i[lane][1];
    assign masku_operand_b_valid_i[lane]  = masku_operand_valid_i[lane][1];
    assign masku_operand_ready_o[lane][1] = masku_operand_b_ready_o[lane];

    assign masku_operand_m_i[lane]        = masku_operand_i[lane][0];
    assign masku_operand_m_valid_i[lane]  = masku_operand_valid_i[lane][0];
    assign masku_operand_ready_o[lane][0] = masku_operand_m_ready_o[lane];
  end: gen_unpack_masku_operands

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
  pe_req_t vinsn_issue;
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

  ////////////////
  //  Mask ALU  //
  ////////////////

  elen_t [NrLanes-1:0]      alu_result;
  logic  [NrLanes*ELEN-1:0] bit_enable;
  logic  [NrLanes*ELEN-1:0] bit_enable_shuffle;
  logic  [NrLanes*ELEN-1:0] bit_enable_mask;

  // Pointers
  //
  // We need a pointer to which bit on the full VRF word we are reading mask operands from.
  logic [idx_width(DataWidth*NrLanes):0] mask_pnt_d, mask_pnt_q;
  // We need a pointer to which bit on the full VRF word we are writing results to.
  logic [idx_width(DataWidth*NrLanes):0] vrf_pnt_d, vrf_pnt_q;

  always_comb begin: p_mask_alu
    alu_result         = '0;
    bit_enable         = '0;
    bit_enable_shuffle = '0;
    bit_enable_mask    = '0;

    if (vinsn_issue_valid) begin
      // Calculate bit enable
      // The result can be taken either from the result of an operation (mask_operand_a_i), or
      // from the previous value of the destination register (mask_operand_b_i). Byte strobes
      // do not work here, since this has to be done at a bit granularity. Therefore, the Mask Unit
      // received both operands, and does a masking depending on the value of the vl.
      if (vinsn_issue.vl >= ELEN*NrLanes)
        bit_enable = '1;
      else begin
        bit_enable[vinsn_issue.vl] = 1'b1;
        bit_enable                 = bit_enable - 1;
      end

      // Shuffle the bit enable signal
      for (int b = 0; b < NrLanes*StrbWidth; b++) begin
        automatic int vrf_byte              = shuffle_index(b, NrLanes, vinsn_issue.eew_vd_op);
        bit_enable_shuffle[8*vrf_byte +: 8] = bit_enable[8*b +: 8];

        // Take the mask into account
        if (!vinsn_issue.vm) begin
          automatic int mask_byte          = shuffle_index(b, NrLanes, vinsn_issue.eew_vmask);
          automatic int mask_byte_lane     = mask_byte[idx_width(StrbWidth) +: idx_width(NrLanes)];
          automatic int mask_byte_offset   = mask_byte[idx_width(StrbWidth)-1:0];
          bit_enable_mask[8*vrf_byte +: 8] = bit_enable_shuffle[8*vrf_byte +: 8] &
            masku_operand_m_i[mask_byte_lane][8*mask_byte_offset +: 8];
        end else begin
          bit_enable_mask[8*vrf_byte +: 8] = bit_enable_shuffle[8*vrf_byte +: 8];
        end
      end

      // Evaluate the instruction
      unique case (vinsn_issue.op) inside
        [VMANDNOT:VMXNOR]: alu_result = (masku_operand_a_i & bit_enable_mask) |
          (masku_operand_b_i & ~bit_enable_mask);
        [VMFEQ:VMSBC] : begin
          automatic logic [ELEN*NrLanes-1:0] alu_result_flat = '0;

          unique case (vinsn_issue.vtype.vsew)
            EW8: for (int b = 0; b < 8*NrLanes; b++) begin
                // Shuffle the source byte, then find the lane and the offset of this byte in the
                // full operand word.
                automatic int src_byte        = shuffle_index(1*b, NrLanes, EW8);
                automatic int src_byte_lane   = src_byte[idx_width(StrbWidth) +: idx_width(NrLanes)];
                automatic int src_byte_offset = src_byte[idx_width(StrbWidth)-1:0];

                // Find the destination byte
                automatic int dest_bit_seq  = b + vrf_pnt_q;
                automatic int dest_byte_seq = dest_bit_seq / StrbWidth;
                automatic int dest_byte     = shuffle_index(dest_byte_seq, NrLanes, EW8);

                alu_result_flat[StrbWidth*dest_byte + dest_bit_seq[idx_width(StrbWidth)-1:0]] =
                (!vinsn_issue.vm && !masku_operand_a_i[src_byte_lane][8*src_byte_offset+1]) ?
                masku_operand_b_i[src_byte_lane][8*src_byte_offset] :
                masku_operand_a_i[src_byte_lane][8*src_byte_offset];
              end
            EW16: for (int b = 0; b < 4*NrLanes; b++) begin
                // Shuffle the source byte, then find the lane and the offset of this byte in the
                // full operand word.
                automatic int src_byte        = shuffle_index(2*b, NrLanes, EW16);
                automatic int src_byte_lane   = src_byte[idx_width(StrbWidth) +: idx_width(NrLanes)];
                automatic int src_byte_offset = src_byte[idx_width(StrbWidth)-1:0];

                // Find the destination byte
                automatic int dest_bit_seq  = b + vrf_pnt_q;
                automatic int dest_byte_seq = dest_bit_seq / StrbWidth;
                automatic int dest_byte     = shuffle_index(dest_byte_seq, NrLanes, EW16);

                alu_result_flat[StrbWidth*dest_byte + dest_bit_seq[idx_width(StrbWidth)-1:0]] =
                (!vinsn_issue.vm && !masku_operand_a_i[src_byte_lane][8*src_byte_offset+1]) ?
                masku_operand_b_i[src_byte_lane][8*src_byte_offset] :
                masku_operand_a_i[src_byte_lane][8*src_byte_offset];
              end
            EW32: for (int b = 0; b < 2*NrLanes; b++) begin
                // Shuffle the source byte, then find the lane and the offset of this byte in the
                // full operand word.
                automatic int src_byte        = shuffle_index(4*b, NrLanes, EW32);
                automatic int src_byte_lane   = src_byte[idx_width(StrbWidth) +: idx_width(NrLanes)];
                automatic int src_byte_offset = src_byte[idx_width(StrbWidth)-1:0];

                // Find the destination byte
                automatic int dest_bit_seq  = b + vrf_pnt_q;
                automatic int dest_byte_seq = dest_bit_seq / StrbWidth;
                automatic int dest_byte     = shuffle_index(dest_byte_seq, NrLanes, EW32);

                alu_result_flat[StrbWidth*dest_byte + dest_bit_seq[idx_width(StrbWidth)-1:0]] =
                (!vinsn_issue.vm && !masku_operand_a_i[src_byte_lane][8*src_byte_offset+1]) ?
                masku_operand_b_i[src_byte_lane][8*src_byte_offset] :
                masku_operand_a_i[src_byte_lane][8*src_byte_offset];
              end
            EW64: for (int b = 0; b < 1*NrLanes; b++) begin
                // Shuffle the source byte, then find the lane and the offset of this byte in the
                // full operand word.
                automatic int src_byte        = shuffle_index(8*b, NrLanes, EW64);
                automatic int src_byte_lane   = src_byte[idx_width(StrbWidth) +: idx_width(NrLanes)];
                automatic int src_byte_offset = src_byte[idx_width(StrbWidth)-1:0];

                // Find the destination byte
                automatic int dest_bit_seq  = b + vrf_pnt_q;
                automatic int dest_byte_seq = dest_bit_seq / StrbWidth;
                automatic int dest_byte     = shuffle_index(dest_byte_seq, NrLanes, EW64);

                alu_result_flat[StrbWidth*dest_byte + dest_bit_seq[idx_width(StrbWidth)-1:0]] =
                  (!vinsn_issue.vm && !masku_operand_a_i[src_byte_lane][8*src_byte_offset+1]) ?
                  masku_operand_b_i[src_byte_lane][8*src_byte_offset] :
                  masku_operand_a_i[src_byte_lane][8*src_byte_offset];
              end
            default:;
          endcase

          // Final assignment
          alu_result = (alu_result_flat & bit_enable_shuffle) |
            (masku_operand_b_i & ~bit_enable_shuffle);
        end
        default: alu_result = '0;
      endcase
    end
  end: p_mask_alu

  /////////////////
  //  Mask unit  //
  /////////////////

  // Vector instructions currently running
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // Interface with the main sequencer
  pe_resp_t pe_resp;

  // Remaining elements of the current instruction in the read operand phase
  vlen_t read_cnt_d, read_cnt_q;
  // Remaining elements of the current instruction in the issue phase
  vlen_t issue_cnt_d, issue_cnt_q;
  // Remaining elements of the current instruction in the commit phase
  vlen_t commit_cnt_d, commit_cnt_q;
  // Effective MASKU stride in case of VSLIDEUP
  // MASKU receives chunks of 64 * NrLanes mask bits from the lanes
  // VSLIDEUP only needs the bits whose index >= than its stride
  // So, the operand requester does not send vl mask bits to MASKU
  // and trims all the unused 64 * NrLanes mask bits chunks
  // Therefore, the stride needs to be trimmed, too
  elen_t trimmed_stride;

  logic [NrLanes-1:0] fake_a_valid;
  logic last_incoming_a;
  logic unbalanced_a;

  // Information about which is the target FU of the request
  assign masku_operand_fu = (vinsn_issue.op inside {[VMFEQ:VMFGE]}) ? MaskFUMFpu : MaskFUAlu;

  always_comb begin: p_masku
    // Maintain state
    vinsn_queue_d = vinsn_queue_q;
    read_cnt_d    = read_cnt_q;
    issue_cnt_d   = issue_cnt_q;
    commit_cnt_d  = commit_cnt_q;

    mask_pnt_d = mask_pnt_q;
    vrf_pnt_d  = vrf_pnt_q;

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

    // Vector instructions currently running
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // We are not ready, by default
    pe_resp                 = '0;
    masku_operand_a_ready_o = '0;
    masku_operand_b_ready_o = '0;
    masku_operand_m_ready_o = '0;

    // Inform the main sequencer if we are idle
    pe_req_ready_o = !vinsn_queue_full;

    /////////////////////
    //  Mask Operands  //
    /////////////////////

    // Is there an instruction ready to be issued?
    if (vinsn_issue_valid) begin
      // Is there place in the mask queue to write the mask operands?
      // Did we receive the mask bits on the MaskM channel?
      if (!vinsn_issue.vm && !mask_queue_full && &masku_operand_m_valid_i) begin
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
            masku_operand_m_i[mask_lane][mask_offset];
        end

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
        if (mask_pnt_d == NrLanes*64 || read_cnt_d == '0) begin
          // Request another beat
          masku_operand_m_ready_o = '1;
          // Reset the pointer
          mask_pnt_d              = '0;
        end
      end
    end

    //////////////////////////////////
    //  Write results to the lanes  //
    //////////////////////////////////

    unbalanced_a = (|commit_cnt_q[idx_width(NrLanes)-1:0] != 1'b0) ? 1'b1 : 1'b0;
    last_incoming_a = ((commit_cnt_q - vrf_pnt_q) < NrLanes) ? 1'b1 : 1'b0;
    for (int unsigned i = 1; i < NrLanes; i++)
      if (i >= {1'b0, commit_cnt_q[idx_width(NrLanes)-1:0]})
        fake_a_valid[i] = last_incoming_a & unbalanced_a;
      else
        fake_a_valid = 1'b0;

    // Is there an instruction ready to be issued?
    if (vinsn_issue_valid) begin
      // This instruction executes on the Mask Unit
      if (vinsn_issue.vfu == VFU_MaskUnit) begin
        // Is there place in the result queue to write the results?
        // Did we receive the operands?
        if (!result_queue_full && &(masku_operand_a_valid_i | fake_a_valid) &&
            (!vinsn_issue.use_vd_op || &masku_operand_b_valid_i)) begin
          // How many elements are we committing in total?
          // Since we are committing bits instead of bytes, we carry out the following calculation
          // with ceil(vl/8) instead.
          automatic int element_cnt_all_lanes           = (ELENB * NrLanes) >> int'(vinsn_issue.vtype.vsew);
          // How many elements are remaining to be committed? Carry out the calculation with
          // ceil(issue_cnt/8).
          automatic int remaining_element_cnt_all_lanes = (issue_cnt_q + 7) / 8;
          remaining_element_cnt_all_lanes               = (remaining_element_cnt_all_lanes +
            (1 << int'(vinsn_issue.vtype.vsew)) - 1) >> int'(vinsn_issue.vtype.vsew);
          if (element_cnt_all_lanes > remaining_element_cnt_all_lanes)
            element_cnt_all_lanes = remaining_element_cnt_all_lanes;

          // Acknowledge the operands of this instruction.
          // At this stage, acknowledge only the first operand, "a", coming from the ALU/VMFpu.
          masku_operand_a_ready_o = masku_operand_a_valid_i;

          // Store the result in the operand queue
          for (int unsigned lane = 0; lane < NrLanes; lane++) begin
            // How many elements are we committing in this lane?
            automatic int element_cnt = element_cnt_all_lanes / NrLanes;
            if (lane < element_cnt_all_lanes[idx_width(NrLanes)-1:0])
              element_cnt += 1;

            result_queue_d[result_queue_write_pnt_q][lane] = '{
              wdata: result_queue_q[result_queue_write_pnt_q][lane].wdata | alu_result[lane],
              be   : be(element_cnt, vinsn_issue.vtype.vsew),
              addr : vaddr(vinsn_issue.vd, NrLanes) +
                (((vinsn_issue.vl - issue_cnt_q) / NrLanes / DataWidth)),
              id : vinsn_issue.id
            };
          end

          // Increment the VRF pointer
          if (vinsn_issue.op inside {[VMFEQ:VMSBC]}) begin
            vrf_pnt_d = vrf_pnt_q + (NrLanes << (int'(EW64) - vinsn_issue.vtype.vsew));

            // Filled-up a word, or finished execution
            if (vrf_pnt_d == DataWidth*NrLanes || vrf_pnt_d >= issue_cnt_q) begin
              result_queue_valid_d[result_queue_write_pnt_q] = {NrLanes{1'b1}};

              // Acknowledge the rest of the operands, which are accessed bit by bit.
              masku_operand_b_ready_o = masku_operand_b_valid_i;

              // Reset VRF pointer
              vrf_pnt_d = '0;

              // Increment result queue pointers and counters
              result_queue_cnt_d += 1;
              if (result_queue_write_pnt_q == ResultQueueDepth-1)
                result_queue_write_pnt_d = '0;
              else
                result_queue_write_pnt_d = result_queue_write_pnt_q + 1;

              // Account for the results that were issued
              issue_cnt_d = issue_cnt_q - NrLanes * DataWidth;
              if (issue_cnt_q < NrLanes * DataWidth)
                issue_cnt_d = '0;
            end
          end else begin
            result_queue_valid_d[result_queue_write_pnt_q] = {NrLanes{1'b1}};

            // Acknowledge the previous value of the destination vector register.
            masku_operand_b_ready_o = masku_operand_b_valid_i;

            // Increment result queue pointers and counters
            result_queue_cnt_d += 1;
            if (result_queue_write_pnt_q == ResultQueueDepth-1)
              result_queue_write_pnt_d = '0;
            else
              result_queue_write_pnt_d = result_queue_write_pnt_q + 1;

            // Account for the results that were issued
            issue_cnt_d = issue_cnt_q - NrLanes * DataWidth;
            if (issue_cnt_q < NrLanes * DataWidth)
              issue_cnt_d = '0;
          end
        end
      end
    end

    // Finished issuing results
    if (vinsn_issue_valid && (
          ( (vinsn_issue.vm || vinsn_issue.vfu == VFU_MaskUnit) && issue_cnt_d == '0) ||
          (!(vinsn_issue.vm || vinsn_issue.vfu == VFU_MaskUnit) && read_cnt_d == '0))) begin
      // Increment vector instruction queue pointers and counters
      vinsn_queue_d.issue_cnt -= 1;
    end

    /////////////////////////////////
    //  Send operands to the VFUs  //
    /////////////////////////////////

    for (int lane = 0; lane < NrLanes; lane++) begin: send_operand
      mask_valid_o[lane] = mask_queue_valid_q[mask_queue_read_pnt_q][lane];
      mask_o[lane]       = mask_queue_q[mask_queue_read_pnt_q][lane];
      // Received a grant from the VFUs.
      // The VLDU and the VSTU acknowledge all the operands at once.
      // Only accept the acknowledgement from the lanes if the current instruction is executing there.
      // Deactivate the request, but do not bump the pointers for now.
      if ((lane_mask_ready_i[lane] && mask_valid_o[lane] && vinsn_issue.vfu inside {VFU_Alu, VFU_MFpu, VFU_MaskUnit}) ||
           vldu_mask_ready_i || vstu_mask_ready_i || sldu_mask_ready_i) begin
        mask_queue_valid_d[mask_queue_read_pnt_q][lane] = 1'b0;
        mask_queue_d[mask_queue_read_pnt_q][lane]       = '0;
      end
    end: send_operand

    // Is this operand going to the lanes?
    mask_valid_lane_o = vinsn_issue.vfu inside {VFU_Alu, VFU_MFpu, VFU_MaskUnit};

    // All lanes accepted the VRF request
    if (!(|mask_queue_valid_d[mask_queue_read_pnt_q]))
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
        commit_cnt_d = commit_cnt_q - NrLanes * (1 << (int'(EW64) - vinsn_commit.vtype.vsew));
        if (commit_cnt_q < (NrLanes * (1 << (int'(EW64) - vinsn_commit.vtype.vsew))))
          commit_cnt_d = '0;
      end

    //////////////////////////////////
    //  Write results into the VRF  //
    //////////////////////////////////

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
      (&result_final_gnt_d || (commit_cnt_q > (NrLanes * DataWidth))))
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
        commit_cnt_d = commit_cnt_q - NrLanes * DataWidth;
        if (commit_cnt_q < (NrLanes * DataWidth))
          commit_cnt_d = '0;
      end

    // Finished committing the results of a vector instruction
    // Some instructions forward operands to the lanes before writing the VRF
    // In this case, wait for the lanes to be written
    if (vinsn_commit_valid && commit_cnt_d == '0 &&
      (!(vinsn_commit.op inside {[VMFEQ:VMSBC]}) || &result_final_gnt_d)) begin
      // Mark the vector instruction as being done
      pe_resp.vinsn_done[vinsn_commit.id] = 1'b1;

      // Update the commit counters and pointers
      vinsn_queue_d.commit_cnt -= 1;
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
        issue_cnt_d = pe_req_i.vl;
        read_cnt_d  = pe_req_i.vl;

        // Trim skipped words
        if (pe_req_i.op == VSLIDEUP) begin
          issue_cnt_d -= vlen_t'(trimmed_stride);
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
  end: p_masku

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q    <= '0;
      read_cnt_q         <= '0;
      issue_cnt_q        <= '0;
      commit_cnt_q       <= '0;
      vrf_pnt_q          <= '0;
      mask_pnt_q         <= '0;
      pe_resp_o          <= '0;
      result_final_gnt_q <= '0;
    end else begin
      vinsn_running_q    <= vinsn_running_d;
      read_cnt_q         <= read_cnt_d;
      issue_cnt_q        <= issue_cnt_d;
      commit_cnt_q       <= commit_cnt_d;
      vrf_pnt_q          <= vrf_pnt_d;
      mask_pnt_q         <= mask_pnt_d;
      pe_resp_o          <= pe_resp;
      result_final_gnt_q <= result_final_gnt_d;
    end
  end

endmodule : masku
