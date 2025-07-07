# `vmfpu` — Instantiate in-lane SIMD FPU, SIMD multiplier, and SIMD divider (pipelined or multi-cycle)

**Module Name:** `vmfpu`

---

## Summary

The `vmfpu` module is part of the Ara RISC-V vector processor and implements the Vector Multiply and Floating Point Unit (VFPU) responsible for executing arithmetic operations that include multiplication and floating point computation. It supports operations over elements coming from the vector register file, controlled by the vector instruction sequencer and interconnected via operand queues.

This module receives instructions, manages multiple operand queues, schedules operations on sub-units (like FP multipliers and ALUs), and routes results back to the operand dispatcher. It plays a key role in exploiting vector-level parallelism in floating point and multiplication domains.

---

## Interface Description

### Clocking and Reset

| Signal | Direction | Description |
|--------|-----------|-------------|
| `clk_i` | Input | Clock signal |
| `rst_ni` | Input | Active-low synchronous reset |

### Operand Queue Interface

| Signal | Direction | Description |
|--------|-----------|-------------|
| `operand_valid_i` | Input | One-hot encoding for operand queue validity |
| `operand_i` | Input | Operands input from the vector register file |
| `operand_ready_o` | Output | Ready handshake for each operand queue |

### Result Interface

| Signal | Direction | Description |
|--------|-----------|-------------|
| `result_req_o` | Output | Valid signal to request writing result |
| `result_id_o` | Output | ID of the instruction producing the result |
| `result_addr_o` | Output | VRF write address |
| `result_wdata_o` | Output | Result data to be written |
| `result_be_o` | Output | Byte enable signal |
| `result_gnt_i` | Input | Grant from operand requester |
| `result_final_gnt_i` | Input | Final commit acknowledgment from operand requester |

---

## Functional Blocks Overview

### 1. Operand Queue Decoding

The module reads from several operand queues concurrently and decodes operand availability. A `onehot` signal (`operand_valid_i`) triggers internal FSMs to accept and latch operand data into internal registers.

This mechanism ensures that the pipeline only proceeds when all necessary operands are ready.

### 2. FSM (Finite State Machine) Control Logic

The FSM implements several states:

- **IDLE**: Waits for operands to be valid.
- **WAIT**: Waits for all operands to be latched and for a backend (like FPU/MUL) to be free.
- **EXECUTE**: Passes the operands to the compute unit and asserts a `valid` signal.
- **DONE**: Waits for the result grant handshake.

Transitions occur on the basis of operand readiness, backend availability, and completion handshakes. This careful control ensures precise handling of instruction lifecycle.

### 3. Backend Compute Unit Selection

Depending on the instruction:

- Integer multiplication might be routed to the `Mul` unit.
- Floating point computation might use FP ALU, FP MUL, or FP FMA.

These units are external to the `vmfpu` module and are connected via operand and result interfaces. The correct selection depends on the `target_fu` and operation code embedded in the vector instruction.

### 4. Stream Registers

Each result-producing unit feeds into a **stream register**, which buffers results until downstream units acknowledge the result (`result_gnt_i`), avoiding backpressure to the compute units.

These registers decouple execution and result storage, facilitating pipeline throughput.

---

## Code Walkthrough

### Module Declaration and Parameters

```systemverilog
module vmfpu import ara_pkg::*; ...
```

The module imports Ara and RVV packages, ensuring access to operand types, configuration constants, and hardware definitions.

It uses several type parameters:

- `NrLanes`, `VLEN`, `vaddr_t`: define structural hardware constraints.
- `operand_queue_cmd_t`, `operand_request_cmd_t`: encapsulate control signals between scheduler and operand queues.

---

### Registers and Internal Signals

Internal signals such as `fsm_state_q`, `operand_valid`, and `stream_reg_payload` track FSM state, operand readiness, and result data, respectively.

These are updated in sequential logic blocks and control combinational data paths.

---

### Operand Gathering and Arbitration

Each operand queue's validity is polled, and the module arbitrates between them using one-hot logic.

When valid operands are detected, the FSM transitions into WAIT and EXECUTE states.

---

### Computation Dispatch

Operations are dispatched to the correct backend depending on instruction decoding logic:

```systemverilog
case (target_fu)
  FPU: begin
    ...
  end
  MUL: begin
    ...
  end
endcase
```

Here, `target_fu` determines which functional unit receives the operands.

---

### Result Capture and Output

Results are written to output ports using stream registers:

```systemverilog
stream_register #(...) i_fpu_stream_reg (
  ...
  .valid_i   (fpu_result_valid),
  .data_i    ({id, addr, result}),
  ...
);
```

Once the result is accepted by the downstream module, the FSM returns to IDLE.
