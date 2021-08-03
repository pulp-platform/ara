# Dependencies

Ara has strong and weak dependencies on several packages. Such dependencies and their licenses are listed in this document.

## Hardware dependencies

Ara needs the following hardware packages to work.

- [axi](https://github.com/pulp-platform/axi)
- [common\_cells](https://github.com/pulp-platform/common_cells)
- [common\_verification](https://github.com/pulp-platform/common_verification)
- [cva6](https://github.com/openhwgroup/cva6)
- [tech\_cells\_generic](https://github.com/pulp-platform/tech_cells_generic)

All of them are licensed under the Solderpad 0.51 license.

## Software

In order to compile the benchmarks, you will need the RISC-V GCC toolchain with support for the Vector Extension, version 0.9.
This is included as a submodule (`toolchain/riscv-gnu-toolchain`).

Unit tests for the vector instructions are given in a patched version of the [riscv\_tests](https://github.com/riscv/riscv-tests/) repository (`apps/riscv-tests`).
The riscv-tests repository is licensed under the BSD license.

The unit tests can also run on Spike, the RISC-V ISA Simulator, which is also included as a submodule (`toolchain/riscv-isa-sim`).
This version of Spike is patched to align the behavior of the `vcsr` CSR with the toolchain and with RVV v0.9.

We provide a Python script to run `clang-format` and format the C and C++ files of this repository (`scripts/run-clang-format.py`).
This file is licensed under the MIT license.

`jacobi2d` comes from an adaptation of the software in `https://github.com/RALC88/riscv-vectorized-benchmark-suite`. The source file `apps/jacobi2d/main.c` contains the original licence.

### Verilator simulations

In order to run Verilator simulations, you will need a modern Verilator installation.
Ara was tested with Verilator v4.106, included as a submodule (`toolchain/verilator`).
Verilator is licensed under the GPL version 3.0.

Verilator simulations also need some testbench helper files, which were adapted from lowRISC.
Such files can be seen in `hardware/tb/verilator/`.
They are licensed under the Apache license version 2.0.
