`define ARA_PROBE(signal, name)                      \
generate begin                                       \
  integer cycle_cnt;                                 \
  integer activity_cnt;                              \
                                                     \
  always_ff @(posedge clk_i or negedge rst_ni) begin \
    if (~rst_ni) begin                               \
      cycle_cnt    = 0;                              \
      activity_cnt = 0;                              \
    end else begin                                   \
      cycle_cnt = cycle_cnt + 1;                     \
      if (signal)                                    \
        activity_cnt = activity_cnt + 1;             \
                                                     \
      if (cycle_cnt == 8) begin                      \
        $display("[%s] %d", name, activity_cnt);     \
        cycle_cnt    = 0;                            \
        activity_cnt = 0;                            \
      end                                            \
    end                                              \
  end                                                \
end endgenerate
