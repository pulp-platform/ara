# `ara`: Top-Level Vector Unit

## Overview

The `ara` module is the **top-level vector processing unit** that implements the RISC-V Vector 1.0 Extension (RVV). It interfaces directly with the **CVA6 scalar core** and contains all vector-specific sub-units required to execute RVV instructions, including:

- A dispatcher (decodes vector instructions, keeps the vector CSR state, injects special micro-operations)
- A sequencer (controls instruction issue to the units, enforce instruction dependencies, collect results)
- Lanes (each lane contains a slice of the vector register file plus the arithmetic units)
- Vector Load/Store Unit (VLSU, it initiates AXI AR/AW transactions and handle the dataflow from/to memory)
- Slide Unit (SLDU, runs vector slides and byte layout reshuffling)
- Mask Unit (MASKU, assembles and distributes mask (predication) bits, executes bit-level mask instructions, and runs more complex bit-level permutations plus vrgather)

The design is **modular and scalable**, with configurable parameters for lane count, VLEN, data types, and extended features like segmentation or MMU support.

The most stable configurations are with a power-of-2 number of lanes from 2 to 16, with a VLEN derived from considering a VLEN-per-lane of 1024 bit/lane.

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
- Keeps the vector CSR state
- Handles register reshuffling for EW mismatches
- Injects special vector micro-ops (e.g., reshuffle slides, segment memory micro-ops)
- Tracks active instructions and completion

### 2. Sequencer (`ara_sequencer`)
- Manages vector instruction lifecycle
- Tracks instruction dependencies with a scoreboard
- Handles scalar responses and exception tracking
- Broadcast work to lanes and special units

### 3. Vector Lanes (`lane`)
- Keeps a slice of the Vector Register File and multiple functional units (FPU, ALU, Multiplier)
- Executes arithmetic and logic vector operations
- Feed Ara's units through the VRF, and receive memory operands from the load unit

### 4. Vector Load/Store Unit (`vlsu`)
- Handles vector memory access
- Interfaces with CVA6's MMU (virtual address translation through dedicated interface) and memory (through AXI4)
- Manages address generation and exception detection for memory operations

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

The sequencer broadcasts instructions to all the units in parallel (VLSU, SLDU, MASKU, Lanes). Also, the all-to-all connected units (VLSU, SLDU, MASKU) are connected to every lane in parallel.

Each lane works on a 64-bit datapath, and every all-to-all unit receives at least one bus of 64-bit from every lane.