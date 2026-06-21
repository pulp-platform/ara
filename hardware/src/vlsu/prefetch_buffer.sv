// Description:
// Sits on Ara's AR/R load path, between the address generator and the AXI cut.
// Phase 0: pure combinational passthrough. No buffering, no prediction, no
// reordering. id is forwarded unmodified (addrgen always drives id=0).
// Exists so that later phases (classifier, predictor, ROB, data buffer) can be
// added incrementally without re-wiring vlsu.sv.

module prefetch_buffer #(
    parameter type axi_ar_t = logic,
    parameter type axi_r_t  = logic
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,

    // AR: from addrgen
    input  axi_ar_t axi_ar_i,
    input  logic    axi_ar_valid_i,
    output logic    axi_ar_ready_o,

    // AR: to the AXI cut / memory
    output axi_ar_t axi_ar_o,
    output logic    axi_ar_valid_o,
    input  logic    axi_ar_ready_i,

    // R: from the AXI cut / memory
    input  axi_r_t  axi_r_i,
    input  logic    axi_r_valid_i,
    output logic    axi_r_ready_o,

    // R: to vldu
    output axi_r_t  axi_r_o,
    output logic    axi_r_valid_o,
    input  logic    axi_r_ready_i
  );

  assign axi_ar_o       = axi_ar_i;
  assign axi_ar_valid_o = axi_ar_valid_i;
  assign axi_ar_ready_o = axi_ar_ready_i;

  assign axi_r_o       = axi_r_i;
  assign axi_r_valid_o = axi_r_valid_i;
  assign axi_r_ready_o = axi_r_ready_i;

endmodule : prefetch_buffer
