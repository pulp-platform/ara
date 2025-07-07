# `masku` — Ara's mask unit, for mask bits dispatch, mask operations, bits handling

## Overview

The Mask Unit (`mask_unit`) and `masku_operands` modules are key components in the Ara vector processor, dedicated to handling RISC-V vector mask instructions. They collectively manage operand preparation, control and sequencing of mask-specific functional units (FUs), and result composition for conditional operations.

---

## Module: `mask_unit`

### Purpose

The `mask_unit` acts as a specialized vector execution unit for handling mask instructions. It coordinates operand preparation, functional unit selection, execution control, and sequencing. It is responsible for:
- Interfacing with the global functional unit request and response buses
- Synchronizing execution based on `vstart`, `vl`, and `vm`
- Handling compressed and uncompressed mask representations

---

### Key Interface Signals

| Signal | Direction | Description |
|--------|-----------|-------------|
| `fu_req_i` / `fu_resp_o` | Input/Output | Generic functional unit interface used across Ara |
| `mask_req_o` / `mask_resp_i` | Output/Input | Internal point-to-point interface between mask unit and back-end |
| `masku_operands_i` | Input | Composite of {{mask, vd, ALU result, FPU result}} per lane |
| `bit_enable_mask_o` | Output | Final per-bit mask after `vm` and mask logic |
| `alu_result_compressed_seq_o` | Output | Per-lane ALU results compressed to 1-bit per element for mask construction |

---

### Key Internal Logic and Structure

#### 1. **Operand Handling (via `masku_operands`)**

The submodule `masku_operands` takes inputs from multiple sources, extracts and deshuffles data from the lanes, and prepares it for mask instruction processing. The unpacked operands include:
- **ALU/FPU results:** used to build comparison masks
- **Mask Register (v0.m):** used for `vm=0` operations or as a source for special instructions like `vmsbc`
- **Destination Register (vd):** included to support tail undisturbed/agnostic policy

#### 2. **Shuffling and De-shuffling**

All inputs from lanes arrive in "shuffled" format (i.e., interleaved across lanes). These are deshuffled into linear vectors using the `deshuffle_index()` function depending on:
- Vector element width (EEW)
- Operand type (source, mask, etc.)

The reverse happens for outgoing data, especially for constructing results such as:
- `bit_enable_mask_o`
- `alu_result_compressed_seq_o`

#### 3. **Functional Unit Arbitration**

The mask unit selects the relevant result from the functional units (ALU or FPU), using the `masku_fu_i` signal. A dynamic multiplexer is created to forward the right result stream to the processing pipeline.

#### 4. **Tail and Mask Handling**

The output mask construction is modified based on:
- `vm` flag: if disabled, `v0.m` is used to mask off elements
- `vl`: vector length to restrict valid lanes
- `vtype.vsew` vs. `eew`: to determine stride and alignment

#### 5. **Spill Registers**

To tolerate back-pressure from consuming stages (e.g., the mask functional unit or output logic), spill registers decouple lane input valid/ready from downstream ready signals.

---

## Module: `masku_operands`

### Purpose

This module prepares operands for mask instructions by:
- Unpacking incoming composite operand vectors per lane
- De-shuffling them into sequential formats
- Constructing masks that control lane execution
- Compressing ALU/FPU results into 1-bit-per-element output for Boolean ops

---

### Operand Extraction

Input:
`masku_operands_i[lane][{mask, vd, alu, fpu}]`

Each lane provides:
- `mask (v0.m)` in index 0
- `vd` in index 1
- ALU and FPU results in indices 2+

The `masku_fu_i` decides which result to select (ALU or FPU) dynamically per instruction.

---

### Output Data Formats

The module produces both:
- **Shuffled (lane-local) outputs**: suitable for vector-wide operation
- **Sequential (deshuffled) outputs**: for scalarized control and masking

Both `vd`, `mask`, and selected result are handled this way, with:
- `*_o` – per-lane outputs
- `*_seq_o` – sequential, deshuffled formats
- `*_compressed_seq_o` – compressed ALU result for Boolean ops

---

### Bit Enable Mask Logic

The `bit_enable_mask_o` signal is key for determining per-element enablement:
- Starts from a pure `vl` bitmask (optional via `VlBitMaskEnable`)
- Combined with mask register `v0` (unless `vm=1`)
- Element-size-aligned using `shuffle_index()` for precise control

Instructions like `vmsbc`, `vmadc` bypass this logic and use `v0` as a true source, not a mask.

---

### ALU/FPU Result Compression

The ALU or FPU result is compressed into a Boolean vector:
- For every element, MSB of its result is selected
- Stored in `alu_result_compressed_seq_o` using logic:
`alu_result_compressed_seq_o[bit_index] = masku_operand_alu_o[lane][bit_offset];`

This compression is needed for e.g., `vmsgt`, `vmfeq`.

---