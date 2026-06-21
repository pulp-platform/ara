// Description:
// Shared types for Ara's vector prefetcher (hardware/src/vlsu/pf_*.sv).

package pf_pkg;

  // State of one pf_data_buffer entry.
  typedef enum logic [1:0] {
    PF_ENTRY_EMPTY,
    PF_ENTRY_IN_FLIGHT,
    PF_ENTRY_VALID
  } pf_entry_state_e;

endpackage : pf_pkg
