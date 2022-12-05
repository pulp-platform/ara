# Ara

[![ci](https://github.com/pulp-platform/ara/actions/workflows/ci.yml/badge.svg)](https://github.com/pulp-platform/ara/actions/workflows/ci.yml)

Ara is a vector unit working as a coprocessor for the CVA6 core.
It supports the RISC-V Vector Extension, [version 1.0](https://github.com/riscv/riscv-v-spec/releases/tag/v1.0).

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

Ara requires a RISC-V LLVM toolchain capable of understanding the vector extension, version 1.0.

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

### SPIKE Simulation

All the applications can be simulated with SPIKE. Run the following command to build and run an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world.spike
make spike-run-hello_world
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

### Ideal Dispatcher mode

CVA6 can be replaced by an ideal FIFO that dispatches the vector instructions to Ara with the maximum issue-rate possible.
In this mode, only Ara and its memory system affect performance.
This mode has some limitations:
 - The dispatcher is a simple FIFO. Ara and the dispatcher cannot have complex interactions.
 - Therefore, the vector program should be fire-and-forget. There cannot be runtime dependencies from the vector to the scalar code.
 - Not all the vector instructions are supported, e.g., the ones that use the `rs2` register.

To compile a program and generate its vector trace:

```bash
cd apps
make bin/${program}.ideal
```

This command will generate the `ideal` binary to be loaded in the L2 memory for the simulation (data accessed by the vector code).
To run the system in Ideal Dispatcher mode:

```bash
cd hardware
make sim app=${program} ideal_dispatcher=1
```

### VCD Dumping

It's possible to dump VCD files for accurate activity-based power analyses. To do so, use the `vcd_dump=1` option to compile the program and to run the simulation:

```bash
make -C apps bin/${program} vcd_dump=1
make -C hardware simc app=${program} vcd_dump=1
```

Currently, the following kernels support automatic VCD dumping: `fmatmul`, `fconv3d`, `fft`, `dwt`, `exp`, `cos`, `log`, `dropout`, `jacobi2d`.

### Linting Flow

We also provide Synopsys Spyglass linting scripts in the hardware/spyglass. Run make lint in the hardware folder, with a specific MemPool configuration, to run the tests associated with the lint_rtl target.

## Publications

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
```
@INPROCEEDINGS{9912071,
  author={Perotti, Matteo and Cavalcante, Matheus and Wistoff, Nils and Andri, Renzo and Cavigelli, Lukas and Benini, Luca},
  booktitle={2022 IEEE 33rd International Conference on Application-specific Systems, Architectures and Processors (ASAP)},
  title={A “New Ara” for Vector Computing: An Open Source Highly Efficient RISC-V V 1.0 Vector Processor Design},
  year={2022},
  volume={},
  number={},
  pages={43-51},
  doi={10.1109/ASAP54787.2022.00017}}
```
