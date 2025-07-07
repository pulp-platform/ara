# `vlsu` - Vector Load/Store Unit

The `vlsu` module is the vector load/store unit of Ara, designed to handle memory operations for vector registers independently of CVA6’s scalar LSU. It supports virtual-to-physical address translation, vector-wide memory transactions, and integrates with the rest of the vector datapath.

---

## Interface Description

### Clock and Reset
- `clk_i`, `rst_ni`: Standard synchronous clock and active-low reset.

### AXI Memory Interface
- `axi_req_o`, `axi_resp_i`: Combined AXI request/response interface via an internal `axi_cut` module for decoupling.

### Dispatcher & Sequencer Interface
- `core_st_pending_i`: Indicates store operations pending in the core.
- `load_complete_o`, `store_complete_o`: Completion flags for memory operations.
- `pe_req_i`, `pe_req_valid_i`: Incoming request from the PE sequencer.
- `pe_req_ready_o`, `pe_resp_o`: Handshake and response interface for both LD and ST.

### Address Generator
- Integrates the `addrgen` module to handle AXI-compliant address generation.
- Outputs: `addrgen_ack_o`, exceptions, and MMU translation support.

### Data Path Interfaces
- `stu_operand_i`, `ldu_result_*`: Vector operand and result ports for each lane.
- `addrgen_operand_i`: Source address input to `addrgen`.

### Mask Interface
- Input and ready signals for masking in both LDU and STU.

### Exception Handling
- Tracks illegal accesses, exceptions from MMU, and LSU-specific exceptions.

---

## Internal Structure

### AXI Decoupling
The `axi_cut` module slices AXI transactions from the core’s memory interface to isolate internal buffering and timing:

```systemverilog
axi_cut i_axi_cut (
  .clk_i, .rst_ni, .mst_req_o, .mst_resp_i, .slv_req_i, .slv_resp_o
);
```

### Address Generator
The `addrgen` submodule manages the following:
- Supports unit-stride, strided, and indexed access
- Exception and translation support (via MMU)
- Works with both LDU and STU concurrently via handshake logic

### Vector Load Unit (VLDU)
Manages vector loads:
- Converts AXI read responses to per-lane vector data
- Applies mask if enabled
- Drives result buses per-lane
- Reports `load_complete_o`, burst exceptions

### Vector Store Unit (VSTU)
Handles vector stores:
- Drives write data + strobes to AXI bus
- Processes per-lane operands
- Tracks store pending & complete states
- Reports burst exceptions

### CSR and MMU Integration
- Handles translation enable flag
- Interacts with SV39 MMU for virtual memory
- Generates proper requests and handles exceptions (page faults, misaligned access)

---

## Key Logic Components

- `addrgen` instantiated with dual ready signals for load and store handshaking.
- Exception aggregation via:
  ```systemverilog
  assign lsu_current_burst_exception_o = stu_current_burst_exception | ldu_current_burst_exception;
  ```

- Store pending logic directly mapped to `vstu`.

- Assertions for:
  - Minimum lane requirement
  - AXI interface width sanity
