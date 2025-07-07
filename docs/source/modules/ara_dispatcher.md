
# `ara_dispatcher` — Vector Instruction Decoder and Issuer

The `ara_dispatcher` is the central instruction decoder and legality checker for Ara’s RISC-V vector unit. It receives instructions from the scalar core (Ariane) via the `acc_req_i` interface and dispatches well-formed vector requests to Ara’s backend using the `ara_req_o` interface.

---

## 🧭 Role in Ara

- Decodes **RISC-V vector instructions (RVV)** from scalar core
- Validates legality based on LMUL, SEW, CSR, segment loads/stores, and support flags
- Manages **control and status registers (CSRs)** for VL, VTYPE, VSTART, VXRM, and VXSAT
- Handles **load/store reshuffling** to maintain consistent EEW across register groups
- Issues vector requests via `ara_req_o` and coordinates responses via `ara_resp_valid`

---

## 🔌 Interface

### Input Ports
| Signal              | Width     | Description |
|---------------------|-----------|-------------|
| `clk_i`             | 1         | Clock input |
| `rst_ni`            | 1         | Active-low reset |
| `acc_req_i`         | struct    | Incoming request from scalar core |
| `ara_req_ready_i`   | 1         | Back-end ready to receive vector request |
| `ara_resp_valid`    | 1         | Back-end has completed a request |
| `ara_resp`          | struct    | Response metadata from Ara |
| `ara_idle_i`        | 1         | Ara is idle, ready to accept new instructions |
| `load_complete_i`   | 1         | Vector load completed |
| `store_complete_i`  | 1         | Vector store completed |

### Output Ports
| Signal              | Width     | Description |
|---------------------|-----------|-------------|
| `acc_resp_o`        | struct    | Response back to scalar core |
| `ara_req_valid_o`   | 1         | Ara request is valid |
| `ara_req_o`         | struct    | Decoded vector request |
| `pending_seg_mem_op_o` | 1     | Pending segment memory operation tracker |

---

## 🔁 FSM States

- `IDLE` — Waiting for valid vector instructions
- `WAIT_IDLE` — Waiting for Ara to become idle (CSR ops)
- `WAIT_IDLE_FLUSH` — Flushes vector state after exceptions
- `RESHUFFLE` — Triggers register reshuffling before execution

---

## 🧠 Internal Concepts

### CSR Registers
- `csr_vl_q`, `csr_vtype_q`, `csr_vstart_q` — Active state of vector CSRs
- `csr_vxrm_q`, `csr_vxsat_q` — Fixed-point rounding/saturation

### EEW Tracking
- `eew_q[0..31]` stores Element Effective Width for each vreg
- Updated upon successful execution of instructions

### Reshuffling
- Needed if same register used with different EEW
- Controlled by `reshuffle_req_d[2:0]` for `vs1`, `vs2`, `vd`
- Buffering via `eew_old_buffer_d`, `eew_new_buffer_d`, etc.

---

## 🔍 Instruction Decoding

Instructions are decoded based on RVV encoding using extracted fields:
- `vmem_type`, `varith_type`, etc.
- `mop`, `nf`, `vm`, `rs1`, `rs2`, `rd`, `mew`, `width`

---

## 📦 Memory Operation Handling

- **Load Types**: VLE, VLSE, VLXE, VLVX
- **Store Types**: VSE, VSSE, VSXE, VSVX
- Unit-stride, strided, indexed, and whole-register
- Segment operations detected if `nf != 0`

---

## 🚨 Illegal Instruction Checks

Illegal cases include:
- EMUL × NF > 8
- Access beyond register 31
- Inconsistent EEW across a register group
- Disallowed CSR writes or invalid opcodes
- Fixed-point ops without hardware support
- Floating-point ops (e.g., `VFREC7`) without FPExt support

---

## 🌀 Reshuffling Flow

- Triggered by EEW mismatch for reused vector registers
- Masked out if same register appears in multiple operand slots
- FSM state switches to `RESHUFFLE`, issues internal reshuffle ops
- Once reshuffling is complete, instruction is re-issued

---

## ⚙️ CSR Handling

All CSR access instructions (e.g., `csrrw`, `csrrs`, `csrrc`, and immediate variants) are handled.
- Only `vstart`, `vxrm`, `vxsat` are writable
- `vl`, `vtype`, `vlenb` are read-only
- Illegal accesses cause exception

---

## ⚠️ Zero VL Behavior

If `vl = 0`, most instructions are treated as NOPs.
- Some exceptions (whole-reg ops, special instructions)
- Response is generated with `req_ready` and `resp_valid` set
- Ensures scalar pipeline doesn't stall

---

## 🔄 Token Toggling

Each accepted instruction flips the `token` bit:
```verilog
ara_req.token = (ara_req_valid_o && ara_req_ready_i) ? ~ara_req_o.token : ara_req_o.token;
```
This ensures a unique identifier for every issued instruction, useful for hazard tracking.

---