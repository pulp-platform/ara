# Ara

Ara is a vector unit working as a coprocessor for the CVA6 core.
It supports the RISC-V Vector Extension, [version 0.9](https://github.com/riscv/riscv-v-spec/releases/tag/0.9).

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

Ara requires a RISC-V GCC toolchain capable of understanding the vector extension, version 0.9.x.

To build this toolchain, run the following command in the project's root directory.

```bash
# Build the GCC toolchain
make toolchain
```
