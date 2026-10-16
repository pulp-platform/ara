#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Hong Pang <hopang@iis.ee.ethz.ch>
#
# Ara kernel sweeps: HW compile -> build ELFs -> parallel sims.
# Timing sweep (default), verification sweep (--check), or both on one HW
# build (--check-then-perf, --check-and-perf). See README.md.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$ROOT/scripts/perf_eval
QUESTA=${QUESTA:-questa-2021.3}
export QUESTA

usage() {
  cat <<EOF
usage: run_all.sh --config <cfg> [options]
  --config <cfg>      HW config in config/<cfg>.mk (e.g. 8_lanes)
  --set k=v           override a config variable (nr_lanes, vlen), repeatable
                      (e.g. --set vlen=4096)
  --check             functional verification sweep instead of the timing sweep
  --check-then-perf   verification sweep, then the timing sweep, on one HW build
  --check-and-perf    both sweeps at once: build all ELFs, then simulate all jobs together
  --perf-anyway       with --check-then-perf: run the timing sweep even if verification fails
  --each k=v1,v2,...  repeat the whole run once per value, in sequence (e.g. --each vlen=4096,8192)
  --only <list>       comma list of kernel, job name, or either with :PREC
                      (e.g. gemv,fmatmul:FP16,fconv2d3x3)
  -j <n>              parallel simulations (default: number of selected jobs)
  --timeout <s>       per-simulation wall-clock limit in seconds (default: none)
  --smoke             tiny sizes, to check the flow in minutes
  --out <dir>         results root instead of results/ (runs go to
                      <dir>/perf_eval/<stamp>/<cfg> and <dir>/verification/<stamp>/<cfg>)
EOF
  exit 2
}

config=; sets=(); only=; par=0; timeout_s=0; smoke=; out=; modes=(perf); perf_anyway=; together=
each=; stamp=; argv=("$@")
while (( $# )); do
  case $1 in
    --config)          config=$2; shift 2 ;;
    --set)             sets+=("$2"); shift 2 ;;
    --check)           modes=(check); shift ;;
    --check-then-perf) modes=(check perf); together=; shift ;;
    --check-and-perf)  modes=(check perf); together=1; shift ;;
    --perf-anyway)     perf_anyway=1; shift ;;
    --each)            each=$2; shift 2 ;;
    --stamp)           stamp=$2; shift 2 ;;   # internal: shared by the --each runs
    --only)            only=$2; shift 2 ;;
    -j)                par=$2; shift 2 ;;
    --timeout)         timeout_s=$2; shift 2 ;;
    --smoke)           smoke=--smoke; shift ;;
    --out)             out=$2; shift 2 ;;
    *)                 usage ;;
  esac
done
[[ -n $config ]] || usage
[[ -n $perf_anyway && ( ${#modes[@]} -lt 2 || -n $together ) ]] && { echo "--perf-anyway needs --check-then-perf" >&2; exit 2; }

# --each: one full run per value, in sequence, under one shared stamp
if [[ -n $each ]]; then
  ekey=${each%%=*}; evals=${each#*=}
  [[ $each == *=* && -n $ekey && -n $evals ]] || { echo "--each wants k=v1,v2,..." >&2; exit 2; }
  for kv in "${sets[@]}"; do
    [[ ${kv%%=*} == "$ekey" ]] && { echo "$ekey is given both in --set and --each" >&2; exit 2; }
  done
  # Drop --each from the arguments, then re-run once per value
  rest=(); skip=
  for a in "${argv[@]}"; do
    if [[ -n $skip ]]; then skip=; continue; fi
    [[ $a == --each ]] && { skip=1; continue; }
    rest+=("$a")
  done
  stamp=$(date +%Y-%m-%d_%H%M)${smoke:+_smoke}
  status=0
  IFS=, read -ra vals <<< "$evals"
  for v in "${vals[@]}"; do
    echo "[$(date +%H:%M:%S)] --each: $ekey=$v"
    "${BASH_SOURCE[0]}" "${rest[@]}" --set "$ekey=$v" --stamp "$stamp" || status=1
  done
  exit $status
fi

# Tag = config + every --set, sorted by variable
tag=$config
while read -r kv; do [[ -n $kv ]] && tag+="_${kv//=/}"; done < <(printf '%s\n' "${sets[@]}" | sort)
set_args=(); for kv in "${sets[@]}"; do set_args+=(--set "$kv"); done

# One stamp for all sweeps of this launch
declare -A subdir=([perf]=perf_eval [check]=verification) cfg_dirs
root=${out:-$ROOT/results}
stamp=${stamp:-$(date +%Y-%m-%d_%H%M)${smoke:+_smoke}}
for m in "${modes[@]}"; do [[ -e $root/${subdir[$m]}/$stamp/$tag ]] && stamp+=_$(date +%S); done
for m in "${modes[@]}"; do cfg_dirs[$m]=$root/${subdir[$m]}/$stamp/$tag; mkdir -p "${cfg_dirs[$m]}"; done
logf=${cfg_dirs[${modes[0]}]}/run_all.log
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$logf"; }

joblist_of() { python3 "$HERE/jobs.py" list --mode "$1" $smoke --only "$only"; }

# --- 1. Pre-flight: check --set keys and job selection ----------------------
python3 "$HERE/jobs.py" check-sets --config "$config" "${set_args[@]}" || exit 2
for m in "${modes[@]}"; do joblist_of "$m" > /dev/null || exit 1; done

# --- 2. HW compile, fresh every launch, shared by all sweeps ----------------
build_rel=build_perf_$tag
build=$ROOT/hardware/$build_rel
mkdir -p "$build"
lock=$build/.perf_eval.lock
# The lock names its build dir too, so a copied tree does not inherit it
if [[ -f $lock ]]; then
  read -r lock_pid lock_dir < "$lock"
  if [[ $lock_dir == "$build" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log "another run_all.sh (pid $lock_pid) is using $build_rel, aborting"; exit 1
  fi
fi
echo "$$ $build" > "$lock"
trap 'rm -f "$lock"; kill 0 2>/dev/null' INT TERM
trap 'rm -f "$lock"' EXIT

hw_log=${cfg_dirs[${modes[0]}]}/hw_compile.log
log "compiling HW into hardware/$build_rel (log: $hw_log)"
rm -rf "$build/work" "$build/compile_$config.tcl"
if ! make -C "$ROOT/hardware" compile "config=$config" "buildpath=$build_rel" "${sets[@]}" \
     > "$hw_log" 2>&1 \
   || grep -q '\*\* Error' "$build/transcript"; then
  log "HW compile failed, see hw_compile.log and $build/transcript"; exit 1
fi
if ! (cd "$build" && $QUESTA vopt +acc -work work ara_tb -o ara_tb_perf -suppress vopt-7033) \
     >> "$hw_log" 2>&1; then
  log "vopt failed, see hw_compile.log"; exit 1
fi

# --- 3./4. Sweeps: build ELFs one at a time, then simulate in parallel ------
# Status loops running in the background (not counted as simulations)
nstatus=0
declare -A status_pid

# apps/bin and data.S are shared: one build at a time, also across launches
build_lock=$ROOT/results/.apps_build.lock
mkdir -p "$ROOT/results"
build_sweep() {
  local mode=$1 cfg_dir=${cfg_dirs[$1]} check=0 j name kernel prec args
  [[ $mode == check ]] && check=1
  logf=$cfg_dir/run_all.log
  local -a joblist
  mapfile -t joblist < <(joblist_of "$mode")
  log "$mode sweep: $cfg_dir  (${#joblist[@]} jobs, HW hardware/$build_rel)"
  for j in "${joblist[@]}"; do
    read -r name kernel prec args <<< "$j"
    log "build $name ($args)"
    # shellcheck disable=SC2086
    ( flock 9; CHECK=$check "$HERE/run_job.sh" build "$cfg_dir/$name" "$config" "${sets[*]}" \
        "$kernel" "$prec" $args ) 9> "$build_lock" || log "  $(cat "$cfg_dir/$name/state")"
  done
}

# Start the simulations of one sweep, at most np at a time over all sweeps
launch_sweep() {
  local mode=$1 np=$2 cfg_dir=${cfg_dirs[$1]} j name jd
  local -a joblist
  mapfile -t joblist < <(joblist_of "$mode")
  logf=$cfg_dir/run_all.log
  ( while :; do python3 "$HERE/parse_log.py" status "$cfg_dir"; sleep 20; done ) &
  status_pid[$mode]=$!
  (( nstatus++ ))
  for j in "${joblist[@]}"; do
    read -r name _ <<< "$j"
    jd=$cfg_dir/$name
    [[ $(cat "$jd/state") == built ]] || continue
    while (( $(jobs -rp | wc -l) - nstatus >= np )); do wait -n; done
    log "sim $name"
    ( "$HERE/run_job.sh" sim "$jd" "$build" "$timeout_s" < /dev/null; log "  $name: $(cat "$jd/state")" ) &
  done
}

wait_sims() { while (( $(jobs -rp | wc -l) > nstatus )); do wait -n; done; }

finish_sweep() {
  local mode=$1 cfg_dir=${cfg_dirs[$1]} rc
  logf=$cfg_dir/run_all.log
  kill "${status_pid[$mode]}" 2>/dev/null; wait "${status_pid[$mode]}" 2>/dev/null
  (( nstatus-- ))
  python3 "$HERE/parse_log.py" status "$cfg_dir"
  python3 "$HERE/parse_log.py" summary "$cfg_dir"; rc=$?
  log "finished: $cfg_dir/summary.csv"
  cat "$cfg_dir/status.txt"
  return $rc
}

njobs() { joblist_of "$1" | wc -l; }

# --- 5. Run the sweeps ------------------------------------------------------
status=0
if [[ -n $together ]]; then
  # Both sweeps share the parallel slots; -j defaults to all jobs of both
  np=$par; (( np > 0 )) || np=$(( $(njobs check) + $(njobs perf) ))
  for m in "${modes[@]}"; do build_sweep "$m"; done
  for m in "${modes[@]}"; do logf=${cfg_dirs[$m]}/run_all.log; log "simulating with -j $np over both sweeps"; launch_sweep "$m" "$np"; done
  wait_sims
  for m in "${modes[@]}"; do finish_sweep "$m" || status=1; done
  logf=${cfg_dirs[perf]}/run_all.log
  log "verification: ${cfg_dirs[check]} ($(grep -m1 '^# verification:' "${cfg_dirs[check]}/summary.csv" | cut -c3-))"
  exit $status
fi

# One sweep after the other; a failed verification skips the perf sweep
for m in "${modes[@]}"; do
  np=$par; (( np > 0 )) || np=$(njobs "$m")
  build_sweep "$m"
  launch_sweep "$m" "$np"
  wait_sims
  finish_sweep "$m"; rc=$?
  (( rc )) && status=1
  if [[ $m == check ]] && (( ${#modes[@]} > 1 )); then
    logf=${cfg_dirs[perf]}/run_all.log
    log "verification: ${cfg_dirs[check]} ($(grep -m1 '^# verification:' "${cfg_dirs[check]}/summary.csv" | cut -c3-))"
    if (( rc )) && [[ -z $perf_anyway ]]; then
      log "verification failed: perf sweep skipped (--perf-anyway runs it regardless)"
      exit 1
    fi
  fi
done
exit $status
