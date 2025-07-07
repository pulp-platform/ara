# `ara_sequencer` — Instruction sequencer and macro dependency check

Overview
--------
The `ara_sequencer` is a central control module in Ara's vector processor that manages instruction dispatching and execution synchronization across its parallel processing elements (PEs). It ensures correct ordering and dependency resolution for vector instructions, tracks the state of each instruction in-flight, and handles hazards and stalling due to resource constraints.

Key Features
------------
- Tracks running vector instructions and their mapping to PEs
- Maintains a global hazard table for dependency management
- Calculates start and end lanes for operand access
- Arbitrates instruction issuance based on operand readiness and structural hazards
- Interfaces with CVA6 via a tokenized valid/ready protocol
- Handles load/store sequencing and exception propagation
- Supports masked vector operations and precise scalar forwarding

Interface Description
---------------------
### Inputs
- `clk_i`, `rst_ni`: Standard clock/reset
- `ara_req_i`, `ara_req_valid_i`: Instruction request from dispatcher
- `pe_req_ready_i`, `pe_resp_i`: PE readiness and response signals
- `alu_vinsn_done_i`, `mfpu_vinsn_done_i`: Completion signals from specific FU types
- `addrgen_ack_i`, `addrgen_exception_i`, `addrgen_exception_vstart_i`, `addrgen_fof_exception_i`: Address generator and exception interfaces
- `pe_scalar_resp_i`, `pe_scalar_resp_valid_i`: Scalar value return for scalar-result instructions

### Outputs
- `ara_req_ready_o`, `ara_resp_o`, `ara_resp_valid_o`: Request response handshake
- `pe_req_o`, `pe_req_valid_o`: Instruction issued to PEs
- `global_hazard_table_o`: Dependency matrix broadcast to operand requesters
- `ara_idle_o`: High when no instruction is in-flight
- `pe_scalar_resp_ready_o`: Ready signal for scalar result

Main Components
---------------
### Instruction State Tracking
- `pe_vinsn_running_q`: Bitmap showing which PE is executing which instruction
- `vinsn_running_q`: Aggregated bitmap indicating if any instruction is live. This signal is extremely useful for debug
- `vinsn_id_n`: Allocated ID for the next instruction using LZC

### Hazard Management
- RAW, WAR, WAW hazards computed against `read_list_q` and `write_list_q`
- `global_hazard_table_o` updated with current hazard vectors
- Enforces correct serialization and prevents premature execution

### Start/End Lane Calculation
- Derives which lanes will produce the first and last valid elements
- Based on `vstart`, `vl`, and `vsew`
- Important for operand alignment and masking

### Issuance Arbitration
- FSM with `IDLE` and `WAIT` states
- Uses counters per VFU to throttle instruction dispatch
- "Gold ticket" system ensures stalled-but-accounted instructions are not blocked

### Functional Unit Interface
- Identifies target VFU for each instruction
- Uses `target_vfus()` function to map to ALU, MFPU, SLDU, MASKU, etc.
- Only issues when operand requesters and FU queues are ready

### Special Features
- Slide unit constraints handled to avoid chaining issues
- Handles scalar results with mask unit coordination
- Exception signaling for burst and address-related faults
- Provides synchronization to CVA6 (via token and response logic)

Instruction Flow
----------------
1. Dispatcher issues instruction to sequencer.
2. Sequencer:
   - Allocates ID
   - Checks for hazards
   - Builds request (`pe_req_d`)
   - Calculates start/end lanes
   - Evaluates VFU counters
3. If resources available:
   - Issues request
   - Updates global hazard table and instruction trackers
4. Enters `WAIT` if instruction needs scalar return or memory ack
5. Once response is received or exception detected, returns to `IDLE`.

FSM States
----------
- **IDLE**: Default state; waits for instruction or handles stalls from the lanes' operand requesters.
- **WAIT**: Holding state for memory/scalar responses.

Dependency tracking and chaining
----------
Dependencies are tracked per instruction, so that chaining can be implemented at vector-element level.

The sequencer only knows which instruction depends on which other instruction, and assign special "hazard" signals to each instruction before issuing it to the units.
Every instruction keeps hazard metadata per operand register, so that it is clear upon which instruction every operand register depends.

Chaining is implemented in each lane, during operand fetch.
Every dependency (RAW, WAR, WAW) on a specific register will throttle the source operand fetch from the VRF. This throttling is controlled by the write throughput of the instruction that generated the dependency.

RAW example:
```
vld v0, addr
vadd v1, v0, v0
```

When executing the `vadd` (`vld` is executing in parallel), a lane will fetch the next element from `v0` only if `vld` has written one element first. This control is a credit-based system with a depth of one element only. Therefore, if `vld` writes 5 elements, the `vadd` only registers one credit for a read.

WAR and WAW hazards are handled in the same way.

WAR example:
```
vmul v2, v1, v1
vadd v1, v0, v0
```

Also in this case, `vadd` will be able to fetch from `v0` only when `vmul` has written into `v2`. This works because if source operands are chained, destination operands are also correctly ordered.

As soon as one instruction that causes a dependency is completes execution, the scoreboard is cleared and the second instruction will be allowed to fetch operands without restrictions.

This works as long as:
 - The second instruction has source operands from the VRF. For example, WAR and WAW stall loads, which would not be able to chain with this mechanism.
 - The first instruction actually writes something into the VRF. Therefore, WAR on store instructions stalls the second instruction until the first one has not completed.

Instruction Issue
----------
The sequencer keeps an instruction counter per functional unit to track how many instructions are in-flight and stall instruction issue whenever the next target functional unit's instruction queue is already full.

A new instruction bumps up the respective counter, and a completed instruction bumps it down.

Since, for timing reasons, instructions flow into the sequencer and bump the respective counter without waiting to be issues, counters can also go beyond their maximum capacity for one cycle. This event is registered through a gold ticket assigned to the instruction, which basically implies that the instruction was already registered by the respective counter. As soon as the counter returns to its maximum capacity (this happens when an instruction is finishes execution in the respective unit), the gold ticket allows the stalled instruction to proceed.

Physical Considerations
-----------------------
- `vinsn_queue_ready`: Derived from counter depth per FU
- `stall_lanes_desynch`: Ensures lane-0 aligned counters for ALU/MFPU
- `global_hazard_table_d`: Matrix [NrVInsn][NrVInsn] with sparse update logic
- Careful pipeline management to support exception-aware issuing
