// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's Serial Divider, operating on elements 64-bit wide.
// The unit serializes the whole computation, so it cannot parallelize sub-64-bit arithmetic.

module simd_div import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth = $bits(elen_t),
    localparam int  unsigned StrbWidth = DataWidth/8,
    localparam type          strb_t    = logic [DataWidth/8-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,
    input  elen_t   operand_a_i,
    input  elen_t   operand_b_i,
    input  strb_t   mask_i,
    input  ara_op_e op_i,
    input  strb_t   be_i,
    input  vew_e    vew_i,
    output elen_t   result_o,
    output strb_t   mask_o,
    input  logic    valid_i,
    output logic    ready_o,
    input  logic    ready_i,
    output logic    valid_o
  );

  ///////////////////
  //  Definitions  //
  ///////////////////

  // The issue CU accepts new requests and issue the operands to the serial divider (serdiv)
  // It handles the input ready_o signal and the serdiv_in_valid
  // When the main handshake is complete, it loads the issue counter and commit counter to track
  // how many elements should be issued and committed.
  // Then, it validates the valid input operands and skips the invalid ones
  // When all the operands have been issued, it waits until the whole result is formed before
  // accepting another external request, as vew_q is used by the serdiv output MUX and
  // should therefore remain stable until the end
  typedef enum logic [2:0] {ISSUE_IDLE, LOAD, ISSUE_VALID, ISSUE_SKIP, WAIT_DONE} issue_state_t;
  // The commit CU stores the various serdiv results in the result buffer
  // It handles the valid_o signal and the serdiv_out_ready
  // After the issue CU has accepted a new request, the commit CU tracks how many operands
  // should be still committed and which results to skip
  // When the whole result is complete, it asserts the valid_o and waits until the result is
  // accepted before committing new data
  typedef enum logic [1:0] {COMMIT_IDLE, COMMIT_READY, COMMIT_SKIP, COMMIT_DONE} commit_state_t;

  issue_state_t  issue_state_d, issue_state_q;
  commit_state_t commit_state_d, commit_state_q;

  // Input registers, buffers for the input operands and related data
  // Kept stable until the complete 64-bit result is formed
  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][ 7:0] w8;
  } operand_t;
  operand_t opa_d, opa_q, opb_d, opb_q;
  vew_e     vew_d, vew_q;
  ara_op_e  op_d, op_q;
  strb_t    be_d, be_q;
  // Output buffer, directly linked to result_o
  elen_t    result_d, result_q;
  assign result_o = result_q;
  // Mask buffer, directly linked to mask_o
  strb_t mask_d, mask_q;
  assign mask_o = mask_q;

  // Counters
  logic       load_cnt, issue_cnt_en, commit_cnt_en;
  logic [2:0] cnt_init_val, issue_cnt_d, issue_cnt_q, commit_cnt_d, commit_cnt_q;

  // Serial Divider
  logic           serdiv_out_ready, serdiv_out_valid, serdiv_in_valid, serdiv_in_ready;
  logic     [1:0] serdiv_opcode;
  elen_t          serdiv_opa, serdiv_opb;
  operand_t       serdiv_result;

  // Partially processed data
  elen_t    opa_w8, opb_w8, opa_w16, opb_w16, opa_w32, opb_w32, opa_w64, opb_w64;
  operand_t serdiv_result_masked, shifted_result;

  ////////////////////////
  //  In/Out registers  //
  ////////////////////////

  // Input registers
  assign opa_d  = (valid_i && ready_o) ? operand_a_i : opa_q;
  assign opb_d  = (valid_i && ready_o) ? operand_b_i : opb_q;
  assign vew_d  = (valid_i && ready_o) ? vew_i       : vew_q;
  assign op_d   = (valid_i && ready_o) ? op_i        : op_q;
  assign be_d   = (valid_i && ready_o) ? be_i        : be_q;
  assign mask_d = (valid_i && ready_o) ? mask_i      : mask_q;

  ///////////////
  //  Control  //
  ///////////////

  // Issue CU
  always_comb begin : issue_cu_p
    ready_o         = 1'b0;
    load_cnt        = 1'b0;
    serdiv_in_valid = 1'b0;
    issue_cnt_en    = 1'b0;
    issue_state_d   = issue_state_q;

    case (issue_state_q)
      ISSUE_IDLE: begin
        // We can accept a new request from the external environment
        ready_o       = 1'b1;
        issue_state_d = valid_i ? LOAD : ISSUE_IDLE;
      end
      LOAD: begin
        // The request was accepted: load how many elements to process/commit
        load_cnt      = 1'b1;
        // Check if the next byte is valid or not. If not, skip it.
        issue_state_d = (be_q[cnt_init_val]) ? ISSUE_VALID : ISSUE_SKIP;
      end
      ISSUE_VALID: begin
        // The inputs are valid
        serdiv_in_valid = 1'b1;
        // Count down when these inputs are consumed by the serdiv
        issue_cnt_en    = (serdiv_in_valid && serdiv_in_ready) ? 1'b1 : 1'b0;
        // Change state only when the serdiv accepts the operands
        if (serdiv_in_valid && serdiv_in_ready) begin
          // If we are issuing the last operands, wait for the whole result to be completed
          if (issue_cnt_q == '0) begin
            issue_state_d = WAIT_DONE;
          // If we are not issuing the last operands, decide if to process or skip the next byte
          end else begin
            issue_state_d = (be_q[issue_cnt_d]) ? ISSUE_VALID : ISSUE_SKIP;
          end
        end
      end
      ISSUE_SKIP: begin
        // Skip the invalid inputs
        issue_cnt_en = 1'b1;
        // If we are issuing the last operands, wait for the whole result to be completed
        if (issue_cnt_q == '0) begin
          issue_state_d = WAIT_DONE;
        // If we are not issuing the last operands, decide if to process or skip the next byte
        end else begin
          issue_state_d = (be_q[issue_cnt_d]) ? ISSUE_VALID : ISSUE_SKIP;
        end
      end
      WAIT_DONE: begin
        // Wait for the entire 64-bit result to be created
        // We need vew_q stable when serdiv_result is produced
        issue_state_d = valid_o ? ISSUE_IDLE : WAIT_DONE;
      end
      default: begin
        issue_state_d = ISSUE_IDLE;
      end
    endcase
  end

  // Commit CU
  always_comb begin : commit_cu_p
    valid_o          = 1'b0;
    serdiv_out_ready = 1'b0;
    commit_cnt_en    = 1'b0;
    commit_state_d   = commit_state_q;

    case (commit_state_q)
      COMMIT_IDLE: begin
        // Start if the issue CU has already started
        if (issue_state_q != ISSUE_IDLE) begin
          commit_state_d = (be_q[cnt_init_val]) ? COMMIT_READY : COMMIT_SKIP;
        end
      end
      COMMIT_READY: begin
        serdiv_out_ready = 1'b1;
        commit_cnt_en    = (serdiv_out_valid && serdiv_out_ready) ? 1'b1 : 1'b0;
        // Change state only when the serdiv produce a valid result
        if (serdiv_out_valid && serdiv_out_ready) begin
          // If we are committing the last result, complete the execution
          if (commit_cnt_q == '0) begin
            commit_state_d = COMMIT_DONE;
          // If we are not committing the last result, decide if to process or skip the next one
          end else begin
            commit_state_d = (be_q[commit_cnt_d]) ? COMMIT_READY : COMMIT_SKIP;
          end
        end
      end
      COMMIT_SKIP: begin
        serdiv_out_ready = 1'b1;
        commit_cnt_en    = 1'b1;
        // If we are skipping the last result, complete the execution
        if (commit_cnt_q == '0) begin
          commit_state_d = COMMIT_DONE;
        // If we are not committing the last result, decide if to process or skip the next one
        end else begin
          commit_state_d = (be_q[commit_cnt_d]) ? COMMIT_READY : COMMIT_SKIP;
        end
      end
      COMMIT_DONE: begin
        // The 64-bit result is complete, validate it
        valid_o        = 1'b1;
        commit_state_d = ready_i ? COMMIT_IDLE : COMMIT_DONE;
      end
      default: begin
        commit_state_d = COMMIT_IDLE;
      end
    endcase
  end

  // Counters
  // issue_cnt  counts how many elements should still be issued, and controls the first wall of
  // MUXes
  // commit_cnt counts how many elements should still be committed
  always_comb begin
    issue_cnt_d  = issue_cnt_q;
    commit_cnt_d = commit_cnt_q;
    cnt_init_val = '0;

    // Track how many elements we should process (load #elements-1)
    case (vew_q)
      EW8 : cnt_init_val = 3'h7;
      EW16: cnt_init_val = 3'h3;
      EW32: cnt_init_val = 3'h1;
      EW64: cnt_init_val = 3'h0;
    endcase
    // Load the initial number of elements to process (i.e., also the number of results to collect)
    if (load_cnt) begin
      issue_cnt_d  = cnt_init_val;
      commit_cnt_d = cnt_init_val;
    end

    // Count down when serdiv accepts one couple of operands or when they are invalid
    if (issue_cnt_en) issue_cnt_d -= 1;
    // Count down when serdiv produce one result or when it is invalid
    if (commit_cnt_en) commit_cnt_d -= 1;
  end

  // Opcode selection
  always_comb begin
    case (op_q)
      VDIVU: serdiv_opcode   = 2'b00;
      VDIV : serdiv_opcode   = 2'b01;
      VREMU: serdiv_opcode   = 2'b10;
      VREM : serdiv_opcode   = 2'b11;
      default: serdiv_opcode = 2'b00;
    endcase
  end

  ////////////////
  //  Datapath  //
  ////////////////

  // serdiv input MUXes
  always_comb begin
    // First wall of MUXes: select one byte/halfword/word/dword from the inputs and fill it with
    // zeroes/sign extend it
    opa_w8 = op_q inside {VDIV, VREM} ?
      {{56{opa_q.w8 [issue_cnt_q[2:0]][ 7]}}, opa_q.w8 [issue_cnt_q[2:0]]} :
      {56'b0, opa_q.w8 [issue_cnt_q[2:0]]};
    opb_w8 = op_q inside {VDIV, VREM} ?
      {{56{opb_q.w8 [issue_cnt_q[2:0]][ 7]}}, opb_q.w8 [issue_cnt_q[2:0]]} :
      {56'b0, opb_q.w8 [issue_cnt_q[2:0]]};

    opa_w16 = op_q inside {VDIV, VREM} ?
      {{48{opa_q.w16[issue_cnt_q[1:0]][15]}}, opa_q.w16[issue_cnt_q[1:0]]} :
      {48'b0, opa_q.w16[issue_cnt_q[1:0]]};
    opb_w16 = op_q inside {VDIV, VREM} ?
      {{48{opb_q.w16[issue_cnt_q[1:0]][15]}}, opb_q.w16[issue_cnt_q[1:0]]} :
      {48'b0, opb_q.w16[issue_cnt_q[1:0]]};

    opa_w32 = op_q inside {VDIV, VREM} ?
      {{32{opa_q.w32[issue_cnt_q[0:0]][31]}}, opa_q.w32[issue_cnt_q[0:0]]} :
      {32'b0, opa_q.w32[issue_cnt_q[0:0]]};
    opb_w32 = op_q inside {VDIV, VREM} ?
      {{32{opb_q.w32[issue_cnt_q[0:0]][31]}}, opb_q.w32[issue_cnt_q[0:0]]} :
      {32'b0, opb_q.w32[issue_cnt_q[0:0]]};

    opa_w64 = opa_q.w64;
    opb_w64 = opb_q.w64;

    // Last 64-bit wide selection MUX
    unique case (vew_q)
      EW8: begin
        serdiv_opa = opa_w8;
        serdiv_opb = opb_w8;
      end
      EW16: begin
        serdiv_opa = opa_w16;
        serdiv_opb = opb_w16;
      end
      EW32: begin
        serdiv_opa = opa_w32;
        serdiv_opb = opb_w32;
      end
      EW64: begin
        serdiv_opa = opa_w64;
        serdiv_opb = opb_w64;
      end
      default:;
    endcase
  end

  // Serial divider
  serdiv #(
    .WIDTH           (ELEN),
    .STABLE_HANDSHAKE(1   )
  ) i_serdiv (
    .clk_i    (clk_i            ),
    .rst_ni   (rst_ni           ),
    .id_i     ('0               ),
    .op_a_i   (serdiv_opa       ),
    .op_b_i   (serdiv_opb       ),
    .opcode_i (serdiv_opcode    ),
    .in_vld_i (serdiv_in_valid  ),
    .in_rdy_o (serdiv_in_ready  ),
    .flush_i  (1'b0             ),
    .out_vld_o(serdiv_out_valid ),
    .out_rdy_i(serdiv_out_ready ),
    .id_o     (/* unconnected */),
    .res_o    (serdiv_result    )
  );

  // Output buffer
  // Shift the partial result and update the output buffer with the new masked byte/halfword/word
  // If we are skipping a byte, just shift
  always_comb begin
    if (commit_state_q == COMMIT_SKIP) begin
      shifted_result       = result_q << 8;
      serdiv_result_masked = '0;
    end else begin
      case (vew_q)
        EW8: begin
          shifted_result       = result_q << 8;
          serdiv_result_masked = {56'b0, serdiv_result.w8[0]};
        end
        EW16: begin
          shifted_result       = result_q << 16;
          serdiv_result_masked = {48'b0, serdiv_result.w16[0]};
        end
        EW32: begin
          shifted_result       = result_q << 32;
          serdiv_result_masked = {32'b0, serdiv_result.w32[0]};
        end
        default: begin
          shifted_result       = '0;
          serdiv_result_masked = serdiv_result;
        end
      endcase
    end
  end
  assign result_d = (commit_cnt_en) ? (shifted_result | serdiv_result_masked) : result_q;

  //////////////////////////////
  //  Sequential assignments  //
  //////////////////////////////

  // In/Out CUs sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_state_q  <= ISSUE_IDLE;
      commit_state_q <= COMMIT_IDLE;

      opa_q    <= '0;
      opb_q    <= '0;
      vew_q    <= EW8;
      op_q     <= VDIV;
      be_q     <= '0;
      mask_q   <= '0;
      result_q <= '0;

      issue_cnt_q  <= '0;
      commit_cnt_q <= '0;
    end else begin
      issue_state_q  <= issue_state_d;
      commit_state_q <= commit_state_d;

      opa_q    <= opa_d;
      opb_q    <= opb_d;
      vew_q    <= vew_d;
      op_q     <= op_d;
      be_q     <= be_d;
      mask_q   <= mask_d;
      result_q <= result_d;

      issue_cnt_q  <= issue_cnt_d;
      commit_cnt_q <= commit_cnt_d;
    end
  end
endmodule : simd_div
