## Introduction

Ara can be synthesized on a VCU128 FPGA and boot Linux through the Cheshire SoC. This folder provides the necessary targets and flow to build RVV-Linux and deploy Ara on FPGA. To make them work, this repository should be deployed as a submodule of Cheshire.

Our entry point is to generate a custom `add_sources.vcu128.tcl` file with specific Ara targets, copy this file into the Cheshire directory, and then use the default Cheshire compile flow, which will use our provided TCL file

## How to Use

Ara should be instantiated as a submodule of Cheshire. This means that the Ara repo should be downloaded through `bender checkout` from the Cheshire directory. Then, Ara's path can be retrived using `bender path ara`.

```bash
git clone git@github.com:pulp-platform/cheshire.git
cd cheshire
git checkout ${COMMIT}
bender checkout
ARA_ROOT=$(bender path ara)
cd ${ARA_ROOT}
```

## FPGA and OS flow

### LINUX-RVV Kernels
Compile kernels to be run on the FPGA under Linux (this will also install the buildroot toolchain)

```bash
cd ${ARA_ROOT}/cheshire/sw

# Choose a kernel from the apps directory
kernel=fmatmul
make ${kernel}-linux
```

### Generate the Linux IMG
Generate the Linux image (containing all the RVV kernels previously built)

```bash
# Generate the Linux img
cd ${ARA_ROOT}/cheshire/sw
make linux-img

# Generate Cheshire's Linux img
cd ${ARA_ROOT}/cheshire
make ara-chs-image
```

### Generate the FPGA bitstream

```bash
cd ${ARA_ROOT}/cheshire
make ara-chs-xilinx
```

### Flash the Linux image on the SD card

```bash
cd ${ARA_ROOT}/cheshire
make ara-chs-xilinx-flash
```

### Program the bitstream

```bash
cd ${ARA_ROOT}/cheshire
make ara-chs-xilinx-program
```

For more information, see Cheshire's documentation (https://pulp-platform.github.io/cheshire/tg/xilinx).

### Example

Example script to boot Linux on a VCU128 FPGA board. Modify the variables as needed.

There should be an open Hardware Target for the VCU128 board. Moreover, a UART terminal is required.

Note: this script requires `bender`. Also, some Cheshire targets may require an up-to-date RISC-V compiler.

```bash
export CHS_ROOT=$(pwd)/cheshire

# Cheshire commit
# FILL ME
export CHS_HASH=

# Do we need a specific GCC/G++ version to build the buildroot GCC compiler?
HOST_TOOLCHAIN_SUFFIX=

# Which RVV kernels to run under Linux
export RVV_KERNELS="hello_world-linux fmatmul-linux fconv3d-linux jacobi2d-linux fdotproduct-linux"

# FPGA details
# FILL ME
export BOARD="vcu128"
export CHS_XILINX_HWS_URL=
export CHS_XILINX_HWS_PATH=

# Info
echo "Using the VCU128 ${CHS_XILINX_HWS_URL} ${CHS_XILINX_HWS_PATH}"
# Clone Cheshire
echo "Cloning Cheshire"
git clone git@github.com:pulp-platform/cheshire.git
cd ${CHS_ROOT}
git checkout ${CHS_HASH}
# Checkout Ara
echo 'Checkout hardware deps'
bender checkout
export ARA_ROOT=$(bender -d ${CHS_ROOT} path ara)
# Compile RVV kernels
echo 'Install the Linux compiler and compile the LINUX RVV kernels'
make -C ${ARA_ROOT}/cheshire/sw ${RVV_KERNELS} HOST_TOOLCHAIN_SUFFIX=${HOST_TOOLCHAIN_SUFFIX}
# Compile the Linux image
echo 'Compile the Linux image'
make -C ${ARA_ROOT}/cheshire/sw linux-img HOST_TOOLCHAIN_SUFFIX=${HOST_TOOLCHAIN_SUFFIX}
# Generate Cheshire's Linux image
echo 'Generate Cheshire Linux image'
make -C ${ARA_ROOT}/cheshire ara-chs-image BOARD=${BOARD}
# Generate the bitstream
echo 'Generate the bitstream'
make -C ${ARA_ROOT}/cheshire ara-chs-xilinx BOARD=${BOARD}
# Flash the SD with Linux
echo 'Flash the SD with Linux'
make -C ${ARA_ROOT}/cheshire ara-chs-xilinx-flash BOARD=${BOARD} CHS_XILINX_HWS_URL=${CHS_XILINX_HWS_URL} CHS_XILINX_HWS_PATH=${CHS_XILINX_HWS_PATH}
# Program the bitstream
echo 'Program the bitstream'
make -C ${ARA_ROOT}/cheshire ara-chs-xilinx-flash BOARD=${BOARD} CHS_XILINX_HWS_URL=${CHS_XILINX_HWS_URL} CHS_XILINX_HWS_PATH=${CHS_XILINX_HWS_PATH}
```

## Bare-metal flow

### Compile the bare-metal programs in `${ARA_ROOT}/cheshire/sw/src`

```bash
cd ${ARA_ROOT}/cheshire/sw
make chs-sw-all
```

### Generate the FPGA bitstream

```bash
cd ${ARA_ROOT}/cheshire
make ara-chs-xilinx
```

### Program the bitstream

Provided that an Hardware Target is available:

```bash
cd ${ARA_ROOT}/cheshire
make ara-chs-xilinx-program
```

### Run programs on the FPGA
The programs can now be injected in the FPGA via JTAG (OpenOCD + GDB).
For more information, see Cheshire's documentation (https://pulp-platform.github.io/cheshire/tg/xilinx).

## Back-Referencing Explained

Here's how we use back-referencing in our setup:

1.  **Generate Custom TCL File**:

    -   We generate a custom `add_sources.vcu128.tcl` file using the `bender script vivado` command with our specific targets (`-t fpga -t vcu128 -t cv64a6_imafdcv_sv39 -t cva6 --define ARA --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen)`).
    -   This custom TCL file includes all the necessary sources and configurations required for the FPGA synthesis with Cheshire + Ara.

2.  **Copy Custom TCL File**:

    -   The generated custom TCL file is then copied into the Cheshire directory (`$(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl`).

3.  **Invoke Cheshire Compile Flow**:

    -   With the custom TCL file in place, we invoke the Cheshire compile flow by running `make -C $(BACKREF_CHS_ROOT) chs-xilinx-all`.
    -   The Cheshire compile flow target depends on the `add_sources.vcu128.tcl` file, and since we have provided our custom version, it will use ours for the synthesis process.

This method ensures that we can extend and customize the compile flow for our specific needs without modifying the Cheshire repository directly.

## Notes

### Variables
 - ARA_CONFIGURATION: thus far, only Ara with 2 lanes has been tested (ARA_CONFIGURATION=2_lanes).
 - HOST_TOOLCHAIN_SUFFIX: the host GCC and G++ should be sufficiently up to date to build the buildroot cross compiler. For environments that track the program version with suffixes, this variable helps choose the correct host compiler version. Use this variable only if needed when installing the buildroot toolchain.
 - BOARD: name of the board, e.g., `vcu128`.
 - CHS_XILINX_HWS_URL: URL of the FPGA, if connected to the net.
 - CHS_XILINX_HWS_PATH: physical PATH of the FPGA.