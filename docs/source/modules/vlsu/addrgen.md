# `addrgen`: Ara Vector Address Generation Unit

**Module role:** Generates memory addresses and issues AXI memory requests for vector memory operations in the Ara vector processor. It supports various memory access patterns, MMU translations, and exceptions.

---

## Overview

The `addrgen` module orchestrates AXI4 address calculation and transaction generation for vector memory instructions, such as:

- **Unit-stride** operations (`VLE`, `VSE`)
- **Strided** operations (`VLSE`, `VSSE`)
- **Indexed** operations (`VLXE`, `VSXE`)
- **Fault-only-first** operations (for trap-early semantics)

It interacts with:
- The PE sequencer (for instruction and operand info)
- AXI memory interface
- MMU translation interface
- Exception/commit tracking logic

---

## Interfaces

### Clock and Reset
- `clk_i`: Module clock
- `rst_ni`: Active-low reset

### Instruction Inputs
- `pe_req_i`: Vector memory request (with fields like base address, stride, indexing mode)
- `pe_req_valid_i`: Validity signal for `pe_req_i`

### AXI Interface (AR/AW)
- `axi_ar_o`: AXI read address channel
- `axi_ar_valid_o`, `axi_ar_ready_i`
- `axi_aw_o`: AXI write address channel
- `axi_aw_valid_o`, `axi_aw_ready_i`

### Operand Vector (for Indexed Access)
- `addrgen_operand_i`: Vector operand for indexed addressing

### LSU/STU Interface
- `axi_addrgen_req_o`: Metadata for AXI transaction (type, alignment, ID)
- `axi_addrgen_valid_o`, `axi_addrgen_ready_i`

### MMU Interface
- `mmu_ptw_valid_o`, `mmu_ptw_ready_i`
- `mmu_ptw_req_o`, `mmu_ptw_resp_i`: Request/response for address translation

### Exception/Status
- `addrgen_exception_o`: Exception status (page fault, misaligned, etc.)
- `addrgen_ack_o`: Indicates memory op completion
- `core_st_pending_i`: Scalar core store hazard indicator

---

## Architecture Overview

The `addrgen` is composed of two different FSMs.

### 1. **Instruction FSM (`state_q`)**

Tracks the high-level progress of memory operations:
- `IDLE`: Waiting for a valid request.
- `ADDRGEN`: Preparing address and issuing AXI transaction.
- `ADDRGEN_IDX_OP`: Handling indexed operands.
- `WAIT_LAST_TRANSLATION`: MMU result wait.
- `ADDRGEN_IDX_OP_END`: Instruction teardown.

### 2. **AXI FSM (`axi_addrgen_state_q`)**

Handles AXI4 physical memory request generation:
- `IDLE`: Idle state
- `AXI_DW_STORE_MISALIGNED`: Align store address and bytes
- `WAITING_CORE_STORE_PENDING`: Wait if scalar store in progress
- `REQUESTING`: Issue AR/AW requests (if possible, through AXI bursts)
- `WAIT_TRANSLATION`: MMU pending

### 3. **Request Queue (FIFO)**

A `fifo_v3` instance stores pending AXI requests. This decouples request generation (`addrgen`) from LSU/STU consumption.

### 4. **Different types of memory operation**

Unit-stride accesses are handled through AXI bursts. The logic checks that each burst complies with AXI4, e.g., no 4-KiB page boundary crossing, max. 256 beats in a burst, etc.
AXI4 bursts are also convenient for virtual-to-physical translation, as each burst is always kept in a single 4-KiB page.
This type of access fully utilizes the memory bus.

Strided accesses, instead, usually under-utilize the bus. Each element is requested through a different AXI transaction.

Indexed memory accesses also under-utilize the bus and stall the front-end until the last element has been checked for exception. Also, they require a source operand, which is deshuffled in the `addrgen`.

### 5. **Translation and Exceptions**

- Requests virtual-to-physical translation via MMU interface
- Detects and propagates:
  - Misaligned accesses
  - Page faults
  - Fault-only-first violations
- Tracks first valid fault via `fof_first_valid_q`
