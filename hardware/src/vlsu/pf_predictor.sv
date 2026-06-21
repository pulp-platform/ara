// Description:
// Address prediction (Sec. 5.2 of the prefetcher design). Phase 2: no
// confidence FSM yet -- fires unconditionally, exactly once, for every
// prefetchable instruction. predicted_next_base = scalar_op + vl *
// byte_stride for both VLE and VLSE: expanding the vstart terms shows they
// cancel algebraically, so vstart needs no special-casing here (only vl's
// own extremes -- 0 and VLMAX -- are real boundary cases).
//
// size_i/size_o: forwarded as-is alongside the predicted address, latched
// in the same cycle as new_insn. This module never re-derives size from
// pe_req_i itself -- pf_classifier already computed it once, and reading
// pe_req fields in two different places for two different outputs is
// exactly the kind of thing that drifts apart silently when one branch
// gets edited later and the other doesn't.
//
// Holds at most one pending prediction via a valid/ready handshake (the
// "1-deep skid register" pf_rob's AR arbitration assumes its caller has):
// the predictive AR can lose arbitration to real traffic for an unbounded
// number of cycles, so the prediction must stay live until accepted. If a
// new qualifying instruction arrives before the old prediction was
// accepted, the old one is simply dropped in favor of the new one -- a
// missed prefetch opportunity, not a correctness bug (Phase 3 is where
// in-flight/throttle accounting becomes load-bearing, not here).

module pf_predictor #(
    parameter type pe_req_t = logic,
    parameter type stride_t = logic,
    parameter type addr_t   = logic,
    parameter type size_t   = logic,
    parameter type id_t     = logic
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,

    input  pe_req_t pe_req_i,
    input  logic    pe_req_valid_i,
    input  logic    prefetchable_i,
    input  stride_t byte_stride_i,
    input  size_t   size_i,

    output logic    predict_valid_o,
    input  logic    predict_ready_i,
    output addr_t   predicted_addr_o,
    output size_t   predicted_size_o
  );

  // addrgen can hold pe_req_valid_i/pe_req_i stable across many cycles while
  // it works through one instruction's AR issuance (e.g. a unit-stride
  // burst split across a page boundary). "valid && prefetchable" alone
  // would re-fire every one of those cycles. An instruction's id cannot be
  // reused by the sequencer until the previous holder of that id has fully
  // retired, so "id changed since the last prediction we fired" is a safe
  // new-instruction edge detector that does not require duplicating
  // addrgen's private vinsn_running_q state.
  id_t  last_id_q;
  logic last_id_valid_q;

  logic new_insn;
  assign new_insn = pe_req_valid_i && prefetchable_i &&
                     (!last_id_valid_q || (pe_req_i.id != last_id_q));

  // Compute in a generously wide temporary so neither operand's native
  // width can silently truncate the product before the final cast down to
  // addr_t -- exactly the kind of boundary bug Phase 2 is meant to catch.
  logic [127:0] predicted_addr_wide;
  assign predicted_addr_wide = 128'(pe_req_i.scalar_op) + 128'(pe_req_i.vl) * 128'(byte_stride_i);

  logic  pending_valid_q;
  addr_t pending_addr_q;
  size_t pending_size_q;

  assign predict_valid_o  = pending_valid_q;
  assign predicted_addr_o = pending_addr_q;
  assign predicted_size_o = pending_size_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      last_id_q       <= '0;
      last_id_valid_q <= 1'b0;
      pending_valid_q <= 1'b0;
      pending_addr_q  <= '0;
      pending_size_q  <= '0;
    end else begin
      if (new_insn) begin
        last_id_q       <= pe_req_i.id;
        last_id_valid_q <= 1'b1;
        pending_valid_q <= 1'b1;
        pending_addr_q  <= addr_t'(predicted_addr_wide);
        pending_size_q  <= size_i;
      end else if (pending_valid_q && predict_ready_i) begin
        pending_valid_q <= 1'b0;
      end
    end
  end

endmodule : pf_predictor
