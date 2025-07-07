# `lane` — Ara's lane, hosting a vector register file slice and functional units

**Module**: `lane`
**Project**: Ara RISC-V Vector Processor
**Author**: Matheus Cavalcante
**License**: SHL-0.51 (Solderpad Hardware License, Version 0.51)
**Description**:
This module represents a **single vector lane** in Ara. It integrates vector register file banks, operand queues, execution units, and interfaces to other Ara submodules.

---

## Table of Contents

1. [Overview](#overview)
2. [Parameters](#parameters)
3. [Key Interfaces](#key-interfaces)
4. [Internal Components](#internal-components)
5. [Slide/AddrGen Arbitration](#slideaddrgen-arbitration)
6. [Assertions](#assertions)

---

## Overview

Each `lane` encapsulates a full vector processing path: sequencer, register file access, operand queues, vector functional units (VFUs), and arbitration logic for shared datapaths (e.g., SLDU/ADDRGEN). Each lane processes a subset of elements and synchronizes with others via the global control.

---

## Parameters

- **NrLanes**: Total number of lanes.
- **VLEN**: Total vector length.
- **CVA6Cfg**: CVA6 configuration structure.
- **FPUSupport, FPExtSupport**: Enables half/single/double FP formats and extended FP support.
- **FixPtSupport**: Enables fixed-point instruction support.
- **pe_req_t_bits / pe_resp_t_bits**: Widths for request/response interfaces with the main dispatcher.

Derived parameters include:
- VRF size per lane, address sizes, data widths.
- Types like `vaddr_t`, `strb_t`, `vlen_t`.

---

## Key Interfaces

### External Control

- `clk_i`, `rst_ni`: Clock/reset.
- `scan_enable_i`, `scan_data_i/o`: Scan chain for testing.

### Sequencer Interaction

- `pe_req_i/pe_req_ready_o/pe_resp_o`: Request-response from dispatcher.
- `alu_vinsn_done_o`, `mfpu_vinsn_done_o`: Signals end of execution per instruction.

### LSU and Exceptions

- `lsu_ex_flush_i/o`: Store flush trigger/acknowledge.

### Operand & Result Interfaces

- Connects to:
  - Store Unit
  - Slide Unit / Address Generator
  - Load Unit
  - Mask Unit
- Supports parallel operand extraction and result routing.

### Vector Register File (VRF)

- Accessed via `operand_requester` and shared by operand queues.
- VRF requests (`vrf_req`) are per bank and read/write vector elements.

---

## Internal Components

### 1. Spill Register

Implements a simple valid/ready handshake break for the mask signal to reduce timing pressure:
```verilog
spill_register #(.T(strb_t)) i_mask_ready_spill_register (...);
```

### 2. Lane Sequencer

- Controls instruction issue, hazard tracking, and VFU command creation.
- Accepts `pe_req` and issues `vfu_operation`.

### 3. Operand Requester

- Converts sequencer commands into vector element reads from VRF.
- Pushes elements to the right operand queue (ALU/MFPU/SLDU).
- Handles exceptions and maintains issue order.

### 4. Vector Register File (VRF)

- Implements a multi-bank vector register file.
- Read requests are broadcast; write requests include byte enable (`be_i`).

### 5. Operand Queues

- Buffer operands per functional unit.
- Synchronize access to shared vector memory buses (Slide/AddrGen).
- Produce outputs for:
  - ALU
  - MFPU
  - STU
  - AddrGen (SLDU)

### 6. Vector Functional Units

- ALU and MFPU implement full vector arithmetic.
- Interfaces allow direct forwarding of results (e.g., for reductions).
- Manage execution flags (vxsat, fflags).

---

## Slide/AddrGen Arbitration

The lane uses **arbitration** to manage access to a shared data bus used by:
- Slide Unit
- Address Generator
- ALU (reductions)
- FPU (reductions)

### Arbitration Control

- Uses a FIFO (`fifo_v3`) to track instruction order.
- Selects which unit drives the bus based on op type.

### Multiplexing

- `stream_mux` chooses among OpQueue, ALU, and MFPU.
- Grants (`*_gnt`) are conditioned on queue arbitration and valid signals.

---

## Assertions

Basic structural checks ensure valid parameter configurations:
```verilog
if (NrLanes == 0)
  $error("[lane] Ara needs to have at least one lane.");
```
