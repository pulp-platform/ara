# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fix typo on the build instructions of the README

### Added

- `benchmarks` app to benchmark Ara
- CI task to create roofline plots of `imatmul` and `fmatmul`, available as artifacts
- Vector floating-point compare instructions (`vmfeq`, `vmfne`, `vmflt`, `vmfle`, `vmfgt`, `vmfge`)
- Vector single-width floating-point/integer type-convert instructions (`vfcvt.xu.f`, `vfcvt.x.f`, `vfcvt.rtz.xu.f`, `vfcvt.rtz.x.f`, `vfcvt.f.xu`, `vfcvt.f.x`)
- Vector widening floating-point/integer type-convert instructions (`vfwcvt.xu.f`, `vfwcvt.x.f`, `vfwcvt.rtz.xu.f`, `vfwcvt.rtz.x.f`, `vfwcvt.f.xu`, `vfwcvt.f.x`, `vfwcvt.f.f`)
- Vector narrowing floating-point/integer type-convert instructions (`vfncvt.xu.f`, `vfncvt.x.f`, `vfncvt.rtz.xu.f`, `vfncvt.rtz.x.f`, `vfncvt.f.xu`, `vfncvt.f.x`, `vfncvt.f.f`)

### Changed

- Add spill register at the lane edge, to cut the timing-critical interface between the Mask unit and the VFUs
- Increase latency of the 16-bit multiplier from 0 to 1 to cut an in-lane timing-critical path

### Changed

- Widen CVA6's cache lines
- Implement back-to-back accelerator instruction issue mechanism on CVA6

## 2.1.0 - 2021-07-16

### Fixed

- Fix calculation of `vstu`'s vector length
- Fix `vslideup` and `vslidedown` operand's vector length trimming
- Mute mask requests on idle lanes
- Mute instructions with vector length zero on the respective `lane_sequencer` and `operand_requester`
- Fix `simd_div`'s offset calculation
- Delay acknowledgment of memory requests if the `axi_inval_filter` is busy

### Added

- Format source files in the `apps` folder with clang-format by running `make format`
- Support for the `2_lanes`, `8_lanes`, and `16_lanes` configurations, besides the default `4_lanes` one

### Changed

- Compile Verilator and Ara's verilated model with LLVM, for a faster compile time.
- Verilator updated to version v4.210.
- Verilation is done with a hierarchical verilation flow
- Replace `ara_soc`'s LLC with a simple main memory
- Reduce number of words on the main memory, for faster Verilation
- Update `common_cells` to v1.22.1
- Update `axi` to v0.29.1

## 2.0.0 - 2021-06-24

### Added

- Script to align all the elf sections to the AXI Data Width (the testbench requires it)
- RISC-V V intrinsics can now be compiled
- Add support for `vsetivli`, `vmv<nr>r.v` instructions
- Add support for strided memory operations
- Add support for stores misaligned w.r.t. the AXI Data Width

### Changed

- Alignment with lowRISC's coding guidelines
- Update Ara support for RISC-V V extension to V 0.10, with the exception of the instructions that were already missing
- Replace toolchain from GCC to LLVM when compiling for RISC-V V extension
- Update toolchain and SPIKE support to RISC-V V 0.10
- Patches for GCC and SPIKE are no longer required
- Ara benchmarks are now compatible with RISC-V V 0.10

### Fixed

- Fix `vrf_seq_byte` definition in the Load Unit
- Fix check to discriminate a valid byte in the VRF word, in the Load Unit
- Fix `axi_addrgen_d.len` calculation in the Address Generation Unit
- Correctly check whether the generated address corresponds to the vector load or the store unit
- Typos on the ChangeLog's dates
- Remove unwanted latches in the `addrgen`, `simd_div`, `instr_queue`, and `decoder`
- Fix `vl == 0` memory operations bug. Ara correctly tells Ariane that the memory operation is over

## 1.2.0 - 2021-04-12

### Added

- Hardware support for:
  - Vector slide instructions (vslideup, vslide1up, vfslide1up, vslidedown, vslide1down, vfslide1down)
- Software implementation of a integer 2D convolution kernel
- CI job to check the conv2d execution on Ara

### Fixed

- Removed dependency to a specific gcc g++ version in Makefile
- Arithmetic and memory vector instructions with `vl == 0` are considered as a `NOP`
- Increment bit width of the vector length type (`vlen_t`), accounting for vectors whose length is `VLMAX`
- Fix vector length calculation for the `MaskB` operand, which depends on `vsew`
- Fix typo on the `vrf_pnt` updating logic at the Mask Unit
- Update README to highlight dependency with Spike
- Update Bender's link dependency to the public CVA6 repository
- Retrigger the `compile` module if the ModelSim compilation did not succeed

### Changed

- The `encoding.h` in the common Ara runtime is now a copy from the `encoding.h` in the Spike submodule

## 1.1.1 - 2021-03-25

### Added

- Parametrization for FPU and FPU-specific formats support, through the `FPUSupport` ara_soc parameter

## 1.1.0 - 2021-03-18

### Added

- GitHub Actions-based CI
- Hardware support for:
  - Vector single-width floating-point fused multiply-add instructions (vfnmacc, vfmsac, vfnmsac, vfnmadd, vfmsub, vfnmsub)
  - Vector floating-point sign-injection instructions (vfsgnj, vfsgnjn, vfsgnjx)
  - Vector widening floating-point add/subtract instructions (vfwadd, vfwsub, vfwadd.w, vfwsub.w)
  - Vector widening floating-point multiply instructions (vfwmul)
  - Vector widening floating-point fused multiply-add instructions (vfwmacc, vfwnmacc, vfwmsac, vfwnmsac)
  - Vector floating-point merge instruction (vfmerge)
  - Vector floating-point move instruction (vfmv)

### Changed

- Contributing guidelines updated to include commit message and C++ code style guidelines

## 1.0.0 - 2021-03-10

### Added

- Hardware support for:
  - Vector single-width floating-point add/subtract instructions (vfadd, vfsub, vfrsub)
  - Vector single-width floating-point multiply instructions (vfmul)
  - Vector single-width floating-point fused multiply-add instructions (vfmacc, vfmadd)
  - Vector single-width floating-point min/max instructions (vfmin, vfmax)
- Software implementation of a floating-point matrix multiplication kernel

## 0.6.0 - 2021-02-24

### Added

- Support for a coherent mode between Ara and Ariane
  - Snoop AW channel from Ara to L2
  - Invalidate Ariane's L1 cache sets accordingly
  - Coherent mode can be toggled together with consistent mode using the LSB of CSR 0x702

### Changed

- Ariane's data cache is active by default
- The matrix multiplication kernel achieves better performance
  - It reports the performance and the utilization for several matrix sizes

## 0.5.0 - 2021-02-14

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

## 0.4.0 - 2021-02-04

### Added

- Hardware compilation with Verilator
- Software implementation of a matrix multiplication kernel

### Changed

- The `riscv_tests_simc` Makefile target was deprecated. The riscv-tests are now run with the Verilated design, which can be called through the `riscv_tests_simv` Makefile target.
- The operand queues now take as a parameter the type conversions they support (currently, `SupportIntExt2`, `SupportIntExt4`, and `SupportIntExt8`)
- The Vector Multiplier unit now has independant pipelines for each element width.

## 0.3.0 - 2021-01-28

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

## 0.2.0 - 2021-01-22

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

## 0.1.0 - 2021-01-06

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
