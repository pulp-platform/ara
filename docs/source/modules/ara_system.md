# `ara_system`: Integration of CVA6 and Ara

## Overview

`ara_system` instantiates and connects the scalar core **CVA6** with the **Ara vector accelerator**. It builds the system-level interface between the two, handles AXI width conversion, invalidation signaling, and merges AXI traffic into a unified master port.

This module is the core of Ara's architectural integration, enabling:
- Vector instruction dispatch from CVA6 to Ara
- Shared AXI access arbitration
- Coherent invalidation handling for vector memory stores
- Flexible benchmarking configurations through parameterization

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
- Interfaces to Ara via CVXIF
- Outputs standard AXI (`ariane_axi_req_t`) at narrow data width

### 2. **Ara Accelerator**
- Fully parameterized vector unit
- Receives CVXIF requests, returns results
- AXI master interface at wide data width

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

## Alternate Configuration: `IDEAL_DISPATCHER`

If `IDEAL_DISPATCHER` is defined:
- CVA6 is replaced with a perfect dispatcher (`accel_dispatcher_ideal`)
- Useful for functional validation or micro-benchmarking Ara in isolation

---
