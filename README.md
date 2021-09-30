# Ara

[![ci](https://github.com/pulp-platform/ara/actions/workflows/ci.yml/badge.svg)](https://github.com/pulp-platform/ara/actions/workflows/ci.yml)

Ara is a vector unit working as a coprocessor for the CVA6 core.
It supports the RISC-V Vector Extension, [version 0.10](https://github.com/riscv/riscv-v-spec/releases/tag/v0.10).

## Dependencies

Check `DEPENDENCIES.md` for a list of hardware and software dependencies of Ara.

## Supported instructions

Check `FUNCTIONALITIES.md` to check which instructions are currently support by Ara.

## Get started

Make sure you clone this repository recursively to get all the necessary submodules:

```bash
git submodule update --init --recursive
```

If the repository path of any submodule changes, run the following command to change your submodule's pointer to the remote repository:

```bash
git submodule sync --recursive
```

## Toolchain

Ara requires a RISC-V LLVM toolchain capable of understanding the vector extension, version 0.10.x.

To build this toolchain, run the following command in the project's root directory.

```bash
# Build the LLVM toolchain
make toolchain-llvm
```

Ara also requires an updated Spike ISA simulator, with support for the vector extension.

To build Spike, run the following command in the project's root directory.

```bash
# Build Spike
make riscv-isa-sim
```

## Verilator

Ara requires an updated version of Verilator, for RTL simulations.

To build it, run the following command in the project's root directory.

```bash
# Build Verilator
make verilator
```

## Configuration

Ara's parameters are centralized in the `config` folder, which provides several configurations to the vector machine.
Please check `config/README.md` for more details.

Prepend `config=chosen_ara_configuration` to your Makefile commands, or export the `ARA_CONFIGURATION` variable, to chose a configuration other than the `default` one.

## Software

### Build Applications

The `apps` folder contains example applications that work on Ara. Run the following command to build an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world
```

Convolutions allow to specify the output matrix size and the size of the filter, with the variables `OUT_MTX_SIZE` up to 112 and `F_SIZE` within {3, 5, 7}. Currently, not all the configurations are supported for all the convolutions. For more information, check the `main.c` file for the convolution of interest.
Example:

```bash
cd apps
make bin/fconv2d OUT_MTX_SIZE=112 F_SIZE=7
```

### RISC-V Tests

The `apps` folder also contains the RISC-V tests repository, including a few unit tests for the vector instructions. Run the following command to build the unit tests:

```bash
cd apps
make riscv_tests
```

## RTL Simulation

To simulate the Ara system with ModelSim, go to the `hardware` folder, which contains all the SystemVerilog files. Use the following command to run your simulation:

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Only compile the hardware without running the simulation.
make compile
# Run the simulation with the *hello_world* binary loaded
app=hello_world make sim
# Run the simulation with the *some_binary* binary. This allows specifying the full path to the binary
preload=/some_path/some_binary make sim
# Run the simulation without starting the gui
app=hello_world make simc
```

We also provide the `simv` makefile target to run simulations with the Verilator model.

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Only compile the hardware without running the simulation.
make verilate
# Run the simulation with the *hello_world* binary loaded
app=hello_world make simv
```

It is also possible to simulate the unit tests compiled in the `apps` folder. Given the number of unit tests, we use Verilator. Use the following command to install Verilator, verilate the design, and run the simulation:

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Verilate the design
make verilate
# Run the tests
make riscv_tests_simv
```

Alternatively, you can also use the `riscv_tests` target at Ara's top-level Makefile to both compile the RISC-V tests and run their simulation.

### Traces

Add `trace=1` to the `verilate`, `simv`, and `riscv_tests_simv` commands to generate waveform traces in the `fst` format.
You can use `gtkwave` to open such waveforms.

## Publication

If you want to use Ara, you can cite us:

```
@Article{Ara2020,
  author = {Matheus Cavalcante and Fabian Schuiki and Florian Zaruba and Michael Schaffner and Luca Benini},
  journal= {IEEE Transactions on Very Large Scale Integration (VLSI) Systems},
  title  = {Ara: A 1-GHz+ Scalable and Energy-Efficient RISC-V Vector Processor With Multiprecision Floating-Point Support in 22-nm FD-SOI},
  year   = {2020},
  volume = {28},
  number = {2},
  pages  = {530-543},
  doi    = {10.1109/TVLSI.2019.2950087}
}
```
