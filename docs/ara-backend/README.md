# How this branch differs from `main`

This branch is the Ara2 source that the Ara2 physical-implementation backend pins and synthesizes. It is `main` plus the setup used for the AdhAra (NMAra) DAC comparison: the
high-bandwidth system, power windows in the kernels, FP32/FP16 kernel variants with precision
selection, kernels written with the same instruction stream as NMAra, and the `perf_eval` sweep.

Read this file before changing the branch, adding a kernel or rebasing onto `main`. All documents of
this branch live in this directory:

| File | Content |
|---|---|
| `README.md` | this file: every difference from `main`, the conventions, how to add a kernel, how to rebase |
| `perf_eval.md` | the `scripts/perf_eval` throughput and verification sweeps |
| `fpu_latency.md` | the FP-compare latency fix (now on `main` too) and the unfixed FP32 FMA latency issue |

## 1. Origin

- Created from `main` at `11ce9fab` (after PR #553: LLM kernels, fused intrinsic `cos`, CI artifact fix).
- The paper branch `hp/ara-be-64` (commits `014252e8` .. `71108196`, 7 commits) was squash-merged on top,
  then adapted as described below. `hp/ara-be-64` itself stays unchanged as the record of the paper runs.
- The paper's Ara2 netlist was synthesized from `hp/ara-be-64` at `4ca9cd14`, before the compare-latency
  fix. This branch has `main`'s `vmfpu.sv`, see section 3.

## 2. Decisions taken when the branch was made

| Topic | Decision | Why |
|---|---|---|
| `exp`, `log`, `cos` | hoisted versions (`kernel/*_hoist.h`): constants broadcast once before the strip loop | same instruction stream as NMAra's kernels, as in the paper |
| `cos` | hoisted **and fused**: the nine multiply/add pairs of the Cephes `cos` are `vfmacc`/`vfmadd`/`vfnmsac` | the paper's Ara2 `cos` was fused (archived ELF: 3 `vfmacc`, 5 `vfmadd`, 1 `vfnmsac`, 5 `vfmul`, 2 `vfadd`); NMAra's `cos` is fused |
| `softmax` | assembly `exp` with hoisted constants (`softmax/lib/exp_asm.h`) | same structure as NMAra's `softmax` (`exp_nmara.h`) |
| `rmsnorm`, `layernorm`, `swiglu`, `geglu` | `main`'s kernels, plus the `FP32` precision token (section 5) | consistent with the other kernels and with NMAra |
| intrinsic `*_intr_bmark` variants | kept in `cos.c`/`exp.c`/`log.c`, not called | `main.c` always calls the hoisted `*_bmark`; there is no switch |
| `LatFCompEW32` 4 -> 5 | not applied | performance only, see `fpu_latency.md` |

## 3. Hardware

| File | Change from `main` | Note |
|---|---|---|
| `hardware/src/ara_soc.sv` | `AxiDataWidth = 64*NrLanes` (`main`: `32*NrLanes`) | the high-bandwidth system of the paper |
| `hardware/tb/ara_testharness.sv` | `AxiDataWidth = 64*NrLanes` | must match `ara_soc` |
| `hardware/tb/ara_tb.sv` | `AxiWideDataWidth = 64 * NrLanes`; `ClockPeriod = `TCK` if `TCK` is defined, else `1ns` | the backend's modelsim flow always passes `-DTCK=$(tck)` |
| `hardware/Makefile` | `questa_version ?= 2021.3` also for `vcd_dump=1` (`main`: 2019.3) | the only change; as in NMAra |
| `hardware/src/lane/vmfpu.sv` | none: `main`'s version | `main` has the compare-latency fix (`a987112a`), which also changed the latency-stall logic; the paper netlist had neither |
| `hardware/src/ara_soc.sv` `i_system_cut` | `.axi_req_t`/`.axi_resp_t` | also on `main` via PR #554 |

Not taken from the paper branch: the time-window `sim-vcd` target, `hardware/scripts/run_vcd.tcl`,
`hardware/scripts/run_gatesim.tcl`, the `do_file` variable and the `ifneq ($(vcd_dump),1)` guards in
`hardware/Makefile`. Gate-level simulation and power-window VCDs are done by the backend.

## 4. Apps infrastructure

| File | Change | Effect |
|---|---|---|
| `apps/Makefile` | `app_prec_defines_template`: every `FP64`/`FP32`/`FP16` token in `def_args_<app>` becomes `-D<TOK>=1` for that app only (target-specific `ENV_DEFINES`) | precision selection; `fft`'s `ifeq ($(ENV_DEFINES),)` special case still works because the global `ENV_DEFINES` stays empty |
| `apps/common/runtime.mk` | `netlist=1` -> `-DNETLIST=1`; `check ?= 1` -> `-DCHECK=$(check)` | `check=0` compiles the result checks out; `NETLIST`/`VCD_DUMP` builds run only the full size |
| `apps/common/util.h` | `PEAK_FLOP_CYCLE(sew)` = `2 * (64/sew) * NR_LANES`; `PRINT_SWEEP(kernel, sew, size, cycles, perf)` prints one `[SWEEP] kernel=… sew=… lanes=… size=… cycles=… flop_cycle=… util=…` line | parsed by `scripts/perf_eval/parse_log.py` |
| `apps/common/script/align_sections.sh` | `ALIGNMENT = 8 * NR_LANES` (`main`: `4 *`) | the AXI beat is `64*NrLanes` bits |
| `apps/common/default_args.mk` | precision tokens and VCD minimum sizes (section 6); new `gemv`, `faxpy` | |
| `apps/common/util.c` | none | `similarity_check` is absolute: `|a - b| <= threshold` |
| `.gitignore` | `!apps/log/`, `!apps/log/**` (the `*log` rule would hide the `log` app); `/results/`, `build_perf_*/` | `apps/*/data.S` stays ignored by `apps/.gitignore` |

`ENV_DEFINES` must not be set on the command line for a whole `make -C apps` build: it would disable
`fft`'s `-DFFT_SAMPLES` special case.

## 5. Kernel conventions on this branch

Every kernel measured by the backend or by `perf_eval` follows these rules.

1. **Precision token.** `def_args_<k>` holds the sizes followed by one or more of `FP64`, `FP32`,
   `FP16`. `apps/Makefile` turns them into `-DFP64=1` etc. Kernels that support one precision only still
   need its token (`"8 1024 FP32"`).
2. **`main.c`** compiles one block per precision, `#if FP64 … #endif`, `#if FP32 …`, `#if FP16 …`, and
   refuses to build without a token:
   ```c
   #if !(FP64 || FP32)
   #error "No precision selected: add FP64 and/or FP32 to def_args_cos in common/default_args.mk"
   #endif
   ```
   (FP32-only kernels: `#if !(FP32)`.)
3. **`gen_data.py`** takes `args = sys.argv[1:]`, separates the precision tokens from the numbers and
   emits only the arrays of the selected precisions. It exits with "Error. Give me …" when a token or a
   size is missing. Data are drawn with `np.random` **without a seed**: every build has new inputs.
4. **Result check.** `#ifndef CHECK` / `#define CHECK 1` / `#endif`, then `if (CHECK) { … }`;
   `check=0` (runtime.mk) disables it. Thresholds are absolute: `1e-4` for all floating-point kernels here
   (`THRESHOLD`, or `THRESHOLD_64b`/`THRESHOLD_32b`). Count all mismatches, print the first
   `MAX_ERR_PRINT`, and `return` the error count.
5. **Size sweep.** Without `NETLIST`/`VCD_DUMP`, the kernel runs a power-of-two sweep from size 4 up to
   the full size (the first point warms the I-cache and is marked `warmup=1` by `perf_eval`); with
   `NETLIST` or `VCD_DUMP` only the full size runs:
   ```c
   #if defined(NETLIST) || defined(VCD_DUMP)
     for (uint64_t avl = N_f64; avl <= N_f64; avl *= 2) {
   #else
     for (uint64_t avl = 4; avl <= N_f64; avl *= 2) {
   #endif
   ```
   (The LLM kernels test `VCD_DUMP` only.) The last, full-size run leaves the result that is checked.
6. **Performance print.** `<K>_FLOPS` per element (or the kernel's FLOP formula), `performance` in
   FLOP/cycle, utilization against `PEAK_FLOP_CYCLE(sew)`, then `PRINT_SWEEP("<k>", sew, size, cycles,
   performance)`. FLOP rule of this setup: every FPnew operation is 1 FLOP, a fused multiply-add 2.
7. **Power window.** Under `VCD_DUMP`, the kernel opens and closes the VCD window by writing the
   `event_trigger` control register; `ara_tb.sv` watches it and calls `$dumpon`/`$dumpoff` on
   `dut.i_ara_soc.i_system`, and `$finish` when the window closes (the program never reaches `tohost`).
   The window is a fixed range of loop iterations inside the steady state:
   ```c
   #ifdef VCD_DUMP
     size_t strip = 0;
   #endif
     while (avl > 0) {
   #ifdef VCD_DUMP
       // VCD window: strips 25..32 (needs len > 32 * VLMAX)
       strip++;
       if (strip == 25)
         *(volatile int64_t *)&event_trigger = +1;
       if (strip == 33)
         *(volatile int64_t *)&event_trigger = -1;
   #endif
   ```
   The `volatile` store keeps the compiler from moving or merging the trigger writes. The window must
   close: below the stated minimum size the stop trigger never fires and the simulation runs to the end
   without a VCD.
8. **Alignment.** Data arrays are aligned to `8 * NR_LANES` bytes (one AXI beat).

### 5.1 Kernel table

| Kernel | Precisions | Function called by `main.c` | VCD window | Minimum size for the window |
|---|---|---|---|---|
| `faxpy` (new) | FP64, FP32, FP16 | `faxpy_v64b`/`_v32b`/`_v16b` (unrolled) | iterations 5..12 | `avl > 12 * 2 * VLMAX` |
| `fdotproduct` | FP64, FP32, FP16 | `fdotp_v64b`/`_v32b`/`_v16b` | FP64: iterations 8..23; FP32/FP16: 3..7 | FP64 `avl >= 12800` (VLEN 4096); others `avl > 8 * 3 * VLMAX` |
| `gemv` (rewritten) | FP64, FP32, FP16 | `gemv_rowwise_*` | columns 16..47 | `N > 48`, `M_core >= VLMAX` |
| `fmatmul` | FP64, FP32, FP16 | 4x4 (LMUL=4) variant only | n = 4..12 (4 unrolled iterations) | `N > 12` |
| `fconv2d` | FP64, FP32, FP16; 3x3 and 7x7 | `fconv2d_{3x3,7x7}`, `fconv2d32_*`, `fconv2d16_*` | output-row iterations j = 3..4 (4 rows) | `M >= 20` |
| `exp` | FP64, FP32 | `exp_1xf64_bmark` / `exp_2xf32_bmark` (hoisted) | FP64 strips 25..32, FP32 strips 13..16 | `len > 32 * VLMAX` / `> 16 * VLMAX` |
| `log` | FP64, FP32 | `log_1xf64_bmark` / `log_2xf32_bmark` (hoisted) | same as `exp` | same as `exp` |
| `cos` | FP64, FP32 | `cos_1xf64_bmark` / `cos_2xf32_bmark` (hoisted, fused) | same as `exp` | same as `exp` |
| `softmax` | FP32 | asm-`exp` version | strip 5 | `innerSize > 5 * VLMAX` |
| `rmsnorm`, `layernorm` | FP32 | `main`'s kernel | the fifth row, whole | `rows >= 6` |
| `swiglu`, `geglu` | FP32 | `main`'s kernel (`__exp_2xf32` from `exp.h`) | strips 5..8 of `VLMAX(m1)` | `len >= 9 * VLMAX(m1)` |

The default sizes in `default_args.mk` are CI/check sizes. Sizes tagged `# VCD: <n>` there are the
minimum for a power window; the backend's `jobs.py` and `perf_eval/jobs.py` set their own sizes.

Kernels not in the table (`imatmul`, `iconv2d`, `fconv3d`, `jacobi2d`, `dropout`, `fft`, `dwt`,
`dotproduct`, `pathfinder`, `roi_align`, `lavamd`, …) are `main`'s, unchanged, without precision tokens.

### 5.2 What the files of a measured kernel contain

| File | `main` | this branch |
|---|---|---|
| `apps/<k>/main.c` | fixed precisions, one size | rules 2, 4, 5, 6 |
| `apps/<k>/kernel/<k>.c` | intrinsic kernel | hoisted/asm or element-width variants, VCD window (rule 7) |
| `apps/<k>/kernel/<k>_hoist.h` (`exp`, `log`, `cos`) | — | fixed-register asm macros: `V<K>_CONST_INIT_F64/F32()` broadcasts the constants into `v16..v29`; `V<K>_F64M1/F32M1(VD, VS)` is the hot path. Register contract at the top of each file |
| `apps/<k>/script/gen_data.py` | sizes only | rule 3 |

## 6. `apps/common/default_args.mk`

| Line | Value |
|---|---|
| `def_args_fmatmul` | `"128 128 128 FP64"   # VCD: 128` |
| `def_args_fconv2d` | `"112 112 7 FP64"` (M N F; F is 3 or 7; M, N multiples of 4) |
| `def_args_gemv` | `"256 256 FP64"   # VCD: 256` |
| `def_args_faxpy` | `"65536 FP64"   # VCD: 16384` |
| `def_args_fdotproduct` | `"16384 FP64 FP32 FP16"   # VCD: 16384` |
| `def_args_exp`, `_cos`, `_log` | `"128 FP64 FP32"`, `"512 FP64 FP32"`, `"512 FP64 FP32"` |
| `def_args_softmax` | `"3 256 FP32"` |
| `def_args_rmsnorm`, `_layernorm` | `"8 1024 FP32"   # rows, hidden size | supports FP32 only` |
| `def_args_swiglu`, `_geglu` | `"4096 FP32"   # supports FP32 only` |

CI builds every app with these defaults, so each must contain its token and fit the CI's check.

## 7. `scripts/perf_eval/`

The throughput (timing) and verification sweeps, `run_all.sh`, `run_job.sh`, `jobs.py` (job tables
`_PERF` and `_CHECK`), `parse_log.py`. Results go to `results/perf_eval/` and `results/verification/`,
HW builds to `hardware/build_perf_<cfg>`. Usage: `perf_eval.md`. Jobs are built with
`make -C apps bin/<k> config=<cfg> check=<0|1> "def_args_<k>=<args> <prec>"`, i.e. the precision token
is appended to the job's sizes.

## 8. The backend contract

The backend clones this branch at a pinned commit (`make ara ARA_COMMIT=…`) and relies on:

- `make -C apps bin/<k> config=<cfg> netlist=1 vcd_dump=1 check=0 "def_args_<k>=<sizes> <PREC>"` builds a
  power job: full size only, no check, the VCD window of rule 7 (the backend's `run_job.sh` appends the
  precision to the job's sizes, so **every measured kernel must accept its token**);
- the VCD scope `dut.i_ara_soc.i_system` (`ara_tb.sv`) and the `event_trigger` register;
- `ara_tb.sv` taking the clock from `TCK`;
- the FPU hierarchy of `vmfpu`/FPnew (the backend's `count_flops.py` counts FLOPs from its handshakes),
  so a change of FPU unit types or instance names needs a check of `count_flops.py`;
- the FLOP model of each job in the backend's `jobs.py`, which must match the kernel's instruction
  stream (used as a cross-check of the counted FLOPs).

Any change to a kernel's instruction stream, window or sizes changes the backend's results; re-run the
affected power jobs.

## 9. Adding a kernel (or a precision) to this branch

1. Write the kernel as on `main` (intrinsics are fine); for a fair comparison with NMAra use the same
   instruction stream as NMAra's kernel (hoisted constants, fused operations).
2. `main.c`: rules 2, 4, 5, 6 of section 5, copying the structure of `apps/cos/main.c` (two precisions)
   or `apps/swiglu/main.c` (FP32 only).
3. `gen_data.py`: rule 3, copying `apps/cos/script/gen_data.py` or `apps/swiglu/script/gen_data.py`.
4. The VCD window (rule 7) in the kernel's steady-state loop, with a comment stating the window and the
   minimum size; check that the default and the backend sizes are above it.
5. `default_args.mk`: sizes plus precision token(s), `# VCD: <n>` if the default is a VCD size.
6. `perf_eval/jobs.py`: one `_PERF` and one `_CHECK` row per precision.
7. `.github/workflows/ci.yml`: add the app to the `simulate` matrix.
8. Backend: add the job and its FLOP model to the backend's `jobs.py`.
9. Verify: `make -C apps bin/<k>` with the defaults; `make -C hardware simc app=<k>` passes on 2/4/8/16
   lanes; a `vcd_dump=1` build opens and closes the window; `scripts/run-clang-format.py` passes
   (CI checks every file under `apps/`).

## 10. Rebasing onto a newer `main`

Files changed on this branch (any `main` change to them will conflict or need a look):
`apps/Makefile`, `apps/common/{default_args.mk,runtime.mk,util.h,script/align_sections.sh}`,
`apps/{cos,exp,log,fconv2d,fdotproduct,fmatmul,gemv,softmax}/` (main.c, kernel, gen_data.py),
`apps/{rmsnorm,layernorm,swiglu,geglu}/{main.c,script/gen_data.py}`,
`hardware/Makefile`, `hardware/src/ara_soc.sv`, `hardware/tb/{ara_tb.sv,ara_testharness.sv}`, `.gitignore`.
Files that exist only here: `apps/faxpy/`, `apps/{cos,exp,log}/kernel/*_hoist.h`,
`apps/fconv2d/fconv2d{16,32}_{3x3,7x7}.c`, `apps/fmatmul/kernel/fmatmul{16,32}.c`, `apps/gemv/script/`,
`apps/softmax/lib/exp_asm.h`, `scripts/perf_eval/`, this directory.

Resolution rules:

- **`main.c`, `gen_data.py` of a measured kernel**: keep this branch's structure (section 5) and port
  `main`'s change into it by hand (e.g. a new threshold or a fixed gold computation). Example: PR #554
  changed `THRESHOLD 1` to `1e-4` in `cos`/`exp`/`log` `main.c`; this branch already uses
  `THRESHOLD_64b`/`_32b = 1e-4`, so keep this branch's file.
- **A `main` change to a kernel's math** (e.g. a fixed polynomial in `exp.h`/`cos.h`/`log.h`): port it to
  the matching `*_hoist.h` macro too, instruction by instruction, and keep the fused form of `cos`.
- **`default_args.mk`**: keep this branch's lines (tokens, `# VCD:` tags); add `main`'s new apps with a
  token if they are measured kernels.
- **`hardware/`**: take `main`, then re-apply the `64*NrLanes` widths, the `TCK` clock and the
  `questa_version` line. Check that `i_system_cut` still matches the `axi` version in `Bender.lock`.
- **`vmfpu.sv` and the FPU**: take `main`; tell the backend (FLOP counting and power results may change).
- **New `main` kernels used by the LLM kernels** (`exp.h`'s `__exp_2xf32`): take `main`.
- After the rebase: `git diff main` must show only the changes listed in sections 3-8; build every app
  with its defaults; run the `perf_eval` verification sweep (`--check`); clang-format.

## 11. Known issues

- **Formatting.** Files taken from the paper branch fail CI's `check-clang-format`; they need
  `clang-format -i` (whitespace only) before CI passes.
- **`dwt`, `pathfinder`** `#define CHECK` without `#ifndef`: a "macro redefined" warning with
  `-DCHECK=$(check)`; harmless (warnings are not errors).
- **Throughput vs the paper.** `main`'s latency-stall change in `vmfpu.sv` and the 1 ns default clock
  (the paper's runs used another default; cycles should not depend on it) are not in the paper's Ara2
  runs; compare cycles before relying on them.
- **FP32 FMA latency** (`LatFCompEW32 = 4`): FP32 FMA chains lose VRF bank arbitration; not fixed, see
  `fpu_latency.md`.
