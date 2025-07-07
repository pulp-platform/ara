# `sldu` — Ara's slide unit, for permutations, shuffles, and slides

## Overview

The Slide Unit (`sldu`) in Ara's vector processor is responsible for implementing vector slide instructions as specified in the RISC-V Vector Extension (RVV). These instructions shift elements within vector registers, either left or right, potentially with a configurable stride, and can support varying effective element widths (EEWs). The design is modular and consists of three components:

- `sldu`: The top-level Slide Unit module
- `sldu_op_dp`: The datapath handling element reshuffling and shifting
- `p2_stride_gen`: A utility module that generates power-of-two strides

This unit supports seamless data flow between the operand lanes and result queues, handling valid/ready handshakes and internal reshuffling, aligning with the RVV specification.

---

## 1. `sldu`: Top-Level Slide Unit

### Purpose

The `sldu` module serves as the interface and coordinator for the entire slide operation. It connects the operand input/output ports, manages the slide operation control logic, and integrates the datapath (`sldu_op_dp`) and the stride generator (`p2_stride_gen`).

### Key Interfaces

- **Clock and Reset**
  - `clk_i`, `rst_ni`: Standard synchronous design signals.

- **Operands**
  - `sldu_operand_i [NrLanes-1:0]`: Operand vector from the lanes.
  - `sldu_operand_valid_i`, `sldu_operand_ready_o`: Valid/ready handshake.
  - `sldu_result_o`, `sldu_result_valid_o`, `sldu_result_ready_i`: Slide result vector and handshake signals.

- **Control**
  - `vinsn_issue_i`: Vector instruction information (EEW, SEW, etc.).
  - `stride_valid_i`, `stride_update_i`: Control inputs for stride progression.
  - `stride_i`: Incoming stride value.

- **Utility**
  - `stride_valid_o`: Asserted if the stride value is a power of two.
  - `popcount_o`: Output of 1-bit population count on stride vector.

### Functionality

- Integrates:
  - **Datapath (`sldu_op_dp`)** for reshuffling and sliding
  - **Stride Generator (`p2_stride_gen`)** for power-of-two stride sequence generation

- Responds to stride updates and dynamically loads new strides.

---

## 2. `sldu_op_dp`: Slide Operand Datapath

### Purpose

This module implements the actual sliding logic of the operands, depending on:
- Source and destination EEW (`eew_src_i`, `eew_dst_i`)
- Direction (`dir_i`)
- Slide amount (`slamt_i`)

It operates with flattened vectors (`op_i_flat`, `op_o_flat`) for simplified internal manipulation.

### Operation

- Uses a large `unique case` block over `{eew_src_i, eew_dst_i, slamt_i, dir_i}` to pattern-match operations.
- For each case, byte-wise manipulation (via `+: 8` slices) rearranges bytes between source and destination.
- The result is assigned back to the `op_o_flat` register, which is then returned to the module interface.

### Notable Features

- Handles conversions across EEWs (e.g., EW8 → EW16)
- Cannot slide and reshuffle in the same cycle (limitation noted in the header)

---

## 3. `p2_stride_gen`: Power-of-Two Stride Generator

### Purpose

This utility module generates stride vectors where exactly one bit is high (i.e., a power-of-two stride), and can sequentially generate the next stride on `update_i`.

### Interfaces

- **Input**
  - `stride_i`: A stride vector to load.
  - `valid_i`: Load enable.
  - `update_i`: Trigger to generate the next stride.

- **Output**
  - `stride_p2_o`: Power-of-two stride vector
  - `valid_o`: Indicates if a valid (non-zero) stride is present
  - `popc_o`: Population count of stride bits

### Functionality

- Uses:
  - **`popcount` module** to count active bits in `stride_i`
  - **`lzc` module** to detect the first active bit
- Computes the next stride by XORing the current with the last stride
- Asserts `valid_o` if the stride is valid

---

## Signal Behavior Across Modules

- `vinsn_issue_i` is propagated across modules to control EEW behaviors and operand reshuffling.
- `sldu_op_dp` interprets the sliding direction (`dir_i`) and index (`slamt_i`) to select the output permutation.
- `stride_p2_o` controls which element is selected during a stride-slide.
- All data vectors (`op_i`, `op_o`) are organized as `elen_t [NrLanes-1:0]`, allowing lane-based parallel operation.

---