#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Hong Pang <hopang@iis.ee.ethz.ch>
#
# Build or simulate one perf_eval job. Normally called by run_all.sh.
#
#   [CHECK=1] run_job.sh build <job_dir> <config> "<k=v ...>" <kernel> <prec> <args...>
#   run_job.sh sim   <job_dir> <hw_build_dir> <timeout_s|0>
#
# <job_dir>/state holds: building | built | running | done | FAILED: <reason>
# CHECK=1 builds with result checking (default: off, for timing).

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QUESTA=${QUESTA:-questa-2021.3}

mode=$1
JOB=$2
mkdir -p "$JOB"
fail() { echo "FAILED: $*" > "$JOB/state"; exit 1; }

if [[ $mode == build ]]; then
  config=$3; sets=$4; kernel=$5; prec=$6; shift 6
  echo building > "$JOB/state"
  echo "${CHECK:-0}" > "$JOB/check"
  # Kernel objects bake in NR_LANES/VLEN but do not depend on them in make
  find "$ROOT/apps/$kernel" -name '*.o' -delete
  # shellcheck disable=SC2086
  cmd=(make -C "$ROOT/apps" "bin/$kernel" "config=$config" $sets "check=${CHECK:-0}" "def_args_$kernel=$* $prec")
  printf '%q ' "${cmd[@]}" > "$JOB/make_cmd.txt"; echo >> "$JOB/make_cmd.txt"
  if ! "${cmd[@]}" > "$JOB/build.log" 2>&1; then
    grep -q 'overflowed' "$JOB/build.log" && fail "ELF does not fit in L2 (see build.log)"
    fail "build (see build.log)"
  fi
  cp "$ROOT/apps/bin/$kernel" "$JOB/${kernel}_${prec}.elf"
  echo built > "$JOB/state"

elif [[ $mode == sim ]]; then
  build=$3; timeout_s=$4
  elf=$(ls "$JOB"/*.elf)
  mkdir -p "$JOB/sim"
  cd "$JOB/sim" || fail "no sim dir"
  echo running > "$JOB/state"
  # Private modelsim.ini, transcript and traces; the compiled library is shared
  $QUESTA vmap work "$build/work" > /dev/null 2>&1 || fail "vmap"
  # Line-buffered, so run.log follows the simulation live
  cmd=(stdbuf -oL -eL $QUESTA vsim -c -onfinish exit -work work -sv_lib "$build/work-dpi/ara_dpi"
       +UVM_NO_RELNOTES "+PRELOAD=$elf" -suppress vsim-3009
       work.ara_tb_perf -do "run -a; quit -f")
  (( timeout_s > 0 )) && cmd=(timeout "$timeout_s" "${cmd[@]}")
  start=$(date +%s)
  "${cmd[@]}" > "$JOB/run.log" 2>&1
  rc=$?
  echo "wall_seconds=$(( $(date +%s) - start ))" >> "$JOB/run.log"
  python3 "$ROOT/scripts/perf_eval/parse_log.py" sweep "$JOB/run.log" "$JOB/sweep.csv"
  (( rc == 124 )) && fail "timeout after ${timeout_s}s"
  ret=$(grep 'Core Test' "$JOB/run.log" | grep -Poh -- '(?<=\(tohost = )-?[0-9]+(?=\))')
  [[ -z $ret ]] && fail "simulation did not finish (vsim rc=$rc)"
  [[ $ret != 0 ]] && fail "program returned tohost=$ret"
  # A checked build also fails on any mismatch the kernel printed
  [[ $(cat "$JOB/check" 2>/dev/null) == 1 ]] && grep -qE '\bError\b|\bFail\b|FAILED' "$JOB/run.log" &&
    fail "result mismatch (see run.log)"
  # Drop the CVA6 trace (~200 MB) of passing runs
  rm -f trace_hart_*.log trace_hart_*.dasm
  echo done > "$JOB/state"

else
  echo "usage: run_job.sh build|sim ..." >&2; exit 2
fi
