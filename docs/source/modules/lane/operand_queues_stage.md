# `operand_queues_stage` — Instantiate the in-lane operand queues

**Author**: Matheus Cavalcante
**License**: Solderpad Hardware License v0.51
**Description**: This module contains the operand queues used in Ara’s vector lanes. It manages operand buffering and dispatching to the appropriate functional units (VFUs) such as ALU, MFPU, STU, SLDU, and Mask Unit. Each operand queue is a parameterized instance of `operand_queue`.

---

## Module Parameters

| Parameter              | Type             | Description |
|------------------------|------------------|-------------|
| `NrLanes`              | `int unsigned`   | Number of vector lanes |
| `VLEN`                 | `int unsigned`   | Vector length in bits |
| `FPUSupport`           | `fpu_support_e`  | FPU support configuration |
| `operand_queue_cmd_t`  | `type`           | Type used for operand queue commands |

---

## Ports

### Clock and Reset

| Name       | Direction | Type     | Description |
|------------|-----------|----------|-------------|
| `clk_i`    | Input     | `logic`  | Clock signal |
| `rst_ni`   | Input     | `logic`  | Asynchronous active-low reset |

### Lane Identification

| Name        | Direction | Type                           | Description |
|-------------|-----------|--------------------------------|-------------|
| `lane_id_i` | Input     | `logic[idx_width(NrLanes)-1:0]`| Lane identifier |

### VRF Interface

Inputs from the Vector Register File.

| Name               | Direction | Type                          | Description |
|--------------------|-----------|-------------------------------|-------------|
| `operand_i`        | Input     | `elen_t[NrOperandQueues-1:0]` | Operands |
| `operand_valid_i`  | Input     | `logic[NrOperandQueues-1:0]`  | Valid bits per operand |

### Operand Requester

| Name                    | Direction | Type                          | Description |
|-------------------------|-----------|-------------------------------|-------------|
| `operand_issued_i`      | Input     | `logic[NrOperandQueues-1:0]`  | Which operands are issued |
| `operand_queue_ready_o` | Output    | `logic[NrOperandQueues-1:0]`  | Readiness flags for operands |
| `operand_queue_cmd_i`   | Input     | `operand_queue_cmd_t[NrOperandQueues-1:0]` | Operand queue commands |
| `operand_queue_cmd_valid_i` | Input | `logic[NrOperandQueues-1:0]`  | Valid bits for queue commands |

### Store Exception Flush Support

| Name              | Direction | Type    | Description |
|-------------------|-----------|---------|-------------|
| `lsu_ex_flush_i`  | Input     | `logic` | Flush input signal |
| `lsu_ex_flush_o`  | Output    | `logic` | Flush output signal |

### Lane Sequencer

| Name               | Direction | Type    | Description |
|--------------------|-----------|---------|-------------|
| `mask_b_cmd_pop_o` | Output    | `logic` | Command pop signal for mask B |
| `sldu_addrgen_cmd_pop_o` | Output | `logic` | Pop command for slide/address generation unit |

### Functional Units Outputs

Documentation continues with full elaboration of each operand_queue instance across VFUs (ALU, MFPU, STU, SLDU, Mask Unit), flushing behavior, and parameter checks...
