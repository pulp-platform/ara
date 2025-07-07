# `simd_mul` — Ara's in-lane SIMD multiplier

**Module Name:** `simd_mul`
**Function:** This module implements a SIMD vector multiplier for Ara.

---

## ❖ Overview

The `simd_mul` module is Ara’s SIMD multiplier, supporting 8/16/32/64-bit elements and fixed-point multiplication with rounding and saturation. It operates in a pipelined manner and can produce one 64-bit result per cycle when fully utilized. It supports several RISC-V vector arithmetic operations (`VMUL`, `VMULH`, `VMULHU`, `VSMUL`, `VMADD`, `VMACC`, etc.).

---

## ❖ Parameters

| Parameter        | Type                 | Description |
|------------------|----------------------|-------------|
| `FixPtSupport`   | `fixpt_support_e`     | Enables fixed-point support and saturation logic. |
| `NumPipeRegs`    | `int unsigned`        | Number of pipeline stages. |
| `ElementWidth`   | `vew_e`               | Specifies element width (EW8, EW16, EW32, EW64). |

---

## ❖ Interface

| Port             | Direction | Type              | Description |
|------------------|-----------|-------------------|-------------|
| `clk_i`          | Input     | `logic`           | Clock. |
| `rst_ni`         | Input     | `logic`           | Active-low reset. |
| `operand_[a|b|c]_i` | Input  | `elen_t`          | Vector operands. |
| `mask_i`         | Input     | `strb_t`          | Element-level mask. |
| `op_i`           | Input     | `ara_op_e`        | Operation selector. |
| `vxrm_i`         | Input     | `vxrm_t`          | Rounding mode. |
| `valid_i`        | Input     | `logic`           | Input valid handshake. |
| `ready_o`        | Output    | `logic`           | Input ready. |
| `result_o`       | Output    | `elen_t`          | Computed result. |
| `mask_o`         | Output    | `strb_t`          | Mask forwarded to next stage. |
| `vxsat_o`        | Output    | `vxsat_t`         | Saturation flags. |
| `valid_o`        | Output    | `logic`           | Output valid. |
| `ready_i`        | Input     | `logic`           | Output ready handshake. |

---

## ❖ Key Internal Structures

### ➤ Operand Packing (`mul_operand_t`)
Unions the operand into multiple views (64, 32, 16, or 8-bit chunks) for ease of SIMD processing.

### ➤ Pipeline Buffers
Multi-stage pipeline implemented using shift-register logic, enabled via `NumPipeRegs`. All operands, opcodes, masks, and valid bits are pipelined.

### ➤ Ready Valid Interface
Flow control logic supports handshake-based data propagation through the pipeline.

---

## ❖ Functional Description

### ➤ Multiply Logic
Supports various operations:
- `VMUL`, `VMULHU`, `VMULHSU`, `VMULH` → Integer multiply
- `VSMUL` → Fixed-point multiply with rounding/saturation
- `VMACC`, `VMADD`, `VNMSAC`, `VNMSUB` → Multiply-accumulate & multiply-subtract

### ➤ Signedness
Sign control logic dynamically selects signed/unsigned behavior based on opcode (`signed_a`, `signed_b`).

### ➤ Result Rounding
Rounding logic for `VSMUL` is driven by `vxrm` mode:
- 00: round to nearest even
- 01: round to nearest, tie to max magnitude
- 10: truncate
- 11: ceiling

### ➤ Saturation (`vxsat`)
When enabled (`FixedPointEnable`), detects overflow and sets corresponding saturation bits.

---

## ❖ Element Width Handling

For each supported width, dedicated combinational blocks handle:
- Partial multiplications
- Optional fixed-point rounding/saturation
- Result assembly and output formatting

### ➤ EW64
- 1 × 64-bit operation
- Uses full 128-bit product

### ➤ EW32
- 2 × 32-bit elements
- Operates on upper/lower halves

### ➤ EW16
- 4 × 16-bit elements
- Operates on 16-bit lanes

### ➤ EW8
- 8 × 8-bit elements
- Operates on each byte independently

---

## ❖ Design Strengths

- Modular and parametric.
- Element-width adaptable.
- Fully pipelined and latency-configurable.
- Supports fixed-point arithmetic with saturating multiply.

---

## ❖ Conclusion

This module provides a highly reusable, parametric vector SIMD multiplier for the Ara architecture. It balances performance (via pipelining) with functionality (including fixed-point support). It is suitable as a drop-in building block for RVV-style SIMD execution pipelines.
