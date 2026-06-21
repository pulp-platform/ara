// Description:
// Reorder buffer + real-path handler (Sec. 5.4 of the prefetcher design).
// One slot tracks one outstanding AR (up to 256 AXI beats for a real miss,
// always exactly 1 beat for a hit), not one beat: the predictor reasons
// about where the *next instruction* starts, so the unit of in-order
// release is "one issued AR", and beat ordering within a real burst is
// already guaranteed by AXI itself.
//
// Phase 2b: data buffer lookups can now hit, keyed on {addr, size} (not
// addr alone -- see pf_data_buffer.sv). A hit is only ever recognized for
// a single-beat (len=0) incoming AR -- a multi-beat unit-stride burst
// always takes the miss path even if its first beat's address+size match
// a cached entry, since the buffer only ever caches one beat per entry.
// On a hit, the slot is filled immediately from the buffer and never
// touches the real AR/R channel at all, which is exactly when a pending
// predictive AR (id=1, arbitrated below) gets to use the freed AR_OUT
// cycle. The real path keeps absolute priority over predictive traffic
// for the shared AR_OUT channel.

module pf_rob import pf_pkg::*; #(
    parameter int  unsigned Depth    = 4,
    parameter type          axi_ar_t = logic,
    parameter type          axi_r_t  = logic,
    parameter type          addr_t   = logic,
    parameter type          size_t   = logic,
    // Dependent parameters. DO NOT CHANGE!
    localparam int unsigned MaxBeats     = 256,
    localparam int unsigned BeatCntWidth = $clog2(MaxBeats + 1),
    localparam int unsigned IdxWidth     = (Depth > 1) ? $clog2(Depth) : 1,
    localparam int unsigned CountWidth   = $clog2(Depth + 1)
  ) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,

    // AR: from addrgen (the real, in-order request stream)
    input  axi_ar_t axi_ar_i,
    input  logic    axi_ar_valid_i,
    output logic    axi_ar_ready_o,

    // AR: predictive (id=1, always single-beat), arbitrated against the
    // real stream below for the one physical AR_OUT channel. Always loses
    // ties; held by the caller (a 1-deep skid register in pf_predictor's
    // caller) until granted. pred_addr_fifo_full_i additionally withholds
    // the grant when the caller's pending-address tracker (AXI's R channel
    // does not echo back the request address, so something has to
    // remember it) has no room left to record this AR's address.
    input  axi_ar_t pred_ar_i,
    input  logic    pred_ar_valid_i,
    output logic    pred_ar_ready_o,
    output logic    pred_ar_fire_o,
    input  logic    pred_addr_fifo_full_i,

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

    // Lookup into the data buffer, queried for every incoming real AR.
    output logic            lookup_valid_o,
    output addr_t           lookup_addr_o,
    output size_t           lookup_size_o,
    input  pf_entry_state_e lookup_state_i,
    input  axi_r_t           lookup_data_i
  );

  // One slot per outstanding AR. beats_left counts AXI beats still owed;
  // is_hit marks a slot whose data came from the buffer (always 1 beat,
  // stored in hit_data, never touches the real R channel on release).
  logic [Depth-1:0][BeatCntWidth-1:0] beats_left_d, beats_left_q;
  logic [Depth-1:0]                   slot_valid_d, slot_valid_q;
  logic [Depth-1:0]                   is_hit_d, is_hit_q;
  axi_r_t [Depth-1:0]                 hit_data_d, hit_data_q;

  logic [IdxWidth-1:0]   alloc_ptr_d, alloc_ptr_q;
  logic [IdxWidth-1:0]   head_ptr_d, head_ptr_q;
  logic [CountWidth-1:0] count_d, count_q;

  localparam logic [BeatCntWidth-1:0] OneBeat = BeatCntWidth'(1);

  logic rob_full;
  assign rob_full = (count_q == Depth);

  assign lookup_valid_o = axi_ar_valid_i;
  assign lookup_addr_o  = addr_t'(axi_ar_i.addr);
  assign lookup_size_o  = size_t'(axi_ar_i.size);

  // A hit is only recognized for a single-beat request: the buffer caches
  // one beat per entry, so a multi-beat burst's first-beat match cannot
  // satisfy the whole burst and is deliberately left as a miss.
  logic is_hit;
  assign is_hit = (axi_ar_i.len == '0) && (lookup_state_i == PF_ENTRY_VALID);

  // A hit consumes zero AR_OUT bandwidth -- only a miss actually needs the
  // real channel, which is exactly when predictive traffic must yield.
  logic real_ar_wants_out;
  assign real_ar_wants_out = axi_ar_valid_i && !is_hit;

  logic ar_fire, real_ar_fire, pred_ar_fire;
  assign axi_ar_ready_o = !rob_full && (is_hit || axi_ar_ready_i);
  assign ar_fire         = axi_ar_valid_i && axi_ar_ready_o;
  assign real_ar_fire    = real_ar_wants_out && axi_ar_ready_o;

  assign pred_ar_ready_o = !real_ar_wants_out && axi_ar_ready_i && !pred_addr_fifo_full_i;
  assign pred_ar_fire    = pred_ar_valid_i && pred_ar_ready_o;
  assign pred_ar_fire_o  = pred_ar_fire;

  assign axi_ar_o       = real_ar_fire ? axi_ar_i : pred_ar_i;
  assign axi_ar_valid_o = real_ar_fire || pred_ar_fire;

  // The arriving real R beat always belongs to the oldest outstanding miss
  // slot: AXI returns same-id responses in issue order, and every miss is
  // forwarded with id=0. A hit slot at the head needs no live R beat at
  // all -- it releases straight from its stored data.
  logic head_is_hit, head_is_miss_waiting;
  assign head_is_hit          = slot_valid_q[head_ptr_q] && is_hit_q[head_ptr_q];
  assign head_is_miss_waiting = slot_valid_q[head_ptr_q] && !is_hit_q[head_ptr_q];

  logic real_r_fire, hit_r_fire, r_fire, r_last_beat;
  assign axi_r_ready_o = axi_r_ready_i && head_is_miss_waiting;
  assign real_r_fire    = axi_r_valid_i && axi_r_ready_o;
  assign hit_r_fire     = head_is_hit && axi_r_ready_i;
  assign r_fire          = real_r_fire || hit_r_fire;
  assign r_last_beat    = head_is_hit
                            || (head_is_miss_waiting && (beats_left_q[head_ptr_q] == OneBeat));

  assign axi_r_valid_o = head_is_hit || (axi_r_valid_i && head_is_miss_waiting);
  assign axi_r_o       = head_is_hit ? hit_data_q[head_ptr_q] : axi_r_i;

  always_comb begin
    beats_left_d = beats_left_q;
    slot_valid_d = slot_valid_q;
    is_hit_d     = is_hit_q;
    hit_data_d   = hit_data_q;
    alloc_ptr_d  = alloc_ptr_q;
    head_ptr_d   = head_ptr_q;
    count_d      = count_q;

    if (ar_fire) begin
      slot_valid_d[alloc_ptr_q] = 1'b1;
      is_hit_d[alloc_ptr_q]     = is_hit;
      if (is_hit) begin
        hit_data_d[alloc_ptr_q]   = lookup_data_i;
        beats_left_d[alloc_ptr_q] = OneBeat;
      end else begin
        beats_left_d[alloc_ptr_q] = {1'b0, axi_ar_i.len} + OneBeat;
      end
      alloc_ptr_d = (alloc_ptr_q == IdxWidth'(Depth - 1)) ? '0 : alloc_ptr_q + 1;
    end

    if (r_fire) begin
      if (r_last_beat) begin
        slot_valid_d[head_ptr_q] = 1'b0;
        head_ptr_d               = (head_ptr_q == IdxWidth'(Depth - 1)) ? '0 : head_ptr_q + 1;
      end else begin
        beats_left_d[head_ptr_q] = beats_left_q[head_ptr_q] - OneBeat;
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
      is_hit_q     <= '0;
      hit_data_q   <= '0;
      alloc_ptr_q  <= '0;
      head_ptr_q   <= '0;
      count_q      <= '0;
    end else if (flush_i) begin
      beats_left_q <= '0;
      slot_valid_q <= '0;
      is_hit_q     <= '0;
      hit_data_q   <= '0;
      alloc_ptr_q  <= '0;
      head_ptr_q   <= '0;
      count_q      <= '0;
    end else begin
      beats_left_q <= beats_left_d;
      slot_valid_q <= slot_valid_d;
      is_hit_q     <= is_hit_d;
      hit_data_q   <= hit_data_d;
      alloc_ptr_q  <= alloc_ptr_d;
      head_ptr_q   <= head_ptr_d;
      count_q      <= count_d;
    end
  end

endmodule : pf_rob
