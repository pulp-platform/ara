
# `ara_dispatcher` — Vector Instruction Decoder and Issuer

The `ara_dispatcher` is the central instruction decoder and legality checker for Ara’s RISC-V vector unit. It receives instructions from the scalar core (CVA6) via the `acc_req_i` interface and dispatches well-formed vector requests to Ara’s backend using the `ara_req_o` interface.

---

## Role in Ara

- Decodes **RISC-V vector instructions (RVV)** from scalar core
- Validates legality based on LMUL, SEW, CSR, segment loads/stores, and support fflags
- Manages **control and status registers (CSRs)** for VL, VTYPE, VSTART, VXRM, and VXSAT
- Handles **load/store reshuffling** to maintain consistent EEW across register groups
- Issues vector requests via `ara_req_o` and coordinates responses via `ara_resp_valid`

---

## Interface

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

## FSM States

- `IDLE` — Waiting for valid vector instructions
- `WAIT_IDLE` — Waiting for Ara to become idle (CSR ops)
- `WAIT_IDLE_FLUSH` — Flushes vector state after exceptions
- `RESHUFFLE` — Triggers register reshuffling before execution

---

## Internal Concepts

### CSR Registers
- `csr_vl_q`, `csr_vtype_q`, `csr_vstart_q` — Active state of vector CSRs
- `csr_vxrm_q`, `csr_vxsat_q` — Fixed-point rounding/saturation

### EEW Tracking
In Ara, every vector register is encoded with a byte layout that forces consecutive vector elements into consecutive lanes (i.e., element 0 in lane 0, element 1 in lane 1, end so on).
This means that a vector interpreted with a different element width will require a byte layout reshuffling to enforce consecutive vector elements in consecutive lanes.

- `eew_q[0..31]` stores Element Effective Width for each vreg. This is basically the byte layout encoding of every vector register
- Updated upon successful dispatch of instructions

### Reshuffling
When a vector register needs to be re-interpreted with a different byte encoding, the Ara's Dispatcher injects slide micro-operations to reshuffle the vector register's byte layout.

- Needed if same register used with different EEW
- Controlled by `reshuffle_req_d[2:0]` for `vs1`, `vs2`, `vd`
- Buffering via `eew_old_buffer_d`, `eew_new_buffer_d`, etc.

---

## Interface with CVA6

Vector instructions are dispatched from CVA6 to Ara when they have reached the top of CVA6's scoreboard, i.e., when they are no more speculative and can be committed from CVA6's perspective.

Ara's dispatcher handshakes the request (and returns a response) if exceptions cannot happen for that instruction or if exceptions are immediately raised during decoding.

For example, arithmetic instructions can raise exceptions only during decoding. Thus, the answer to CVA6 is really fast (1 cycle).

Memory operations can raise errors on the memory bus or exceptions during virtual-to-physical translation. Therefore, memory instructions freeze the dispatcher until the VLSU has reported back an exception or the absence of it.
This process requires more than 1 cycle.

---

## Instruction Decoding

Instructions are decoded based on RVV encoding using extracted fields:
- `vmem_type`, `varith_type`, etc.
- `mop`, `nf`, `vm`, `rs1`, `rs2`, `rd`, `mew`, `width`

---

## Memory Operation Handling

- **Load Types**: VLE, VLSE, VLXE, VLVX
- **Store Types**: VSE, VSSE, VSXE, VSVX
- Unit-stride, strided, indexed, and whole-register
- Segment operations detected if `nf != 0`

---

## Illegal Instruction Checks

Illegal cases include:
- Illegal operand registers given the current SEW, LMUL state
- EMUL × NF > 8
- Access beyond register 31
- Inconsistent EEW across a register group
- Disallowed CSR writes or invalid opcodes
- Fixed-point ops without hardware support
- Floating-point ops (e.g., `VFREC7`) without FPExt support

---

## Reshuffling Flow

- Triggered by EEW mismatch for reused vector registers
- Masked out if same register appears in multiple operand slots
- FSM state switches to `RESHUFFLE`, issues internal reshuffle ops
- Once reshuffling is complete, instruction is re-issued

---

## CSR Handling

All CSR access instructions (e.g., `csrrw`, `csrrs`, `csrrc`, and immediate variants) are handled.
- Only `vstart`, `vxrm`, `vxsat` are writable
- `vl`, `vtype`, `vlenb` are read-only
- Illegal accesses cause exception

---

## Zero VL Behavior

If `vl = 0`, most instructions are treated as NOPs.
- Some exceptions (whole-reg ops, special instructions)
- Response is generated with `req_ready` and `resp_valid` set
- Ensures scalar pipeline doesn't stall