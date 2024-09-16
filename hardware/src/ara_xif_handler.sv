// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Frederic zur Bonsen <fzurbonsen@student.ethz.ch>
// Description:
// Handler to take care of the XIF signals

module ara_xif_handler #(
  parameter int       unsigned NrLanes        = 0,
  parameter int       unsigned HARTID_WIDTH   = ariane_pkg::NR_RGPR_PORTS,
  parameter int       unsigned ID_WIDTH       = ariane_pkg::TRANS_ID_BITS,
  parameter type      readregflags_t          = logic,
  parameter type      writeregflags_t         = logic,
  parameter type      x_req_t                 = logic,
  parameter type      x_resp_t                = logic,
  parameter type      x_issue_req_t           = logic,
  parameter type      x_issue_resp_t          = logic,
  parameter type      x_result_t              = logic,
  parameter type      x_acc_resp_t            = logic,
  parameter type      csr_sync_t              = logic,
  parameter type      instr_pack_t            = logic
  ) (
  // Clock and Reset
  input logic                     clk_i,
  input logic                     rst_ni,
  // XIF
  input  x_req_t                  core_v_xif_req_i,
  output x_resp_t                 core_v_xif_resp_o,
  // <-> Ara Dispatcher
  output instr_pack_t             instruction_o,
  output logic                    instruction_valid_o,
  input  logic                    instruction_ready_i,
  input  csr_sync_t               csr_sync_i,
  input  x_resp_t                 core_v_xif_resp_i,
  // Temp
  input  logic                    ara_idle,
  input  logic [NrLanes-1:0]      vxsat_flag,
  input  logic [NrLanes-1:0][4:0] fflags_ex,
  input  logic [NrLanes-1:0]      fflags_ex_valid,
  input  logic                    load_complete,
  input  logic                    store_complete,
  input  logic                    store_pending
);

  localparam int unsigned XIF_BUF_DEPTH = 4;

  // Helpers
  logic commit_ok, commit_kill;
  logic xif_issue_decode_ok;
  logic push_instr_buffer;
  logic buffer_full, buffer_empty;

  // XIF issue decoder to pre-decode and check for errors
  x_issue_req_t  predec_xif_issue_req;
  logic          predec_xif_issue_req_valid;
  x_issue_resp_t predec_xif_issue_resp;

  instr_pack_t instr_to_buffer;

  // Speculative CSR sync logic
  logic csr_sync_valid, predec_csr_spec_mod_reg, predec_csr_spec_mod, buf_has_spec_csr_insn;
  enum logic {NORMAL_OP, WAIT_EMPTY_BUF} csr_sync_state_d, csr_sync_state_q;

  // Effective commit or kill on the XIF commit intf
  assign commit_ok   = core_v_xif_req_i.commit_valid & !core_v_xif_req_i.commit_commit_kill;
  assign commit_kill = core_v_xif_req_i.commit_valid & core_v_xif_req_i.commit_commit_kill;

  // No errors at decode time for this RVV vector insn
  assign xif_issue_decode_ok = predec_xif_issue_resp.accept;

  // Push a new instruction from the XIF issue intf into the speculative XIF buffer
  assign push_instr_buffer = core_v_xif_req_i.issue_valid & core_v_xif_resp_o.issue_ready &
                             xif_issue_decode_ok & ~commit_kill;

  // Pass through the pre-decoder
  // Pre-decode the instruction if the buffer is not full
  assign predec_xif_issue_req_valid  = core_v_xif_req_i.issue_valid & ~buffer_full;
  assign predec_xif_issue_req.instr  = core_v_xif_req_i.issue_req_instr;
  assign predec_xif_issue_req.hartid = core_v_xif_req_i.issue_req_hartid;
  assign predec_xif_issue_req.id     = core_v_xif_req_i.issue_req_id;

  // Input to the XIF buffer
  assign instr_to_buffer.instr         = core_v_xif_req_i.issue_req_instr;
  assign instr_to_buffer.hartid        = core_v_xif_req_i.issue_req_hartid;
  assign instr_to_buffer.id            = core_v_xif_req_i.issue_req_id;
  assign instr_to_buffer.is_writeback  = predec_xif_issue_resp.writeback;
  assign instr_to_buffer.register_read = predec_xif_issue_resp.register_read;
  assign instr_to_buffer.rs1           = '0;
  assign instr_to_buffer.rs2           = '0;
  assign instr_to_buffer.rs_valid      = '0;
  assign instr_to_buffer.frm           = fpnew_pkg::RNE;
  assign instr_to_buffer.is_spec_csr   = predec_csr_spec_mod;

  always_comb begin
    // Pass through
    core_v_xif_resp_o = core_v_xif_resp_i;

    // Issue ready if buffer has space, and we are not waiting for it to be empty
    core_v_xif_resp_o.issue_ready              = ~buffer_full & (csr_sync_state_q != WAIT_EMPTY_BUF);
    core_v_xif_resp_o.issue_resp_accept        = predec_xif_issue_resp.accept;
    core_v_xif_resp_o.issue_resp_writeback     = predec_xif_issue_resp.writeback;
    core_v_xif_resp_o.issue_resp_register_read = predec_xif_issue_resp.register_read;
    core_v_xif_resp_o.issue_resp_is_vfp        = predec_xif_issue_resp.is_vfp;

    // Always ready for buffering the registers
    core_v_xif_resp_o.register_ready = 1'b1;
  end

  ara_pre_decoder #(
    .NrLanes                (NrLanes       ),
    .x_issue_req_t          (x_issue_req_t ),
    .x_issue_resp_t         (x_issue_resp_t),
    .csr_sync_t             (csr_sync_t    )
  ) i_xif_issue_pre_decoder (
    .clk_i                  (clk_i                     ),
    .rst_ni                 (rst_ni                    ),
    .cvxif_issue_req_i      (predec_xif_issue_req      ),
    .cvxif_issue_req_valid_i(predec_xif_issue_req_valid),
    .cvxif_issue_resp_o     (predec_xif_issue_resp     ),
    .csr_sync_valid_i       (csr_sync_valid            ),
    .csr_sync_i             (csr_sync_i                ),
    .csr_spec_mod_o         (predec_csr_spec_mod       ),
    .csr_spec_mod_reg_o     (predec_csr_spec_mod_reg   )
  );

  ara_ring_buffer #(
    .ID_WIDTH             (ID_WIDTH                           ),
    .DEPTH                (XIF_BUF_DEPTH                      ),
    .readregflags_t       (readregflags_t                     ),
    .dtype                (instr_pack_t                       )
  ) i_xif_buffer (
    .clk_i                (clk_i                              ),
    .rst_ni               (rst_ni                             ),
    .full_o               (buffer_full                        ),
    .empty_o              (buffer_empty                       ),
    .push_i               (push_instr_buffer                  ),
    .commit_i             (commit_ok                          ),
    .register_valid_i     (core_v_xif_req_i.register_valid    ),
    .flush_i              (commit_kill                        ),
    .ready_i              (instruction_ready_i                ),
    .valid_o              (instruction_valid_o                ),
    .commit_id_i          (core_v_xif_req_i.commit_id         ),
    .reg_id_i             (core_v_xif_req_i.register_id       ),
    .id_i                 (instr_to_buffer.id                 ),
    .data_i               (instr_to_buffer                    ),
    .rs1_i                (core_v_xif_req_i.register_rs[0]    ),
    .rs2_i                (core_v_xif_req_i.register_rs[1]    ),
    .rs_valid_i           (core_v_xif_req_i.register_rs_valid ),
    .frm_i                (core_v_xif_req_i.frm               ),
    .data_o               (instruction_o                      ),
    .keep_spec_csr_insn_o (buf_has_spec_csr_insn              )
  );

  // Speculative CSR sync FSM:
  // 1) Upon a commit kill, the speculative CSRs have to be rolled back.
  //    During the roll back, the pre-decoder cannot decode!
  //    a) If the xif buffer contains instructions that modified the spec CSRs, wait
  //       until the xif buffer is empty and then sync.
  //    b) If the buffer does not contain them, just sync immediately (optimization).
  // 2) Upon an instruction that modifies the spec CSRs through a register value,
  //    we accept it and wait for it to modify the current state of the real CSRs.
  //    Then, we sync. This operation is slow, but rare.
  always_comb begin
    csr_sync_state_d = csr_sync_state_q;
    csr_sync_valid   = 1'b0;

    unique case(csr_sync_state_q)
      WAIT_EMPTY_BUF: begin
        // Stall the issue intf here and wait for empty xif buffer
        if (buffer_empty) begin
          // Sync and unstall the issue intf
          csr_sync_valid   = 1'b1;
          csr_sync_state_d = NORMAL_OP;
        end
      end
      default: begin
        if (commit_kill) begin
          // We are not accepting the instruction here
          if (buf_has_spec_csr_insn) begin
            // Stall the intf and wait until we can safely sync
            csr_sync_state_d = WAIT_EMPTY_BUF;
          end else begin
            // Sync without stalling the issue intf
            csr_sync_valid = 1'b1;
          end
        end else begin
          // Accept the instruction and stall in the next cycle
          if (predec_csr_spec_mod_reg) csr_sync_state_d = WAIT_EMPTY_BUF;
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(~rst_ni) begin
      csr_sync_state_q = NORMAL_OP;
    end else begin
      csr_sync_state_q = csr_sync_state_d;
    end
  end
endmodule : ara_xif_handler
