// Description:
// Shared types for Ara's vector prefetcher (hardware/src/vlsu/pf_*.sv).

package pf_pkg;

  // State of one pf_data_buffer entry. Deliberately two-valued, not three:
  // an entry is only ever created when its R data actually lands, never
  // pre-allocated the moment a predictive AR is issued. There is no
  // window where an address is "known to be in flight but not yet
  // valid" as far as the data buffer is concerned -- a query during that
  // window simply reports EMPTY, which is indistinguishable from "never
  // requested" and is handled by the existing miss path with no extra
  // branch. Counting how many predictive ARs are currently outstanding
  // (for throttling) is a separate, address-agnostic concern that lives
  // in its own counter, not in this state machine -- see pf_predictor.sv.
  typedef enum logic {
    PF_ENTRY_EMPTY,
    PF_ENTRY_VALID
  } pf_entry_state_e;

endpackage : pf_pkg
