// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Mask Unit Operands Module
//
// Author: Moritz Imfeld <moimfeld@student.ethz.ch>
//
//
// Description:
//  Module takes operands coming from the lanes and then unpacks and prepares them
//  for mask instruction execution.
//
//
// Incoming Operands:
// masku_operands_i = {v0.m, vd, alu_result, fpu_result}
//

module masku_operands import ara_pkg::*; import rvv_pkg::*; #(
    parameter int unsigned NrLanes   = 0,
    parameter type         pe_req_t  = logic,
    parameter type         pe_resp_t = logic,
    // Vl bit mask disabled by default since we fetch vd from opqueues
    // to provide tail undisturbed policy at bit granularity.
    // Enable this if the datapath is changed and vd is no more fetched.
    localparam int unsigned VlBitMaskEnable = 0
  ) (
    input logic clk_i,
    input logic rst_ni,

    // Control logic
    input masku_fu_e                        masku_fu_i,    // signal deciding from which functional unit the result should be taken from
    input pe_req_t                          vinsn_issue_i,
    input logic [idx_width(ELEN*NrLanes):0] vrf_pnt_i,

    // Operands and operand handshake signals coming from lanes
    input  logic [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_valid_i,
    output logic [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operand_ready_o,
    input elen_t [NrLanes-1:0][NrMaskFUnits+2-1:0] masku_operands_i,

    // Operands prepared for masku execution
    output elen_t [     NrLanes-1:0] masku_operand_alu_o,     // ALU/FPU result (shuffled, uncompressed)
    output logic  [     NrLanes-1:0] masku_operand_alu_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_alu_ready_i,
    output logic  [NrLanes*ELEN-1:0] masku_operand_alu_seq_o, // ALU/FPU result (deshuffled, uncompressed)
    output logic  [     NrLanes-1:0] masku_operand_alu_seq_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_alu_seq_ready_i,
    output elen_t [     NrLanes-1:0] masku_operand_vd_o,     // vd (shuffled)
    output logic  [     NrLanes-1:0] masku_operand_vd_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_vd_ready_i,
    output logic  [NrLanes*ELEN-1:0] masku_operand_vd_seq_o, // vd (deshuffled)
    output logic  [     NrLanes-1:0] masku_operand_vd_seq_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_vd_seq_ready_i,
    output elen_t [     NrLanes-1:0] masku_operand_m_o,       // Mask (shuffled)
    output logic  [     NrLanes-1:0] masku_operand_m_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_m_ready_i,
    output logic  [NrLanes*ELEN-1:0] masku_operand_m_seq_o,   // Mask (deshuffled)
    output logic  [     NrLanes-1:0] masku_operand_m_seq_valid_o,
    input  logic  [     NrLanes-1:0] masku_operand_m_seq_ready_i,
    output logic  [NrLanes*ELEN-1:0] bit_enable_mask_o,           // Bit mask for mask unit instructions (shuffled like mask register)
    output logic  [NrLanes*ELEN-1:0] alu_result_compressed_seq_o  // ALU/FPU results compressed (from sew to 1-bit) (deshuffled, in mask format)
  );

  // Imports
  import cf_math_pkg::idx_width;

  // Local Parameter
  localparam int unsigned DATAPATH_WIDTH = NrLanes * ELEN; // Mask Unit datapath width

  // Helper signals
  logic [DATAPATH_WIDTH-1:0] deshuffled_vl_bit_mask; // this bit enable signal is only dependent on vl
  logic [DATAPATH_WIDTH-1:0] shuffled_vl_bit_mask;   // this bit enable signal is only dependent on vl
  vew_e                      bit_enable_shuffle_eew;

  elen_t [NrLanes-1:0] masku_operand_vd_d;
  logic  [NrLanes-1:0] masku_operand_vd_lane_valid;
  logic  [NrLanes-1:0] masku_operand_vd_lane_ready;
  logic  [NrLanes-1:0] masku_operand_vd_spill_valid;
  logic  [NrLanes-1:0] masku_operand_vd_spill_ready;

  elen_t [NrLanes-1:0] masku_operand_m_d;
  logic  [NrLanes-1:0] masku_operand_m_lane_valid;
  logic  [NrLanes-1:0] masku_operand_m_lane_ready;
  logic  [NrLanes-1:0] masku_operand_m_spill_valid;
  logic  [NrLanes-1:0] masku_operand_m_spill_ready;

  // Extract operands from input (input comes in "shuffled form" from the lanes)
  for (genvar lane = 0; lane < NrLanes; lane++) begin
    assign masku_operand_alu_o[lane] = masku_operands_i[lane][2 + masku_fu_i];
    assign masku_operand_vd_d[lane] = masku_operands_i[lane][1];
    assign masku_operand_m_d[lane] = masku_operands_i[lane][0];
  end

  // ----------
  // Deshuffle input sources
  // ----------
  always_comb begin
    masku_operand_m_seq_o   = '0;
    masku_operand_vd_seq_o = '0;
    masku_operand_alu_seq_o = '0;
    for (int b = 0; b < (NrLanes * ELENB); b++) begin
      automatic int deshuffle_alu_idx = deshuffle_index(b, NrLanes, vinsn_issue_i.eew_vs2);
      automatic int deshuffle_vd_idx = deshuffle_index(b, NrLanes, vinsn_issue_i.eew_vd_op);
      automatic int deshuffle_m_idx = deshuffle_index(b, NrLanes, vinsn_issue_i.eew_vmask);
      automatic int lane_idx    = b / ELENB; // rounded down to nearest integer
      automatic int lane_offset = b % ELENB;
      masku_operand_alu_seq_o[8*deshuffle_alu_idx +: 8] = masku_operand_alu_o[lane_idx][8*lane_offset +: 8];
      masku_operand_vd_seq_o[8*deshuffle_vd_idx +: 8] = masku_operand_vd_o[lane_idx][8*lane_offset +: 8];
      masku_operand_m_seq_o[8*deshuffle_m_idx +: 8] = masku_operand_m_o[lane_idx][8*lane_offset +: 8];
    end
  end

  always_comb begin
    masku_operand_vd_spill_ready = 1'b0;
    masku_operand_m_spill_ready  = 1'b0;
    for (int lane = 0; lane < NrLanes; lane++) begin
      masku_operand_vd_spill_ready[lane] = masku_operand_vd_ready_i[lane] | masku_operand_vd_seq_ready_i[lane];
      masku_operand_m_spill_ready[lane]  = masku_operand_m_ready_i[lane]  | masku_operand_m_seq_ready_i[lane];
    end
  end

  for (genvar lane = 0; lane < NrLanes; lane++) begin : gen_masku_operands_spill_regs
    spill_register #(
      .T       ( elen_t )
    ) i_spill_register_vd (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .valid_i (masku_operand_vd_lane_valid[lane]),
      .ready_o (masku_operand_vd_lane_ready[lane]),
      .data_i  (masku_operand_vd_d[lane]),
      .valid_o (masku_operand_vd_spill_valid[lane]),
      .ready_i (masku_operand_vd_spill_ready[lane]),
      .data_o  (masku_operand_vd_o[lane])
    );

    spill_register #(
      .T       ( elen_t )
    ) i_spill_register_m (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .valid_i (masku_operand_m_lane_valid[lane]),
      .ready_o (masku_operand_m_lane_ready[lane]),
      .data_i  (masku_operand_m_d[lane]),
      .valid_o (masku_operand_m_spill_valid[lane]),
      .ready_i (masku_operand_m_spill_ready[lane]),
      .data_o  (masku_operand_m_o[lane])
    );
  end

  for (genvar lane = 0; lane < NrLanes; lane++) begin
    assign masku_operand_vd_valid_o[lane]     = masku_operand_vd_spill_valid[lane];
    assign masku_operand_vd_seq_valid_o[lane] = masku_operand_vd_spill_valid[lane];

    assign masku_operand_m_valid_o[lane]     = masku_operand_m_spill_valid[lane];
    assign masku_operand_m_seq_valid_o[lane] = masku_operand_m_spill_valid[lane];
  end

  always_comb begin
    masku_operand_vd_lane_valid = 1'b0;
    masku_operand_m_lane_valid  = 1'b0;
    for (int lane = 0; lane < NrLanes; lane++) begin
      masku_operand_vd_lane_valid[lane] = masku_operand_valid_i[lane][1];
      masku_operand_m_lane_valid[lane]  = masku_operand_valid_i[lane][0];
    end
  end

  // ------------------------------------------------
  // Generate shuffled and unshuffled bit level masks
  // ------------------------------------------------

  // Generate shuffled bit level mask
  assign bit_enable_shuffle_eew = vinsn_issue_i.op inside {[VMFEQ:VMSBC]} ? vinsn_issue_i.vtype.vsew : vinsn_issue_i.eew_vd_op;

  always_comb begin
    // Default assignments
    deshuffled_vl_bit_mask = '0;
    shuffled_vl_bit_mask   = '0;
    bit_enable_mask_o      = '0;

    // Generate deshuffled vl bit mask
    if (VlBitMaskEnable) begin
      for (int unsigned i = 0; i < DATAPATH_WIDTH; i++) begin
        if (i < vinsn_issue_i.vl) begin
          deshuffled_vl_bit_mask[i] = 1'b1;
        end
      end
    end

    for (int unsigned b = 0; b < NrLanes * ELENB; b++) begin
      // local helper signals
      logic [idx_width(DATAPATH_WIDTH)-1:0] src_operand_byte_shuffle_index;
      logic [idx_width(DATAPATH_WIDTH)-1:0] mask_operand_byte_shuffle_index;
      logic [       idx_width(NrLanes)-1:0] mask_operand_byte_shuffle_lane_index;
      logic [    idx_width(ELENB)-1:0] mask_operand_byte_shuffle_lane_offset;

      // get shuffle idices
      // Note: two types of shuffle indices are needed because the source operand and the
      //       mask register might not have the same effective element width (eew)
      src_operand_byte_shuffle_index        = shuffle_index(b, NrLanes, bit_enable_shuffle_eew);
      mask_operand_byte_shuffle_index       = shuffle_index(b, NrLanes, vinsn_issue_i.eew_vmask);
      mask_operand_byte_shuffle_lane_index  = mask_operand_byte_shuffle_index[idx_width(ELENB) +: idx_width(NrLanes)];
      mask_operand_byte_shuffle_lane_offset = mask_operand_byte_shuffle_index[idx_width(ELENB)-1:0];

      // shuffle bit enable
      if (VlBitMaskEnable) begin
        shuffled_vl_bit_mask[8*src_operand_byte_shuffle_index +: 8] = deshuffled_vl_bit_mask[8*b +: 8];
        // Generate bit-level mask
        bit_enable_mask_o[8*src_operand_byte_shuffle_index +: 8] = shuffled_vl_bit_mask[8*src_operand_byte_shuffle_index +: 8];
      end else begin
        shuffled_vl_bit_mask = '0;
        bit_enable_mask_o = '0;
      end

      if (!vinsn_issue_i.vm && !(vinsn_issue_i.op inside {VMADC, VMSBC})) begin // exception for VMADC and VMSBC, because they use the mask register as a source operand (and not as a mask)
        bit_enable_mask_o[8*src_operand_byte_shuffle_index +: 8] &= masku_operand_m_o[mask_operand_byte_shuffle_lane_index][8*mask_operand_byte_shuffle_lane_offset +: 8];
      end
    end
  end

  // -------------------------------------------
  // Compress ALU/FPU results into a mask vector
  // -------------------------------------------
  always_comb begin
    alu_result_compressed_seq_o = '1;
    for (int b = 0; b < ELENB * NrLanes; b++) begin
      if ((b % (1 << vinsn_issue_i.eew_vs2)) == '0) begin
        automatic int src_byte        = shuffle_index(b, NrLanes, vinsn_issue_i.eew_vs2);
        automatic int src_byte_lane   = src_byte[idx_width(ELENB) +: idx_width(NrLanes)];
        automatic int src_byte_offset = src_byte[idx_width(ELENB)-1:0];

        automatic int dest_bit_seq  = (b >> vinsn_issue_i.eew_vs2) + vrf_pnt_i;
        automatic int dest_byte_seq = dest_bit_seq / ELENB;
        alu_result_compressed_seq_o[ELENB * dest_byte_seq + dest_bit_seq[idx_width(ELENB)-1:0]] = masku_operand_alu_o[src_byte_lane][8 * src_byte_offset];
      end
    end
  end

  // Control
  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_unpack_masku_operands
    // immediately acknowledge operands coming from functional units
    assign masku_operand_alu_valid_o[lane] = masku_operand_valid_i[lane][2 + masku_fu_i];
  end: gen_unpack_masku_operands


  // assign the operand_ready signal that goes to the lane operand queues
  always_comb begin
    // by default, assign '0 to operand ready signals
    masku_operand_ready_o = '0;
    for (int lane = 0; lane < NrLanes; lane++) begin
      // Acknowledge alu operand
      for (int operand_fu = 0; operand_fu < NrMaskFUnits; operand_fu++) begin
        masku_operand_ready_o[lane][2 + operand_fu] = (masku_fu_e'(operand_fu) == masku_fu_i) && masku_operand_alu_ready_i[lane];
      end
      // Acknowledge vd operands
      masku_operand_ready_o[lane][1] = masku_operand_vd_lane_ready[lane];
      // Acknowledge mask operand
      masku_operand_ready_o[lane][0] = masku_operand_m_lane_ready[lane];
    end
  end


endmodule : masku_operands
