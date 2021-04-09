// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is the vector register file of one lane.

module vector_regfile import ara_pkg::*; #(
    parameter  int  unsigned NrBanks   = 0,     // Number of banks in the vector register file
    parameter  int  unsigned VRFSize   = 0,     // Size of the VRF, in bits
    parameter  type          vaddr_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t),
    localparam int  unsigned StrbWidth = DataWidth / 8,
    localparam type          strb_t    = logic [StrbWidth-1:0]
  ) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // Interface with the VRF
    input  logic     [NrBanks-1:0]         req_i,
    input  vaddr_t   [NrBanks-1:0]         addr_i,
    input  opqueue_e [NrBanks-1:0]         tgt_opqueue_i,
    input  logic     [NrBanks-1:0]         wen_i,
    input  elen_t    [NrBanks-1:0]         wdata_i,
    input  strb_t    [NrBanks-1:0]         be_i,
    // Operands
    output elen_t    [NrOperandQueues-1:0] operand_o,
    output logic     [NrOperandQueues-1:0] operand_valid_o
  );

  //////////////////
  //  Parameters  //
  //////////////////

  localparam int unsigned NumWords = VRFSize / NrBanks / DataWidth;

  ///////////////
  //  Signals  //
  ///////////////

  elen_t    [NrBanks-1:0] rdata;
  logic     [NrBanks-1:0] rdata_valid_q;
  opqueue_e [NrBanks-1:0] tgt_opqueue_q;

  // Generate the rdata_valid and tgt_opqueue signals by delaying the request by one cycle
  always_ff @(posedge clk_i or negedge rst_ni) begin: p_rdata_valid
    if (!rst_ni) begin
      rdata_valid_q <= '0;
      tgt_opqueue_q <= '0;
    end else begin
      rdata_valid_q <= req_i & ~wen_i;
      tgt_opqueue_q <= tgt_opqueue_i;
    end
  end

  /////////////
  //  Banks  //
  /////////////

  for (genvar bank = 0; bank < NrBanks; bank++) begin: gen_banks
    tc_sram #(
      .NumWords (NumWords ),
      .DataWidth(DataWidth),
      .NumPorts (1        )
    ) data_sram (
      .clk_i  (clk_i                             ),
      .rst_ni (rst_ni                            ),
      .req_i  (req_i[bank]                       ),
      .we_i   (wen_i[bank]                       ),
      .rdata_o(rdata[bank]                       ),
      .wdata_i(wdata_i[bank]                     ),
      .be_i   (be_i[bank]                        ),
      .addr_i (addr_i[bank][$clog2(NumWords)-1:0])
    );
  end : gen_banks

  ///////////////////
  //  Multiplexer  //
  ///////////////////

  stream_xbar #(
    .NumInp   (NrBanks        ),
    .NumOut   (NrOperandQueues),
    .DataWidth(DataWidth      ),
    .AxiVldRdy('1             )
  ) i_vrf_mux (
    .clk_i  (clk_i          ),
    .rst_ni (rst_ni         ),
    .flush_i(1'b0           ),
    .rr_i   ('0             ),
    .data_i (rdata          ),
    .valid_i(rdata_valid_q  ),
    .ready_o(/* Unused */   ),
    .sel_i  (tgt_opqueue_q  ),
    .data_o (operand_o      ),
    .valid_o(operand_valid_o),
    .idx_o  (/* Unused */   ),
    .ready_i('1             ) // Always ready
  );

endmodule : vector_regfile
