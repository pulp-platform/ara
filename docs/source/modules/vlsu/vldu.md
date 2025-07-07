
# `vldu`: Ara's Vector Load Unit

The `vldu` module implements Ara’s **Vector Load Unit**. It is responsible for loading data from memory into the Vector Register File (VRF) by receiving memory transactions via the AXI R channel and delivering vector data, possibly masked, to the lanes. This unit supports:
- **Masked/unmasked vector loads**
- **Multi-instruction pipelining** with an internal instruction queue
- **AXI burst handling**
- **Exception tracking** and safe partial commits

---

## 📌 Module Parameters

| Parameter         | Description                                                |
|-------------------|------------------------------------------------------------|
| `NrLanes`         | Number of vector lanes.                                    |
| `VLEN`            | Vector register length in bits.                            |
| `vaddr_t`         | Address type for vector register file addressing.          |
| `pe_req_t`        | Vector instruction request type.                           |
| `pe_resp_t`       | Vector instruction response type.                          |
| `AxiDataWidth`    | Width of the AXI data channel.                             |
| `AxiAddrWidth`    | Width of the AXI address channel.                          |
| `axi_r_t`         | AXI R-channel data type.                                   |

---

## 🔌 Interfaces

### ▶️ Inputs
- **Clock & Reset**: `clk_i`, `rst_ni`
- **Memory Load Channel**: `axi_r_i`, `axi_r_valid_i`
- **Instruction Inputs**:
  - `pe_req_i`, `pe_req_valid_i`: New vector instruction
  - `pe_vinsn_running_i`: Tracks active vector instructions
  - `axi_addrgen_req_i`, `axi_addrgen_req_valid_i`: Load address metadata
  - `addrgen_illegal_load_i`: Signals illegal access
- **Masking Support**:
  - `mask_i`, `mask_valid_i`: Per-lane mask bytes
- **Flush**: `lsu_ex_flush_i`

### ⏹ Outputs
- **AXI Handshake**: `axi_r_ready_o`
- **Instruction Handshake**: `pe_req_ready_o`
- **Memory Completion**: `load_complete_o`
- **Response**: `pe_resp_o`, `ldu_current_burst_exception_o`
- **Lane Interface**:
  - `ldu_result_req_o`, `ldu_result_addr_o`, `ldu_result_wdata_o`
  - `ldu_result_id_o`, `ldu_result_be_o`

---

## 🔧 Internal Structure

### 1. Mask Cut
- Uses `spill_register_flushable` for each lane.
- Applies masking only when `vm=0`.
- Ensures valid masks are acknowledged only when a masked instruction is issued.

### 2. Vector Instruction Queue (VIQ)
- Triple-pointers:
  - `accept_pnt`, `issue_pnt`, `commit_pnt`
- Accepts instructions and issues them sequentially.
- Maintains counts of inflight and committed instructions.
- Separate counters track committed/issued instructions and their remaining byte loads.

### 3. Result Queue (RQ)
- Per-lane dual-entry queue buffering data before final commitment.
- Data is written to VRF only after **final grants** (`ldu_result_final_gnt_i`) are received.
- Supports partial writes for `vstart > 0`.

### 4. AXI Data Reception
- Data is read beat-by-beat.
- Beat slicing is calculated with `beat_lower_byte` and `beat_upper_byte`.
- Data is shuffled using `shuffle_index` based on element size (vsew).
- Per-lane address and ID are calculated and stored in `result_queue`.

### 5. VRF Commit Logic
- All data must be granted and acknowledged before commit.
- Updates commit counters and triggers `load_complete_o`.

### 6. Exception Handling FSM
- States:
  - `IDLE`
  - `VALID_RESULT_QUEUE`
  - `WAIT_RESULT_QUEUE`
  - `HANDLE_EXCEPTION`
- Ensures partially buffered results are committed before signaling an exception.
- Keeps `ldu_current_burst_exception_o` accurate for safe exception replay.

---

## 🔁 Instruction Lifecycle

1. **Accept**: Valid `pe_req_i` is accepted if there's space and VFU matches.
2. **Issue**: Begins loading AXI data. Uses mask unit if applicable.
3. **AXI Read**: Transfers data beat-by-beat to result queue.
4. **VRF Commit**: Writes to VRF after grant. Signals completion.
5. **Exception**: If exception occurs mid-load, transitions to FSM to commit partials.

---

## ✅ Design Considerations

- **Masking Support**: Integrated at per-byte level using per-lane strobes.
- **Pipeline Decoupling**: Three-phase VIQ lets accept, issue, and commit progress independently.
- **Exception Robustness**: Can gracefully handle faults without data corruption.
- **Performance**: Decouples address generation, AXI, and VRF phases to maximize throughput.
- **Alignment & vstart**: First load carefully handles misalignment and partial data.

---

If you'd like a downloadable `.md` version, I can generate it for you.