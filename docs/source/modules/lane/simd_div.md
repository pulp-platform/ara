# `simd_div` — Ara's in-lane SIMD divider

## Overview

The `simd_div` module implements Ara’s **Serial Divider**, designed to execute **vector division and remainder operations** element-by-element. The unit supports signed and unsigned divisions for different vector element widths (8, 16, 32, 64 bits) but operates **serially** — processing one element at a time using a backend divider (`serdiv`). Its serial nature restricts intra-vector parallelism but simplifies design complexity and area.

This module is parameterized with CVA6 configuration settings and is tailored for use within Ara’s scalar/vector datapath execution pipeline.

---

## Interface Description

| Port         | Width                   | Direction | Description |
|--------------|-------------------------|-----------|-------------|
| `clk_i`      | 1                       | input     | Clock signal |
| `rst_ni`     | 1                       | input     | Active-low synchronous reset |
| `operand_a_i`| `elen_t`                | input     | Dividend operand vector element |
| `operand_b_i`| `elen_t`                | input     | Divisor operand vector element |
| `mask_i`     | `strb_t`                | input     | Mask bits for each byte |
| `op_i`       | `ara_op_e`              | input     | Operation type: VDIV, VREM, VDIVU, VREMU |
| `be_i`       | `strb_t`                | input     | Byte-enable per vector element |
| `vew_i`      | `vew_e`                 | input     | Vector element width (VEW): EW8, EW16, etc. |
| `result_o`   | `elen_t`                | output    | Final division result vector element |
| `mask_o`     | `strb_t`                | output    | Output mask signal |
| `valid_i`    | 1                       | input     | New valid input transaction |
| `ready_o`    | 1                       | output    | Module ready to accept input |
| `ready_i`    | 1                       | input     | Downstream ready for result |
| `valid_o`    | 1                       | output    | Output is valid |

---

## Module Structure and Key Components

### FSMs: Issue and Commit Control Units

- **`issue_state_q/d` (FSM):**
  - Accepts operands from upstream.
  - Tracks issued bytes.
  - Serially sends one operand pair to the divider.

- **`commit_state_q/d` (FSM):**
  - Collects results from the divider.
  - Buffers and shifts them into output.
  - Drives `valid_o` when the entire result is ready.

### Operands and Control Buffers

- Input operands `opa_q`, `opb_q` and their staging versions `opa_d`, `opb_d`.
- Opcode and vector element width held in `op_q`, `vew_q`.

### Counters

- `issue_cnt_q/d`: How many elements still to be issued.
- `commit_cnt_q/d`: How many results still to be committed.
- Both counters decrement as each element is processed or skipped (masked off).

### Divider Core

- Uses the `serdiv` instance, a serial divider supporting signed/unsigned division and remainder.

- **Supported Opcodes:**
  - `VDIV` – signed division
  - `VDIVU` – unsigned division
  - `VREM` – signed remainder
  - `VREMU` – unsigned remainder

### Operand Width Handling

Each element width (VEW) has a specialized operand unpacking logic:

- **EW8**: 8-bit → Sign-extended to 64-bit.
- **EW16**: 16-bit → Sign-extended to 64-bit.
- **EW32**: 32-bit → Sign-extended to 64-bit.
- **EW64**: Already native 64-bit.

These are extracted from the operand unions and sign-extended (for signed ops).

### Output Construction

- Partial results are shifted into the final `result_q`.
- Results are masked and merged based on the current element width and byte enables.

---

## Timing and Pipeline

- **Fully serialized pipeline.**
- Accepts new input **only** when the previous result is fully committed.
- Maintains FSM state and stable operand/context throughout.

---

## Summary

The `simd_div` module performs element-wise division operations using a serial pipeline. It supports dynamic masking, multiple VEWs, and signed/unsigned operation types. Internally, it uses compact FSMs to serialize operand issue and result collection, reducing area at the cost of throughput.
