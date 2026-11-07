# Integer extension versus an older destination load

Ara main `34bd3bc152421b4601a7bf3d6e8e91ffb545c99e`, two lanes,
VLEN=2048. The test uses the official runtime, `ara_tb`, CVA6, and locked
dependencies. It has no SoC integration or private software dependency.

Each case loads v8, v16, and v24 with `vl4re8.v`, then immediately executes
an integer extension into v24. It checks every destination element, all
four memory regions' guards, VL, and vstart. Four separate cases cover
zero/sign extension with VF4/e32 and VF8/e64 at m4 and VLMAX.

| Case | Main errors | Fixed errors |
| --- | ---: | ---: |
| `vzext.vf4` | 224 | 0 |
| `vsext.vf4` | 224 | 0 |
| `vzext.vf8` | 120 | 0 |
| `vsext.vf8` | 120 | 0 |

Both versions execute the same ELF. It makes 1037 checks. Main returns
tohost=1 and finishes at 121.2165 us. The patch returns tohost=0 and finishes
at 118.7655 us. No HDL deadline is reached. VCS W-2024.09-SP1 wall times
were 17.47 s and 16.74 s. No performance claim follows from these runs.

The existing requester protocol permits one source read for every two
older writes. VF4/VF8 extensions can produce four/eight result writes per
source read. The new result can therefore reach v24 before the older load
finishes. The patch waits for the existing dependency bits to clear for
these four widening conversions. This also conservatively delays their
RAW and WAR dependencies. Other request types retain the existing protocol.

RVV 1.0 section 11.3 specifies zero/sign extension from SEW/4 or SEW/8 to
SEW. The scalar byte formula in the test computes this result independently.
The test uses disjoint, aligned source and destination groups.

Use the official `make -C hardware checkout` dependency setup first. Keep
`Bender.lock` unchanged. The CVA6 HPDcache submodule is
`04de80896981527c34fbbd35d7b1ef787a082d7c`. Build the application from the
Ara checkout:

```sh
LLVM_ROOT=/path/to/llvm-20.1.0
make -C apps config=2_lanes LLVM_INSTALL_DIR="$LLVM_ROOT" \
  LLVM_FLAGS="--target=riscv64-unknown-elf --sysroot=$LLVM_ROOT/riscv64-unknown-elf -isystem $LLVM_ROOT/riscv64-unknown-elf/include -march=rv64gcv_zfh_zvfh -mabi=lp64d -mno-relax -fuse-ld=lld --rtlib=compiler-rt -L$LLVM_ROOT/riscv64-unknown-elf/lib" \
  LLVM_V_FLAGS="-fno-vectorize -fno-slp-vectorize -mno-implicit-float" \
  bin/ext_hazards
```

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
  +PRELOAD=/absolute/path/to/frozen/ext_hazards.elf > run.log 2>&1
```

The two bounds are limits, not measured run times. Require all four
`EXT_CASE` lines, `EXT_DONE cases=4 checks=1037 errors=0`, tohost=0,
normal `$finish`, and no assertion or runtime error. A zero process return
does not establish success. Each parallel run needs its own parent and
working directory because `ara_tb` also creates `../gold_results.txt`.

The patched RTL also passes the unmodified official `vsext`, `vzext`, and
`vwmul` tests. Both RTL versions pass VCS analysis/elaboration. Effective
`+lint=all` reports the same 427 diagnostics after source-path and line
normalization. Real full-port requester wrappers pass Design Compiler
analysis, elaboration, link, and `compile -no_map`: zero latches and
756/765 flip-flops. `check_design` and loop checks pass. Generic internal
operators remain unmapped. This is a structural check, with no cell-library
mapping, timing closure, or other lane/configuration claim.

The RTL keeps the original authors and Solderpad license. The test has an
Apache-2.0 SPDX identifier. The test, patch adaptation, and this explanation
were prepared with AI assistance and checked against actual simulation data.
