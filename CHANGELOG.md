# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## 0.6.0 - 2020-02-24

### Added

- Support for a coherent mode between Ara and Ariane
  - Snoop AW channel from Ara to L2
  - Invalidate Ariane's L1 cache sets accordingly
  - Coherent mode can be toggled together with consistent mode using the LSB of CSR 0x702
- Hardware support for:
  - Vector single-width floating-point add/subtract instructions (vfadd, vfsub, vfrsub)
  - Vector single-width floating-point multiply instructions (vfmul)
  - Vector single-width floating-point divide instructions (vfdiv)
  - Vector single-width floating-point fused multiply-add instructions (vfmacc, vfmadd)
- Software implementation of a floating-point matrix multiplication kernel

### Changed

- Ariane's data cache is active by default
- The matrix multiplication kernel achieves better performance
  - It reports the performance and the utilization for several matrix sizes

## 0.5.0 - 2020-02-14

### Added

- Hardware support for:
  - Vector single-width integer divide instructions (vdivu, vdiv, vremu, vrem)
  - Vector integer comparison instructions (vmseq, vmsne, vmsltu, vmslt, vmsleu, vmsle, vmsgtu, vmsgt)
  - Vector carry-out of add-with-carry and subtract-with-borrow instructions (vmadc, vmsbc)
- Runtime measurement functions
- Consistent mode which orders scalar and vector loads/stores.
  - Conservative ordering without address comparison
  - Consistent mode is enabled per default, can be disabled by clearing the LSB of CSR 0x702.

### Fixed

- Ariane's accelerator dispatcher module was rewritten, fixing a bug where instructions would get skipped.
- The Vector Store unit takes the EEW of the source vector register into account to shuffle the elements before writing them to memory.

### Changed

- Vector mask instructions (vmand, vmnand, vmandnot, vmxor, vmor, vmnor, vmornot, vmxnor) no longer require the non-compliant constraint that the vector length is divisible by eight.

## 0.4.0 - 2020-02-04

### Added

- Hardware compilation with Verilator
- Software implementation of a matrix multiplication kernel

### Changed

- The `riscv_tests_simc` Makefile target was deprecated. The riscv-tests are now run with the Verilated design, which can be called through the `riscv_tests_simv` Makefile target.
- The operand queues now take as a parameter the type conversions they support (currently, `SupportIntExt2`, `SupportIntExt4`, and `SupportIntExt8`)
- The Vector Multiplier unit now has independant pipelines for each element width.

## 0.3.0 - 2020-01-28

### Added

- Hardware support for:
  - Vector single-width integer multiply instructions (vmul, vmulh, vmulhu, vmulhsu)
  - Vector single-width integer multiply-add instructions (vmacc, vnmsac, vmadd, vnmsub)
  - Vector integer add-with-carry/subtract-with-borrow instructions (vadc, vsbc)
  - Vector widening integer multiply instructions (vwmul, vwmulu, vwmulsu)
  - Vector widening integer multiply-add instructions (vwmaccu, vwmacc, vwmaccsu, vwmaccus)

### Changed

- Explicit scan chain signals added to the lane's and Ara's interfaces

### Fixed

- Miscellaneous fixes for compatibility with Synopsys DC
- Send the correct bits of the address to the Vector Register File's banks
- Correctly calculate the initial address of each vector register in the VRF

## 0.2.0 - 2020-01-22

### Added

- Hardware support for:
  - Bit-shift instructions (vsll, vsrl, vsra)
  - Vector widening integer add/subtract (vwadd, vwaddu, vwsub, vwsubu)
  - Vector integer extension (vzext, vsext)
  - Vector integer merge and move instructions (vmerge, vmv)
  - Vector narrowing integer right shift instructions (vnsrl, vnsra)

### Changed

- Bender updated to version 0.21.0

### Fixed

- CVA6's forwarding mechanism of operand B for accelerator instructions

## 0.1.0 - 2020-01-06

### Added

- Hardware support for:
  - Vector configuration instructions (vsetvl/vsetvli)
  - Unit-strided vector loads and vector stores
  - Basic arithmetic and logic instructions (vand, vor, vxor, vadd, vsub, vrsub, vmin-u, vmax-u)
  - Predicated instructions through a mask unit
  - Vector mask instructions (vmand, vmnand, vmandnot, vmor, vmnor, vmornot, vmxor, vmxnor)
  - Length multipliers

- Implementation of a synthesizable Ara SoC top-level

- Software support for RISC-V Vector code

- Continuous integration tests through riscv-tests executed both with Spike and on Ara
