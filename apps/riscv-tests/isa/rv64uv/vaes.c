// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvkned AES instruction tests.
// Test vectors come from NIST FIPS 197 Appendix A.1, A.3, and B.

#include "vector_macros.h"

static const int k_block_configs[] = {1, 2, 4, 8};

static const uint32_t rk128_0[4] = {0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09};
static const uint32_t rk128_1[4] = {0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a};
static const uint32_t rk128_2[4] = {0xf295c2f2, 0x43b9967a, 0x7a803559, 0x7ff65973};
static const uint32_t plaintext[4] = {0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0};
static const uint32_t ciphertext[4] = {0x1d842539, 0xfb09dc02, 0x978511dc, 0x320b6a19};
static const uint32_t state_after_rk0[4] = {0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9};
static const uint32_t state_after_round1[4] = {0xf27f9ca4, 0x2b359f68, 0x43ea5b6b, 0x49506a02};
static const uint32_t state_after_round9[4] = {0x1ef240eb, 0x84382e59, 0xe713a18b, 0xd242c31b};
static const uint32_t state_after_ct_rk10[4] = {0xb57d31e9, 0x722c32cb, 0x5f892e3d, 0x940709af};
static const uint32_t state_after_inv_round9[4] = {0xa6466e87, 0x8ce74cf2, 0xd84a904d, 0x95c3ec97};
static const uint32_t state_before_final_decrypt[4] = {0x305dbfd4, 0xae52b4e0, 0xf11141b8, 0xe598271e};

static const uint32_t all_rk128[11][4] = {
    {0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09},
    {0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a},
    {0xf295c2f2, 0x43b9967a, 0x7a803559, 0x7ff65973},
    {0x7d47803d, 0x3efe1647, 0x447e231e, 0x3b887a6d},
    {0x41a544ef, 0x7f5b52a8, 0x3b2571b6, 0x00ad0bdb},
    {0xf8c6d1d4, 0x879d837c, 0xbcb8f2ca, 0xbc15f911},
    {0x7aa3886d, 0xfd3e0b11, 0x4186f9db, 0xfd9300ca},
    {0x0ef7544e, 0xf3c95f5f, 0xb24fa684, 0x4fdca64e},
    {0x2173d2ea, 0xd2ba8db5, 0x60f52b31, 0x2f298d7f},
    {0xf36677ac, 0x21dcfa19, 0x4129d128, 0x6e005c57},
    {0xa8f914d0, 0x8925eec9, 0xc80c3fe1, 0xa60c63b6},
};

static const uint32_t rk256_0[4] = {0x10eb3d60, 0xbe71ca15, 0xf0ae732b, 0x81777d85};
static const uint32_t rk256_1[4] = {0x072c351f, 0xd708613b, 0xa310982d, 0xf4df1409};
static const uint32_t rk256_2[4] = {0x1154a39b, 0xaf25698e, 0x5f8b1aa5, 0xdefc6720};
static const uint32_t rk256_3[4] = {0x1a9cb0a8, 0xcd94d193, 0x6e8449be, 0x9a5b5db7};

static volatile uint32_t buf_vd[8 * 4] __attribute__((aligned(128)));
static volatile uint32_t buf_vs2[8 * 4] __attribute__((aligned(128)));
static volatile uint32_t buf_out[8 * 4] __attribute__((aligned(128)));

static inline int aes_vl(int blocks) { return blocks * 4; }

static void aes_vset_blocks(int blocks) {
  switch (blocks) {
    case 1: VSET(4, e32, m1); break;
    case 2: VSET(8, e32, m2); break;
    case 4: VSET(16, e32, m4); break;
    case 8: VSET(32, e32, m8); break;
    default:
      printf("Invalid block count: %d\n", blocks);
      num_failed++;
      break;
  }
}

static inline void aes_vset4(void) { VSET(4, e32, m1); }

static void rep4(volatile uint32_t *dst, const uint32_t src[4], int blocks) {
  for (int b = 0; b < blocks; ++b)
    for (int i = 0; i < 4; ++i) dst[b * 4 + i] = src[i];
}

static void store_v8(int blocks) {
  aes_vset_blocks(blocks);
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_out) : "memory");
}

static void store_v16(int blocks) {
  aes_vset_blocks(blocks);
  asm volatile("vse32.v v16, (%0)" ::"r"(buf_out) : "memory");
}

static void load_vv(int blocks, const uint32_t state[4], const uint32_t key[4]) {
  rep4(buf_vd, state, blocks);
  rep4(buf_vs2, key, blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
}

static void load_vs(int blocks, const uint32_t state[4], const uint32_t key[4]) {
  rep4(buf_vd, state, blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(key) : "memory");
  aes_vset_blocks(blocks);
}

static void start_case(const char *name, int blocks) {
  ++test_case;
  printf("Test %d (%d blocks): %s\n", test_case, blocks, name);
}

static void expect_words(const char *name, int blocks, const uint32_t expected[4], int reg_v16) {
  if (reg_v16)
    store_v16(blocks);
  else
    store_v8(blocks);

  for (int i = 0; i < aes_vl(blocks); ++i) {
    uint32_t got = buf_out[i];
    uint32_t exp = expected[i % 4];
    if (got != exp) {
      printf("  FAILED at word %d: got 0x%08x expected 0x%08x\n", i, got, exp);
      num_failed++;
      return;
    }
  }
  printf("  PASSED.\n");
}

static void test_aes128_key_schedule(int blocks) {
  start_case("vaeskf1.vi AES-128 key schedule", blocks);

  rep4(buf_vs2, rk128_0, blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");

  asm volatile("vaeskf1.vi v8, v16, 1");
  expect_words("vaeskf1 round 1", blocks, all_rk128[1], 0);

  asm volatile("vaeskf1.vi v16, v8, 2");
  expect_words("vaeskf1 round 2", blocks, all_rk128[2], 1);

  asm volatile("vaeskf1.vi v8, v16, 3");
  expect_words("vaeskf1 round 3", blocks, all_rk128[3], 0);

  asm volatile("vaeskf1.vi v16, v8, 4");
  expect_words("vaeskf1 round 4", blocks, all_rk128[4], 1);

  asm volatile("vaeskf1.vi v8, v16, 5");
  expect_words("vaeskf1 round 5", blocks, all_rk128[5], 0);

  asm volatile("vaeskf1.vi v16, v8, 6");
  expect_words("vaeskf1 round 6", blocks, all_rk128[6], 1);

  asm volatile("vaeskf1.vi v8, v16, 7");
  expect_words("vaeskf1 round 7", blocks, all_rk128[7], 0);

  asm volatile("vaeskf1.vi v16, v8, 8");
  expect_words("vaeskf1 round 8", blocks, all_rk128[8], 1);

  asm volatile("vaeskf1.vi v8, v16, 9");
  expect_words("vaeskf1 round 9", blocks, all_rk128[9], 0);

  asm volatile("vaeskf1.vi v16, v8, 10");
  expect_words("vaeskf1 round 10", blocks, all_rk128[10], 1);
}

static void test_aes256_key_schedule(int blocks) {
  start_case("vaeskf2.vi AES-256 even round", blocks);
  rep4(buf_vd, rk256_0, blocks);
  rep4(buf_vs2, rk256_1, blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaeskf2.vi v8, v16, 2");
  expect_words("vaeskf2 round 2", blocks, rk256_2, 0);

  start_case("vaeskf2.vi AES-256 odd round", blocks);
  rep4(buf_vd, rk256_1, blocks);
  rep4(buf_vs2, rk256_2, blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaeskf2.vi v8, v16, 3");
  expect_words("vaeskf2 round 3", blocks, rk256_3, 0);
}

static void test_vaesz_vs(int blocks) {
  start_case("vaesz.vs", blocks);
  load_vs(blocks, plaintext, all_rk128[0]);
  asm volatile("vaesz.vs v8, v16");
  expect_words("vaesz.vs", blocks, state_after_rk0, 0);
}

static void test_vaesem_vv(int blocks) {
  start_case("vaesem.vv", blocks);
  load_vv(blocks, state_after_rk0, all_rk128[1]);
  asm volatile("vaesem.vv v8, v16");
  expect_words("vaesem.vv", blocks, state_after_round1, 0);
}

static void test_vaesem_vs(int blocks) {
  start_case("vaesem.vs", blocks);
  load_vs(blocks, state_after_rk0, all_rk128[1]);
  asm volatile("vaesem.vs v8, v16");
  expect_words("vaesem.vs", blocks, state_after_round1, 0);
}

static void test_vaesef_vv(int blocks) {
  start_case("vaesef.vv", blocks);
  load_vv(blocks, state_after_round9, all_rk128[10]);
  asm volatile("vaesef.vv v8, v16");
  expect_words("vaesef.vv", blocks, ciphertext, 0);
}

static void test_vaesef_vs(int blocks) {
  start_case("vaesef.vs", blocks);
  load_vs(blocks, state_after_round9, all_rk128[10]);
  asm volatile("vaesef.vs v8, v16");
  expect_words("vaesef.vs", blocks, ciphertext, 0);
}

static void test_vaesdm_vv(int blocks) {
  start_case("vaesdm.vv", blocks);
  load_vv(blocks, state_after_ct_rk10, all_rk128[9]);
  asm volatile("vaesdm.vv v8, v16");
  expect_words("vaesdm.vv", blocks, state_after_inv_round9, 0);
}

static void test_vaesdm_vs(int blocks) {
  start_case("vaesdm.vs", blocks);
  load_vs(blocks, state_after_ct_rk10, all_rk128[9]);
  asm volatile("vaesdm.vs v8, v16");
  expect_words("vaesdm.vs", blocks, state_after_inv_round9, 0);
}

static void test_vaesdf_vv(int blocks) {
  start_case("vaesdf.vv", blocks);
  load_vv(blocks, state_before_final_decrypt, all_rk128[0]);
  asm volatile("vaesdf.vv v8, v16");
  expect_words("vaesdf.vv", blocks, plaintext, 0);
}

static void test_vaesdf_vs(int blocks) {
  start_case("vaesdf.vs", blocks);
  load_vs(blocks, state_before_final_decrypt, all_rk128[0]);
  asm volatile("vaesdf.vs v8, v16");
  expect_words("vaesdf.vs", blocks, plaintext, 0);
}

static void test_encrypt_vv(int blocks) {
  start_case("AES-128 encrypt .vv", blocks);
  load_vs(blocks, plaintext, all_rk128[0]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 1; i <= 9; ++i) {
    rep4(buf_vs2, all_rk128[i], blocks);
    aes_vset_blocks(blocks);
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesem.vv v8, v16");
  }
  rep4(buf_vs2, all_rk128[10], blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesef.vv v8, v16");
  expect_words("encrypt .vv", blocks, ciphertext, 0);
}

static void test_decrypt_vv(int blocks) {
  start_case("AES-128 decrypt .vv", blocks);
  load_vs(blocks, ciphertext, all_rk128[10]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 9; i >= 1; --i) {
    rep4(buf_vs2, all_rk128[i], blocks);
    aes_vset_blocks(blocks);
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesdm.vv v8, v16");
  }
  rep4(buf_vs2, all_rk128[0], blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesdf.vv v8, v16");
  expect_words("decrypt .vv", blocks, plaintext, 0);
}

static void test_encrypt_vs(int blocks) {
  start_case("AES-128 encrypt .vs", blocks);
  load_vs(blocks, plaintext, all_rk128[0]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 1; i <= 9; ++i) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[i]) : "memory");
    aes_vset_blocks(blocks);
    asm volatile("vaesem.vs v8, v16");
  }
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[10]) : "memory");
  aes_vset_blocks(blocks);
  asm volatile("vaesef.vs v8, v16");
  expect_words("encrypt .vs", blocks, ciphertext, 0);
}

static void test_decrypt_vs(int blocks) {
  start_case("AES-128 decrypt .vs", blocks);
  load_vs(blocks, ciphertext, all_rk128[10]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 9; i >= 1; --i) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[i]) : "memory");
    aes_vset_blocks(blocks);
    asm volatile("vaesdm.vs v8, v16");
  }
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[0]) : "memory");
  aes_vset_blocks(blocks);
  asm volatile("vaesdf.vs v8, v16");
  expect_words("decrypt .vs", blocks, plaintext, 0);
}

static void test_roundtrip(int blocks) {
  start_case("AES-128 round-trip", blocks);
  load_vs(blocks, plaintext, all_rk128[0]);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 1; i <= 9; ++i) {
    rep4(buf_vs2, all_rk128[i], blocks);
    aes_vset_blocks(blocks);
    asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
    asm volatile("vaesem.vv v8, v16");
  }
  rep4(buf_vs2, all_rk128[10], blocks);
  aes_vset_blocks(blocks);
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vaesef.vv v8, v16");

  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[10]) : "memory");
  aes_vset_blocks(blocks);
  asm volatile("vaesz.vs v8, v16");
  for (int i = 9; i >= 1; --i) {
    aes_vset4();
    asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[i]) : "memory");
    aes_vset_blocks(blocks);
    asm volatile("vaesdm.vs v8, v16");
  }
  aes_vset4();
  asm volatile("vle32.v v16, (%0)" ::"r"(all_rk128[0]) : "memory");
  aes_vset_blocks(blocks);
  asm volatile("vaesdf.vs v8, v16");
  expect_words("round-trip", blocks, plaintext, 0);
}

static void run_config(int blocks) {
  printf("\n=== Zvkned configuration: %d blocks ===\n", blocks);
  test_aes128_key_schedule(blocks);
  test_aes256_key_schedule(blocks);
  test_vaesz_vs(blocks);
  test_vaesem_vv(blocks);
  test_vaesem_vs(blocks);
  test_vaesef_vv(blocks);
  test_vaesef_vs(blocks);
  test_vaesdm_vv(blocks);
  test_vaesdm_vs(blocks);
  test_vaesdf_vv(blocks);
  test_vaesdf_vs(blocks);
  test_encrypt_vv(blocks);
  test_decrypt_vv(blocks);
  test_encrypt_vs(blocks);
  test_decrypt_vs(blocks);
  test_roundtrip(blocks);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  for (unsigned i = 0; i < sizeof(k_block_configs) / sizeof(k_block_configs[0]); ++i)
    run_config(k_block_configs[i]);

  EXIT_CHECK();
}
