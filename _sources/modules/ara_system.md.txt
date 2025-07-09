# `ara_system`: Integration of CVA6 and Ara

## Overview

`ara_system` instantiates and connects the scalar core **CVA6** with the **Ara vector accelerator**. It builds the system-level interface between the two, handles AXI width conversion, invalidation signaling, and merges AXI traffic into a unified master port.

This module is the core of Ara's architectural integration, enabling:
- Vector instruction dispatch from CVA6 to Ara
- Shared AXI access arbitration
- Coherent invalidation handling for vector memory stores
- Flexible benchmarking configurations through parameterization

CVA6 is a RV64GC RISC-V Linux-ready core. It features one L1 instruction cache and one L1 data cache connecting to the L2 memory.

CVA6 is the only "RISC-V core" properly speaking, meaning that it is the only one accessing the program's instruction flow.

Ara is a tighlty-coupled accelerator plugged into CVA6, and receives vector instructions from CVA6.

Both Ara and CVA6 have a private AXI4-compliant Load-Store unit. Ara's one directly connects to the L2 memory, bypassing CVA6's L1 data cache.

This allows for potential coherence and memory operation ordering issues.

---

## Memory Coherence and Consistency

Memory coherence is enforced through three main mechanisms:
 - Memory writes are serialized through a single memory bus.
 - CVA6 L1-D$ is write-through.
 - An invalidation filter snoops on Ara's AXI AW memory bus and invalidates the potentially-stale sets in CVA6's L1-D$.

Memory ordering is enforced by CVA6 and control signals between CVA6 and Ara. No memory operations are issued or started until it's safe to do so.
For example, pending vector stores prevent CVA6 from issuing scalar memory operations, and vector memory operations are not dispatched to Ara if there is a pending scalar store.

---

## Virtual memory support

Ara uses CVA6's MMU to translate virtual addresses into physical ones. This is done through the MMU interface.

---

## Parameters

### Ara + RVV Parameters

| Name          | Description |
|---------------|-------------|
| `NrLanes`     | Number of vector lanes |
| `VLEN`        | Vector register length (in bits) |
| `OSSupport`   | Enables OS features |
| `FPUSupport`  | Enabled FP precisions |
| `FPExtSupport`| Support for `vfrec7`, `vfrsqrt7` |
| `FixPtSupport`| Enable fixed-point ops |
| `SegSupport`  | Support for segmented memory ops |

### CVA6 and AXI Interface

| Name                | Description |
|---------------------|-------------|
| `CVA6Cfg`           | CVA6 configuration record |
| `exception_t`       | CVA6 exception type |
| `accelerator_req_t` | Accelerator interface (CVA6 → Ara) |
| `accelerator_resp_t`| Accelerator interface (Ara → CVA6) |
| `acc_mmu_{req,resp}`| MMU interface |
| `cva6_to_acc_t`     | Packed request interface |
| `acc_to_cva6_t`     | Packed response interface |
| `Axi*Width`         | AXI bus widths |
| AXI typedefs        | All channel and request/response types |

---

## Ports

| Port         | Direction | Description |
|--------------|-----------|-------------|
| `clk_i`      | Input     | Clock signal |
| `rst_ni`     | Input     | Active-low reset |
| `boot_addr_i`| Input     | Initial fetch address for CVA6 |
| `hart_id_i`  | Input     | Hardware thread ID |
| `scan_*`     | In/Out    | Scan chain (test) |
| `axi_req_o`  | Output    | AXI master request (merged) |
| `axi_resp_i` | Input     | AXI master response (merged) |

---

## Internal Blocks

### 1. **CVA6 Core**
- Scalar processor core
- Interfaces to Ara via a dedicated accelerator port
- Outputs standard AXI (`ariane_axi_req_t`) at narrow data width to L2 memory

### 2. **Ara Accelerator**
- Fully parameterized vector unit
- Receives CVA6 requests, returns results and exceptions
- AXI master interface at wide data width (`32 * #Lanes` data width)

### 3. **AXI Width Converter**
- `axi_dw_converter` adjusts CVA6's narrow AXI (e.g., 64-bit) to match Ara/system-wide bus width

### 4. **AXI Invalidation Filter**
- Detects vector memory stores and emits invalidation signals
- Ensures cache coherence with CVA6
- Integrated with Ara's AXI path

### 5. **AXI Multiplexer**
- Merges CVA6 and Ara AXI requests
- Handles arbitration, backpressure, and spill registers

---

## Vector Interface Handling

- The `acc_to_cva6_t` signal is extended to include `inval_valid` and `inval_addr`, enabling memory coherence notification from Ara back to CVA6.
- Ara can assert `inval_valid` when performing stores that require CVA6 cache line invalidation.
- `acc_cons_en` gate controls the invalidation path.

---

## Alternative Configuration: `IDEAL_DISPATCHER`

The ideal dispatcher is just a tool to benchmark Ara's performance with an ideal vector instruction dispatcher instantiated INSTEAD OF CVA6.

If `IDEAL_DISPATCHER` is defined:
- CVA6 is replaced with a perfect dispatcher (`accel_dispatcher_ideal`), i.e., a FIFO containing the dynamic instruction trace of the program plus the correct register file values
- Useful for functional validation/benchmarking or micro-benchmarking Ara in isolation
