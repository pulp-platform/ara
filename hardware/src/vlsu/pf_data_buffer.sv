// Description:
// Fully-associative prefetch data buffer (Sec. 5.6 of the prefetcher design).
// Phase 1: skeleton only. Nothing ever writes a valid entry (alloc_i/fill_i
// are unconnected at this phase), so every lookup reports EMPTY by
// construction. The lookup/alloc/fill port shapes are final so that Phase 2
// only has to fill in storage and tag comparison, not re-wire pf_rob.

module pf_data_buffer import pf_pkg::*; #(
    parameter int  unsigned Depth  = 4,
    parameter type          addr_t = logic,
    parameter type          data_t = logic
  ) (
    input  logic            clk_i,
    input  logic            rst_ni,

    // Mispredict / pattern-break flush. Unused until Phase 4.
    input  logic            flush_i,

    // Lookup: queried by pf_rob for every incoming AR.
    input  logic            lookup_valid_i,
    input  addr_t            lookup_addr_i,
    output pf_entry_state_e lookup_state_o,
    output data_t            lookup_data_o,

    // Reserve an in-flight slot for a newly-issued prefetch AR. Unused until
    // Phase 3 (nothing issues prefetch ARs yet).
    input  logic             alloc_valid_i,
    input  addr_t            alloc_addr_i,

    // Fill a slot once its prefetch R data arrives. Unused until Phase 2.
    input  logic             fill_valid_i,
    input  addr_t            fill_addr_i,
    input  data_t            fill_data_i
  );

  // No storage yet: Depth/clk_i/rst_ni/flush_i/alloc_*/fill_* are kept as
  // real ports for interface stability, but nothing is wired to them this
  // phase, so the buffer is empty by construction, not by override.
  assign lookup_state_o = PF_ENTRY_EMPTY;
  assign lookup_data_o  = '0;

endmodule : pf_data_buffer
