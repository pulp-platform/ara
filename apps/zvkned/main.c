// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES-128 ECB correctness test using RISC-V Zvkned vector crypto extension.
// Test vectors from NIST FIPS 197, Appendix A.1 (key schedule) and
// Appendix B (encrypt/decrypt).
//
// TEST_BLOCKS (default: auto from NR_LANES) controls how many independent
// 128-bit AES element groups are processed in parallel.
// Override at compile time with -DTEST_BLOCKS=N (1, 2, 4, or 8).
// Maps to VL = TEST_BLOCKS * 4 elements at SEW=32. LMUL remains m1; with the
// default VLEN=4096, one vector register already holds all supported cases.

#include <stdint.h>
#include <string.h>

#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#include "runtime.h"
#endif

// ---------------------------------------------------------------------------
// TEST_BLOCKS configuration
// ---------------------------------------------------------------------------

// Auto-select TEST_BLOCKS based on NR_LANES if not explicitly set.
// With NR_LANES lanes, a single AES block (4 columns) uses min(4, NR_LANES)
// lanes. To exercise all lanes, we need ceil(NR_LANES / 4) blocks, clamped
// to a valid LMUL (1, 2, 4, 8). For NR_LANES <= 4, TEST_BLOCKS=1 suffices.
#ifndef TEST_BLOCKS
#if defined(NR_LANES) && NR_LANES > 4
#if NR_LANES <= 8
#define TEST_BLOCKS 2
#elif NR_LANES <= 16
#define TEST_BLOCKS 4
#else
#define TEST_BLOCKS 8
#endif
#else
#define TEST_BLOCKS 1
#endif
#endif

#define TEST_VL (TEST_BLOCKS * 4)

// Max supported TEST_BLOCKS (8 blocks → 32 words)
#define MAX_WORDS (8 * 4)

#if TEST_BLOCKS != 1 && TEST_BLOCKS != 2 && TEST_BLOCKS != 4 && TEST_BLOCKS != 8
#error "TEST_BLOCKS must be 1, 2, 4, or 8"
#endif

// ---------------------------------------------------------------------------
// VL helpers
// ---------------------------------------------------------------------------

// Set VL = TEST_VL with SEW=32, LMUL=m1.
static inline void aes_vset(void) {
  unsigned long vl;
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(TEST_VL));
  (void)vl;
}

// Set VL=4, m1 (for loading single-block .vs keys)
static inline void aes_vset4(void) {
  unsigned long vl;
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
  (void)vl;
}

// ---------------------------------------------------------------------------
// NIST FIPS 197 test vectors – stored as little-endian uint32_t words.
// ---------------------------------------------------------------------------

static const uint32_t aes128_key[4] __attribute__((aligned(16))) = {
    0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09};

static const uint32_t plaintext[4] __attribute__((aligned(16))) = {
    0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0};

static const uint32_t expected_ct[4] = {0x1d842539, 0xfb09dc02, 0x978511dc,
                                        0x320b6a19};

// Intermediate states for single-instruction tests
static const uint32_t state_after_rk0[4] = {0xbee33d19, 0x2be2f4a0, 0x2a8dc69a,
                                            0x0848f8e9};

static const uint32_t state_after_round1[4] = {0xf27f9ca4, 0x2b359f68,
                                               0x43ea5b6b, 0x49506a02};

static const uint32_t state_after_round9[4] = {0x1ef240eb, 0x84382e59,
                                               0xe713a18b, 0xd242c31b};

static const uint32_t state_after_ct_rk10[4] = {0xb57d31e9, 0x722c32cb,
                                                0x5f892e3d, 0x940709af};

static const uint32_t state_after_inv_round9[4] = {0xa6466e87, 0x8ce74cf2,
                                                   0xd84a904d, 0x95c3ec97};

static const uint32_t state_before_final_decrypt[4] = {0x305dbfd4, 0xae52b4e0,
                                                       0xf11141b8, 0xe598271e};

static const uint32_t expected_rk[11][4] = {
    {0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09}, // RK 0
    {0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a}, // RK 1
    {0xf295c2f2, 0x43b9967a, 0x7a803559, 0x7ff65973}, // RK 2
    {0x7d47803d, 0x3efe1647, 0x447e231e, 0x3b887a6d}, // RK 3
    {0x41a544ef, 0x7f5b52a8, 0x3b2571b6, 0x00ad0bdb}, // RK 4
    {0xf8c6d1d4, 0x879d837c, 0xbcb8f2ca, 0xbc15f911}, // RK 5
    {0x7aa3886d, 0xfd3e0b11, 0x4186f9db, 0xfd9300ca}, // RK 6
    {0x0ef7544e, 0xf3c95f5f, 0xb24fa684, 0x4fdca64e}, // RK 7
    {0x2173d2ea, 0xd2ba8db5, 0x60f52b31, 0x2f298d7f}, // RK 8
    {0xf36677ac, 0x21dcfa19, 0x4129d128, 0x6e005c57}, // RK 9
    {0xa8f914d0, 0x8925eec9, 0xc80c3fe1, 0xa60c63b6}, // RK10
};

// ---------------------------------------------------------------------------
// Working buffers (aligned, sized for max TEST_BLOCKS=8)
// ---------------------------------------------------------------------------
static uint32_t buf_vd[MAX_WORDS] __attribute__((aligned(128)));
static uint32_t buf_vs2[MAX_WORDS] __attribute__((aligned(128)));
static uint32_t buf_result[MAX_WORDS] __attribute__((aligned(128)));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Replicate a 4-word AES block across TEST_BLOCKS blocks.
static void rep4(uint32_t *dst, const uint32_t src[4]) {
  for (int b = 0; b < TEST_BLOCKS; b++)
    for (int i = 0; i < 4; i++)
      dst[b * 4 + i] = src[i];
}

// Compare TEST_VL words: each 4-word block must match expected[].
static int cmp_blocks(const uint32_t *got, const uint32_t *expected,
                      const char *tag) {
  int err = 0;
  for (int i = 0; i < TEST_VL; i++) {
    if (got[i] != expected[i % 4]) {
      printf("  %s[%d]: got 0x%x, exp 0x%x\n", tag, i, (unsigned)got[i],
             (unsigned)expected[i % 4]);
      err = 1;
    }
  }
  return err;
}

// Store v8 → buf_result, then compare blocks against expected.
static int store_and_check(const uint32_t expected[4], const char *tag) {
  aes_vset();
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  return cmp_blocks(buf_result, expected, tag);
}

// Load replicated state into v8, replicated key into v16 (.vv variant).
static void load_vv(const uint32_t state[4], const uint32_t key[4]) {
  rep4(buf_vd, state);
  rep4(buf_vs2, key);
  aes_vset();
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
}

// Load replicated state into v8 (full LMUL), key into v16 with m1 (.vs
// variant).
static void load_vs(const uint32_t state[4], const uint32_t key[4]) {
  rep4(buf_vd, state);
  aes_vset();
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(key) : "memory");
  aes_vset();
}

// ---------------------------------------------------------------------------
// Test 1 – vaeskf1.vi (AES-128 key schedule, rounds 1..10)
// ---------------------------------------------------------------------------
static int test_key_schedule(void) {
  uint32_t round_keys[11][4] __attribute__((aligned(16)));
  int fail = 0;
  printf("Test 1: vaeskf1 (key schedule, %d blocks)\n", TEST_BLOCKS);

  // Copy RK0
  rep4(buf_vd, aes128_key);
  aes_vset();

  // Load RK0 → v16
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vd) : "memory");

  // Generate round keys 1..10, alternating v8↔v16.
  // Round number is an immediate, so we must unroll.
  asm volatile("vaeskf1.vi v8, v16, 1");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[1][i] = buf_result[i];

  asm volatile("vaeskf1.vi v16, v8, 2");
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[2][i] = buf_result[i];

  asm volatile("vaeskf1.vi v8, v16, 3");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[3][i] = buf_result[i];

  asm volatile("vaeskf1.vi v16, v8, 4");
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[4][i] = buf_result[i];

  asm volatile("vaeskf1.vi v8, v16, 5");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[5][i] = buf_result[i];

  asm volatile("vaeskf1.vi v16, v8, 6");
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[6][i] = buf_result[i];

  asm volatile("vaeskf1.vi v8, v16, 7");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[7][i] = buf_result[i];

  asm volatile("vaeskf1.vi v16, v8, 8");
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[8][i] = buf_result[i];

  asm volatile("vaeskf1.vi v8, v16, 9");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[9][i] = buf_result[i];

  asm volatile("vaeskf1.vi v16, v8, 10");
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_result) : "memory");
  for (int i = 0; i < 4; i++)
    round_keys[10][i] = buf_result[i];

  for (int i = 0; i < 4; i++)
    round_keys[0][i] = aes128_key[i];

  for (int i = 0; i < 11; i++) {
    int mismatch = 0;
    for (int j = 0; j < 4; j++) {
      if (round_keys[i][j] != expected_rk[i][j]) {
        printf("  RK%d[%d]: got 0x%x, exp 0x%x\n", i, j,
               (unsigned)round_keys[i][j], (unsigned)expected_rk[i][j]);
        mismatch = 1;
      }
    }
    if (mismatch) {
      printf("  FAIL round key %d\n", i);
      fail++;
    }
  }

  // For multi-block, also verify all blocks match (check block 0 vs others)
  if (TEST_BLOCKS > 1) {
    // Re-check the last generated key stored in buf_result
    for (int b = 1; b < TEST_BLOCKS; b++)
      for (int i = 0; i < 4; i++)
        if (buf_result[b * 4 + i] != buf_result[i]) {
          printf("  Block %d mismatch at [%d]: 0x%x vs 0x%x\n", b, i,
                 (unsigned)buf_result[b * 4 + i], (unsigned)buf_result[i]);
          fail++;
        }
  }

  if (!fail)
    printf("  PASSED (all 11 round keys)\n");
  return fail;
}

// ---------------------------------------------------------------------------
// Tests 2-9 – Single-instruction checks
// Each tests one instruction with realistic AES round-state inputs.
// .vv variants use replicated state+key; .vs variants use broadcast key.
// ---------------------------------------------------------------------------

static int test_vaesz_vs(void) {
  printf("Test 2: vaesz.vs (%d blocks)\n", TEST_BLOCKS);
  load_vs(plaintext, expected_rk[0]);
  asm volatile("vaesz.vs v8, v16");
  if (store_and_check(state_after_rk0, "RK0")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesem_vv(void) {
  printf("Test 3: vaesem.vv (%d blocks)\n", TEST_BLOCKS);
  load_vv(state_after_rk0, expected_rk[1]);
  asm volatile("vaesem.vv v8, v16");
  if (store_and_check(state_after_round1, "R1")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesem_vs(void) {
  printf("Test 4: vaesem.vs (%d blocks)\n", TEST_BLOCKS);
  load_vs(state_after_rk0, expected_rk[1]);
  asm volatile("vaesem.vs v8, v16");
  if (store_and_check(state_after_round1, "R1")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesef_vv(void) {
  printf("Test 5: vaesef.vv (%d blocks)\n", TEST_BLOCKS);
  load_vv(state_after_round9, expected_rk[10]);
  asm volatile("vaesef.vv v8, v16");
  if (store_and_check(expected_ct, "CT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesef_vs(void) {
  printf("Test 6: vaesef.vs (%d blocks)\n", TEST_BLOCKS);
  load_vs(state_after_round9, expected_rk[10]);
  asm volatile("vaesef.vs v8, v16");
  if (store_and_check(expected_ct, "CT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesdm_vv(void) {
  printf("Test 7: vaesdm.vv (%d blocks)\n", TEST_BLOCKS);
  load_vv(state_after_ct_rk10, expected_rk[9]);
  asm volatile("vaesdm.vv v8, v16");
  if (store_and_check(state_after_inv_round9, "R9")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesdm_vs(void) {
  printf("Test 8: vaesdm.vs (%d blocks)\n", TEST_BLOCKS);
  load_vs(state_after_ct_rk10, expected_rk[9]);
  asm volatile("vaesdm.vs v8, v16");
  if (store_and_check(state_after_inv_round9, "R9")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesdf_vv(void) {
  printf("Test 9: vaesdf.vv (%d blocks)\n", TEST_BLOCKS);
  load_vv(state_before_final_decrypt, expected_rk[0]);
  asm volatile("vaesdf.vv v8, v16");
  if (store_and_check(plaintext, "PT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

static int test_vaesdf_vs(void) {
  printf("Test 10: vaesdf.vs (%d blocks)\n", TEST_BLOCKS);
  load_vs(state_before_final_decrypt, expected_rk[0]);
  asm volatile("vaesdf.vs v8, v16");
  if (store_and_check(plaintext, "PT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
// Test 11 – AES-128 encryption (.vv)
// vaesz.vs + vaesem.vv×9 + vaesef.vv
// ---------------------------------------------------------------------------
static int test_encrypt_vv(void) {
  printf("Test 11: AES-128 encrypt .vv (%d blocks)\n", TEST_BLOCKS);

  // Round 0: AddRoundKey
  load_vs(plaintext, expected_rk[0]);
  asm volatile("vaesz.vs v8, v16");

  // Rounds 1-9: middle
  for (int i = 1; i <= 9; i++) {
    rep4(buf_vs2, expected_rk[i]);
    aes_vset();
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesem.vv v8, v16");
  }

  // Round 10: final
  rep4(buf_vs2, expected_rk[10]);
  aes_vset();
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesef.vv v8, v16");

  if (store_and_check(expected_ct, "CT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
// Test 12 – AES-128 decryption (.vv)
// vaesz.vs + vaesdm.vv×9 + vaesdf.vv
// ---------------------------------------------------------------------------
static int test_decrypt_vv(void) {
  printf("Test 12: AES-128 decrypt .vv (%d blocks)\n", TEST_BLOCKS);

  // Round 0: AddRoundKey with RK10
  load_vs(expected_ct, expected_rk[10]);
  asm volatile("vaesz.vs v8, v16");

  // Rounds 9-1: decrypt middle
  for (int i = 9; i >= 1; i--) {
    rep4(buf_vs2, expected_rk[i]);
    aes_vset();
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesdm.vv v8, v16");
  }

  // Final: decrypt with RK0
  rep4(buf_vs2, expected_rk[0]);
  aes_vset();
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesdf.vv v8, v16");

  if (store_and_check(plaintext, "PT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
// Test 13 – AES-128 encryption (.vs)
// vaesz.vs + vaesem.vs×9 + vaesef.vs
// ---------------------------------------------------------------------------
static int test_encrypt_vs(void) {
  printf("Test 13: AES-128 encrypt .vs (%d blocks)\n", TEST_BLOCKS);

  // Round 0: AddRoundKey
  load_vs(plaintext, expected_rk[0]);
  asm volatile("vaesz.vs v8, v16");

  // Rounds 1-9: middle (.vs — key broadcast from group 0)
  for (int i = 1; i <= 9; i++) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[i]) : "memory");
    aes_vset();
    asm volatile("vaesem.vs v8, v16");
  }

  // Round 10: final (.vs)
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[10]) : "memory");
  aes_vset();
  asm volatile("vaesef.vs v8, v16");

  if (store_and_check(expected_ct, "CT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
// Test 14 – AES-128 decryption (.vs)
// vaesz.vs + vaesdm.vs×9 + vaesdf.vs
// ---------------------------------------------------------------------------
static int test_decrypt_vs(void) {
  printf("Test 14: AES-128 decrypt .vs (%d blocks)\n", TEST_BLOCKS);

  // Round 0: AddRoundKey with RK10
  load_vs(expected_ct, expected_rk[10]);
  asm volatile("vaesz.vs v8, v16");

  // Rounds 9-1: decrypt middle (.vs)
  for (int i = 9; i >= 1; i--) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[i]) : "memory");
    aes_vset();
    asm volatile("vaesdm.vs v8, v16");
  }

  // Final: decrypt with RK0 (.vs)
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[0]) : "memory");
  aes_vset();
  asm volatile("vaesdf.vs v8, v16");

  if (store_and_check(plaintext, "PT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
// Test 15 – Round-trip: encrypt then decrypt must recover plaintext
// ---------------------------------------------------------------------------
static int test_roundtrip(void) {
  printf("Test 15: encrypt-then-decrypt round-trip (%d blocks)\n", TEST_BLOCKS);

  // Encrypt (.vv)
  load_vs(plaintext, expected_rk[0]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 1; i <= 9; i++) {
    rep4(buf_vs2, expected_rk[i]);
    aes_vset();
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesem.vv v8, v16");
  }
  rep4(buf_vs2, expected_rk[10]);
  aes_vset();
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesef.vv v8, v16");

  // Decrypt (.vs — different variant to cross-check)
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[10]) : "memory");
  aes_vset();
  asm volatile("vaesz.vs v8, v16");
  for (int i = 9; i >= 1; i--) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[i]) : "memory");
    aes_vset();
    asm volatile("vaesdm.vs v8, v16");
  }
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(expected_rk[0]) : "memory");
  aes_vset();
  asm volatile("vaesdf.vs v8, v16");

  if (store_and_check(plaintext, "RT")) {
    printf("  FAIL\n");
    return 1;
  }
  printf("  PASSED\n");
  return 0;
}

// ---------------------------------------------------------------------------
int main(void) {
  int num_failed = 0;

  printf("=== Zvkned AES-128 Test Suite (TEST_BLOCKS=%d, VL=%d) ===\n\n",
         TEST_BLOCKS, TEST_VL);

  num_failed += test_key_schedule();
  num_failed += test_vaesz_vs();
  num_failed += test_vaesem_vv();
  num_failed += test_vaesem_vs();
  num_failed += test_vaesef_vv();
  num_failed += test_vaesef_vs();
  num_failed += test_vaesdm_vv();
  num_failed += test_vaesdm_vs();
  num_failed += test_vaesdf_vv();
  num_failed += test_vaesdf_vs();
  num_failed += test_encrypt_vv();
  num_failed += test_decrypt_vv();
  num_failed += test_encrypt_vs();
  num_failed += test_decrypt_vs();
  num_failed += test_roundtrip();

  printf("\n=== Summary: %d test(s) failed ===\n", num_failed);
  return num_failed;
}
