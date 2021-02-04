// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File:   simd_div.sv
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Date:   04.02.2021
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's Serial Divider, operating on elements 64-bit wide.
// The unit serializes the whole computation, so it cannot parallelize sub-64-bit arithmetic.

module simd_div import ara_pkg::*; import rvv_pkg::*; #(
    // Dependant parameters. DO NOT CHANGE!
    parameter int  unsigned DataWidth = $bits(elen_t),
    parameter int  unsigned StrbWidth = DataWidth/8,
    parameter type          strb_t    = logic [DataWidth/8-1:0]
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

  /*****************
   *  Definitions  *
   *****************/

  // The issue CU accepts new requests and issue the operands to the serial divider (serdiv)
  // It handles the input ready_o signal and the serdiv_in_valid
  // When the main handshake is complete, it loads the issue counter and commit counter to track
  //how many elements should be issued and committed.
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

  /**********************
   *  In/Out registers  *
   **********************/

  // Input registers
  assign opa_d  = (valid_i && ready_o) ? operand_a_i : opa_q;
  assign opb_d  = (valid_i && ready_o) ? operand_b_i : opb_q;
  assign vew_d  = (valid_i && ready_o) ? vew_i       : vew_q;
  assign op_d   = (valid_i && ready_o) ? op_i        : op_q;
  assign be_d   = (valid_i && ready_o) ? be_i        : be_q;
  assign mask_d = (valid_i && ready_o) ? mask_i      : mask_q;

  /************
   *  Control  *
   ************/

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
  // issue_cnt  counts how many elements should still be issued, and controls the first wall of MUXes
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

  /**************
   *  Datapath  *
   **************/

  // serdiv input MUXes
  always_comb begin
    // First wall of MUXes: select one byte/halfword/word/dword from the inputs and fill it with zeroes/sign extend it
    opa_w8  = op_q inside {VDIV, VREM} ? {{56{opa_q.w8 [issue_cnt_q[2:0]][ 7]}}, opa_q.w8 [issue_cnt_q[2:0]]} : {56'b0, opa_q.w8 [issue_cnt_q[2:0]]};
    opb_w8  = op_q inside {VDIV, VREM} ? {{56{opb_q.w8 [issue_cnt_q[2:0]][ 7]}}, opb_q.w8 [issue_cnt_q[2:0]]} : {56'b0, opb_q.w8 [issue_cnt_q[2:0]]};
    opa_w16 = op_q inside {VDIV, VREM} ? {{48{opa_q.w16[issue_cnt_q[1:0]][15]}}, opa_q.w16[issue_cnt_q[1:0]]} : {48'b0, opa_q.w16[issue_cnt_q[1:0]]};
    opb_w16 = op_q inside {VDIV, VREM} ? {{48{opb_q.w16[issue_cnt_q[1:0]][15]}}, opb_q.w16[issue_cnt_q[1:0]]} : {48'b0, opb_q.w16[issue_cnt_q[1:0]]};
    opa_w32 = op_q inside {VDIV, VREM} ? {{32{opa_q.w32[issue_cnt_q[0:0]][31]}}, opa_q.w32[issue_cnt_q[0:0]]} : {32'b0, opa_q.w32[issue_cnt_q[0:0]]};
    opb_w32 = op_q inside {VDIV, VREM} ? {{32{opb_q.w32[issue_cnt_q[0:0]][31]}}, opb_q.w32[issue_cnt_q[0:0]]} : {32'b0, opb_q.w32[issue_cnt_q[0:0]]};
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
    .WIDTH(ELEN),
    .STABLE_HANDSHAKE(1)
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

  /****************************
   *  Sequential assignments  *
   ****************************/

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

// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
//         Andreas Traber    <traber@iis.ee.ethz.ch>, ETH Zurich
//
// Date: 18.10.2018
// Description: simple 64bit serial divider
// MODIFICATION: in_rdy_o is kept stable during handshake

module serdiv_mod import ariane_pkg::*; #(
    parameter WIDTH = 64
  ) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    // input IF
    input  logic [TRANS_ID_BITS-1:0] id_i,
    input  logic [WIDTH-1:0]         op_a_i,
    input  logic [WIDTH-1:0]         op_b_i,
    input  logic [1:0]               opcode_i, // 0: udiv, 2: urem, 1: div, 3: rem
    // handshake
    input  logic                     in_vld_i, // there is a cycle delay from in_rdy_o->in_vld_i, see issue_read_operands.sv stage
    output logic                     in_rdy_o,
    input  logic                     flush_i,
    // output IF
    output logic                     out_vld_o,
    input  logic                     out_rdy_i,
    output logic [TRANS_ID_BITS-1:0] id_o,
    output logic [WIDTH-1:0]         res_o
  );

  /////////////////////////////////////
  // signal declarations
  /////////////////////////////////////

  enum logic [1:0] {IDLE, DIVIDE, FINISH} state_d, state_q;

  logic [WIDTH-1:0] res_q, res_d;
  logic [WIDTH-1:0] op_a_q, op_a_d;
  logic [WIDTH-1:0] op_b_q, op_b_d;
  logic             op_a_sign, op_b_sign;
  logic             op_b_zero, op_b_zero_q, op_b_zero_d;

  logic [TRANS_ID_BITS-1:0] id_q, id_d;

  logic rem_sel_d, rem_sel_q;
  logic comp_inv_d, comp_inv_q;
  logic res_inv_d, res_inv_q;

  logic [WIDTH-1:0] add_mux;
  logic [WIDTH-1:0] add_out;
  logic [WIDTH-1:0] add_tmp;
  logic [WIDTH-1:0] b_mux;
  logic [WIDTH-1:0] out_mux;

  logic [$clog2(WIDTH+1)-1:0] cnt_q, cnt_d;
  logic                       cnt_zero;

  logic [WIDTH-1:0]           lzc_a_input, lzc_b_input, op_b;
  logic [$clog2(WIDTH)-1:0]   lzc_a_result, lzc_b_result;
  logic [$clog2(WIDTH+1)-1:0] shift_a;
  logic [$clog2(WIDTH+1):0]   div_shift;

  logic a_reg_en, b_reg_en, res_reg_en, ab_comp, pm_sel, load_en;
  logic lzc_a_no_one, lzc_b_no_one;
  logic div_res_zero_d, div_res_zero_q;


  /////////////////////////////////////
  // align the input operands
  // for faster division
  /////////////////////////////////////

  assign op_b_zero = (op_b_i == 0);
  assign op_a_sign = op_a_i[$high(op_a_i)];
  assign op_b_sign = op_b_i[$high(op_b_i)];

  assign lzc_a_input = (opcode_i[0] & op_a_sign) ? {~op_a_i, 1'b0} : op_a_i;
  assign lzc_b_input = (opcode_i[0] & op_b_sign) ? ~op_b_i         : op_b_i;

  lzc #(
    .MODE  ( 1     ), // count leading zeros
    .WIDTH ( WIDTH )
  ) i_lzc_a (
    .in_i    ( lzc_a_input  ),
    .cnt_o   ( lzc_a_result ),
    .empty_o ( lzc_a_no_one )
  );

  lzc #(
    .MODE  ( 1     ), // count leading zeros
    .WIDTH ( WIDTH )
  ) i_lzc_b (
    .in_i    ( lzc_b_input  ),
    .cnt_o   ( lzc_b_result ),
    .empty_o ( lzc_b_no_one )
  );

  assign shift_a   = (lzc_a_no_one) ? WIDTH : lzc_a_result;
  assign div_shift = (lzc_b_no_one) ? WIDTH : lzc_b_result-shift_a;

  assign op_b = op_b_i <<< $unsigned(div_shift);

  // the division is zero if |opB| > |opA| and can be terminated
  assign div_res_zero_d = (load_en) ? ($signed(div_shift) < 0) : div_res_zero_q;

  /////////////////////////////////////
  // Datapath
  /////////////////////////////////////

  assign pm_sel = load_en & ~(opcode_i[0] & (op_a_sign ^ op_b_sign));

  // muxes
  assign add_mux = (load_en) ? op_a_i : op_b_q;

  // attention: logical shift by one in case of negative operand B!
  assign b_mux = (load_en) ? op_b : {comp_inv_q, (op_b_q[$high(op_b_q):1])};

  // in case of bad timing, we could output from regs -> needs a cycle more in the FSM
  assign out_mux = (rem_sel_q) ? op_a_q : res_q;
  // assign out_mux     = (rem_sel_q) ? op_a_d : res_d;

  // invert if necessary
  assign res_o = (res_inv_q) ? -$signed(out_mux) : out_mux;

  // main comparator
  assign ab_comp = ((op_a_q == op_b_q) | ((op_a_q > op_b_q) ^ comp_inv_q)) & ((|op_a_q) | op_b_zero_q);

  // main adder
  assign add_tmp = (load_en) ? 0                : op_a_q;
  assign add_out = (pm_sel) ? add_tmp + add_mux : add_tmp - $signed(add_mux);

  /////////////////////////////////////
  // FSM, counter
  /////////////////////////////////////

  assign cnt_zero = (cnt_q == 0);
  assign cnt_d    = (load_en) ? div_shift :
                    (~cnt_zero) ? cnt_q - 1 : cnt_q;

  always_comb begin : p_fsm
    // default
    state_d    = state_q;
    in_rdy_o   = 1'b0;
    out_vld_o  = 1'b0;
    load_en    = 1'b0;
    a_reg_en   = 1'b0;
    b_reg_en   = 1'b0;
    res_reg_en = 1'b0;

    unique case (state_q)
      IDLE: begin
        in_rdy_o = 1'b1;

        if (in_vld_i) begin
          //          in_rdy_o  = 1'b0;// there is a cycle delay until the valid signal is asserted by the id stage
          a_reg_en = 1'b1;
          b_reg_en = 1'b1;
          load_en  = 1'b1;
          state_d  = DIVIDE;
        end
      end
      DIVIDE: begin
        if(~div_res_zero_q) begin
          a_reg_en   = ab_comp;
          b_reg_en   = 1'b1;
          res_reg_en = 1'b1;
        end
        // can end the division now if the result is clearly 0
        if(div_res_zero_q) begin
          out_vld_o = 1'b1;
          state_d   = FINISH;
          if(out_rdy_i) begin
            // in_rdy_o = 1'b1;// there is a cycle delay until the valid signal is asserted by the id stage
            state_d = IDLE;
          end
        end else if (cnt_zero) begin
          state_d = FINISH;
        end
      end
      FINISH: begin
        out_vld_o = 1'b1;

        if (out_rdy_i) begin
          // in_rdy_o = 1'b1;// there is a cycle delay until the valid signal is asserted by the id stage
          state_d = IDLE;
        end
      end
      default : state_d = IDLE;
    endcase

    if (flush_i) begin
      in_rdy_o  = 1'b0;
      out_vld_o = 1'b0;
      a_reg_en  = 1'b0;
      b_reg_en  = 1'b0;
      load_en   = 1'b0;
      state_d   = IDLE;
    end
  end

  /////////////////////////////////////
  // regs, flags
  /////////////////////////////////////

  // get flags
  assign rem_sel_d   = (load_en) ? opcode_i[1]                                                        : rem_sel_q;
  assign comp_inv_d  = (load_en) ? opcode_i[0] & op_b_sign                                            : comp_inv_q;
  assign op_b_zero_d = (load_en) ? op_b_zero                                                          : op_b_zero_q;
  assign res_inv_d   = (load_en) ? (~op_b_zero | opcode_i[1]) & opcode_i[0] & (op_a_sign ^ op_b_sign) : res_inv_q;

  // transaction id
  assign id_d = (load_en) ? id_i : id_q;
  assign id_o = id_q;

  assign op_a_d = (a_reg_en) ? add_out : op_a_q;
  assign op_b_d = (b_reg_en) ? b_mux   : op_b_q;
  assign res_d  = (load_en) ? '0       :
                    (res_reg_en) ? {res_q[$high(res_q)-1:0], ab_comp} : res_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (~rst_ni) begin
      state_q        <= IDLE;
      op_a_q         <= '0;
      op_b_q         <= '0;
      res_q          <= '0;
      cnt_q          <= '0;
      id_q           <= '0;
      rem_sel_q      <= 1'b0;
      comp_inv_q     <= 1'b0;
      res_inv_q      <= 1'b0;
      op_b_zero_q    <= 1'b0;
      div_res_zero_q <= 1'b0;
    end else begin
      state_q        <= state_d;
      op_a_q         <= op_a_d;
      op_b_q         <= op_b_d;
      res_q          <= res_d;
      cnt_q          <= cnt_d;
      id_q           <= id_d;
      rem_sel_q      <= rem_sel_d;
      comp_inv_q     <= comp_inv_d;
      res_inv_q      <= res_inv_d;
      op_b_zero_q    <= op_b_zero_d;
      div_res_zero_q <= div_res_zero_d;
    end
  end

endmodule

