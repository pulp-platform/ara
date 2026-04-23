// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvkg (vghsh.vv / vgmul.vv) instruction tests.
// Each instruction operates on 128-bit element groups (EGS=4, SEW=32).
// The scalar reference below mirrors the Spike specification:
//   vghsh.vv vd, vs2, vs1:  vd = brev8( GFMUL( brev8(vd ^ vs1), brev8(vs2) ) )
//   vgmul.vv vd, vs2    :   vd = brev8( GFMUL( brev8(vd)       , brev8(vs2) ) )
// with GFMUL in GF(2^128), reduction polynomial x^128 + x^7 + x^2 + x + 1
// (low-byte XOR constant 0x87).

#include "vector_macros.h"

static const int k_gcm_groups[] = {1, 2, 4, 8};

// Arbitrary but fixed test vectors. These are NOT NIST GCM vectors; they are
// chosen to stress every bit position of the GF(2^128) multiplier while being
// reproducible and self-verifying via the scalar reference above.
static const uint32_t k_vd[4]  = {0xdeadbeefu, 0xcafebabeu,
                                  0x12345678u, 0x9abcdef0u};
static const uint32_t k_vs2[4] = {0x00112233u, 0x44556677u,
                                  0x8899aabbu, 0xccddeeffu};
static const uint32_t k_vs1[4] = {0xfeedfaceu, 0xbaadc0deu,
                                  0x0badcafeu, 0x5a5a5a5au};

static volatile uint32_t buf_vd [32] __attribute__((aligned(128)));
static volatile uint32_t buf_vs2[32] __attribute__((aligned(128)));
static volatile uint32_t buf_vs1[32] __attribute__((aligned(128)));
static volatile uint32_t buf_out[32] __attribute__((aligned(128)));

static void start_case(const char *name, int groups) {
  ++test_case;
  printf("Test %d (%d groups): %s\n", test_case, groups, name);
}

static void vset_gcm_groups(int groups) {
  switch (groups) {
  case 1: VSET(4,  e32, m1); break;
  case 2: VSET(8,  e32, m2); break;
  case 4: VSET(16, e32, m4); break;
  case 8: VSET(32, e32, m8); break;
  default:
    printf("Unsupported Zvkg group count: %d\n", groups);
    ++num_failed;
    break;
  }
}

static void rep32(volatile uint32_t *dst, const uint32_t src[4], int groups) {
  for (int g = 0; g < groups; ++g)
    for (int i = 0; i < 4; ++i)
      dst[g * 4 + i] = src[i];
}

static int check32(const uint32_t expected[4], int groups) {
  for (int i = 0; i < groups * 4; ++i) {
    uint32_t exp = expected[i % 4];
    if (buf_out[i] != exp) {
      printf("  FAILED at word %d: got 0x%08x expected 0x%08x\n", i,
             buf_out[i], exp);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

// ---------------------------------------------------------------------------
// Scalar reference: 128-bit GF(2^128) multiply + brev8, matching Spike.
// ---------------------------------------------------------------------------

static uint8_t brev8_byte(uint8_t x) {
  x = (uint8_t)(((x & 0xF0u) >> 4) | ((x & 0x0Fu) << 4));
  x = (uint8_t)(((x & 0xCCu) >> 2) | ((x & 0x33u) << 2));
  x = (uint8_t)(((x & 0xAAu) >> 1) | ((x & 0x55u) << 1));
  return x;
}

static void brev8_eg(uint32_t x[4]) {
  for (int w = 0; w < 4; ++w) {
    uint32_t v = x[w];
    uint32_t r = 0;
    for (int b = 0; b < 4; ++b) {
      uint8_t byte = (uint8_t)(v >> (8 * b));
      r |= (uint32_t)brev8_byte(byte) << (8 * b);
    }
    x[w] = r;
  }
}

static int isset128(const uint32_t X[4], int bit) {
  return (X[bit / 32] >> (bit % 32)) & 1u;
}

static void xor128(uint32_t Z[4], const uint32_t H[4]) {
  for (int i = 0; i < 4; ++i) Z[i] ^= H[i];
}

// 128-bit left shift by 1 across the 4x32 element group (LE layout).
static void lshift128(uint32_t X[4]) {
  uint64_t lo = ((uint64_t)X[1] << 32) | X[0];
  uint64_t hi = ((uint64_t)X[3] << 32) | X[2];
  uint64_t carry = (lo >> 63) & 1ull;
  lo <<= 1;
  hi = (hi << 1) | carry;
  X[0] = (uint32_t)lo;
  X[1] = (uint32_t)(lo >> 32);
  X[2] = (uint32_t)hi;
  X[3] = (uint32_t)(hi >> 32);
}

static void gfmul128(uint32_t Z[4], const uint32_t S[4], const uint32_t H_in[4]) {
  uint32_t H[4];
  for (int i = 0; i < 4; ++i) H[i] = H_in[i];
  for (int i = 0; i < 4; ++i) Z[i] = 0;
  for (int bit = 0; bit < 128; ++bit) {
    if (isset128(S, bit)) xor128(Z, H);
    int reduce = (H[3] >> 31) & 1u;
    lshift128(H);
    if (reduce) H[0] ^= 0x87u;
  }
}

static void vghsh_ref(uint32_t out[4], const uint32_t vd[4],
                      const uint32_t vs2[4], const uint32_t vs1[4]) {
  uint32_t Y[4], X[4], H[4], S[4], Z[4];
  for (int i = 0; i < 4; ++i) { Y[i] = vd[i];  X[i] = vs1[i]; H[i] = vs2[i]; }
  brev8_eg(H);
  for (int i = 0; i < 4; ++i) S[i] = Y[i] ^ X[i];
  brev8_eg(S);
  gfmul128(Z, S, H);
  brev8_eg(Z);
  for (int i = 0; i < 4; ++i) out[i] = Z[i];
}

static void vgmul_ref(uint32_t out[4], const uint32_t vd[4],
                      const uint32_t vs2[4]) {
  uint32_t Y[4], H[4], Z[4];
  for (int i = 0; i < 4; ++i) { Y[i] = vd[i]; H[i] = vs2[i]; }
  brev8_eg(Y);
  brev8_eg(H);
  gfmul128(Z, Y, H);
  brev8_eg(Z);
  for (int i = 0; i < 4; ++i) out[i] = Z[i];
}

// ---------------------------------------------------------------------------
// Hardware exercises
// ---------------------------------------------------------------------------

static void test_vghsh(int groups) {
  uint32_t expected[4];

  start_case("vghsh.vv", groups);
  vghsh_ref(expected, k_vd, k_vs2, k_vs1);
  rep32(buf_vd,  k_vd,  groups);
  rep32(buf_vs2, k_vs2, groups);
  rep32(buf_vs1, k_vs1, groups);
  vset_gcm_groups(groups);
  asm volatile("vle32.v v8,  (%0)" ::"r"(buf_vd)  : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vle32.v v24, (%0)" ::"r"(buf_vs1) : "memory");
  asm volatile("vghsh.vv v8, v16, v24");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_out) : "memory");
  check32(expected, groups);
}

static void test_vgmul(int groups) {
  uint32_t expected[4];

  start_case("vgmul.vv", groups);
  vgmul_ref(expected, k_vd, k_vs2);
  rep32(buf_vd,  k_vd,  groups);
  rep32(buf_vs2, k_vs2, groups);
  vset_gcm_groups(groups);
  asm volatile("vle32.v v8,  (%0)" ::"r"(buf_vd)  : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf_vs2) : "memory");
  asm volatile("vgmul.vv v8, v16");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf_out) : "memory");
  check32(expected, groups);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  for (unsigned i = 0; i < sizeof(k_gcm_groups) / sizeof(k_gcm_groups[0]); ++i) {
    const int groups = k_gcm_groups[i];
    printf("\n=== Zvkg configuration: %d groups ===\n", groups);
    test_vghsh(groups);
    test_vgmul(groups);
  }

  EXIT_CHECK();
}
