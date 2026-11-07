# Legal integer-extension overlap with inactive destination elements

Tested base: Ara main `34bd3bc152421b4601a7bf3d6e8e91ffb545c99e`.
Configuration: two lanes, VLEN=2048, official `ara_tb`, CVA6, locked dependencies.

The test places an EW8 source in v11, the high register of the EW32/m4
destination v8-v11. It executes `vzext.vf4` or `vsext.vf4` with VL=255.
Two masked cases use alternating or all-zero mask bits. VL=0 and
vstart=VL controls require the complete destination to remain unchanged.
All cases use tu/mu. The independent byte formula checks all 256 elements,
three regions' guards, VL, and vstart.

The official [2024-04-11 ISA manual](https://docs.riscv.org/reference/isa/v20240411/_attachments/riscv-unprivileged.pdf)
contains RVV 1.0. Its Vector Operands section (standalone section 5.2)
permits this widening overlap because the source EMUL is at least one and
occupies the highest destination registers. It makes different-EEW overlap
mask- and tail-agnostic regardless of vta/vma. Section 3.4.3 defines the
allowed old-value or all-ones choices for agnostic elements. The older v1.0
repository tag lacks this explicit overlap clarification. This test uses the
published 2024 rule. Active results remain exact. No-body controls accept
only old values.

| Case | Main errors | Candidate errors |
| --- | ---: | ---: |
| Zero extension, unmasked | 1 | 0 |
| Sign extension, unmasked | 1 | 0 |
| Zero extension, alternating mask | 32 | 0 |
| Zero extension, all mask bits clear | 64 | 0 |
| VL=0 | 0 | 0 |
| vstart=VL | 0 | 0 |

Both RTL versions run the same ELF, SHA256
`99562c0863d2333a4af0983e1d98766d006181456915d627f15ce8e04bef76bd`.
The test makes 1842 checks. Main finishes normally at 201.0115 us with 98
errors and tohost=1. The candidate finishes at 199.7635 us with zero errors
and tohost=0. Wall times were 28.27 s and 28.48 s. Neither reaches its deadline.

Main updates the destination EEW for the extension but does not rewrite
inactive elements that still use the old source encoding. A later whole
register store therefore exports the wrong inactive element values.
The candidate writes these elements as all ones under the original instruction
ID. It retains the active operand and mask lengths. It waits for older work,
then waits for the original request handshake and all completion writes.
The no-body path creates neither reshuffles nor fill writes.

The attached passive observer checks four accepted/completed fill operations
per lane, 256 full-byte-enable VRF writes per lane, and no late writes,
unknown control, or open fill ID. It never drives or forces the DUT.
It reports zero errors on this test. Compile it after the generated source
list, and add `-top extension_observer` to VCS elaboration. The ordinary
regressions use the same production RTL without this case-specific observer.

The test exports through scalar x5 (`t0`). An earlier export used x8 as its
base and exposed a separate generic reshuffle-mask name collision with vector
v8. Its original input and failures remain recorded. The explicit base only
isolates that export defect. The expected vector values are unchanged.
This patch does not change that separate whole-register-store path.

Use the official `make -C hardware checkout` dependency setup first. Keep
`Bender.lock` unchanged. The CVA6 HPDcache submodule is
`04de80896981527c34fbbd35d7b1ef787a082d7c`. Build the application from the
Ara checkout:

```sh
LLVM_ROOT=/path/to/llvm-20.1.0
make -C apps config=2_lanes LLVM_INSTALL_DIR="$LLVM_ROOT" \
  LLVM_FLAGS="--target=riscv64-unknown-elf --sysroot=$LLVM_ROOT/riscv64-unknown-elf -isystem $LLVM_ROOT/riscv64-unknown-elf/include -march=rv64gcv_zfh_zvfh -mabi=lp64d -mno-relax -fuse-ld=lld --rtlib=compiler-rt -L$LLVM_ROOT/riscv64-unknown-elf/lib" \
  LLVM_V_FLAGS="-fno-vectorize -fno-slp-vectorize -mno-implicit-float" \
  bin/extension_tail
```

For the candidate-only passive checks, run this command after `bash compile.sh`:

```sh
vlogan -full64 -sverilog -timescale=1ns/1ps -assert svaext \
  "$ARA_ROOT/apps/extension_tail/observer.sv"
```

Add `-top extension_observer` to the VCS elaboration command below.
Use the normal command without this observer on main and on ordinary regressions.

Freeze that ELF and use it on both RTL versions. Generate a distinct VCS
build directory for each checkout:

```sh
ARA_ROOT=$PWD
BUILD_DIR="$PWD/build-ext-hazards"
SPIKE_ROOT=/path/to/spike
mkdir "$BUILD_DIR"
bender --local --git-submodules false script vcs \
  -t rtl -t cv64a6_imafdcv_sv39 \
  -t tech_cells_generic_include_tc_sram -t tech_cells_generic_include_tc_clk \
  -t exclude_first_pass_decoder -t ara_test -t cva6_test \
  -D NR_LANES=2 -D VLEN=2048 -D ARIANE_ACCELERATOR_PORT=1 \
  --vlogan-args="-full64 -assert svaext +v2k -timescale=1ns/1ps" \
  > "$BUILD_DIR/compile.sh"
cd "$BUILD_DIR"
bash compile.sh
vcs -full64 -sverilog -timescale=1ns/1ps -assert svaext -top ara_tb \
  "$ARA_ROOT/hardware/tb/dpi/elfloader.cc" \
  -CFLAGS "-I$SPIKE_ROOT/include" -o simv
mkdir -p run/work
cd run/work
printf 'run 20ms\nquit\n' > control.tcl
timeout 600 "$BUILD_DIR/simv" -ucli -i control.tcl \
  +PRELOAD=/absolute/path/to/frozen/extension_tail.elf > run.log 2>&1
```

The two bounds are limits, not measured run times. Require all six
`TAIL_CASE` lines, `TAIL_DONE cases=6 checks=1842 errors=0`, tohost=0,
normal `$finish`, and no assertion or runtime error. A zero process return
does not establish success. Each parallel run needs its own parent and
working directory because `ara_tb` also creates `../gold_results.txt`.


The candidate passes unmodified official vadd, vsext, vzext, vwmul, vmv,
vmerge, and vfmvfs tests. VCS analysis and elaboration pass. Effective
`+lint=all` has the same 427 normalized diagnostics on both versions.
Design Compiler checks the real dispatcher, Ara sequencer, lane sequencer,
and VALU through full-port wrappers. Both versions pass analysis, elaboration,
link, `compile -no_map`, design checks, and loop checks with zero latches.
The candidate dispatcher has 741 flip-flops versus 738 on main. The other
three candidate results reuse byte-identical module/type inputs from the
combined experiment. All source SHA256 values were checked before reuse.
This is a generic structural check, without mapped timing or area results.

The scope is the listed two-lane inputs. It does not establish all six
extension selectors, all legal overlap placements, fault restart, or other
lane counts. The separate source-group scan covered by PR #421 is excluded.
Original RTL authors and licenses remain. The new test and observer use
Apache-2.0. AI assistance was used for adaptation, tests, and this text.
