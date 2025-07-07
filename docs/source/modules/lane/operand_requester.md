
# `operand_requester` Module Documentation

## Overview

The `operand_requester` module orchestrates operand fetches from the Vector Register File (VRF) and delivers them to operand queues. It supports:

- **VRF access arbitration** across multiple operand queues and functional units
- **Hazard tracking** to prevent data hazards between instructions
- **Per-bank grant handling** for load/store, ALU, mask, slide units, etc.
- **VRF write-backs** from functional units
- **Exception flushing** for store-related hazards

---

## Interface Description

### Inputs

- `clk_i`, `rst_ni`: Clock and active-low reset.
- `global_hazard_table_i`: Tracks instruction dependencies across vector instructions.
- `operand_request_i`, `operand_request_valid_i`: Requests from operand queues.
- `lsu_ex_flush_i`: Flush signal for store exceptions.
- `operand_queue_ready_i`: Queue ready status for issued operands.
- Functional unit write-back inputs (`*_result_*_i`): ALU, MFPU, Mask, Slide, Load.

### Outputs

- `operand_request_ready_o`: Ready to accept new requests.
- `lsu_ex_flush_o`: Acknowledge exception flush.
- `vrf_*_o`: Outputs for accessing the VRF (read/write).
- `operand_queue_*_o`: Commands and valid signals for operand queues.
- Functional unit grant outputs (`*_result_*_gnt_o`, `*_result_final_gnt_o`)

---

## Internal Mechanisms

### Stream Registers

For results written back from VLDU, Slide, and Mask units, **stream registers** are used to buffer incoming data and synchronize write-backs. These wrap ID, address, data, and byte-enable.

Each stream register:
- Buffers a result from a VFU
- Issues a valid signal
- Acknowledges with a grant signal

Final grants are issued when data is truly committed to VRF to avoid releasing hazards prematurely.

---

### Hazard Management

- Each operand requester tracks hazards using `requester_metadata_t`.
- Hazards are checked against a global hazard table.
- Stalls are inserted if a dependency is not resolved.

Hazards specifically handled:
- **Write-after-read (WAR)** and **write-after-write (WAW)**
- **Widening operations** (doubling vector width) use toggling counters to synchronize requests.

---

### Operand Fetch State Machine

Each operand requester has a **2-state FSM**:
- `IDLE`: Wait for a new request.
- `REQUESTING`: Issue operand accesses to the VRF.

On receiving a valid request:
- VRF address is computed
- Metadata is initialized
- Commands are sent to the operand queue
- Transition to `REQUESTING`

In `REQUESTING`:
- Stall if hazard unresolved
- Issue bank-aligned requests
- Update address and element counters
- Transition to `IDLE` once all elements are read

---

### Arbitration

Each VRF bank instantiates:

1. **High-Priority Arbiter**:
   - ALU
   - MFPU
   - Mask Unit

2. **Low-Priority Arbiter**:
   - Slide Address Generator
   - Load Unit
   - Store-Related Operand Queues

3. **Top-Level Arbiter**:
   - Selects between high and low priority
   - Drives VRF signals: `vrf_req_o`, `vrf_addr_o`, `vrf_wen_o`, etc.

---

## Exception Flushing

On store-related exceptions (`lsu_ex_flush_i`), operand requests associated with:
- `StA` (Store Address)
- `SlideAddrGenA`
- `MaskM`

are **aborted** immediately. Metadata is reset, and the FSM transitions back to `IDLE`.

---

## Summary

The `operand_requester` is critical in enabling efficient, hazard-free operand distribution to functional units. Its arbitration logic ensures fair and deterministic VRF access, while its hazard control and exception handling mechanisms preserve correctness in concurrent instruction execution.