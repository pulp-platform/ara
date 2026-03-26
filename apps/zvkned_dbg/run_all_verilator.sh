#!/usr/bin/env bash
# Build and run all Zvkned single-instruction tests on the Verilator RTL sim.
# Each test recompiles bin/zvkned_dbg with a different -DTEST_XXX, then runs
# `make simv` from the hardware directory with a timeout to catch stalls.
set -euo pipefail

ARA_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APPS_DIR="$ARA_DIR/apps"
HW_DIR="$ARA_DIR/hardware"

# Timeout per simulation in seconds (adjust as needed)
SIM_TIMEOUT="${SIM_TIMEOUT:-120}"

TESTS=(
  TEST_VAESZ
  TEST_VAESEM
  TEST_VAESEM_VS
  TEST_VAESEF
  TEST_VAESEF_VS
  TEST_VAESDM
  TEST_VAESDM_VS
  TEST_VAESDF
  TEST_VAESDF_VS
  TEST_VAESKF1
  TEST_VAESKF2_EVEN
  TEST_VAESKF2_ODD
)

pass=0
fail=0
timeout_count=0

for test in "${TESTS[@]}"; do
  echo "=== $test ==="

  # Force recompile of main.c.o by removing it
  rm -f "$APPS_DIR/zvkned_dbg/main.c.o"

  # Rebuild bin/zvkned_dbg with the test define
  if ! make -C "$APPS_DIR" bin/zvkned_dbg ENV_DEFINES="-D$test" 2>&1 | tail -3; then
    echo "  COMPILE ERROR"
    ((fail++))
    echo ""
    continue
  fi

  # Run Verilator simulation with timeout
  output=""
  sim_exit=0
  output=$(timeout "$SIM_TIMEOUT" make -C "$HW_DIR" simv app=zvkned_dbg 2>&1) || sim_exit=$?

  # timeout(1) returns 124 on timeout
  if [ "$sim_exit" -eq 124 ]; then
    echo "$output" | sed 's/^/  /'
    echo "  >>> TIMEOUT after ${SIM_TIMEOUT}s (possible stall) <<<"
    ((fail++))
    ((timeout_count++))
    echo ""
    continue
  fi

  # Print simulation output
  echo "$output" | sed 's/^/  /'

  # Check result
  result=$(echo "$output" | grep -E "^(PASS|FAIL)$" | tail -1 || echo "")
  if [ "$result" = "PASS" ]; then
    ((pass++))
  else
    echo "  >>> FAIL (exit=$sim_exit) <<<"
    ((fail++))
  fi
  echo ""
done

# Clean up: remove the .o so the tree isn't left with a random test define baked in
rm -f "$APPS_DIR/zvkned_dbg/main.c.o"

echo "========================================"
echo "Results: $pass passed, $fail failed ($timeout_count timeouts) out of ${#TESTS[@]}"
echo "========================================"

[ "$fail" -eq 0 ]
