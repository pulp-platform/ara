
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
- `vinsn_running_q`: Aggregated bitmap indicating if any instruction is live
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
- **IDLE**: Default state; waits for instruction or handles operand delay.
- **WAIT**: Holding state for memory/scalar responses.

Physical Considerations
-----------------------
- `vinsn_queue_ready`: Derived from counter depth per FU
- `stall_lanes_desynch`: Ensures lane-0 aligned counters for ALU/MFPU
- `global_hazard_table_d`: Matrix [NrVInsn][NrVInsn] with sparse update logic
- Careful pipeline management to support exception-aware issuing

Debugging Aids
--------------
- `ara_idle_o` signal is useful for performance counters and host sync
- Gold ticket logic ensures deterministic debugging of stalls
- Fine-grain visibility into `read_list_q`/`write_list_q` helps trace hazards

Recommendations
---------------
- Always probe `global_hazard_table_o` to track true dependencies
- Monitor `vinsn_queue_issue` to analyze stall causes
- Align slide/mask-heavy operations to minimize all-to-all congestion
