# perf_eval — Ara kernel sweeps

Two sweeps over nine kernels (fdotproduct, faxpy, cos, log, exp, softmax, gemv,
fconv2d, fmatmul):

- **Timing sweep** (default, 22 jobs): utilization against elements/lane and
  bytes/lane, with result checking compiled out.
- **Verification sweep** (`--check`, 25 jobs): smaller sizes with result checking on.
  Each job still sweeps from size 4 but checks only the last (full) size;
  faxpy runs only its full size, because y is read-modify-write. fconv2d runs
  both the 7x7 and the 3x3 filter.

## Run it

```sh
# Quick checks that the flow works (minutes)
scripts/perf_eval/run_all.sh --config 8_lanes --smoke
scripts/perf_eval/run_all.sh --config 8_lanes --check --smoke

# Verification sweep
scripts/perf_eval/run_all.sh --config 8_lanes --check

# Verification, then timing on the same HW build; the timing sweep is skipped if
# any check fails (hours; use tmux or nohup so it survives logout)
scripts/perf_eval/run_all.sh --config 8_lanes --check-then-perf

# ... or run the timing sweep even if a check fails
scripts/perf_eval/run_all.sh --config 8_lanes --check-then-perf --perf-anyway

# Both sweeps at once: all ELFs first, then all jobs simulated together
scripts/perf_eval/run_all.sh --config 8_lanes --check-and-perf

# Timing sweep of 4 and 8 lanes in parallel
scripts/perf_eval/run_all.sh --config 4_lanes >& run_4l.log &
scripts/perf_eval/run_all.sh --config 8_lanes >& run_8l.log &
```

Launches with different `--config`/`--set` values can run in parallel: they
build into different HW directories, their ELF builds take turns through a lock
(`results/.apps_build.lock`), and their simulations run concurrently. Two
launches with the *same* configuration refuse to share a HW build directory.

Run from the repo root (any shell; the scripts are bash). The toolchain is taken
from `install/` (or `INSTALL_DIR`), as for any app build. Sizes come from
`jobs.py`; `apps/common/default_args.mk` is not changed.

## Options

| Option | Meaning |
|---|---|
| `--config 8_lanes` | HW config `config/<cfg>.mk` (required): `2_lanes`, `4_lanes`, `8_lanes`, `16_lanes` |
| `--set k=v` | override a config variable for both the HW and the kernels, repeatable: `nr_lanes`, `vlen` |
| `--check` | verification sweep instead of the timing sweep |
| `--check-then-perf` | verification sweep, then the timing sweep, on one HW compile; the timing sweep is skipped if any check fails |
| `--perf-anyway` | with `--check-then-perf`: run the timing sweep even if verification fails |
| `--check-and-perf` | both sweeps on one HW compile: build all ELFs, then simulate all jobs together (`-j` is shared) |
| `--each k=v1,v2` | repeat the whole run (HW compile and sweeps) once per value, in sequence, under one shared `<date>_<HHMM>` (e.g. `--each vlen=4096,8192`) |
| `--only gemv,fmatmul:FP16` | run only these jobs: kernel, job name (e.g. `fconv2d3x3`), either with `:PREC` |
| `-j N` | parallel simulations (default: one per job) |
| `--timeout S` | kill a simulation after S seconds |
| `--smoke` | tiny sizes (both sweeps), to check the flow in minutes |
| `--out DIR` | results root instead of `results/` |

Every `--set` value becomes part of the HW build directory and the results
directory name, so builds and results of different settings never collide.
Result checking is controlled by `--check`, not by `--set check=...`.

Every job's data lives in the 32 MiB L2; a job that does not fit fails its
build with "ELF does not fit in L2".

## What happens

1. **Pre-flight** — the `--set` keys and the job selection are validated.
2. **HW compile** — fresh, once per launch, into `hardware/build_perf_<cfg>`;
   all jobs and both sweeps share it.
3. **Build** — one ELF per job, one at a time (`check=1` for verification,
   `check=0` for timing).
4. **Simulate** — all jobs in parallel, each in its own directory.
5. With `--check-then-perf`, steps 3-4 run for the verification sweep first,
   then for the timing sweep. With `--check-and-perf`, step 3 runs for both
   sweeps, then step 4 for all their jobs at once.
6. With `--each`, all of the above repeats per value.

A verification job passes only if the program returns 0 (`tohost = 0`) **and**
its `run.log` has no `Error` / `Fail` / `FAILED` line.

## Results

| Sweep | Directory |
|---|---|
| timing | `results/perf_eval/<date>_<HHMM>/<cfg>/` |
| verification | `results/verification/<date>_<HHMM>/<cfg>/` |

`--check-then-perf`, `--check-and-perf` and `--each` use one `<date>_<HHMM>`
for everything they run, so the timing numbers sit next to the verification
run that validated them. `<cfg>` is the config plus every `--set`, sorted by
variable name, e.g. `8_lanes_vlen4096`, whatever order the options are given in.

| File | Content |
|---|---|
| `status.txt` | one line per job: state (and PASS/FAIL for verification) and latest util point, refreshed every 20 s |
| `summary.csv` | all sweep points of all jobs, with the git commit and, for verification, `verification: N/M PASS` at the top |
| `run_all.log` | the launch log; `hw_compile.log` sits in the first sweep's directory |
| `<job>/run.log` | the full simulation output, written live |
| `<job>/sweep.csv` | that job's sweep points |
| `<job>/*.elf`, `make_cmd.txt` | the binary and the exact command that built it |

Watch a run while it goes:

```sh
watch cat results/perf_eval/<run>/8_lanes/status.txt
tail -f   results/perf_eval/<run>/8_lanes/gemv_FP32/run.log
```

CSV columns: `check` is PASS/FAIL for verification jobs and `-` for timing jobs.
`size` is the swept dimension (vector length for fdotproduct, faxpy, cos, log,
exp; columns for gemv; N for fconv2d; innerSize for softmax; P for fmatmul).
`elems_per_lane = size / lanes`, `bytes_per_lane = size * bytes / lanes`.
Rows with `warmup=1` are the first point (size 4), run only to warm the I-cache.
Utilization is against `PEAK_FLOP_CYCLE(sew) = 2 * (64/sew) * NR_LANES`
(`apps/common/util.h`).

## Kernels

Ara's RVV kernels, with these additions:

- FP32/FP16 versions of faxpy, fmatmul and fconv2d (and of the unrolled
  fdotproduct/faxpy kernels) are element-width copies of the FP64 kernels.
- fmatmul always uses its 4x4 (LMUL=4) variant.
- softmax pass 3 scales by one reciprocal per strip.
- fconv2d 3x3 tiles the columns when an input row does not fit one register
  group, as fconv2d 7x7 already does.
- fdotproduct always reduces, except in `VCD_DUMP` builds (power measurement).

The swept size is also the row stride for gemv, fconv2d, softmax and fmatmul,
so smaller sweep points work on a dense prefix of the data.

## Change sizes

Edit the tables in `scripts/perf_eval/jobs.py`: `_PERF` (timing: full and smoke
sizes) and `_CHECK` (verification: check and smoke sizes).

## Checking outside the flow

The kernels check results by default; `make -C apps bin/<kernel> check=0`
builds without checking. The precision is a token in the kernel's arguments,
e.g. `make -C apps bin/gemv def_args_gemv="120 2048 FP32"`.
