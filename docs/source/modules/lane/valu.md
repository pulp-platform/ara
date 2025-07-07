# `valu` - Instantiate the in-lane SIMD ALU (unpipelined)

## Overview

The `valu` module is a central component of Ara's vector processing pipeline. It acts as a SIMD (Single Instruction, Multiple Data) integer Arithmetic Logic Unit, capable of executing vector instructions over 64-bit wide data lanes. Its primary role is to execute integer operations across multiple vector lanes in parallel and to manage operations including fixed-point arithmetic, scalar replication, vector reductions, narrowing operations, and interaction with the mask unit and slide unit.

This documentation serves as a **golden reference**, explaining every functional aspect of the `valu` module in detail.

---

## Table of Contents

1. [Module Parameters](#module-parameters)
2. [Top-Level Interface](#top-level-interface)
3. [Vector Instruction Queue](#vector-instruction-queue)
4. [Result Queue](#result-queue)
5. [Scalar Operand Processing](#scalar-operand-processing)
6. [Mask Operand Handling](#mask-operand-handling)
7. [Reduction Support](#reduction-support)
8. [Narrowing Instructions](#narrowing-instructions)
9. [SIMD ALU Execution](#simd-alu-execution)
10. [Fixed-Point Rounding and Saturation](#fixed-point-rounding-and-saturation)
11. [Control and State Machines](#control-and-state-machines)
12. [Instruction Lifecycle](#instruction-lifecycle)
13. [Commit and Writeback](#commit-and-writeback)
14. [Summary](#summary)

---

## Module Parameters

```systemverilog
parameter int unsigned NrLanes;
parameter int unsigned VLEN;
parameter fixpt_support_e FixPtSupport;
parameter type vaddr_t;
parameter type vfu_operation_t;
```

- `NrLanes`: Number of vector lanes.
- `VLEN`: Vector register length.
- `FixPtSupport`: Enable or disable fixed-point support.
- `vaddr_t`, `vfu_operation_t`: Type definitions for vector addresses and operations.

---

## Top-Level Interface

The `valu` module interfaces with several components:
- **Dispatcher**: Provides new vector operations (`vfu_operation_i`) and receives `vxsat_flag_o`.
- **Lane sequencer**: Coordinates the execution flow.
- **Operand queues**: Deliver source operands (`alu_operand_i`).
- **VRF**: Accepts results for writeback.
- **Slide Unit**: Exchanges operands and results for inter-lane reduction.
- **Mask Unit**: Manages masking for selective operations.

---

## Vector Instruction Queue

The queue tracks in-flight instructions and separates their execution phases:
- `accept_pnt`: Points to the next free entry for acceptance.
- `issue_pnt`: Instruction to be executed next.
- `commit_pnt`: Instruction whose results are being written back.

Each instruction is described by a `vfu_operation_t` struct and includes the vector operation, destination ID, and control fields like `vm` and `vsew`.

---

## Result Queue

This FIFO queue temporarily stores computation results, including:
- `wdata`: Resulting word.
- `id`: Instruction ID.
- `addr`: Target vector address.
- `be`: Byte enable.
- `mask`: Whether this result is to be forwarded to the mask unit.

Two pointers (`write_pnt`, `read_pnt`) and a count (`result_queue_cnt_q`) track the queue status.

---

## Scalar Operand Processing

Scalar values from instructions are **replicated** to 64-bit words depending on `vsew`. For instance:
- `EW8`: replicated 8×
- `EW16`: replicated 4×
- etc.

This ensures compatibility with SIMD-wide operations.

---

## Mask Operand Handling

When vector masking is enabled (`vm == 0`), a `spill_register` sends result data to the mask unit, filtered via the `mask_operand_ready_i` signal.

---

## Reduction Support

Reduction operations are divided into:
- **Intra-lane**: Sequential accumulation within a single lane.
- **Inter-lane**: Exchange of partial sums between lanes via the Slide Unit.

The ALU manages:
- Internal counters (`reduction_rx_cnt_q`)
- Inter-lane state transitions (e.g., `INTER_LANES_REDUCTION_TX`)
- Final SIMD reduction in lane 0

---

## Narrowing Instructions

Instructions like `VNSRA`, `VNCLIP` produce only **half the normal element width per cycle**. The module uses a toggle (`narrowing_select_q`) to alternate writing high/low halves.

---

## SIMD ALU Execution

The core computation is handled by `simd_alu`, parameterized by fixed-point support and rounding. It takes:
- `alu_operand_a` and `alu_operand_b`
- The operation (`op_i`)
- The mask (`mask_i`)
- A rounding modifier (`rm`)

Results are fed to the result queue and selectively masked.

---

## Fixed-Point Rounding and Saturation

When enabled, rounding and saturation are implemented via `fixed_p_rounding` and internal saturation flags (`alu_vxsat_q`). The saturation flag `vxsat_flag_o` is updated during commit.

---

## Control and State Machines

### ALU State (`alu_state_q`)

Defines execution phase:
- `NO_REDUCTION`
- `INTRA_LANE_REDUCTION`
- `INTER_LANES_REDUCTION_TX`
- `INTER_LANES_REDUCTION_RX`
- `SIMD_REDUCTION`
- `LN0_REDUCTION_COMMIT`

The FSM governs transitions based on instruction type, operand readiness, and SLDU handshake.

---

## Instruction Lifecycle

1. **Acceptance**: New vector instructions are stored in the queue.
2. **Issue**: Instructions are fetched and executed if operands are valid.
3. **Execution**: Results are generated (immediately or over multiple cycles).
4. **Commit**: Data is written to the vector register file or sent to the mask unit.

---

## Commit and Writeback

- Writeback to VRF is gated by `alu_result_gnt_i`.
- Results for masking go through `mask_operand_o`.
- Queue counters and state pointers are updated accordingly.

---

## Summary

The `valu` module implements a fully-pipelined vector integer ALU with:
- Support for all base and masking vector instructions.
- Seamless integration with reductions and fixed-point logic.
- FSM-based execution flow for consistent processing.
- A robust result queuing and commitment system.

It is a pivotal unit in Ara's vector architecture, balancing performance, flexibility, and functional completeness.
