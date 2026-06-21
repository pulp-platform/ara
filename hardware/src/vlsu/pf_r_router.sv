// Description:
// R data demux by id (Sec. 5.5 of the prefetcher design). Pure
// combinational, no state: id=0 (real path) goes to pf_rob, id=1
// (predictive) goes to the data buffer fill port. fill_addr is not derived
// here -- AXI's R channel never echoes back the request address, so the
// address comes from a side FIFO at the prefetch_buffer.sv top level,
// popped in lockstep with pred_r_fire_o.
//
// A predictive beat is always single-beat (Sec. pf_rob.sv only ever issues
// len=0 predictive ARs), so every one accepted here is an immediate,
// complete fill -- there is no buffer-full backpressure to apply on this
// side, since pf_data_buffer always has room via FIFO replacement.

module pf_r_router #(
    parameter type axi_r_t = logic
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

    // Predictive completions -> pf_data_buffer fill port
    output logic   pred_r_fire_o,
    output axi_r_t fill_data_o
  );

  logic is_pred;
  assign is_pred = (r_i.id == 1);

  assign real_r_valid_o = r_valid_i && !is_pred;
  assign real_r_o        = r_i;

  assign pred_r_fire_o = r_valid_i && is_pred;
  assign fill_data_o    = r_i;

  assign r_ready_o = is_pred ? 1'b1 : real_r_ready_i;

endmodule : pf_r_router
