// Description:
// Address tracking FIFO (Sec. 5.3.5 of the prefetcher design). AXI's R
// channel never echoes back the request address, so this remembers
// {addr, size} for every outstanding predictive AR, in issue order, until
// its R beat arrives and needs to know what it was fetching.
//
// Pure FIFO semantics only: pop order must equal push order. *When* to
// push or pop is the caller's job (throttle on the push side, the R router
// on the pop side) and is deliberately not this module's concern -- keeping
// the two separate means a bug in "is this a real pop opportunity" can
// never be confused with a bug in "did the FIFO preserve order."

module pf_addr_fifo #(
    parameter int  unsigned Depth  = 4,
    parameter type          addr_t = logic,
    parameter type          size_t = logic
  ) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,

    input  logic  push_valid_i,
    input  addr_t push_addr_i,
    input  size_t push_size_i,
    output logic  full_o,

    input  logic  pop_i,
    output addr_t pop_addr_o,
    output size_t pop_size_o,
    output logic  empty_o
  );

  typedef struct packed {
    addr_t addr;
    size_t size;
  } entry_t;

  entry_t push_data, pop_data;
  assign push_data = entry_t'{addr: push_addr_i, size: push_size_i};

  fifo_v3 #(
    .DEPTH(Depth),
    .dtype(entry_t)
  ) i_fifo (
    .clk_i     (clk_i       ),
    .rst_ni    (rst_ni      ),
    .flush_i   (flush_i     ),
    .testmode_i(1'b0        ),
    .data_i    (push_data   ),
    .push_i    (push_valid_i),
    .full_o    (full_o      ),
    .data_o    (pop_data    ),
    .pop_i     (pop_i       ),
    .empty_o   (empty_o     ),
    .usage_o   (/* unused */)
  );

  assign pop_addr_o = pop_data.addr;
  assign pop_size_o = pop_data.size;

endmodule : pf_addr_fifo
