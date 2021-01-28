# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
