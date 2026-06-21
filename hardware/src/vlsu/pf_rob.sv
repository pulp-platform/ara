// Description:
// Reorder buffer + real-path handler (Sec. 5.4 of the prefetcher design).
// One slot tracks one outstanding AR burst (up to 256 AXI beats), not one
// beat: the predictor reasons about where the *next instruction* starts, so
// the unit of in-order release is "one issued AR", and beat ordering within
// a burst is already guaranteed by AXI itself.
//
// Phase 1: the data buffer is always empty (Sec. pf_data_buffer.sv), so the
// lookup below never reports a hit -- every AR takes the real (miss) path:
// forwarded downstream unmodified (id=0), and released to vldu strictly in
// the order it was issued. Phase 2+ adds the hit/in-flight branches without
// touching the slot/pointer machinery below.

module pf_rob import pf_pkg::*; #(
    parameter int  unsigned Depth    = 4,
    parameter type          axi_ar_t = logic,
    parameter type          axi_r_t  = logic,
    parameter type          addr_t   = logic,
    parameter type          data_t   = logic,
    // Dependent parameters. DO NOT CHANGE!
    localparam int unsigned MaxBeats     = 256,
    localparam int unsigned BeatCntWidth = $clog2(MaxBeats + 1),
    localparam int unsigned IdxWidth     = (Depth > 1) ? $clog2(Depth) : 1,
    localparam int unsigned CountWidth   = $clog2(Depth + 1)
  ) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,

    // AR: from addrgen
    input  axi_ar_t axi_ar_i,
    input  logic    axi_ar_valid_i,
    output logic    axi_ar_ready_o,

    // AR: to the real memory path
    output axi_ar_t axi_ar_o,
    output logic    axi_ar_valid_o,
    input  logic    axi_ar_ready_i,

    // R: from the real memory path
    input  axi_r_t axi_r_i,
    input  logic   axi_r_valid_i,
    output logic   axi_r_ready_o,

    // R: to vldu, released strictly in the order ARs were issued
    output axi_r_t axi_r_o,
    output logic   axi_r_valid_o,
    input  logic   axi_r_ready_i,

    // Lookup into the data buffer, queried for every incoming AR.
    output logic            lookup_valid_o,
    output addr_t           lookup_addr_o,
    input  pf_entry_state_e lookup_state_i,
    input  data_t            lookup_data_i
  );

  // One slot per outstanding AR burst. beats_left counts AXI beats still
  // owed for that burst; the slot retires when its last beat is consumed.
  logic [Depth-1:0][BeatCntWidth-1:0] beats_left_d, beats_left_q;
  logic [Depth-1:0]                   slot_valid_d, slot_valid_q;

  logic [IdxWidth-1:0]   alloc_ptr_d, alloc_ptr_q;
  logic [IdxWidth-1:0]   head_ptr_d, head_ptr_q;
  logic [CountWidth-1:0] count_d, count_q;

  logic rob_full;
  assign rob_full = (count_q == Depth);

  // Queried for Phase 2+ visibility; Phase 1 never acts on the result
  // (lookup_state_i is always PF_ENTRY_EMPTY).
  assign lookup_valid_o = axi_ar_valid_i;
  assign lookup_addr_o  = addr_t'(axi_ar_i.addr);

  // An AR is only accepted when both the ROB has a free slot and the real
  // path can take it -- either side withholding its ready blocks the other.
  logic ar_fire;
  assign axi_ar_ready_o = !rob_full && axi_ar_ready_i;
  assign axi_ar_valid_o = axi_ar_valid_i && !rob_full;
  assign axi_ar_o       = axi_ar_i;
  assign ar_fire         = axi_ar_valid_i && axi_ar_ready_o;

  // The arriving R beat always belongs to the oldest outstanding slot: AXI
  // returns same-id responses in issue order, and every AR forwarded today
  // carries id=0 (real path only -- Phase 1 has no prefetch traffic).
  logic r_fire, r_last_beat;
  assign r_last_beat   = slot_valid_q[head_ptr_q] && (beats_left_q[head_ptr_q] == BeatCntWidth'(1));
  assign axi_r_ready_o = axi_r_ready_i && slot_valid_q[head_ptr_q];
  assign axi_r_valid_o = axi_r_valid_i && slot_valid_q[head_ptr_q];
  assign axi_r_o       = axi_r_i;
  assign r_fire         = axi_r_valid_i && axi_r_ready_o;

  always_comb begin
    beats_left_d = beats_left_q;
    slot_valid_d = slot_valid_q;
    alloc_ptr_d  = alloc_ptr_q;
    head_ptr_d   = head_ptr_q;
    count_d      = count_q;

    if (ar_fire) begin
      slot_valid_d[alloc_ptr_q] = 1'b1;
      beats_left_d[alloc_ptr_q] = {1'b0, axi_ar_i.len} + BeatCntWidth'(1);
      alloc_ptr_d               = (alloc_ptr_q == IdxWidth'(Depth - 1)) ? '0 : alloc_ptr_q + 1;
    end

    if (r_fire) begin
      if (r_last_beat) begin
        slot_valid_d[head_ptr_q] = 1'b0;
        head_ptr_d               = (head_ptr_q == IdxWidth'(Depth - 1)) ? '0 : head_ptr_q + 1;
      end else begin
        beats_left_d[head_ptr_q] = beats_left_q[head_ptr_q] - BeatCntWidth'(1);
      end
    end

    unique case ({ar_fire, r_fire && r_last_beat})
      2'b10:   count_d = count_q + CountWidth'(1);
      2'b01:   count_d = count_q - CountWidth'(1);
      default: count_d = count_q;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      beats_left_q <= '0;
      slot_valid_q <= '0;
      alloc_ptr_q  <= '0;
      head_ptr_q   <= '0;
      count_q      <= '0;
    end else if (flush_i) begin
      beats_left_q <= '0;
      slot_valid_q <= '0;
      alloc_ptr_q  <= '0;
      head_ptr_q   <= '0;
      count_q      <= '0;
    end else begin
      beats_left_q <= beats_left_d;
      slot_valid_q <= slot_valid_d;
      alloc_ptr_q  <= alloc_ptr_d;
      head_ptr_q   <= head_ptr_d;
      count_q      <= count_d;
    end
  end

endmodule : pf_rob
