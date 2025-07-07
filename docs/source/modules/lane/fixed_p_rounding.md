# `fixed_p_rounding` - Set up fixed-point arithmetic rounding information

## Overview

The `fixed_p_rounding` module implements fixed-point rounding logic for Ara's vector execution stage. It operates on 64-bit wide elements and generates rounding result bits for each element stream based on the rounding mode and vector element width (VEW).

---

## Ports

### Inputs

| Name            | Type         | Description |
|-----------------|--------------|-------------|
| `operand_a_i`   | `elen_t`     | Encodes the shift amount `j` for each sub-element. |
| `operand_b_i`   | `elen_t`     | Source operand to extract rounding bits from. |
| `valid_i`       | `logic`      | Enables rounding logic when high. |
| `op_i`          | `ara_op_e`   | Operation type; rounding occurs only on selected operations. |
| `vew_i`         | `vew_e`      | Specifies the vector element width: `EW8`, `EW16`, `EW32`, or `EW64`. |
| `vxrm_i`        | `vxrm_t`     | RISC-V vector rounding mode: `00`, `01`, `10`, or `11`. |

### Output

| Name            | Type         | Description |
|-----------------|--------------|-------------|
| `r_o`           | `strb_t`     | Output rounding bits for each element. |

---

## Internal Structures

### `rounding_args`
A `union packed` type that allows simultaneous interpretation of a 64-bit value as:
- 8 x 8-bit (`w8`)
- 4 x 16-bit (`w16`)
- 2 x 32-bit (`w32`)
- 1 x 64-bit (`w64`)

---

## Functional Behavior

Rounding logic is triggered only when `valid_i` is high and `op_i` matches one of:
- `VSSRA`
- `VSSRL`
- `VNCLIP`
- `VNCLIPU`

Depending on `vew_i` and `vxrm_i`, different rounding strategies are selected.

### Rounding Modes (`vxrm_i`)
- `00` (RNU): Round to Nearest, Up.
- `01` (RNE): Round to Nearest, ties to Even.
- `10` (RTZ): Round Towards Zero (no rounding).
- `11` (ROD): Round towards -∞ for negative and +∞ for positive.

### Element Width Handling

Each `vew_i` type (`EW8`, `EW16`, etc.) leads to different slicing of input operands.

#### Example for `EW8`, `vxrm = 00`:
```verilog
for (int i = 0; i < 8; i++) begin
  j      = opa.w8[i];
  r_o[i] = opb.w8[i][j-1];
end
```

#### Example for `EW32`, `vxrm = 01`:
```verilog
for (int i = 0; i < 2; i++) begin
  j      = opa.w32[i];
  r_o[i] = opb.w32[i][j-1] & opb.w32[i][j];
end
```

#### For `vxrm = 10`, no rounding is performed:
```verilog
r_o = '0;
```

#### For `vxrm = 11` (ROD), more logic is applied:
- Negates the `j`th bit
- ORs the masked remaining bits using a lookup from `bit_select`

---

## Lookup Table: `bit_select`

This is a constant table used to mask and check lower bits for rounding:
```verilog
bit_select = {
  64'h0000000000000000,
  64'h0000000000000001,
  64'h0000000000000003,
  ...
  64'h7FFFFFFFFFFFFFFF
};
```

Each index `j` selects `bit_select[j]` to help evaluate whether remaining bits are non-zero.

---

## Summary

This module is essential for accurate fixed-point rounding in Ara's vector datapath, adhering to RISC-V vector rounding modes. It is carefully tailored to handle various element widths and vector rounding policies as per the RISC-V specification.

---