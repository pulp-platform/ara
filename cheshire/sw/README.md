# Build software for Cheshire Ara

Ara should be instantiated as a submodule of Cheshire. This means that the Ara repo should be downloaded through `bender checkout` from the Cheshire directory. Then, Ara's path can be retrived using `bender path ara`.

```bash
git clone git@github.com:pulp-platform/cheshire.git
cd cheshire
git checkout ${COMMIT}
bender checkout
ARA_ROOT=$(bender path ara)
cd ${ARA_ROOT}
```
## Operating System

### Build an RVV-ready Linux Image with vector kernels

1) Compile kernels to be run on the FPGA under Linux (this will also install the buildroot toolchain)

```bash
cd ${ARA_ROOT}/cheshire/sw

# Choose a kernel from the apps directory
kernel=fmatmul
make ${kernel}-linux
```

2) Generate the Linux image (containing all the RVV kernels previously built)

```bash
# Generate the Linux img
cd ${ARA_ROOT}/cheshire/sw
make linux-img
```

### Compile RiVec software

To compile a RiVec application, follow the following steps.

Be sure the rivec-bmarks have been initialized:

```bash
make -C ${ARA_ROOT}/apps/rivec-bmarks
```

Then, set up the application and then compile it for scalar and vector.

For example, for `_axpy`:

```bash
make rivec-bmark-_axpy
```

To build all the rivec apps:

```bash
make rivec-all
```

This command also moves large input dataset files from RiVec into the `rootfs` directory. If the payload size needs to be limited, please manually remove all the largest input files from `cva6-sdk/rootfs` and `cva6-sdk/buildroot/output/target`.

To automatically prune the largest input datasets, execute:

```bash
make rivec-all-small
```

## Bare-metal

Compile the source files with the vector extension support enable:

```bash
make chs-sw-all
```

This command will also copy the necessary dependencies to `sw/tests` and enable the vector extension at compile time.

## Notes

If the version of the default host compiler is too low, the build of the buildroot toolchain can fail.
Host `gcc` and `g++` version 11.2.0 work.

For IIS builds:
```
make [linux_img, ${kernel}-linux] TOOLCHAIN_SUFFIX=-11.2.0
```
