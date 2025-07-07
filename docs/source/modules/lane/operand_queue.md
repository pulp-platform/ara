# `operand_queue` — Buffer between the VRF and the functional units

**Module Path**: `operand_queue.sv`
**Description**:
This module implements a configurable operand queue used to buffer and manipulate elements from the Vector Register File (VRF) before they are consumed by Functional Units (FUs). It includes support for type conversion, data widening, floating-point normalization, and reduction operations. It is a key part of Ara’s vector execution pipeline.

---

## Table of Contents
1. [Interface Overview](#interface-overview)
2. [Parameterization](#parameterization)
3. [Command FIFO](#command-fifo)
4. [Data Buffer (Input FIFO)](#data-buffer-input-fifo)
5. [Credit-Based Flow Control](#credit-based-flow-control)
6. [Floating-Point Leading Zero Count](#floating-point-leading-zero-count)
7. [Type Conversion Logic](#type-conversion-logic)
8. [Neutral Value Padding for Reductions](#neutral-value-padding-for-reductions)
9. [Operand Output Control](#operand-output-control)
10. [State Management](#state-management)
11. [Conclusion](#conclusion)

---

## Interface Overview

### Inputs:
- `clk_i`, `rst_ni`: Clock and active-low reset.
- `flush_i`: Flushes internal state (used during exception recovery or pipeline flush).
- `lane_id_i`: Identifier for the lane this operand queue belongs to.
- `operand_queue_cmd_i`, `operand_queue_cmd_valid_i`: Command inputs that define the behavior for each operand.
- `operand_i`, `operand_valid_i`: Operand data from the VRF.
- `operand_issued_i`: Tracks how many operands were issued.
- `operand_ready_i`: One-hot vector indicating readiness of connected FU ports.

### Outputs:
- `cmd_pop_o`: Optional indication that command has been popped (only if `AccessCmdPop` is enabled).
- `operand_queue_ready_o`: Signals readiness to accept new operands.
- `operand_o`, `operand_valid_o`, `operand_target_fu_o`: Operand data sent to FU, with valid and target signals.

---

## Parameterization

- `CmdBufDepth`, `DataBufDepth`: FIFO depths for commands and data.
- `FPUSupport`: Enum to control which FP formats (Half, Single, Double) are supported.
- `SupportIntExt[2|4|8]`: Enable widening integer operations.
- `SupportReduct`, `SupportNtrVal`: Support for reductions and neutral padding.
- `AccessCmdPop`: Enables external visibility into command buffer pops.

---

## Command FIFO

The command buffer stores upcoming operand operations as defined by the scheduler. These determine how operands are transformed. The `fifo_v3` module ensures in-order delivery and tracks usage internally. Commands are consumed only when enough operands are emitted.

---

## Data Buffer (Input FIFO)

An operand input FIFO buffers incoming VRF values until they are needed. Each cycle, values may be pushed (if valid) and popped (when used). Internally, a credit-based system ensures no overflows and supports simultaneous push/pop.

---

## Credit-Based Flow Control

The signal `operand_queue_ready_o` is driven by comparing current FIFO usage (`ibuf_usage_q`) with capacity. The usage counter is updated based on:
- Operand issued → increment
- Operand consumed → decrement

Flush logic resets the usage tracker.

---

## Floating-Point Leading Zero Count

The module optionally instantiates LZC (Leading Zero Counter) logic to normalize subnormal FP inputs:
- `fp8_m_lzc`, `fp16_m_lzc`, `fp32_m_lzc`: Count zeros in mantissas of FP formats.
- Used for wide FP conversions (e.g., fp8→fp16, fp16→fp32, etc.)

---

## Type Conversion Logic

The `type_conversion` block:
- Handles all widening cases (sign/zero-extension for int8→int16/32/64).
- Supports floating-point widening with exponent/mantissa adjustment.
- Applies neutral padding for inactive lanes during reductions.
- Includes element reordering logic for FP conversions and `shuffle_index`.

Conversion modes supported:
- `OpQueueConversionSExt*`, `ZExt*`, `WideFP2`, `AdjustFPCvt`
- Neutral-padding via `OpQueueReductionZExt` or default padding for final packet

---

## Neutral Value Padding for Reductions

When `SupportNtrVal` is set and reduction is active:
- MSBs are padded with harmless neutral values to avoid altering result.
- Based on EEW (element width) and command-provided `ntr_red`.

Neutral values vary per target (ALU, MFPU) and FP format, with special encoding:
- e.g., `0x7ff0000000000000` for FP64 max

---

## Operand Output Control

Output logic in `obuf_control` block:
- Tracks how many operands have been emitted (`elem_count_q`)
- Selects sub-operands in packet (`select_q`)
- Pops from FIFO when all elements of an operand are consumed
- Updates target FU routing info
- Resets state on flush or command completion

Operand conversion and sequencing are tightly controlled to maintain data integrity across pipeline stages.

---

## State Management

Sequential registers:
- `select_q`, `elem_count_q`: Maintain operand fragment selection and element counter.
- Updated on each operand emission or reset on flush.

---

## Conclusion

The `operand_queue` module is a sophisticated component handling:
- Pipelined operand buffering
- Element-wise manipulation (conversion, widening, neutral fill)
- Intelligent control of operand delivery timing
- Support for multiple vector formats, FP pipelines, and reduction ops

It ensures high flexibility and correctness in vector operand preparation before execution in Ara’s VFUs.
