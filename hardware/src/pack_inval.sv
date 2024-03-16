// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Frederic zur Bonsen <fzurbonsen@student.ethz.ch>
// Description:
// Module to handle packing of inval into XIF

module pack_inval #(
	parameter int 						unsigned AxiAddrWidth = 64
	) (
	input logic 						clk_i,
	input logic 						rst_ni,

	input acc_pkg::accelerator_resp_t	acc_resp_i,
	input acc_pkg::accelerator_req_t 	acc_req_i,
	input logic 						inval_valid_i,
	input logic [AxiAddrWidth-1:0]		inval_addr_i,

	output acc_pkg::accelerator_resp_t  acc_resp_pack_o,
	output logic						inval_ready_o,
	output logic						acc_cons_en_o,

	core_v_xif 							xif_mod_p
  );

  always_comb begin : pack_inval
  	xif_mod_p.mod_resp_pack 			= xif_mod_p.mod_resp;
  	xif_mod_p.mod_resp_pack.inval_valid = inval_valid_i;
  	xif_mod_p.mod_resp_pack.inval_addr  = inval_addr_i;
  	inval_ready_o 						= xif_mod_p.mod_req.inval_ready;
  	acc_cons_en_o 						= xif_mod_p.mod_req.acc_cons_en;
  end

endmodule : pack_inval