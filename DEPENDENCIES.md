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

In order to compile the benchmarks, you will need the RISC-V GCC toolchain with support for the Vector Extension.

Unit tests for the vector instructions are given in a patched version of the [riscv\_tests](https://github.com/riscv/riscv-tests/) repository.

### Verilator simulations

In order to run Verilator simulations, you will need a modern Verilator installation.
It is licensed under the GPL version 3.0.
