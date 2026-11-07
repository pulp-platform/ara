# Active nonzero vstart arithmetic

With VL=4 and vstart=1, current Ara main executes `vadd.vv` and
`vsext.vf4` but overwrites destination element zero. That prestart element
must retain its previous value. RVV 1.0 section 3.7 permits an
implementation to reject a vstart value that it cannot produce for that
instruction. It does not permit changing prestart elements.

The dispatcher patch rejects active nonzero vstart for VADD.vv/vx/vi and
the six integer extensions. It leaves the existing vstart>=VL no-write
path in place. It adds no restart execution capability and changes no
load/store or CSR interface. The test checks VADD.vv and VSEXT.vf4 with
vstart=0, 1, and VL. Source loads finish before each target, so this test
does not depend on the separate extension WAW fix.

The software accepts either correct execution from the requested start or
a precise illegal-instruction exception. A rejection must report cause 2,
the exact target instruction in mtval, and the original vstart. It must
leave the complete destination unchanged. The handler then clears vstart
and resumes after the four-byte target. It rejects unexpected traps.

| Official RTL | Six cases | Result |
| --- | --- | --- |
| main `34bd3bc152421b4601a7bf3d6e8e91ffb545c99e` | 54 checks | Two prestart errors, no traps, tohost=1 |
| main plus this dispatcher patch | 62 checks | Zero errors, two exact cause-2 traps, tohost=0 |

The same ELF runs on both versions. Eight additional checks run only when
the two traps occur. Normal-start and empty-body controls pass on both
versions. Both runs finish normally before the finite 20 ms HDL and
600 s wall-clock bounds.

Use the official `make -C hardware checkout` setup and leave Bender.lock
unchanged. Build with the existing application entry:

```sh
LLVM_ROOT=/path/to/llvm-20.1.0
make -C apps config=2_lanes LLVM_INSTALL_DIR="$LLVM_ROOT" \
  LLVM_FLAGS="--target=riscv64-unknown-elf --sysroot=$LLVM_ROOT/riscv64-unknown-elf -isystem $LLVM_ROOT/riscv64-unknown-elf/include -march=rv64gcv_zfh_zvfh -mabi=lp64d -mno-relax -fuse-ld=lld --rtlib=compiler-rt -L$LLVM_ROOT/riscv64-unknown-elf/lib" \
  LLVM_V_FLAGS="-fno-vectorize -fno-slp-vectorize -mno-implicit-float" \
  bin/active_vstart
```

Freeze that ELF for the original/patched comparison. For each checkout,
use a separate VCS build and run directory:

```sh
ARA_ROOT=$PWD
BUILD_DIR="$PWD/build-active-vstart"
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
  +PRELOAD=/absolute/path/to/frozen/active_vstart.elf > run.log 2>&1
```

Require all six `VSTART_CASE` lines, the complete `VSTART_DONE` summary,
tohost=0, normal `$finish`, and no unexpected assertion or runtime error.
Expected trap traces for the two rejected targets are part of this test.
The bounds are limits, not run times. Give each parallel run a separate
parent because ara_tb also creates `../gold_results.txt`.

Validation uses 2 lanes/VLEN2048, the official ara_tb and real CVA6, locked
dependencies, LLVM 20.1.0, and VCS W-2024.09-SP1. Patched RTL passes the
unmodified official vadd, vsext, vzext, and vwmul tests. Both dispatcher
versions pass real full-port Design Compiler analysis, elaboration, link,
and generic `compile -no_map`, with 738 flip-flops and zero latches.
Design and loop checks pass. Effective VCS lint has the same 427
diagnostics. No technology mapping or timing closure was performed.
The direct nonzero-start probes cover the two stated instruction forms,
not all SEW/LMUL/opcode combinations.

The RTL retains the original authors and Solderpad license. The new
software has an Apache-2.0 SPDX identifier. The patch, test, and explanation
were prepared with AI assistance.
