// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvbc (vclmul.v{v,x} / vclmulh.v{v,x}) instruction tests.
// Per-element carry-less multiplication in GF(2). SEW=64 only.
//   vclmul  : vd[i] = low 64 bits of  clmul(vs2[i], op)
//   vclmulh : vd[i] = high 64 bits of clmul(vs2[i], op)
// where op = vs1[i] for .vv, rs1 for .vx.

#include "vector_macros.h"

static const int k_vls[] = {4, 8, 16, 32};

// Deterministic inputs, chosen to exercise most bit positions.
static const uint64_t k_vs2[4] = {
    0x0123456789abcdefull,
    0xfedcba9876543210ull,
    0xdeadbeefcafef00dull,
    0xaaaaaaaa55555555ull,
};
static const uint64_t k_vs1[4] = {
    0x00112233445566ffull,
    0x8899aabbccddeeffull,
    0xfeedfacebaadc0deull,
    0x5555aaaa5555aaaaull,
};
static const uint64_t k_rs1 = 0xd0f5bd2c63e7a194ull;

static volatile uint64_t buf_vs2[64] __attribute__((aligned(128)));
static volatile uint64_t buf_vs1[64] __attribute__((aligned(128)));
static volatile uint64_t buf_out[64] __attribute__((aligned(128)));

static void start_case(const char *name, int vl) {
  ++test_case;
  printf("Test %d (vl=%d): %s\n", test_case, vl, name);
}

static void vset_e64_vl(int vl) {
  switch (vl) {
  case 4:  VSET(4,  e64, m1); break;
  case 8:  VSET(8,  e64, m2); break;
  case 16: VSET(16, e64, m4); break;
  case 32: VSET(32, e64, m8); break;
  default:
    printf("Unsupported VL %d\n", vl);
    ++num_failed;
    break;
  }
}

static void fill64(volatile uint64_t *dst, const uint64_t *src, int n,
                   int pattern_len) {
  for (int i = 0; i < n; ++i)
    dst[i] = src[i % pattern_len];
}

// ---------------------------------------------------------------------------
// Scalar reference: 64 x 64 carry-less multiply over GF(2).
// ---------------------------------------------------------------------------

static uint64_t clmul_lo(uint64_t a, uint64_t b) {
  uint64_t lo = 0;
  for (int i = 0; i < 64; ++i)
    if ((b >> i) & 1ull) lo ^= a << i;
  return lo;
}

static uint64_t clmul_hi(uint64_t a, uint64_t b) {
  uint64_t hi = 0;
  for (int i = 1; i < 64; ++i)
    if ((b >> i) & 1ull) hi ^= a >> (64 - i);
  return hi;
}

static int check_vv(int vl, int high) {
  for (int i = 0; i < vl; ++i) {
    uint64_t a = k_vs2[i % 4];
    uint64_t b = k_vs1[i % 4];
    uint64_t exp = high ? clmul_hi(a, b) : clmul_lo(a, b);
    if (buf_out[i] != exp) {
      printf("  FAILED at i=%d: got 0x%016llx expected 0x%016llx\n", i,
             (unsigned long long)buf_out[i], (unsigned long long)exp);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static int check_vx(int vl, int high) {
  for (int i = 0; i < vl; ++i) {
    uint64_t a = k_vs2[i % 4];
    uint64_t exp = high ? clmul_hi(a, k_rs1) : clmul_lo(a, k_rs1);
    if (buf_out[i] != exp) {
      printf("  FAILED at i=%d: got 0x%016llx expected 0x%016llx\n", i,
             (unsigned long long)buf_out[i], (unsigned long long)exp);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

// ---------------------------------------------------------------------------
// Hardware exercises
// ---------------------------------------------------------------------------

static void test_vclmul_vv(int vl) {
  start_case("vclmul.vv", vl);
  fill64(buf_vs2, k_vs2, vl, 4);
  fill64(buf_vs1, k_vs1, vl, 4);
  vset_e64_vl(vl);
  asm volatile("vle64.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vle64.v v24, (%0)" ::"r"(buf_vs1) : "memory");
  asm volatile("vclmul.vv v8, v16, v24");
  asm volatile("vse64.v v8, (%0)" ::"r"(buf_out) : "memory");
  check_vv(vl, /*high=*/0);
}

static void test_vclmulh_vv(int vl) {
  start_case("vclmulh.vv", vl);
  fill64(buf_vs2, k_vs2, vl, 4);
  fill64(buf_vs1, k_vs1, vl, 4);
  vset_e64_vl(vl);
  asm volatile("vle64.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vle64.v v24, (%0)" ::"r"(buf_vs1) : "memory");
  asm volatile("vclmulh.vv v8, v16, v24");
  asm volatile("vse64.v v8, (%0)" ::"r"(buf_out) : "memory");
  check_vv(vl, /*high=*/1);
}

static void test_vclmul_vx(int vl) {
  start_case("vclmul.vx", vl);
  fill64(buf_vs2, k_vs2, vl, 4);
  vset_e64_vl(vl);
  asm volatile("vle64.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vclmul.vx v8, v16, %0" ::"r"(k_rs1));
  asm volatile("vse64.v v8, (%0)" ::"r"(buf_out) : "memory");
  check_vx(vl, /*high=*/0);
}

static void test_vclmulh_vx(int vl) {
  start_case("vclmulh.vx", vl);
  fill64(buf_vs2, k_vs2, vl, 4);
  vset_e64_vl(vl);
  asm volatile("vle64.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vclmulh.vx v8, v16, %0" ::"r"(k_rs1));
  asm volatile("vse64.v v8, (%0)" ::"r"(buf_out) : "memory");
  check_vx(vl, /*high=*/1);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  for (unsigned i = 0; i < sizeof(k_vls) / sizeof(k_vls[0]); ++i) {
    const int vl = k_vls[i];
    printf("\n=== Zvbc configuration: vl=%d ===\n", vl);
    test_vclmul_vv(vl);
    test_vclmulh_vv(vl);
    test_vclmul_vx(vl);
    test_vclmulh_vx(vl);
  }

  EXIT_CHECK();
}
