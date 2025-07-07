# `ara_soc`: Top-Level Dummy SoC for Ara

## Overview

The `ara_soc` module is a top-level **dummy system-on-chip** used to instantiate the **Ara vector processor** alongside the scalar **CVA6 core**, enabling test and benchmarking in a standalone simulation environment.

This SoC includes:
- Ara + CVA6 integration
- L2 memory (a simple SRAM, called DRAM in the file for historical reasons)
- UART peripheral
- Control and status registers
- AXI crossbar interconnect and protocol adapters

It is **parameterizable** to support varying numbers of vector lanes and data widths, enabling scalable evaluation of Ara across configurations.

---

## Parameters

| Name              | Description                                                                 |
|-------------------|-----------------------------------------------------------------------------|
| `NrLanes`         | Number of parallel vector lanes (2–16, power-of-two)                        |
| `VLEN`            | Vector length in bits (usually `1024 × NrLanes`)                            |
| `OSSupport`       | Enable OS-level support in CVA6                                             |
| `FPUSupport`      | Enables FP16, FP32, FP64 support                                            |
| `FPExtSupport`    | Enable optional `vfrec7` / `vfrsqrt7` instructions                          |
| `FixPtSupport`    | Enables fixed-point support                                                 |
| `SegSupport`      | Enables segmented memory instructions                                       |
| `Axi*Width`       | AXI bus widths for data, address, ID, user                                  |
| `AxiRespDelay`    | AXI response delay in picoseconds (used in gate-level simulations)          |
| `L2NumWords`      | Number of words in simulated SRAM (`4MiB / lane` default)                   |

---

## Memory Map

| Region   | Base Address      | Size    |
|----------|-------------------|---------|
| `SRAM`   | `0x8000_0000`     | 1 GB    |
| `UART`   | `0xC000_0000`     | 4 KB    |
| `CTRL`   | `0xD000_0000`     | 4 KB    |

---

## Internal Structure

### AXI Crossbar
- One master (CVA6+Ara system)
- Three slaves: SRAM, UART, control registers
- Managed via `axi_xbar` with routing rules

### SRAM (L2 Memory)
- Backed by synthesizable SRAM (`tc_sram`)
- Connected via `axi_to_mem` and `axi_atop_filter` (atomics filtered out)

### UART
- APB interface exposed to the environment
- Internally connected via AXI-Lite and AXI width converter

### Control Registers
- Control and status block (exit signal, counters, etc.)
- Connected via AXI-Lite

### CVA6 + Ara Integration
- Instantiated via `ara_system`
- Custom configuration generated dynamically from RVV template config

---

## Interfaces

### Inputs
- `clk_i`, `rst_ni`: Clock and active-low reset
- `scan_enable_i`, `scan_data_i`: Scan chain inputs (for DFT)
- `uart_prdata_i`, `uart_pready_i`, `uart_pslverr_i`: UART bus inputs

### Outputs
- `exit_o`: Simulation termination flag
- `hw_cnt_en_o`: Hardware counter enable signal
- `scan_data_o`: Scan chain output
- `uart_*`: APB UART outputs

---

## Configuration Notes

CVA6 is configured dynamically using:

```systemverilog
function automatic config_pkg::cva6_user_cfg_t gen_usr_cva6_config(...);
```
