// Description:
// Fully-associative prefetch data buffer (Sec. 5.6 of the prefetcher
// design). Phase 2b: real storage, but only EMPTY/VALID are reachable --
// IN_FLIGHT (Phase 3) has no producer yet, since alloc_valid_i is still
// unconnected at the prefetch_buffer.sv top level.
//
// Entry is {addr, size, data, state}, not just {addr, data, state}: a hit
// requires addr == query_addr AND size == query_size. Address-only
// matching would let e.g. a vlse32 prefetch at address A satisfy a later
// vlse64 real request at the same address A, silently handing vldu data
// that was fetched (and sized) for the wrong element width. FIFO
// replacement on fill, no dedup against an already-cached {addr,size} (a
// harmless minor inefficiency: a lookup only needs *a* matching valid
// entry, not a unique one).

module pf_data_buffer import pf_pkg::*; #(
    parameter int  unsigned Depth  = 4,
    parameter type          addr_t = logic,
    parameter type          size_t = logic,
    parameter type          data_t = logic,
    // Dependent parameters. DO NOT CHANGE!
    localparam int unsigned IdxWidth = (Depth > 1) ? $clog2(Depth) : 1
  ) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,

    // Lookup: queried by pf_rob for every incoming real AR.
    input  logic            lookup_valid_i,
    input  addr_t           lookup_addr_i,
    input  size_t           lookup_size_i,
    output pf_entry_state_e lookup_state_o,
    output data_t            lookup_data_o,

    // Reserve an in-flight slot for a newly-issued prefetch AR. Unused
    // until Phase 3 -- nothing drives this port yet.
    input  logic  alloc_valid_i,
    input  addr_t alloc_addr_i,
    input  size_t alloc_size_i,

    // Fill a slot once its prefetch R data arrives (pf_r_router, id=1,
    // already gated on RESP_OKAY upstream of this port).
    input  logic  fill_valid_i,
    input  addr_t fill_addr_i,
    input  size_t fill_size_i,
    input  data_t fill_data_i
  );

  addr_t           [Depth-1:0] addr_q;
  size_t           [Depth-1:0] size_q;
  data_t           [Depth-1:0] data_q;
  pf_entry_state_e [Depth-1:0] state_q;

  logic [IdxWidth-1:0] replace_ptr_d, replace_ptr_q;
  assign replace_ptr_d = (replace_ptr_q == IdxWidth'(Depth - 1)) ? '0 : replace_ptr_q + 1;

  logic [Depth-1:0] hit_match;
  for (genvar i = 0; i < Depth; i++) begin : g_match
    assign hit_match[i] = (state_q[i] == PF_ENTRY_VALID)
                            && (addr_q[i] == lookup_addr_i)
                            && (size_q[i] == lookup_size_i);
  end

  always_comb begin
    lookup_state_o = PF_ENTRY_EMPTY;
    lookup_data_o  = '0;
    for (int unsigned i = 0; i < Depth; i++) begin
      if (lookup_valid_i && hit_match[i]) begin
        lookup_state_o = PF_ENTRY_VALID;
        lookup_data_o  = data_q[i];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= '0;
      addr_q        <= '0;
      size_q        <= '0;
      data_q        <= '0;
      replace_ptr_q <= '0;
    end else if (flush_i) begin
      state_q       <= '0;
      replace_ptr_q <= '0;
    end else begin
      replace_ptr_q <= replace_ptr_q;
      if (fill_valid_i) begin
        state_q[replace_ptr_q] <= PF_ENTRY_VALID;
        addr_q[replace_ptr_q]  <= fill_addr_i;
        size_q[replace_ptr_q]  <= fill_size_i;
        data_q[replace_ptr_q]  <= fill_data_i;
        replace_ptr_q          <= replace_ptr_d;
      end
    end
  end

endmodule : pf_data_buffer
