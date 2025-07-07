# `ara`: Top-Level Vector Unit

## Overview

The `ara` module is the **top-level vector processing unit** that implements the RISC-V Vector Extension (RVV). It interfaces directly with the **CVA6 scalar core** and contains all vector-specific sub-units required to execute RVV instructions, including:

- A dispatcher (decodes vector instructions, injects reshuffles)
- A sequencer (controls operand dispatch and result collection)
- Lanes (vector ALUs)
- Vector Load/Store Unit (VLSU)
- Slide Unit (SLDU)
- Mask Unit (MASKU)

The design is **modular and scalable**, with configurable parameters for lane count, VLEN, data types, and extended features like segmentation or MMU support.

---

## Parameters

| Name | Description |
|------|-------------|
| `NrLanes` | Number of parallel vector lanes |
| `VLEN` | Vector length (in bits) |
| `OSSupport` | Enables MMU and fault-only-first logic |
| `FPUSupport` | Enables FP16/32/64 support |
| `FPExtSupport` | Enables `vfrec7`, `vfrsqrt7` |
| `FixPtSupport` | Enables fixed-point support |
| `SegSupport` | Enables segmented memory operations |
| `CVA6Cfg` | CVA6 configuration record |
| `Axi*Width` | AXI bus widths |
| `axi_*` | AXI channel and bundle typedefs |
| `exception_t`, `accelerator_*`, `acc_mmu_*` | Types for accelerator/MMU interfacing |

---

## Ports

| Port | Dir | Description |
|------|-----|-------------|
| `clk_i`, `rst_ni` | In | Clock and reset |
| `scan_*` | In/Out | Scan chain (test) |
| `acc_req_i`, `acc_resp_o` | In/Out | Vector accelerator interface (with CVA6) |
| `axi_req_o`, `axi_resp_i` | Out/In | AXI memory interface |

---

## Internal Units

### 1. Dispatcher (`ara_dispatcher`)
- Fully decodes RVV instructions
- Handles register reshuffling for EW mismatches
- Injects vector micro-ops
- Tracks active instructions and completion

### 2. Sequencer (`ara_sequencer`)
- Manages vector instruction lifecycle
- Handles scalar responses and exception tracking
- Dispatches work to lanes and special units

### 3. Vector Lanes (`lane`)
- One per lane
- Executes vector ALU, FPU, and logic ops
- Connects to mask, slide, load, and store units

### 4. Vector Load/Store Unit (`vlsu`)
- Handles vector memory access
- Interfaces with MMU and AXI
- Manages address generation and fault detection

### 5. Slide Unit (`sldu`)
- Performs byte-reshuffling and slide ops
- Optimized for power-of-two strides
- All-to-all lane connectivity

### 6. Mask Unit (`masku`)
- Centralized logic for mask generation and bit-level access
- Handles mask combination ops (e.g., `vfirst`, `vcpop`)
- Shares scalar result lines with the sequencer

---

## MMU Support

When `OSSupport = 1`, the module:
- Interfaces with CVA6's MMU (via SV39)
- Performs virtual-to-physical address translation
- Supports fault-only-first loads and address exceptions

---

## Interconnect & Communication

- **AXI Bus**: All memory traffic goes through `axi_req_o`, shared by `vlsu`.
- **Lane Communication**: Mask, slide, and result buses are coordinated across all lanes.
- **Pipeline Control**: All stages use ready/valid handshake semantics.
- **Flush Support**: For load/store exceptions via `lsu_ex_flush_*`.

---

## Key Internal Types

- `ara_req_t`, `ara_resp_t`: Internal vector instruction & response format
- `vaddr_t`: Lane-local VRF address
- `strb_t`: Byte-enable for partial updates
- `vxrm_t`, `vtype_t`: RISC-V RVV control metadata

---

## Assertions

```systemverilog
if (NrLanes == 0) ...
if (NrLanes != 2**$clog2(NrLanes)) ...
if (NrLanes > MaxNrLanes) ...
if (VLEN == 0) ...
if (VLEN < ELEN) ...
if (VLEN != 2**$clog2(VLEN)) ...
