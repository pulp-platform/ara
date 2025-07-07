# `vstu`: Ara Vector Store Unit

The `vstu` module implements the **vector store unit** of the Ara RISC-V vector processor. It is responsible for generating and issuing memory write (store) operations via the AXI W and B channels. It consumes vector operands from the vector lanes, aligns and masks them, and dispatches them as AXI bursts to memory. It supports vector masking, vector start (`vstart`) handling, and exception processing in case of illegal transactions or MMU faults.

---

## Contents

- [Module Parameters](#module-parameters)
- [Interface Overview](#interface-overview)
- [Key Functional Blocks](#key-functional-blocks)
- [AXI Write Logic](#axi-write-logic)
- [Mask Handling](#mask-handling)
- [Instruction Queue and State](#instruction-queue-and-state)
- [Exception Handling](#exception-handling)
- [Bugs and Issues](#bugs-and-issues)

---

## Module Parameters

| Parameter         | Description |
|------------------|-------------|
| `NrLanes`         | Number of vector lanes. |
| `VLEN`            | Maximum vector length (elements). |
| `vaddr_t`         | Addressing type for vector register file. |
| `pe_req_t`, `pe_resp_t` | Types for PE request/response. |
| `AxiDataWidth`    | AXI write data width (W channel). |
| `AxiAddrWidth`    | AXI address width. |
| `axi_w_t`, `axi_b_t` | AXI W and B channel types. |

---

## Interface Overview

### Inputs

- `pe_req_i`, `pe_req_valid_i`, `pe_vinsn_running_i`: Vector instruction from the PE.
- `axi_addrgen_req_i`, `axi_addrgen_req_valid_i`: AXI address and burst info from address generator.
- `stu_operand_i`, `stu_operand_valid_i`: Operand data and valid signals from each lane.
- `mask_i`, `mask_valid_i`: Byte-wise mask from the Mask Unit.
- `axi_w_ready_i`, `axi_b_valid_i`, `axi_b_i`: AXI handshake and write response signals.

### Outputs

- `axi_w_o`, `axi_w_valid_o`: Write payload to AXI W channel.
- `axi_b_ready_o`: Write response acknowledgment.
- `stu_operand_ready_o`: Ready signals to lanes for operand acceptance.
- `mask_ready_o`: Mask consumption indicator.
- `store_pending_o`, `store_complete_o`: Store state indicators.
- `axi_addrgen_req_ready_o`: Handshake with address generator.
- `stu_current_burst_exception_o`: Store exception notifier.

---

## Key Functional Blocks

The VSTU can change the byte layout of the vector registers on-the-fly and does not usually require reshuffles.

### Vector Instruction Queue

A FIFO queue stores incoming instructions and tracks three execution stages:
- **Accept**: Instruction is accepted and stored.
- **Issue**: Instruction is issued to AXI and operand lanes.
- **Commit**: Instruction waits for AXI `b` response.

Pointers and counters (`accept_pnt`, `issue_pnt`, `commit_pnt`, `issue_cnt`, `commit_cnt`) track instruction flow through these phases.

### Operand Registers

Each lane has a spill register to buffer operand data. Flushable on `lsu_ex_flush_i`.

### Mask Registers

Byte-wise mask signals are buffered using flushable registers. Used for element-wise masking when `vm=0`.

---

## AXI Write Logic

1. **Operand Check**: Ensures all operands and masks are valid.
2. **Byte Mapping**: Converts vector lane data into AXI word-aligned format using `shuffle_index`.
3. **AXI Beat Formation**: Constructs and sends AXI W payloads with `strb` indicating valid bytes.
4. **Beat Completion**: Monitors burst length and prepares next instruction or beat.

### Byte Validity Logic

Determines the effective byte count from:
- vstart offset
- mask enablement
- lane alignment
- AXI burst alignment

---

## Instruction Issuing

Handles issuing multiple micro-ops per vector store using:
- `issue_cnt_bytes_q`: Tracks bytes left.
- `axi_len_q`, `vrf_pnt_q`: AXI and VRF pointers.
- `vinsn_running_q`: Tracks active instructions.

---

## B Channel Handling

Upon receiving a valid response (`axi_b_valid_i`), the unit:
- Acknowledges the AXI response
- Updates commit pointer and counters
- Signals store completion to dispatcher

---

## Exception Handling

Catches and handles:
- Address generation faults
- MMU-related exceptions
- Store permission violations

Flushes affected instructions if they’re the only pending ones and transitions the state accordingly.
