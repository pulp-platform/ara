# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

 - Avoid corner-case in which the sequencer issues the same instruction multiple times when two units become non-ready at the same time
 - The lane sequencer now calculates the correct number of elements to be requested by the `MASKU` operand requesters
 - When the instruction queue of the SLDU is not empty, read from it to update the commit counter, and not from the incoming request
 - Masked operations now target the MASKU as well for the issue checks in the main sequencer
 - The granularity of the issue checks/gold tickets is now at a PE level
 - Avoid losing hazard-related information in the pipeline between the main sequencer and the operand requesters
 - Fix anticipated grant bug from operand requester to LDU, SLDU, MASKU, because of the stream registers. Now, the three units wait for a final true grant before commiting
 - The mask unit does not require synchronized lanes anymore to commit an instruction
 - MASKU does not wait anymore for valid incoming data from inactive lanes
 - Fix corner-case comparison in MASKU to provide the expected behavior
 - Fix MaskB-queue vector length in the lane sequencer
 - VALU cleans up the partial result of a reduction when no more needed
 - VALU can step from normalOp->reduction and vice-versa without issues
 - VALU's counters can now count bits when operating on mask vectors
 - Fix the vector length for mask instructions that run on the VALU/VMFPU
 - Don't let indexed memory operations interfere with the reductions in MASKU
 - Enforce strict in-order execution of FPU operations in VMFPU
 - Fixed AXI-inval-filter policy for D$ lines invalidation upon vector stores that are misaligned w.r.t. the D$ line width
 - Fix lane sequencer checks for floating-point comparisons
 - Fix synthesis error occuring due to the continuous assignmnet in the always block of mask unit
 - Fix wrong variable in `vmerge` and `vmv` `riscv-tests`
 - Re-introduce WAIT_STATE to avoid hazards when changin LMUL
 - Fix the PEs-ready signals related conditions in the main sequencer
 - Fix misaligned memory operations with more than 255 beats (>= 256 beats)
 - Fix stripmining condition in dispatcher
 - CVA6 tracks writes to floating-point scalar registers by the accelerator
 - Fixed de-synch bug in vector-FPU
 - Fix masked VSLIDEUP. Use only the mask bits with index higher than the stride
 - Fix SLDU issue_counter modification upon new VSLIDEUP incoming instruction
 - Fix whole-register-move destination register re-encoding
 - `vslide1up` always writes the scalar element in `vd`
 - Don't trim `vslide1up` counters since it always writes the scalar element
 - Wait for the current reduction to be over to execute the next VALU instruction, also when reduction workload is unbalanced and some lanes are only a pass-through
 - Reshuffle the source registers vs when an in-lane operation operates on element with vsew != eew_q[vs]
 - Fix the data target for `.spike` app compilations
 - `make -C apps clean` performs a deeper clean of the temporary object files
 - Fix riscv-isa-sim patch and bump pointer to riscv-isa-sim submodule
 - Fix VALU issue_counter initialization for mask logical operations
 - `vslideup` instructions that have `stride >= vl_q` have no effect
 - `benchmark.sh` keeps into account the number of lanes during program compilation
 - Fix typo in `performance.py` related to `fconv2d`
 - Fix lmul checks on `vs1` for conversion instructions
 - Fix `eew_vs1` for widening instructions
 - Fix cleaning of the accumulator after partial reduction in `valu`
 - De-parametrize FFT on the data-type
 - New reductions should start only when the previous operation is over
 - Prevent VMFPU from acknowledging the opqueues when their issue is over
 - Operand requesters sanitize partial operands during a reduction
 - Fix load/store-complete signals to CVA6
 - Remove latches/repeated-signals from `masku`
 - Reshuffle all the registers of a register group that have `eew_q != eew_d` when `LMUL > 1`
 - `VLXE` and `VSXE` need to wait that the SlideAddrGenA opreq is free before being issued by the lane sequencer to the operand requester stage
 - Do not trap instructions with no operands in the main sequencer
 - Commit a reduction only after a grant from the VRF
 - Solve duplicate verify function in `roi_align`
 - Don't let the lanes sample more than once the same instruction when the workload is unbalanced and the instruction stalls in the main sequencer
 - Don't mute instructions on mask vectors in the lane sequencer when `vl == 0` in that lane
 - Remove unintentional latches from `valu`, `simd_mul`, `lane_sequencer`
 - Fix `vxsat` CSR update in `dispatcher`
 - Fix parameter passing through the hierarchy for fixed point support
 - Decouple `cmdBuffer` and `dataBuffer` depths in opQueues
 - Avoid handshaking wrong results in VMFPU
 - Fix eew reshuffle for mask logical operations
 - Fix eew reshuffle for `vmv.v.v` operations
 - Remove timing loop between `vmfpu` and `operand_requesters`
 - Solve some of the Warnings from SpyGlass run
 - Fix masku handshake. All the lanes should handshake together in input
 - Start solving `sldu` counter widths warnings
 - Fix `vslideup` wrong counter trimming
 - Reset gating registers before the integer multipliers in `vmfpu`
 - Fix narrowing for `vnclip` and `vnclipu`

### Added

 - The sequencer can issue instructions to non-full units even if the other units are full
 - Vector indexed unordered/ordered load (`vluxei8`, `vluxei16`, `vluxei32`, `vluxei64`, `vloxei8`, `vloxei16`, `vloxei32`, `vloxei64`)
 - Vector indexed unordered/ordered stores (`vsuxei8`, `vsuxei16`, `vsuxei32`, `vsuxei64`, `vsoxei8`, `vsoxei16`, `vsoxei32`, `vsoxei64`)
 - Vector integer reductions (`vredsum`, `vredmaxu`, `vredmax`, `vredminu`, `vredmin`, `vredand`, `vredor`, `vredxor`, `vwredsumu`, `vwredsum`)
 - Introduce the global hazard table in the main sequencer, to provide up-to-date information to the operand requesters about the status of the different dependant instructions
 - Integer and Floating-Point scalar move instructions (`vmv.x.s`, `vmv.s.x`, `vmv.f.s`, `vmv.s.f`)
 - Add support for `apps` simulation with `spike`
 - Support for vector single-width floating-point reduction instructions: `vfredusum`, `vfredosum`, `vfredmin`, `vfredmax`
 - Support for Vector widening floating-point reductions: `vfwredusum`, `vfwredosum`
 - fdotproduct benchmark to evaluate dot products with reductions
 - fredsum benchmark to evaluate fp-reductions
 - riscv-tests for `vfredusum`, `vfredosum`, `vfredmin`, `vfredmax`, `vfwredusum`, `vfwredosum`
 - Support for vector single-width fractional multiply with rounding and saturation instruction: `vsmul`
 - Support for vector single-width scaling shift instructions: `vssra`, `vssrl`
 - Support for vector narrowing fixed-point clip instructions: `vnclip`, `vnclipu`
 - Vector floating-point classify instruction (`vfclass`)
 - Vector floating-point divide instructions (`vfdiv`, `vfrdiv`)
 - Vector floating-point square-root instruction (`vfsqrt`)
 - Add simple test for source registers reshuffle, when VSEW != EEW_vs
 - Add support for ideal-dispatcher simulation
 - Add compile-time garbage-collection to strip unused functions out and decrease the memory footprint of the binary
 - Add benchmarking capability with the ideal-dispatcher system + performance plotting. The support is limited to simluation with QuestaSim only
 - Plot jacobi2d performance
 - Plot dropout performance
 - Add FFT benchmark and print its performance
 - Add DWT benchmark and print its performance
 - Add fp-exp, fp-cos, fp-log benchmarks from rivec bmark suite + print performance
 - Ideal Dispatcher tracer now supports strided memory operations
 - Add Softmax benchmark and print its performance
 - Add [f]dotproduct apps and benchmarks, and plot their performance
 - Add a specific script to handle [f]dotproduct performance plotting
 - Add a script to benchmark all the applications together locally
 - Add HW cycle counter to better measure runtime cycles with short vectors
 - Add Pathfinder `app` and `benchmark`, and plot its performance
 - Add Roi-Align `app` and `benchmark`, and plot its performance
 - Support for vector mask instructions: `vmsbf`, `vmsof`, `vmsif`, `viota`, `vid`
 - Add support for vector mask population count and find first set bit instructions: `vcpop.m`, `vfirst.m`
 - Add Spyglass linting script
 - Add parametrized support for Fixed-Point math
 - Add optimized ASM version of exp 64-bit
 - Add optimized ASM version of `roi_align`
 - Add support for cache warming before benchmarks
 - Add support to check the results of the ideal dispatcher runs
 - Add HW/SW environment for automatic VCD dumping
 - Support for vector floating-point reciprocal estimate instruction: `vfrec7`
 - Support for vector floating-point reciprocal square-root estimate instruction: `vfrsqrt7`
 - Support for vector narrowing floating-point convert instruction: `vfncvt.rod.f.f`
 - Parametrize `vfrec7`, `vfrsqrt7` and `vfncvt.rod.f.f` support
 - Add guards in the testbench to successfully compile in post-layout simulations
 - Add VCD dumping features to `imatmul`
 - `core_id_i` added to the interface of the system
 - Clock-gate the system bank macros when not used (VRF, D$, I$)
 - Spill register on `sldu` input signals to better isolate the unit

### Changed

 - Fixed-Point instructions were added (`VSADDU`, `VSADD`, `VAADD`, `VAADDU`, `VSSUBU`, `VSSUB`, `VASUB`, `VASUBU`)
 - The main sequencer issues instructions every time the target unit has a non-full instruction queue
 - The main sequencer stalls if the instructions target a lane, and its operand requesters are not ready
 - New instructions enter the main sequencer with a token that marks them as new, and the related counter is updated upon arrival
 - Update `README` with instructions on how to compile convolutions
 - Refactor `benchmark` app
 - Double the testbench memory size
 - Update the `python-requirements` list
 - Remove the assign keyword from the always block of masku.sv
 - Update LLVM to version `15.0.0` (RVV 1.0)
 - Update Spike to version `1.1.1-dev` (RVV 1.0)
 - Update `newlib` from commit 84d068 to 5192d5
 - Ara's dispatcher goes to WAIT_STATE only when the new LMUL is lower than the old one
 - Updated target -march to rv64gcv_zfh_zvfh0p1 to enable half-floats support
 - Halve CVA6's L1 caches to ease backend timing closure
 - Remove CVA6's cache patch from `hardware/patches` (CVA6 is now updated)
 - Increase addrgen queue depth to four, to better hide memory latency
 - The RESHUFFLE state is now iterative and reshuffles all the vector registers that need this operation
 - Performance metrics are now calculated by an external performance.py script, instead of during the program simulation, which just prints out the cycle count
 - 7x7 kernel 2dconvs now support arbitrary vector lengths
 - Default con vlen in the config files is now NR_LANES*1024
 - Optimize jacobi2d in ASM, +align store address
 - Replace `apps/common/script/datagen.sh` with new input data source-of-truth (`apps/common/default_arguments.mk`) during app compilation
 - benchmark.sh can now also benchmark just one app at a time via an input argument
 - Adapt `fdotproduct` to `dotproduct` structure
 - Pre-calculate next-cycle `aligned_start_address` in `addrgen` for timing reasons
 - Add `is_reduct` signal to the operand queues, to gate the neutral value filling
 - The hw-counter can be enabled or disabled via software to work also with an environment with cache warming
 - The dropout vectors are now explicitly memory aligned
 - `matmul` generates data offline like all the other benchmarks
 - Refactor `benchmark.sh` script
 - Update `LLVM` to `16`. This brings faster compilations and a prototype of auto-vectorization (disabled by default here!)
 - All the data-gen scripts generate now random data
 - Patch `riscv-tests` `crt0.S` also before compiling `riscv-tests`
 - Almost align all the vector/matrix sizes in `benchmark.sh`
 - Generate data for `fmatmul` at compile time
 - SIMD multipliers are now power gated
 - Roll-back to Verilator v4.214
 - Parametrize `addrgen` queue depth
 - SIMD-multipliers are now gated singularly depending on VSEW
 - Optimize `pathfinder` kernel
 - Optimize `dwt` kernel
 - Optimize `dotproduct` kernel
 - Optimize `fft` kernel
 - Simplify the reduction engine for both `valu` and `vmfpu`, to avoid spurious valid signals to the `sldu`
 - Fix commit for `dtc` installation (`spike` dependency)
 - Simplify the datapath of the slide unit. The `sldu` supports only powers of two, and cannot slide and reshuffle at the same time. Non-power-of-two slides are now handled with micro operations.

## 2.2.0 - 2021-11-02

### Fixed

- Fix typo on the build instructions of the README
- Fix Gnuplot installation on GitHub's CI
- The number of elements requested by the Store Unit and the Element Requester now depends both on the requested eew and the past `eew` of the vector of the used register
- When the VRF is written and `EMUL > 1`, the `eew` of all the interested registers is updated
- Memory operations can change EMUL when EEW != VSEW
- The LSU now correctly handles bursts with a saturated length of 256 beats
- AXI transactions on an opposite channel w.r.t. the channel currently in use are started only after the completion of the previous transactions
- Fix the number of elements to be requested for a `vslidedown` instruction
- Generate `data.S` files before compiling the programs
- Clean intermediate app object files with `make clean`
- Add a `fence` before stopping the cycle counter, to let the last vector store complete

### Added

- `benchmarks` app to benchmark Ara
- CI task to create roofline plots of `imatmul` and `fmatmul`, available as artifacts
- Vector floating-point compare instructions (`vmfeq`, `vmfne`, `vmflt`, `vmfle`, `vmfgt`, `vmfge`)
- Vector single-width floating-point/integer type-convert instructions (`vfcvt.xu.f`, `vfcvt.x.f`, `vfcvt.rtz.xu.f`, `vfcvt.rtz.x.f`, `vfcvt.f.xu`, `vfcvt.f.x`)
- Vector widening floating-point/integer type-convert instructions (`vfwcvt.xu.f`, `vfwcvt.x.f`, `vfwcvt.rtz.xu.f`, `vfwcvt.rtz.x.f`, `vfwcvt.f.xu`, `vfwcvt.f.x`, `vfwcvt.f.f`)
- Vector narrowing floating-point/integer type-convert instructions (`vfncvt.xu.f`, `vfncvt.x.f`, `vfncvt.rtz.xu.f`, `vfncvt.rtz.x.f`, `vfncvt.f.xu`, `vfncvt.f.x`, `vfncvt.f.f`)
- Vector whole-register move instruction `vmv<nr>`
- Vector whole-register load/store `vl1r`, `vs1r`
- Vector load/store mask `vle1`, `vse1`
- Whole-register instructions are executed also if `vtype.vl == 0`
- Makefile option (`trace=1`) to generate waveform traces when running simulations with Verilator
- Add `fconv3d` kernel, optimized for 7x7 filters
- Optimize `fconv2d` and `iconv2d` kernels for 3x3 filters
- Add convolutions to the `benchmark` app, and print the related roofline plots
- Add corner case test to `vslidedown` instruction

### Changed

- Add spill register at the lane edge, to cut the timing-critical interface between the Mask unit and the VFUs
- Increase latency of the 16-bit multiplier from 0 to 1 to cut an in-lane timing-critical path
- Widen CVA6's cache lines
- Implement back-to-back accelerator instruction issue mechanism on CVA6
- Use https protocol when cloning DTC from main Makefile
- Use https protocol for newlib-cygwin in .gitmodules
- Cut a timing-critical path from Addrgen to Sequencer (1 cycle more to start an AXI transaction)
- Cut a timing-critical path in the `VSTU`, relative to the calculation of the pointer to the `VRF` word received from the lanes
- Create `ara_system` wrapper containing Ara, Ariane, and an AXI mux, instantiated from within Ara's SoC
- Retime address calculation of the `addrgen`
- Push `MASKU` operand muxing from the lanes to the Mask Unit
- Reduce CVA6's default cache size
- Update Verilator to `v4.214`
- Update bender to `v0.23.1`

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
