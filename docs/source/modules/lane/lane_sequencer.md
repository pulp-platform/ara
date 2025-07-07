# `lane_sequencer` — Set up the in-lane operations

## Overview

The `lane_sequencer` module in Ara coordinates the execution of vector instructions within an individual lane. It acts as a local micro-sequencer for a single lane, interpreting commands from the main sequencer, dispatching operand requests, managing operand queues, and issuing operations to local functional units such as ALU, MFPU, and Mask Unit.

This document breaks down the functionality into sections, each focusing on a specific group of responsibilities or sub-components of the module.

---

## Parameters

- **`NrLanes`**: Number of lanes in the vector unit.
- **`pe_req_t`, `pe_resp_t`**: Packed types for communication with the main sequencer.
- **`operand_request_cmd_t`**: Structure for operand requests.
- **`vfu_operation_t`**: Packed structure for vector functional unit operation control.

---

## 1. Main Sequencer Interface

The interface with the main sequencer involves:
- Handshake mechanism (`pe_req_valid_i`, `pe_req_ready_o`)
- A mechanism to avoid re-sampling an already seen instruction using a combination of:
  - `last_id_q`
  - `en_sync_mask_q`

### Key Functionality
- Instruction ID tracking to prevent double-sampling
- Register-based handshake with `fall_through_register` instance
- Conditional request masking based on synchronization and instruction validity

---

## 2. Operand Request Queues

Each lane manages several operand request queues, which are not simple FIFOs due to the need for:
- Hazard tracking
- Fine-grained operand reuse or bypassing

### Mechanism
- A set of `operand_request` and `operand_request_valid` signals per operand queue
- Update logic that resets, flushes, or pushes requests as needed

### Notable Logic
- Upon memory exceptions (`lsu_ex_flush_o`), select queues are flushed.

---

## 3. VRGATHER FSM (Finite State Machine)

Manages VRGATHER/VCOMPRESS operand scheduling using:
- `spill_register` for buffering incoming `vrgat_req_t` transactions
- FSM with two states: `IDLE` and `REQUESTING`
- Counter `vrgat_cmd_req_cnt_q` to track the number of outstanding requests

### Coordination
Ensures `MaskB` operand queue isn't double-booked, and only services requests when not full.

---

## 4. Operand Request Dispatch Logic

A massive combinational block prepares operand requests depending on the current operation. Vector instructions are categorized by their VFU:
- **ALU operations**
- **Floating point via MFPU**
- **Load/Store**
- **Slide operations**
- **Mask logic or comparisons**
- **Special (non-standard) requests**

Each VFU type causes specific requests to be sent to matching operand queues with:
- Proper vector element width (`eew`)
- Vector length (`vl`)
- Start index (`vstart`)
- Hazard flags

This block also defines how VL is distributed across lanes and balances load when VL is not divisible by lane count.

---

## 5. VFUs Operation Dispatch

Issues operations to the appropriate VFU (ALU, MFPU, Mask Unit) using `vfu_operation_o` and `vfu_operation_valid_o`.

### Highlights
- Determines correct VFU based on instruction type
- Ensures operations are balanced per-lane
- Prevents spurious instructions by validating VL and vector enable masks

---

## 6. Instruction Bookkeeping

Bookkeeping logic tracks which instructions are running (`vinsn_running_q`) and which are completed (`vinsn_done_q`).

### Responsibilities
- Ensures instructions are only started once
- Marks completion using signals from ALU and MFPU
- Notifies the main sequencer via `pe_resp_o.vinsn_done`

---

## 7. Synchronous and Asynchronous State Updates

All state is registered with clock and reset to ensure correct FSM behavior and sequential pipeline consistency.

---

## Conclusion

The `lane_sequencer` is a central piece of the Ara vector processor responsible for:
- Correctly dispatching instruction executions
- Coordinating operand fetching
- Managing control signals between sequencer, operand queues, and VFUs
- Supporting special masking and vector gathering behavior

Its design is highly modular and ready for extension for additional VFUs or operand features.