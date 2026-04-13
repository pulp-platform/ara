#!/usr/bin/env bash
# Build and run all Zvkned single-instruction tests on Spike.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPS_DIR="$(dirname "$SCRIPT_DIR")"
ARA_DIR="$(cd "$APPS_DIR/.." && pwd)"

CC="$ARA_DIR/install/riscv-llvm/bin/clang"
SPIKE="$ARA_DIR/install/riscv-isa-sim/bin/spike"
SPIKE_ISA="rv64gcv_zfh_zvkb_zvkned_zvl4096b"

CFLAGS="-march=rv64gcv_zfh_zvfh_zvkned -mabi=lp64d -mno-relax -fuse-ld=lld \
  -fno-vectorize -mllvm -scalable-vectorization=off \
  -mllvm -riscv-v-vector-bits-min=0 -mno-implicit-float \
  -mcmodel=medany -I$APPS_DIR/common -O3 -ffast-math -fno-common \
  -fno-builtin-printf -DNR_LANES=4 -DVLEN=4096 \
  -DPREALLOCATE=1 -DSPIKE=1 \
  -I$APPS_DIR/riscv-tests/env \
  -I$APPS_DIR/riscv-tests/benchmarks/common \
  -ffunction-sections -fdata-sections -std=gnu99"

LDFLAGS="-static -nostartfiles -lm -nostdlib \
  -T$APPS_DIR/riscv-tests/benchmarks/common/test.ld \
  -Wl,--gc-sections"

RUNTIME_OBJS=(
  "$APPS_DIR/riscv-tests/benchmarks/common/crt.S.o.spike"
  "$APPS_DIR/riscv-tests/benchmarks/common/syscalls.c.o.spike"
  "$APPS_DIR/common/util.c.o.spike"
)

DATA_OBJ="$SCRIPT_DIR/data.S.o.spike"

# Ensure runtime objects and data.S exist
for obj in "${RUNTIME_OBJS[@]}" "$DATA_OBJ"; do
  if [ ! -f "$obj" ]; then
    echo "ERROR: missing $obj — run 'make spike-run-zvkned_dbg' once first"
    exit 1
  fi
done

TESTS=(
  TEST_VAESZ
  TEST_VAESZ_2G
  TEST_VAESEM
  TEST_VAESEM_2G
  TEST_VAESEM_VS
  TEST_VAESEM_VS_2G
  TEST_VAESEF
  TEST_VAESEF_2G
  TEST_VAESEF_VS
  TEST_VAESEF_VS_2G
  TEST_VAESDM
  TEST_VAESDM_2G
  TEST_VAESDM_VS
  TEST_VAESDM_VS_2G
  TEST_VAESDF
  TEST_VAESDF_2G
  TEST_VAESDF_VS
  TEST_VAESDF_VS_2G
  TEST_VAESKF1
  TEST_VAESKF2_EVEN
  TEST_VAESKF2_ODD
)

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

pass=0
fail=0
errors=""

for test in "${TESTS[@]}"; do
  OBJ="$TMPDIR/${test}.o"
  ELF="$TMPDIR/${test}.elf"

  # Compile main.c with the test define
  $CC $CFLAGS -D"$test" -c "$SCRIPT_DIR/main.c" -o "$OBJ" 2>&1

  # Link
  $CC $CFLAGS -o "$ELF" "$DATA_OBJ" "$OBJ" "${RUNTIME_OBJS[@]}" $LDFLAGS 2>&1

  # Run on spike
  output=$($SPIKE --isa="$SPIKE_ISA" "$ELF" 2>&1) || true
  result=$(echo "$output" | grep -E "^(PASS|FAIL)$" || echo "ERROR")

  # Print full output indented
  echo "=== $test ==="
  echo "$output" | sed 's/^/  /'
  echo ""

  if [ "$result" = "PASS" ]; then
    ((pass++))
  else
    ((fail++))
  fi
done

echo ""
echo "Results: $pass passed, $fail failed (out of ${#TESTS[@]})"

if [ $fail -gt 0 ]; then
  echo ""
  echo "=== Failures ==="
  printf "$errors"
  exit 1
fi
