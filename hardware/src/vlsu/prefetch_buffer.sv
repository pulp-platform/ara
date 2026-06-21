// Description:
// Sits on Ara's AR/R load path, between the address generator and the AXI
// cut. Pure module-to-module wiring, no decision logic of its own (Sec.
// "文件拆分" of the prefetcher design) -- the actual behavior lives in
// pf_classifier.sv, pf_predictor.sv, pf_addr_fifo.sv, pf_rob.sv,
// pf_r_router.sv and pf_data_buffer.sv.
//
// Phase 2b: classifier + predictor fire unconditionally (no confidence FSM
// yet) for every VLE/VLSE instruction observed on pe_req_i, which is wired
// in separately from (not derived from) the AR/R traffic below -- stride/
// EEW/vl live only in the instruction, never on the AXI channels. A hit is
// only ever recognized for a single-beat (len=0) request whose {addr,
// size} both match a cached entry, since the buffer caches one beat per
// entry. A predictive (id=1) completion is only cached if its r_resp is
// RESP_OKAY.

module prefetch_buffer import pf_pkg::*; import axi_pkg::*; #(
    parameter int  unsigned AxiAddrWidth = 0,
    parameter int  unsigned AxiDataWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_r_t      = logic,
    parameter type          pe_req_t     = logic,
    parameter type          stride_t     = logic,
    parameter type          size_t       = logic,
    parameter type          id_t         = logic,
    // ROB depth: number of real ARs (hit or miss) that may be outstanding
    // at once. Matches VaddrgenInsnQueueDepth (ara_pkg.sv) so this stage
    // does not reduce Ara's existing outstanding-request capacity.
    parameter int  unsigned RobDepth          = 4,
    // Data buffer entry count (Sec. 5.6: "4-8 entries").
    parameter int  unsigned DataBufDepth      = 4,
    // Depth of the side FIFO tracking addresses of outstanding predictive
    // ARs -- AXI's R channel never echoes back the request address.
    parameter int  unsigned PredAddrFifoDepth = 4,
    // Dependent parameters. DO NOT CHANGE!
    localparam type         addr_t       = logic [AxiAddrWidth-1:0]
  ) (
    input  logic    clk_i,
    input  logic    rst_ni,

    // Instruction stream, observed in parallel with the AR/R traffic below
    // (not derived from it -- see header comment).
    input  pe_req_t pe_req_i,
    input  logic    pe_req_valid_i,

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

  logic flush;
  assign flush = 1'b0; // Phase 4 adds mispredict flush; nothing drives it yet.

  // ---------------------------------------------------------------------
  // 5.1 / 5.2: classify + predict the next instruction's base address.
  // size_o/predicted_size_o are forwarded end-to-end, never re-derived.
  // ---------------------------------------------------------------------
  logic    prefetchable;
  stride_t byte_stride;
  size_t   classified_size;

  pf_classifier #(
    .pe_req_t(pe_req_t),
    .stride_t(stride_t),
    .size_t  (size_t  )
  ) i_pf_classifier (
    .pe_req_i      (pe_req_i       ),
    .prefetchable_o(prefetchable   ),
    .byte_stride_o (byte_stride    ),
    .size_o        (classified_size)
  );

  logic  predict_valid, predict_ready;
  addr_t predicted_addr;
  size_t predicted_size;

  pf_predictor #(
    .pe_req_t(pe_req_t),
    .stride_t(stride_t),
    .addr_t  (addr_t  ),
    .size_t  (size_t  ),
    .id_t    (id_t    )
  ) i_pf_predictor (
    .clk_i           (clk_i          ),
    .rst_ni          (rst_ni         ),
    .pe_req_i        (pe_req_i       ),
    .pe_req_valid_i  (pe_req_valid_i ),
    .prefetchable_i  (prefetchable   ),
    .byte_stride_i   (byte_stride    ),
    .size_i          (classified_size),
    .predict_valid_o (predict_valid  ),
    .predict_ready_i (predict_ready  ),
    .predicted_addr_o(predicted_addr ),
    .predicted_size_o(predicted_size )
  );

  // Package the predicted address into a real, single-beat AXI AR with
  // id=1. size comes from the predictor's forwarded classification, not a
  // fresh read of pe_req_i -- this module has no business knowing the
  // instruction's internal field layout twice.
  axi_ar_t pred_ar;
  assign pred_ar = '{
    id     : 1,
    addr   : predicted_addr,
    len    : '0,
    size   : predicted_size,
    cache  : CACHE_MODIFIABLE,
    burst  : BURST_INCR,
    default: '0
  };

  // ---------------------------------------------------------------------
  // Pending-predictive-address tracker (see header comment).
  // ---------------------------------------------------------------------
  logic  pred_addr_fifo_push, pred_addr_fifo_pop;
  logic  pred_addr_fifo_full;
  addr_t pred_addr_fifo_addr_out;
  size_t pred_addr_fifo_size_out;

  pf_addr_fifo #(
    .Depth (PredAddrFifoDepth),
    .addr_t(addr_t           ),
    .size_t(size_t           )
  ) i_pred_addr_fifo (
    .clk_i       (clk_i                  ),
    .rst_ni      (rst_ni                 ),
    .flush_i     (flush                  ),
    .push_valid_i(pred_addr_fifo_push    ),
    .push_addr_i (predicted_addr         ),
    .push_size_i (predicted_size         ),
    .full_o      (pred_addr_fifo_full    ),
    .pop_i       (pred_addr_fifo_pop     ),
    .pop_addr_o  (pred_addr_fifo_addr_out),
    .pop_size_o  (pred_addr_fifo_size_out),
    .empty_o     (/* unused */          )
  );

  // ---------------------------------------------------------------------
  // 5.4: ROB + real-path handler. Arbitrates real vs. predictive AR for
  // the one physical AR_OUT channel (real always wins); releases to vldu
  // strictly in the order real ARs were issued, regardless of whether
  // each one was satisfied by a buffer hit or a real fetch.
  // ---------------------------------------------------------------------
  logic            lookup_valid;
  addr_t           lookup_addr;
  size_t           lookup_size;
  pf_entry_state_e lookup_state;
  axi_r_t          lookup_data;

  axi_r_t real_r;
  logic   real_r_valid, real_r_ready;

  pf_rob #(
    .Depth   (RobDepth),
    .axi_ar_t(axi_ar_t),
    .axi_r_t (axi_r_t ),
    .addr_t  (addr_t  ),
    .size_t  (size_t  )
  ) i_pf_rob (
    .clk_i                (clk_i              ),
    .rst_ni               (rst_ni             ),
    .flush_i              (flush              ),
    .axi_ar_i             (axi_ar_i           ),
    .axi_ar_valid_i       (axi_ar_valid_i     ),
    .axi_ar_ready_o       (axi_ar_ready_o     ),
    .pred_ar_i            (pred_ar            ),
    .pred_ar_valid_i      (predict_valid      ),
    .pred_ar_ready_o      (predict_ready      ),
    .pred_ar_fire_o       (pred_addr_fifo_push),
    .pred_addr_fifo_full_i(pred_addr_fifo_full),
    .axi_ar_o             (axi_ar_o           ),
    .axi_ar_valid_o       (axi_ar_valid_o     ),
    .axi_ar_ready_i       (axi_ar_ready_i     ),
    .axi_r_i              (real_r             ),
    .axi_r_valid_i        (real_r_valid       ),
    .axi_r_ready_o        (real_r_ready       ),
    .axi_r_o              (axi_r_o            ),
    .axi_r_valid_o        (axi_r_valid_o      ),
    .axi_r_ready_i        (axi_r_ready_i      ),
    .lookup_valid_o       (lookup_valid       ),
    .lookup_addr_o        (lookup_addr        ),
    .lookup_size_o        (lookup_size        ),
    .lookup_state_i       (lookup_state       ),
    .lookup_data_i        (lookup_data        )
  );

  // ---------------------------------------------------------------------
  // 5.5: split the one physical R channel by id; gate the fill on resp.
  // ---------------------------------------------------------------------
  logic  fill_valid;
  addr_t fill_addr;
  size_t fill_size;
  axi_r_t fill_data;

  pf_r_router #(
    .axi_r_t(axi_r_t),
    .addr_t (addr_t ),
    .size_t (size_t )
  ) i_pf_r_router (
    .r_i                  (axi_r_i                ),
    .r_valid_i            (axi_r_valid_i          ),
    .r_ready_o            (axi_r_ready_o          ),
    .real_r_o             (real_r                 ),
    .real_r_valid_o       (real_r_valid           ),
    .real_r_ready_i       (real_r_ready           ),
    .pred_addr_fifo_pop_o (pred_addr_fifo_pop     ),
    .pred_addr_fifo_addr_i(pred_addr_fifo_addr_out),
    .pred_addr_fifo_size_i(pred_addr_fifo_size_out),
    .fill_valid_o         (fill_valid             ),
    .fill_addr_o          (fill_addr              ),
    .fill_size_o          (fill_size              ),
    .fill_data_o          (fill_data              )
  );

  // ---------------------------------------------------------------------
  // 5.6: data buffer. alloc_* (Phase 3, IN_FLIGHT) is still unconnected.
  // ---------------------------------------------------------------------
  pf_data_buffer #(
    .Depth (DataBufDepth),
    .addr_t(addr_t      ),
    .size_t(size_t      ),
    .data_t(axi_r_t     )
  ) i_pf_data_buffer (
    .clk_i         (clk_i       ),
    .rst_ni        (rst_ni      ),
    .flush_i       (flush       ),
    .lookup_valid_i(lookup_valid),
    .lookup_addr_i (lookup_addr ),
    .lookup_size_i (lookup_size ),
    .lookup_state_o(lookup_state),
    .lookup_data_o (lookup_data ),
    .alloc_valid_i (1'b0        ),
    .alloc_addr_i  ('0          ),
    .alloc_size_i  ('0          ),
    .fill_valid_i  (fill_valid  ),
    .fill_addr_i   (fill_addr   ),
    .fill_size_i   (fill_size   ),
    .fill_data_i   (fill_data   )
  );

endmodule : prefetch_buffer
