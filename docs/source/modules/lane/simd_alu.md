# `simd_alu` - Ara's in-lane SIMD ALU (`simd_alu`)

This document provides an in-depth technical explanation of the `simd_alu` module in the Ara vector processor. The `simd_alu` (Single Instruction, Multiple Data Arithmetic Logic Unit) is responsible for element-wise ALU operations on 64-bit vector elements. It supports fixed-point arithmetic, saturating arithmetic, logical and comparison operations, shift instructions, and narrowing/rounding/merge instructions.

---

## Summary

- **Module Name:** `simd_alu`
- **Source:** `simd_alu.sv`
- **Author:** Matheus Cavalcante
- **License:** Solderpad Hardware License, Version 0.51
- **Purpose:** Implements vector ALU functionality supporting element-wise operations, fixed-point saturation, rounding, comparisons, and shifts for Ara’s 64-bit SIMD vector datapath.

---

## Inputs

| Signal                | Type                       | Description |
|----------------------|----------------------------|-------------|
| `operand_a_i`        | `elen_t` (64-bit)          | First operand for the ALU operation |
| `operand_b_i`        | `elen_t` (64-bit)          | Second operand |
| `valid_i`            | `logic`                    | Enables processing of a new instruction |
| `vm_i`               | `logic`                    | Vector mask enable |
| `mask_i`             | `strb_t` (byte-wide mask)  | Byte-level mask controlling predicate effects |
| `narrowing_select_i` | `logic`                    | Select for narrowing results |
| `op_i`               | `ara_op_e`                 | ALU operation code |
| `vew_i`              | `vew_e`                    | Vector element width selector (EW8, EW16, etc.) |
| `rm`                 | `strb_t`                   | Rounding mode (used in fixed-point ops) |
| `vxrm_i`             | `vxrm_t`                   | Fixed-point rounding mode (VXRM) |

## Outputs

| Signal       | Type          | Description |
|--------------|---------------|-------------|
| `result_o`   | `elen_t`      | Final result after SIMD ALU computation |
| `vxsat_o`    | `vxsat_t`     | Overflow saturation flags per lane |

---

## Internal Types

- `alu_operand_t`: Unions allowing the interpretation of a 64-bit value as 8/16/32/64-bit elements.
- `alu_sat_operand_t`: Extended width unions for saturation detection.

---

## Main Features and Functionality

### 1. **Vector Element Width Awareness**

Operations are performed on lanes as defined by `vew_i`:
- `EW8`: 8x 8-bit operations
- `EW16`: 4x 16-bit
- `EW32`: 2x 32-bit
- `EW64`: 1x 64-bit

Each operation adapts to the selected width via unpacking the input operands accordingly.

### 2. **ALU Operation Decoding**

The module uses a large `case` statement on `op_i` to implement logic/arithmetic/comparison instructions. Many instructions use nested `case` statements based on `vew_i`.

### 3. **Saturation and Fixed-Point Handling**

Fixed-point operations (e.g., `VSADD`, `VASUB`, `VNCLIP`) are handled conditionally using `FixPtSupport`. Overflow checks are done by checking high bits and flags are set in `vxsat`.

### 4. **Mask Logic & Merging**

The mask signal (`mask_i`) interacts with `vm_i` and is embedded in certain instruction results (e.g., comparisons). Merge and scalar move operations use the mask to choose between operands.

### 5. **Shift & Narrowing Operations**

Includes support for:
- Logical/arithmetic shifts (`VSLL`, `VSRL`, `VSRA`)
- Narrowing shift with optional rounding (`VNSRL`, `VNSRA`)
- Clip instructions (`VNCLIP`, `VNCLIPU`) with saturation

### 6. **Rounding Modes (VXRM)**

Rounding behavior for fixed-point arithmetic and narrowing instructions is selected via `vxrm_i`, using 4 defined rounding modes (e.g., round to nearest even, zero, etc.).

---

## Assertions

- The final assertion checks that `DataWidth == $bits(alu_operand_t)` to ensure 64-bit operation compatibility.

---

## Instruction Categories

Instructions include but are not limited to:

| Category          | Examples |
|-------------------|----------|
| Logical           | `VAND`, `VOR`, `VXOR` |
| Arithmetic        | `VADD`, `VSUB`, `VSADDU`, `VSADD` |
| Comparison        | `VMSEQ`, `VMSLT`, `VMAX`, `VMIN`, etc. |
| Saturating        | `VSSUB`, `VSSUBU`, `VSADDU` |
| Fixed-point       | `VASUB`, `VNCLIP`, `VSSRA`, `VSSRL` |
| Merging/Masking   | `VMERGE`, `VMXOR`, `VMXNOR`, etc. |
| Shift Operations  | `VSLL`, `VSRA`, `VNSRA`, etc. |

---

## Design Considerations

- **Efficiency:** Optimized for combinational output with modular per-lane calculations.
- **Flexibility:** Supports varied element widths and rounding behavior.
- **Masking Support:** Integrated mask control for conditional computation.
- **Saturation Awareness:** vxsat flags make it suitable for overflow-sensitive ops.
- **RISC-V RVV Compatible:** Aligns with vector instruction format and control conventions.

---

## Example Behavior (Pseudocode)

```systemverilog
// VADD with EW16 and two operands
for (int i = 0; i < 4; i++) {
    res.w16[i] = opa.w16[i] + opb.w16[i];
}
```
