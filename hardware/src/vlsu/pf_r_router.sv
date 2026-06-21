// Description:
// R data demux by id (Sec. 5.5 of the prefetcher design). Pure
// combinational, no state: id=0 (real path) goes to pf_rob, id=1
// (predictive) pops its {addr, size} from the pending-address tracker
// (pf_addr_fifo, instantiated at the prefetch_buffer.sv top level -- AXI's
// R channel never echoes back the request address) and, only if r_resp is
// RESP_OKAY, fills the data buffer. A non-OKAY response (SLVERR/DECERR/
// EXOKAY) still pops the tracker -- it must, or the tracker desyncs from
// future predictive completions -- but is otherwise discarded: caching it
// would let corrupt data masquerade as a hit on a later real access. This
// check did not exist in the original Phase 2 milestone; vldu's own real
// path has never checked r_resp (it trusts the bus), but a prefetch result
// sitting in the buffer for an arbitrary number of cycles before anyone
// asks for it is a different risk profile and gets checked here.
//
// A predictive beat is always single-beat (Sec. pf_rob.sv only ever issues
// len=0 predictive ARs), so every one accepted here is an immediate,
// complete pop+fill decision -- there is no buffer-full backpressure to
// apply on this side, since pf_data_buffer always has room via FIFO
// replacement.

module pf_r_router import axi_pkg::RESP_OKAY; #(
    parameter type axi_r_t = logic,
    parameter type addr_t  = logic,
    parameter type size_t  = logic
  ) (
    // R: from the AXI cut / memory -- carries both real (id=0) and
    // predictive (id=1) completions on the one physical channel.
    input  axi_r_t r_i,
    input  logic   r_valid_i,
    output logic   r_ready_o,

    // R: real-path completions -> pf_rob
    output axi_r_t real_r_o,
    output logic   real_r_valid_o,
    input  logic   real_r_ready_i,

    // Pop the pending-address tracker the moment a predictive beat
    // arrives, regardless of resp -- the tracker only knows issue order,
    // not whether the fetch succeeded.
    output logic   pred_addr_fifo_pop_o,
    input  addr_t  pred_addr_fifo_addr_i,
    input  size_t  pred_addr_fifo_size_i,

    // Fill the data buffer -- gated on RESP_OKAY.
    output logic   fill_valid_o,
    output addr_t  fill_addr_o,
    output size_t  fill_size_o,
    output axi_r_t fill_data_o
  );

  logic is_pred;
  assign is_pred = (r_i.id == 1);

  assign real_r_valid_o = r_valid_i && !is_pred;
  assign real_r_o        = r_i;

  assign pred_addr_fifo_pop_o = r_valid_i && is_pred;

  // Strict equality, not "inside {RESP_OKAY, RESP_EXOKAY}": EXOKAY only
  // means a successful *exclusive* access, and Ara never issues exclusive
  // ARs (no lock semantics anywhere in addrgen), so a subordinate
  // returning EXOKAY here would itself be a protocol violation -- treat
  // it the same as SLVERR/DECERR and discard, rather than cache it.
  assign fill_valid_o = r_valid_i && is_pred && (r_i.resp == RESP_OKAY);
  assign fill_addr_o  = pred_addr_fifo_addr_i;
  assign fill_size_o  = pred_addr_fifo_size_i;
  assign fill_data_o  = r_i;

  assign r_ready_o = is_pred ? 1'b1 : real_r_ready_i;

endmodule : pf_r_router
