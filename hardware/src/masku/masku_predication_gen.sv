// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description: Generate the mask predication strobe for out-of-MASKU masked operations

module masku_predication_gen import ara_pkg::*; import rvv_pkg::*; #(
  parameter  int  unsigned NrLanes   = 0,
  parameter  int  unsigned VLEN      = 0,
  parameter  type          pe_req_t  = logic,
  // Dependant parameters. DO NOT CHANGE!
  localparam int  unsigned DataWidth = $bits(elen_t), // Width of the lane datapath
  localparam int  unsigned StrbWidth = DataWidth/8,
  localparam type          strb_t    = logic [StrbWidth-1:0], // Byte-strobe type
  localparam type          vlen_t    = logic[$clog2(VLEN+1)-1:0]
) (
  input  pe_req_t                                  vinsn_issue_i,     // Instruction in the issue phase
  input  logic    [idx_width(DataWidth*NrLanes):0] masku_pred_pnt_i,
  input  elen_t   [NrLanes-1:0]                    masku_operand_m_i,
  output strb_t   [NrLanes-1:0]                    masku_pred_strb_o
);

  import cf_math_pkg::idx_width;

  always_comb begin
    // Copy data from the mask operands into the mask queue
    for (int vrf_seq_byte = 0; vrf_seq_byte < NrLanes*StrbWidth; vrf_seq_byte++) begin
      // Map vrf_seq_byte to the corresponding byte in the VRF word.
      automatic int vrf_byte = shuffle_index(vrf_seq_byte, NrLanes, vinsn_issue_i.vtype.vsew);

      // At which lane, and what is the byte offset in that lane, of the byte vrf_byte?
      // NOTE: This does not work if the number of lanes is not a power of two.
      // If that is needed, the following two lines must be changed accordingly.
      automatic int vrf_lane   = vrf_byte >> $clog2(StrbWidth);
      automatic int vrf_offset = vrf_byte[idx_width(StrbWidth)-1:0];

      // The VRF pointer can be broken into a byte offset, and a bit offset
      automatic int vrf_pnt_byte_offset = masku_pred_pnt_i >> $clog2(StrbWidth);
      automatic int vrf_pnt_bit_offset  = masku_pred_pnt_i[idx_width(StrbWidth)-1:0];

      // A single bit from the mask operands can be used several times, depending on the eew.
      automatic int mask_seq_bit  = vrf_seq_byte >> int'(vinsn_issue_i.vtype.vsew);
      automatic int mask_seq_byte = (mask_seq_bit >> $clog2(StrbWidth)) + vrf_pnt_byte_offset;
      // Shuffle this source byte
      automatic int mask_byte     = shuffle_index(mask_seq_byte, NrLanes, vinsn_issue_i.eew_vmask);
      // Account for the bit offset
      automatic int mask_bit = (mask_byte << $clog2(StrbWidth)) +
        mask_seq_bit[idx_width(StrbWidth)-1:0] + vrf_pnt_bit_offset;

      // At which lane, and what is the bit offset in that lane, of the mask operand from
      // mask_seq_bit?
      automatic int mask_lane   = mask_bit >> idx_width(DataWidth);
      automatic int mask_offset = mask_bit[idx_width(DataWidth)-1:0];

      // Copy the mask operand
      masku_pred_strb_o[vrf_lane][vrf_offset] = masku_operand_m_i[mask_lane][mask_offset];
    end
  end

endmodule
