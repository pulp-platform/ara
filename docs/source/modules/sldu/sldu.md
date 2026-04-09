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

The slide unit's datapath can only handle power-of-two strides. Every non-power-of-two stride is broken down into power-of-two strides. This ensures a lightweight interconnect datapath in the slide unit while accelerating the common case. Non-power-of-2 slides are extremely rare.

The slide unit can also reshuffle, i.e., perform a slide-by-zero with different input and output data widths. This is used to change the byte layout of a vector register file.

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
- To have a simpler datapath, it cannot slide and reshuffle in the same cycle

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

## Zvkned AES Support

When `Zvkned(CryptoSupport)` is enabled, the SLDU serves as the cross-lane permutation engine for AES instructions. It performs **Phase 2** of the 3-phase ALU-SLDU-ALU pipeline used by AES round and key schedule instructions.

### Role in the AES Pipeline

The SLDU receives intermediate results from the VALU (after SubBytes), performs a cross-column permutation, and returns the result to the VALU (for MixColumns + AddRoundKey). This reuses the existing SLDU datapath and avoids dedicated AES shuffle hardware.

### AES ShiftRows / InvShiftRows

For AES round instructions, the SLDU performs the ShiftRows (encrypt) or InvShiftRows (decrypt) byte permutation across the 4 columns of each 128-bit AES element group.

Each 32-bit AES column is laid out as `[7:0]=row0, [15:8]=row1, [23:16]=row2, [31:24]=row3`. The permutation operates per-element-group (4 columns), selecting source bytes from neighboring columns:

**ShiftRows** (for `vaesem`, `vaesef`):
- Row 0: stays in place
- Row 1: sourced from column `(c+1) % 4`
- Row 2: sourced from column `(c+2) % 4`
- Row 3: sourced from column `(c+3) % 4`

**InvShiftRows** (for `vaesdm`, `vaesdf`):
- Row 0: stays in place
- Row 1: sourced from column `(c+3) % 4`
- Row 2: sourced from column `(c+2) % 4`
- Row 3: sourced from column `(c+1) % 4`

The permutation is computed combinationally using column indices derived from `NrLanes` and `AesColsPerLane` (= DataWidth / 32).

### AES Key Schedule Prefix-XOR

For key schedule instructions (`vaeskf1`, `vaeskf2`), the SLDU performs a prefix-XOR chain across the 4 columns of each element group:

```
Input from VALU Phase 0:  [w0, w1, w2, temp]
  where temp = SubWord(RotWord(w3)) ^ Rcon

XOR chain:
  nw0 = w0 ^ temp
  nw1 = w1 ^ nw0
  nw2 = w2 ^ nw1

Output to VALU Phase 1:   [nw0, nw1, nw2, nw2]
```

The `nw2` value is placed in both column 2 and column 3 positions, so that the VALU can compute `nw3 = old_w3 ^ nw2` in Phase 3.

### Active Lane Masking

When `VL` is smaller than one full beat (fewer than `2 * NrLanes` columns), the SLDU computes an active lane mask to avoid marking inactive lanes as valid — which would cause a deadlock since no VALU would be waiting to grant on those lanes.

### Parameterization

Key AES parameters in the SLDU:
- `AesColsPerLane = DataWidth / 32` — AES columns per 64-bit lane (typically 2)
- `AesColsPerGroup = 4` — columns per 128-bit AES element group
- `AesGroupsPerBeat = (NrLanes * AesColsPerLane) / AesColsPerGroup` — element groups processed per beat
