// Description:
// Sits on Ara's AR/R load path, between the address generator and the AXI
// cut. Pure module-to-module wiring, no combinational logic of its own (Sec.
// "文件拆分" of the prefetcher design) -- the actual behavior lives in
// pf_rob.sv and pf_data_buffer.sv.
//
// Phase 1: pf_data_buffer is a permanently-empty skeleton, so pf_rob's
// lookup always misses and every AR takes the real path: forwarded
// downstream unmodified (id=0, as addrgen always drives it) and released to
// vldu strictly in the order it was issued.

module prefetch_buffer import pf_pkg::*; #(
    parameter int  unsigned AxiAddrWidth = 0,
    parameter int  unsigned AxiDataWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_r_t      = logic,
    // ROB depth: number of AR bursts that may be outstanding at once.
    // Matches VaddrgenInsnQueueDepth (ara_pkg.sv) so this stage does not
    // reduce Ara's existing outstanding-request capacity.
    parameter int  unsigned RobDepth     = 4,
    // Dependent parameters. DO NOT CHANGE!
    localparam type         addr_t       = logic [AxiAddrWidth-1:0],
    localparam type         data_t       = logic [AxiDataWidth-1:0]
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

  // No predictor/throttle yet (Phase 2/3), so nothing ever flushes or issues
  // a prefetch AR. Kept as wires (not tied off inside pf_rob/pf_data_buffer)
  // so the next phase only has to drive them from here.
  logic flush;
  assign flush = 1'b0;

  logic            lookup_valid;
  addr_t           lookup_addr;
  pf_entry_state_e lookup_state;
  data_t           lookup_data;

  logic  alloc_valid;
  addr_t alloc_addr;
  logic  fill_valid;
  addr_t fill_addr;
  data_t fill_data;
  assign alloc_valid = 1'b0;
  assign alloc_addr  = '0;
  assign fill_valid  = 1'b0;
  assign fill_addr   = '0;
  assign fill_data   = '0;

  pf_rob #(
    .Depth   (RobDepth),
    .axi_ar_t(axi_ar_t),
    .axi_r_t (axi_r_t ),
    .addr_t  (addr_t  ),
    .data_t  (data_t  )
  ) i_pf_rob (
    .clk_i         (clk_i          ),
    .rst_ni        (rst_ni         ),
    .flush_i       (flush          ),
    .axi_ar_i      (axi_ar_i       ),
    .axi_ar_valid_i(axi_ar_valid_i ),
    .axi_ar_ready_o(axi_ar_ready_o ),
    .axi_ar_o      (axi_ar_o       ),
    .axi_ar_valid_o(axi_ar_valid_o ),
    .axi_ar_ready_i(axi_ar_ready_i ),
    .axi_r_i       (axi_r_i        ),
    .axi_r_valid_i (axi_r_valid_i  ),
    .axi_r_ready_o (axi_r_ready_o  ),
    .axi_r_o       (axi_r_o        ),
    .axi_r_valid_o (axi_r_valid_o  ),
    .axi_r_ready_i (axi_r_ready_i  ),
    .lookup_valid_o(lookup_valid   ),
    .lookup_addr_o (lookup_addr    ),
    .lookup_state_i(lookup_state   ),
    .lookup_data_i (lookup_data    )
  );

  pf_data_buffer #(
    .Depth (RobDepth),
    .addr_t(addr_t  ),
    .data_t(data_t  )
  ) i_pf_data_buffer (
    .clk_i         (clk_i        ),
    .rst_ni        (rst_ni       ),
    .flush_i       (flush        ),
    .lookup_valid_i(lookup_valid ),
    .lookup_addr_i (lookup_addr  ),
    .lookup_state_o(lookup_state ),
    .lookup_data_o (lookup_data  ),
    .alloc_valid_i (alloc_valid  ),
    .alloc_addr_i  (alloc_addr   ),
    .fill_valid_i  (fill_valid   ),
    .fill_addr_i   (fill_addr    ),
    .fill_data_i   (fill_data    )
  );

endmodule : prefetch_buffer
