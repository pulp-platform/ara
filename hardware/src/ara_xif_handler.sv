// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Frederic zur Bonsen <fzurbonsen@student.ethz.ch>
// Description:
// Handler to take care of the XIF signals

module ara_xif_handler #(
	parameter int 		unsigned NrLanes 		= 0,
	parameter int 		unsigned HARTID_WIDTH 	= ariane_pkg::NR_RGPR_PORTS,
	parameter int 		unsigned ID_WIDTH 		= ariane_pkg::TRANS_ID_BITS,
	parameter type 		readregflags_t 			= logic,
    parameter type 		writeregflags_t 		= logic,
    parameter type 		x_req_t 				= core_v_xif_pkg::x_req_t,
    parameter type 		x_resp_t 				= core_v_xif_pkg::x_resp_t,
    parameter type 		x_issue_req_t 			= core_v_xif_pkg::x_issue_req_t,
    parameter type 		x_issue_resp_t 			= core_v_xif_pkg::x_issue_resp_t,
    parameter type 		x_result_t 				= core_v_xif_pkg::x_result_t,
    parameter type 		x_acc_resp_t 			= core_v_xif_pkg::x_acc_resp_t,
    parameter type 		csr_sync_t 				= logic,
    parameter type 		instr_pack_t 			= logic
	) (
	// Clock and Reset
	input logic 				clk_i,
	input logic 				rst_ni,
	// XIF
	input  x_req_t            	core_v_xif_req_i,
    output x_resp_t           	core_v_xif_resp_o,
    // <-> Ara Dispatcher
    output instr_pack_t 		instruction_o,
    output logic 				instruction_valid_o,
    input  logic 				instruction_ready_i,
    input  csr_sync_t 			csr_sync_i,
    input  x_resp_t 			core_v_xif_resp_i,
    // Temp
    input  logic 				ara_idle,
    input  logic [NrLanes-1:0]  vxsat_flag,
    input  logic      [NrLanes-1:0][4:0] fflags_ex,
    input  logic      [NrLanes-1:0]      fflags_ex_valid,
    input  logic 	load_complete,
    input  logic 	store_complete,
    input  logic   	store_pending
	);

  logic                         csr_stall;
  logic                         csr_block;
  logic                         csr_stall_d, csr_stall_q;
  logic [ID_WIDTH-1:0]          csr_instr_id_d, csr_instr_id_q;

  // Second dispatcher to handle pre decoding
  x_resp_t  core_v_xif_resp_decoder2;
  x_req_t   core_v_xif_req_decoder2;
  ara_pre_decoder #(
    .NrLanes(NrLanes),
    .x_req_t (x_req_t),
    .x_resp_t (x_resp_t),
    .x_issue_req_t(x_issue_req_t),
    .x_issue_resp_t(x_issue_resp_t),
    .x_acc_resp_t(x_acc_resp_t),
    .csr_sync_t (csr_sync_t)
  ) i_pre_decoder (
    .clk_i              (clk_i           ),
    .rst_ni             (rst_ni          ),
    // Interface with the sequencer
    .ara_req_ready_i    (core_v_xif_req_decoder2.issue_valid),
    .ara_idle_i         (ara_idle        ),
    // XIF
    .core_v_xif_req_i  (core_v_xif_req_decoder2),
    .core_v_xif_resp_o (core_v_xif_resp_decoder2),
    // CSR sync
    .sync_i            (core_v_xif_req_i.commit_valid && core_v_xif_req_i.commit_commit_kill),
    .csr_sync_i        (csr_sync_i          ),
    .csr_stall_o       (csr_stall         )
  );

  logic new_instr;
  logic load_next_instr;
  logic buffer_full;

  assign new_instr = core_v_xif_req_i.issue_valid && core_v_xif_resp_o.issue_ready && core_v_xif_resp_o.issue_resp_accept && !csr_block;
  assign load_next_instr = instruction_ready_i && instruction_valid_o;

  // Issued instruction
  instr_pack_t instr_to_buffer;

  assign instr_to_buffer.instr = core_v_xif_req_i.issue_req_instr;
  assign instr_to_buffer.hartid = core_v_xif_req_i.issue_req_hartid;
  assign instr_to_buffer.id = core_v_xif_req_i.issue_req_id;
  assign instr_to_buffer.register_read = core_v_xif_resp_o.issue_resp_register_read;
  assign instr_to_buffer.rs1 = '0;
  assign instr_to_buffer.rs2 = '0;
  assign instr_to_buffer.rs_valid = '0;
  assign instr_to_buffer.frm = fpnew_pkg::RNE;
  assign instr_to_buffer.is_writeback = core_v_xif_resp_o.issue_resp_writeback;

  // to keep track of the returned instructions
  logic [ID_WIDTH-1:0]  result_id;

  ara_ring_buffer #(
    .ID_WIDTH(ID_WIDTH),
    .DEPTH(4),
    .readregflags_t(readregflags_t),
    .dtype(instr_pack_t)
    ) i_ring_buffer (
      .clk_i                (clk_i                              ),
      .rst_ni               (rst_ni                             ),
      .full_o               (buffer_full                        ),
      .empty_o              (                                   ),
      .push_i               (new_instr                          ),
      .commit_i             (core_v_xif_req_i.commit_valid && !core_v_xif_req_i.commit_commit_kill),
      .register_valid_i     (core_v_xif_req_i.register_valid    ),
      .flush_i              (core_v_xif_req_i.commit_valid && core_v_xif_req_i.commit_commit_kill),
      .ready_i              (load_next_instr                  ),
      .valid_o              (instruction_valid_o                  ),
      .commit_id_i          (core_v_xif_req_i.commit_id         ),
      .reg_id_i             (core_v_xif_req_i.register_id       ),
      .id_i                 (instr_to_buffer.id                 ),
      .data_i               (instr_to_buffer                    ),
      .rs1_i                (core_v_xif_req_i.register_rs[0]    ),
      .rs2_i                (core_v_xif_req_i.register_rs[1]    ),
      .rs_valid_i           (core_v_xif_req_i.register_rs_valid ),
      .frm_i                (core_v_xif_req_i.frm               ),
      .data_o               (instruction_o                    )
    );

  always_comb begin
    // Set default
    core_v_xif_req_decoder2       = core_v_xif_req_i;
    core_v_xif_resp_o             = core_v_xif_resp_i;
    core_v_xif_resp_o.issue_ready = 1'b0;
    csr_block                     = 1'b0;
    csr_stall_d                   = csr_stall_q;
    csr_instr_id_d                = csr_instr_id_q;

    // Zero everything but the issue if
    core_v_xif_req_decoder2.register_valid      = '0;
    core_v_xif_req_decoder2.register_hartid     = '0;
    core_v_xif_req_decoder2.register_id         = '0;
    core_v_xif_req_decoder2.register_rs[0]      = '0;
    core_v_xif_req_decoder2.register_rs[1]      = '0;
    core_v_xif_req_decoder2.register_rs_valid   = '0;
    core_v_xif_req_decoder2.commit_valid        = '0;
    core_v_xif_req_decoder2.commit_id           = '0;
    core_v_xif_req_decoder2.commit_hartid       = '0;
    core_v_xif_req_decoder2.commit_commit_kill  = '0;
    core_v_xif_req_decoder2.result_ready        = '0;
    // core_v_xif_req_decoder2.frm                 = '0;
    core_v_xif_req_decoder2.store_pending       = '0;
    core_v_xif_req_decoder2.acc_cons_en         = '0;
    core_v_xif_req_decoder2.inval_ready         = '0;

    // Construct relevant inputs for pre decoder
    core_v_xif_req_decoder2.register_valid    = core_v_xif_req_i.issue_valid;
    core_v_xif_req_decoder2.result_ready      = core_v_xif_req_i.issue_valid;
    core_v_xif_req_decoder2.issue_valid       = core_v_xif_req_i.issue_valid && !buffer_full;

    // issue response
    if (core_v_xif_req_i.issue_valid && !buffer_full && !(core_v_xif_req_i.commit_valid && core_v_xif_req_i.commit_commit_kill))
      core_v_xif_resp_o.issue_ready = 1'b1;
    core_v_xif_resp_o.issue_resp_accept         = core_v_xif_resp_decoder2.issue_resp_accept;
    core_v_xif_resp_o.issue_resp_writeback      = core_v_xif_resp_decoder2.issue_resp_writeback;
    core_v_xif_resp_o.issue_resp_register_read  = core_v_xif_resp_decoder2.issue_resp_register_read;
    core_v_xif_resp_o.issue_resp_is_vfp         = core_v_xif_resp_decoder2.issue_resp_is_vfp;

    // If we predecode a vsetvl instruction we need to stall to wait for its response to correctly compute the CSR's in the predecoder
    if (csr_stall) begin
      csr_stall_d = 1'b1;
      csr_instr_id_d = core_v_xif_req_i.issue_req_id;
    end

    // If we are waiting for a vsetvl to complete we need to mask the outpu of the pre decoder
    if (csr_stall_q) begin
      csr_block = 1'b1;
      core_v_xif_resp_o.issue_ready = 1'b0;
      // If the registers for the stalling instruction are passed we can resolve the stall of the pre decoder
      if (core_v_xif_req_i.register_id == csr_instr_id_q && core_v_xif_req_i.register_valid) begin
        core_v_xif_req_decoder2.register_valid  = 1'b1;
        core_v_xif_req_decoder2.result_ready    = 1'b1;
        core_v_xif_req_decoder2.issue_valid     = 1'b1;
        core_v_xif_req_decoder2.register_rs[0]  = core_v_xif_req_i.register_rs[0];
        core_v_xif_req_decoder2.register_rs[1]  = core_v_xif_req_i.register_rs[1];
        // Mask decoded instruction
        core_v_xif_req_decoder2.issue_req_instr = instruction_o.instr;
        // Stop stalling the pre decoder
        csr_stall_d = 1'b0;
      end
    end

    if (core_v_xif_req_i.commit_valid && core_v_xif_req_i.commit_commit_kill) begin
      csr_stall_d = 1'b0;
    end

    // register
    core_v_xif_resp_o.register_ready = core_v_xif_req_i.register_valid;

    // result
    core_v_xif_resp_o.result_rd = instruction_o.instr[11:7];
    core_v_xif_resp_o.result_we = instruction_o.is_writeback;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : csr_stall_fsm
    if(~rst_ni) begin
      csr_stall_q     <= 0;
      csr_instr_id_q  <= 0;
    end else begin
      csr_stall_q     <= csr_stall_d;
      csr_instr_id_q  <= csr_instr_id_d;
    end
  end
endmodule : ara_xif_handler