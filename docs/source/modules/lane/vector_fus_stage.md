# `vector_fus_stage` Module Documentation

**Module Name**: `vector_fus_stage`
**Authors**: Matheus Cavalcante
**Description**: This is Ara’s vector execution stage. It instantiates and connects the vector functional units (VFUs) for each lane, specifically the **Vector ALU (VALU)** and the **Vector Multiplier/FPU (VMFPU)**, enabling SIMD-style parallel vector operations.

---

## 1. Overview

This module coordinates the operation of all vector functional units for one lane in the Ara vector processor. It interfaces with:
- The **Dispatcher** for configuration (e.g., rounding/saturation).
- The **Lane Sequencer** for operation dispatch and handshaking.
- The **Vector Register File (VRF)** for read/write data movement.
- The **Slide Unit**, to handle reduction and data forwarding.
- The **Mask Unit**, to apply selective operation masking.

---

## 2. Parameters

| Parameter        | Type        | Description |
|------------------|-------------|-------------|
| `NrLanes`        | `int`       | Number of lanes in the vector processor |
| `VLEN`           | `int`       | Vector register length |
| `CVA6Cfg`        | Struct      | Configuration of the CVA6 processor |
| `FPUSupport`     | Enum        | Enable/disable support for FP16, FP32, FP64 |
| `FPExtSupport`   | Enum        | Enable external FP operations (like vfrec7, vfrsqrt7) |
| `FixPtSupport`   | Enum        | Support for fixed-point arithmetic |
| `vaddr_t`        | Type        | Type used to address vector elements |
| `vfu_operation_t`| Type        | Type representing vector functional unit operations |

---

## 3. Submodule Instantiations

### 3.1 `VALU` - Vector ALU

Handles all integer and fixed-point arithmetic operations.

- Inputs:
  - Operands (`alu_operand_i`)
  - Operation type (`vfu_operation_i`)
  - Control flags (`alu_vxrm_i`, mask info)
- Outputs:
  - Result back to VRF (`alu_result_wdata_o`, `alu_result_addr_o`)
  - Done signal per instruction (`alu_vinsn_done_o`)
  - Reductions (`alu_red_complete_o`)
  - Saturation flag (`alu_vxsat`)
- Handshake signals:
  - `alu_ready_o`, `alu_result_gnt_i`, mask signals

### 3.2 `VMFPU` - Vector Multiplier/FPU

Handles:
- Integer multiply and multiply-accumulate
- All floating-point operations (add, mul, div, sqrt, etc.)
- Optional external FP instructions
- Fixed-point arithmetic extensions

- Inputs:
  - 3 operands (`mfpu_operand_i`)
  - Operation type (`vfu_operation_i`)
- Outputs:
  - Result and writeback signals (`mfpu_result_*`)
  - Exception flags (`fflags_ex_o`)
  - Completion tracking (`mfpu_vinsn_done_o`, `fpu_red_complete_o`)
- Handshake and masking similar to `VALU`

---

## 4. Interface Summary

### 4.1 Input/Output Overview

- **Inputs from Dispatcher**:
  - `alu_vxrm_i`: Rounding mode
  - `vfu_operation_i`: Operation type
  - `vfu_operation_valid_i`: Validity

- **Operand Queues**:
  - ALU: `alu_operand_i[1:0]`, `alu_operand_valid_i`
  - MFPU: `mfpu_operand_i[2:0]`, `mfpu_operand_valid_i`

- **VRF Writeback**:
  - ALU: `alu_result_*`
  - MFPU: `mfpu_result_*`

- **Mask Interface**:
  - Shared `mask_i`, `mask_valid_i`
  - Split readiness signals: `alu_mask_ready`, `mfpu_mask_ready`

- **Slide Unit**:
  - Slide operands (`sldu_operand_i`)
  - Slide handshake per unit
  - Reduction request/ack (`sldu_*_req_valid_o`, `sldu_*_gnt_i`)

- **Saturation**:
  - `vxsat_flag_o`: Indicates whether saturation occurred

- **FPU Exceptions**:
  - `fflags_ex_o`, `fflags_ex_valid_o`

---

## 5. Control Logic and Signal Routing

### 5.1 Masking Coordination

- Shared input mask: `mask_i`, `mask_valid_i`
- Readiness `mask_ready_o = alu_mask_ready | mfpu_mask_ready`
- Broadcast strategy requires tagged mask handling if instruction queue > 1.

### 5.2 Saturation Flag Aggregation

Both units can set a saturation flag:
```systemverilog
assign vxsat_flag_o = mfpu_vxsat | alu_vxsat;
```

---

## 6. Lane-Level Operation and Modular Structure

This module is fully **parameterized per-lane**, enabling reuse across multiple vector lanes. Each lane runs its own instance of this module, and each instance manages:
- One ALU (`i_valu`)
- One MFPU (`i_vmfpu`)

The control strategy is uniform:
- Operand queues → functional units
- Results → VRF
- Status → dispatcher/sequencer
- Mask/Slide → helpers

---

## 7. Design Notes

- Uses the `ara_pkg` and `rvv_pkg` definitions for consistency across Ara.
- Designed to be flexible with regard to precision, operation type, and lane width.
- Follows strict handshake protocols to avoid hazards.
- Clean separation of logic for ALU and MFPU makes it easy to extend or adapt.
- Interfacing with the Mask and Slide Units is modular and scalable.
