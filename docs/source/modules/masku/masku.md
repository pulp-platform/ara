# `masku` — Ara's mask unit, for mask bits dispatch, mask operations, bits handling

# Mask Unit

The Mask Unit (MASKU) handles the mask-layout vectors in Ara.
The MASKU is connected to all the lanes directly, through dedicated result queues, and through the VALU/VMFPU.

The mask unit can:
  1) Create mask predication bits and distribute them to the other computational units.
  2) Completely or partially process instructions that use mask-layout vectors (e.g., `vmsof`, `viota`, `vcompress`, `vmand`, `vmseq`).
  3) Execute `vrgather` instructions.

The instructions executed in the MASKU can be either fully handled by the MASKU, i.e., their execution is completely done in the MASKU, or partially handled by the MASKU when part of the computation also happens in a different unit.

Fully handle:
 - `vrgather`, `vrgatherei16`, `vcompress`
 - `vcpop`, `vfirst`
 - `viota`, `vid`
 - `vmsbf`, `vmsif`, `vmsof`

Partially handle:
 - Masked instructions (predication)
 - Mask logical instructions (e.g., `vmand`)
 - Comparison instructions (e.g., `vmseq`, `vmfeq`)
 - `vmadc`, `vmsbc`

## Working principles:
The mask unit receives an instruction broadcasted by the main sequencer and saves it in its instruction queue.

Depending on the instruction type, the MASKU will initialize the related state (e.g., counters) and start the execution.

There are mainly four types of instructions that use different control signals in the mask unit:
  A) Masked instructions (predication)
  B) Vector gather instructions
  C) All the other instructions supported by the MASKU

The MASKU receives source operands from the lanes and the received payload is always balanced, e.g., every MASKU will receive multiple `NrLanes * 64` balanced payloads.

### A
All the masked instructions executed outside of the MASKU are type-A.
When a masked instruction is executed outside of the MASKU, the units responsible to handle the instruction stall until receiveing the predication mask bits from the MASKU.

The lane sequencers of each lane will always enable the `MaskM` operand requester and queue to fetch the `v0` mask vector and send it to the MASKU.
The MASKU can receive `NrLanes * 64` bits of `v0` vector from the lanes every cycle.

Upon reception of a chunk of the `v0` operand, the MASKU processes it (mask source) to create `NrLanes` 8-bit byte strobes, one per lane. The mask strobes are saved in the mask queue, connected to all the other Ara units directly.
The MASKU handshaked the input `v0` chunk once it is fully processed, to get the next chunk if needed.

Each bit of each mask strobe corresponds to a byte of the data bus. If the mask strobe bit is at `1`, the corresponding byte on the data bus is active and will be written. Otherwise, the corresponding byte is not active and will not be written.

Note: the strobe creation happens in the MASKU since the mask bits are not always saved sequentially in `v0` and are never saved with a EW1 encoding. Instead, the content of `v0` can be encoded with EW8, EW16, EW32, or EW64 byte-layout encoding. This implies that, even for in-lane operations, the `i`th mask bit is never saved in the `i % NrLanes`th lane's VRF chunk.
EW1 is avoided when possible since it would require a more complex reshuffling stage. Only the MASKU can handle bit-level reshuffling.

### B
Vector gather instructions (`vrgather`, `vcompress`) are completely executed by the MASKU in two stages.

First, the lane sequencers of each lane will enable the `AluA` operand requester and queue to inject the index operand (`vs1`) into the `MASKU` through the ALU.

The MASKU processes the incoming source operands from `vs1` to create the indices used for the vector gather operation. These indices are used to 1) create a request to the `MaskB` opqueue of each lane

Note: since `vrgather` can be masked, it needs three input sources to the MASKU at full operations. We inject the indexes through the ALU to re-use the already-existing connections from the ALU to the MASKU. On the other hand, we use the `vd` operand queue to forward the source operand register elements (`vs2`) through the `MaskB` since this request is non-standard (i.e., it does not come from the main sequencer) and the `MaskB` is not connected to further units (e.g., the ALU), simplifying the control.

### C
Vector instructions that do not belong to A) and B) categories belong to C).
 - `vcpop`, `vfirst`: these instructions process a mask input vector, accumulate a result, and returns it as a scalar element to the main sequencer (and then, to CVA6)
 - `viota`, `vid`: these instructions write back a non-mask vector into the VRF. `viota` requires a mask-vector as a source operand.
 - `vmsbf`, `vmsif`, `vmsof`: these instructions take mask-vector as inputs and write back mask vectors into the VRF.
 - Mask logical instructions (e.g., `vmand`): these instructions are executed by the ALU/FPU. The resulting mask vector is filtered and written back by the MASKU.
 - Comparison instructions (e.g., `vmseq`, `vmfeq`): these instructions are executed by the ALU/FPU. The resulting mask vector is shuffled and written back by the MASKU.
 - `vmadc`, `vmsbc`: these instructions are executed by the ALU/FPU. The resulting mask vector is filtered and written back by the MASKU.

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
