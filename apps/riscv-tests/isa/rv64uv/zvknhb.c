// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvknhb instruction tests.

#include "vector_macros.h"

static const int k_sha256_groups[] = {1, 2, 4, 8};
static const int k_sha512_groups[] = {1, 2, 4};

static const uint32_t k_sha256_k[4] = {
    0x428a2f98u,
    0x71374491u,
    0xb5c0fbcfu,
    0xe9b5dba5u,
};

static const uint32_t k_sha256_h[8] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
};

static const uint32_t k_sha256_sched_vd[4] = {
    0x80000000u, 0x00000000u, 0x00000000u, 0x00000000u,
};

static const uint32_t k_sha256_sched_vs2[4] = {
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u,
};

static const uint32_t k_sha256_sched_vs1[4] = {
    0x00000000u, 0xdecafbadu, 0x00000000u, 0x00000000u,
};

static const uint64_t k_sha512_k[4] = {
    0x428a2f98d728ae22ull,
    0x7137449123ef65cdull,
    0xb5c0fbcfec4d3b2full,
    0xe9b5dba58189dbbcull,
};

static const uint64_t k_sha512_h[8] = {
    0x6a09e667f3bcc908ull, 0xbb67ae8584caa73bull,
    0x3c6ef372fe94f82bull, 0xa54ff53a5f1d36f1ull,
    0x510e527fade682d1ull, 0x9b05688c2b3e6c1full,
    0x1f83d9abfb41bd6bull, 0x5be0cd19137e2179ull,
};

static const uint64_t k_sha512_sched_vd[4] = {
    0x8000000000000000ull, 0x0000000000000000ull,
    0x0000000000000000ull, 0x0000000000000000ull,
};

static const uint64_t k_sha512_sched_vs2[4] = {
    0x0000000000000000ull, 0x0000000000000000ull,
    0x0000000000000000ull, 0x0000000000000000ull,
};

static const uint64_t k_sha512_sched_vs1[4] = {
    0x0000000000000000ull, 0xdecafbadcafebeefull,
    0x0000000000000000ull, 0x0000000000000000ull,
};

static volatile uint32_t buf32_vd[32] __attribute__((aligned(128)));
static volatile uint32_t buf32_vs2[32] __attribute__((aligned(128)));
static volatile uint32_t buf32_vs1[32] __attribute__((aligned(128)));
static volatile uint32_t buf32_out[32] __attribute__((aligned(128)));

static volatile uint64_t buf64_vd[16] __attribute__((aligned(128)));
static volatile uint64_t buf64_vs2[16] __attribute__((aligned(128)));
static volatile uint64_t buf64_vs1[16] __attribute__((aligned(128)));
static volatile uint64_t buf64_out[16] __attribute__((aligned(128)));

static void start_case(const char *name, int groups) {
  ++test_case;
  printf("Test %d (%d groups): %s\n", test_case, groups, name);
}

static void vset_sha256_groups(int groups) {
  switch (groups) {
  case 1:
    VSET(4, e32, m1);
    break;
  case 2:
    VSET(8, e32, m2);
    break;
  case 4:
    VSET(16, e32, m4);
    break;
  case 8:
    VSET(32, e32, m8);
    break;
  default:
    printf("Unsupported SHA-256 group count: %d\n", groups);
    ++num_failed;
    break;
  }
}

static void vset_sha512_groups(int groups) {
  switch (groups) {
  case 1:
    VSET(4, e64, m2);
    break;
  case 2:
    VSET(8, e64, m4);
    break;
  case 4:
    VSET(16, e64, m8);
    break;
  default:
    printf("Unsupported SHA-512 group count: %d\n", groups);
    ++num_failed;
    break;
  }
}

static void rep32(volatile uint32_t *dst, const uint32_t src[4], int groups) {
  for (int g = 0; g < groups; ++g)
    for (int i = 0; i < 4; ++i)
      dst[g * 4 + i] = src[i];
}

static void rep64(volatile uint64_t *dst, const uint64_t src[4], int groups) {
  for (int g = 0; g < groups; ++g)
    for (int i = 0; i < 4; ++i)
      dst[g * 4 + i] = src[i];
}

static int check32(const uint32_t expected[4], int groups) {
  for (int i = 0; i < groups * 4; ++i) {
    uint32_t exp = expected[i % 4];
    if (buf32_out[i] != exp) {
      printf("  FAILED at word %d: got 0x%08x expected 0x%08x\n", i,
             buf32_out[i], exp);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static int check64(const uint64_t expected[4], int groups) {
  for (int i = 0; i < groups * 4; ++i) {
    uint64_t exp = expected[i % 4];
    if (buf64_out[i] != exp) {
      printf("  FAILED at word %d: got 0x%016llx expected 0x%016llx\n", i,
             (unsigned long long)buf64_out[i], (unsigned long long)exp);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static inline uint32_t ror32(uint32_t x, unsigned sh) {
  return (x >> sh) | (x << (32 - sh));
}

static inline uint64_t ror64(uint64_t x, unsigned sh) {
  return (x >> sh) | (x << (64 - sh));
}

static inline uint32_t sha256_sum0(uint32_t x) {
  return ror32(x, 2) ^ ror32(x, 13) ^ ror32(x, 22);
}

static inline uint32_t sha256_sum1(uint32_t x) {
  return ror32(x, 6) ^ ror32(x, 11) ^ ror32(x, 25);
}

static inline uint32_t sha256_sig0(uint32_t x) {
  return ror32(x, 7) ^ ror32(x, 18) ^ (x >> 3);
}

static inline uint32_t sha256_sig1(uint32_t x) {
  return ror32(x, 17) ^ ror32(x, 19) ^ (x >> 10);
}

static inline uint64_t sha512_sum0(uint64_t x) {
  return ror64(x, 28) ^ ror64(x, 34) ^ ror64(x, 39);
}

static inline uint64_t sha512_sum1(uint64_t x) {
  return ror64(x, 14) ^ ror64(x, 18) ^ ror64(x, 41);
}

static inline uint64_t sha512_sig0(uint64_t x) {
  return ror64(x, 1) ^ ror64(x, 8) ^ (x >> 7);
}

static inline uint64_t sha512_sig1(uint64_t x) {
  return ror64(x, 19) ^ ror64(x, 61) ^ (x >> 6);
}

static inline uint32_t sha_ch32(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (~x & z);
}

static inline uint32_t sha_maj32(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

static inline uint64_t sha_ch64(uint64_t x, uint64_t y, uint64_t z) {
  return (x & y) ^ (~x & z);
}

static inline uint64_t sha_maj64(uint64_t x, uint64_t y, uint64_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

static void sha256_schedule_ref(uint32_t out[4], const uint32_t vd[4],
                                const uint32_t vs2[4], const uint32_t vs1[4]) {
  const uint32_t w0 = vd[0];
  const uint32_t w1 = vd[1];
  const uint32_t w2 = vd[2];
  const uint32_t w3 = vd[3];
  const uint32_t w4 = vs2[0];
  const uint32_t w9 = vs2[1];
  const uint32_t w10 = vs2[2];
  const uint32_t w11 = vs2[3];
  const uint32_t w12 = vs1[0];
  const uint32_t w14 = vs1[2];
  const uint32_t w15 = vs1[3];

  out[0] = sha256_sig1(w14) + w9 + sha256_sig0(w1) + w0;
  out[1] = sha256_sig1(w15) + w10 + sha256_sig0(w2) + w1;
  out[2] = sha256_sig1(out[0]) + w11 + sha256_sig0(w3) + w2;
  out[3] = sha256_sig1(out[1]) + w12 + sha256_sig0(w4) + w3;
}

static void sha512_schedule_ref(uint64_t out[4], const uint64_t vd[4],
                                const uint64_t vs2[4], const uint64_t vs1[4]) {
  const uint64_t w0 = vd[0];
  const uint64_t w1 = vd[1];
  const uint64_t w2 = vd[2];
  const uint64_t w3 = vd[3];
  const uint64_t w4 = vs2[0];
  const uint64_t w9 = vs2[1];
  const uint64_t w10 = vs2[2];
  const uint64_t w11 = vs2[3];
  const uint64_t w12 = vs1[0];
  const uint64_t w14 = vs1[2];
  const uint64_t w15 = vs1[3];

  out[0] = sha512_sig1(w14) + w9 + sha512_sig0(w1) + w0;
  out[1] = sha512_sig1(w15) + w10 + sha512_sig0(w2) + w1;
  out[2] = sha512_sig1(out[0]) + w11 + sha512_sig0(w3) + w2;
  out[3] = sha512_sig1(out[1]) + w12 + sha512_sig0(w4) + w3;
}

static void sha256_compress_round(uint32_t *a, uint32_t *b, uint32_t *c,
                                  uint32_t *d, uint32_t *e, uint32_t *f,
                                  uint32_t *g, uint32_t *h, uint32_t kw) {
  const uint32_t t1 = *h + sha256_sum1(*e) + sha_ch32(*e, *f, *g) + kw;
  const uint32_t t2 = sha256_sum0(*a) + sha_maj32(*a, *b, *c);

  *h = *g;
  *g = *f;
  *f = *e;
  *e = *d + t1;
  *d = *c;
  *c = *b;
  *b = *a;
  *a = t1 + t2;
}

static void sha512_compress_round(uint64_t *a, uint64_t *b, uint64_t *c,
                                  uint64_t *d, uint64_t *e, uint64_t *f,
                                  uint64_t *g, uint64_t *h, uint64_t kw) {
  const uint64_t t1 = *h + sha512_sum1(*e) + sha_ch64(*e, *f, *g) + kw;
  const uint64_t t2 = sha512_sum0(*a) + sha_maj64(*a, *b, *c);

  *h = *g;
  *g = *f;
  *f = *e;
  *e = *d + t1;
  *d = *c;
  *c = *b;
  *b = *a;
  *a = t1 + t2;
}

static void sha256_compress_ref(uint32_t out[4], const uint32_t vd[4],
                                const uint32_t vs2[4], uint32_t kw_first,
                                uint32_t kw_second) {
  uint32_t a = vs2[3];
  uint32_t b = vs2[2];
  uint32_t c = vd[3];
  uint32_t d = vd[2];
  uint32_t e = vs2[1];
  uint32_t f = vs2[0];
  uint32_t g = vd[1];
  uint32_t h = vd[0];

  sha256_compress_round(&a, &b, &c, &d, &e, &f, &g, &h, kw_first);
  sha256_compress_round(&a, &b, &c, &d, &e, &f, &g, &h, kw_second);

  out[0] = f;
  out[1] = e;
  out[2] = b;
  out[3] = a;
}

static void sha512_compress_ref(uint64_t out[4], const uint64_t vd[4],
                                const uint64_t vs2[4], uint64_t kw_first,
                                uint64_t kw_second) {
  uint64_t a = vs2[3];
  uint64_t b = vs2[2];
  uint64_t c = vd[3];
  uint64_t d = vd[2];
  uint64_t e = vs2[1];
  uint64_t f = vs2[0];
  uint64_t g = vd[1];
  uint64_t h = vd[0];

  sha512_compress_round(&a, &b, &c, &d, &e, &f, &g, &h, kw_first);
  sha512_compress_round(&a, &b, &c, &d, &e, &f, &g, &h, kw_second);

  out[0] = f;
  out[1] = e;
  out[2] = b;
  out[3] = a;
}

static void test_sha256_schedule(int groups) {
  uint32_t expected[4];

  start_case("vsha2ms.vv SHA-256", groups);
  sha256_schedule_ref(expected, k_sha256_sched_vd, k_sha256_sched_vs2,
                      k_sha256_sched_vs1);
  rep32(buf32_vd, k_sha256_sched_vd, groups);
  rep32(buf32_vs2, k_sha256_sched_vs2, groups);
  rep32(buf32_vs1, k_sha256_sched_vs1, groups);
  vset_sha256_groups(groups);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf32_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf32_vs2) : "memory");
  asm volatile("vle32.v v24, (%0)" ::"r"(buf32_vs1) : "memory");
  asm volatile("vsha2ms.vv v8, v16, v24");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check32(expected, groups);
}

static void test_sha256_compress_low(int groups) {
  const uint32_t state_vd[4] = {
      k_sha256_h[7], k_sha256_h[6], k_sha256_h[3], k_sha256_h[2],
  };
  const uint32_t state_vs2[4] = {
      k_sha256_h[5], k_sha256_h[4], k_sha256_h[1], k_sha256_h[0],
  };
  const uint32_t kw[4] = {
      k_sha256_k[0] + k_sha256_sched_vd[0], k_sha256_k[1], 0x89abcdefu,
      0x01234567u,
  };
  uint32_t expected[4];

  start_case("vsha2cl.vv SHA-256", groups);
  sha256_compress_ref(expected, state_vd, state_vs2, kw[0], kw[1]);
  rep32(buf32_vd, state_vd, groups);
  rep32(buf32_vs2, state_vs2, groups);
  rep32(buf32_vs1, kw, groups);
  vset_sha256_groups(groups);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf32_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf32_vs2) : "memory");
  asm volatile("vle32.v v24, (%0)" ::"r"(buf32_vs1) : "memory");
  asm volatile("vsha2cl.vv v8, v16, v24");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check32(expected, groups);
}

static void test_sha256_compress_high(int groups) {
  const uint32_t state_vd[4] = {
      k_sha256_h[7], k_sha256_h[6], k_sha256_h[3], k_sha256_h[2],
  };
  const uint32_t state_vs2[4] = {
      k_sha256_h[5], k_sha256_h[4], k_sha256_h[1], k_sha256_h[0],
  };
  const uint32_t kw[4] = {
      0xdeadbeefu, 0xcafebabeu, k_sha256_k[2], k_sha256_k[3],
  };
  uint32_t expected[4];

  start_case("vsha2ch.vv SHA-256", groups);
  sha256_compress_ref(expected, state_vd, state_vs2, kw[2], kw[3]);
  rep32(buf32_vd, state_vd, groups);
  rep32(buf32_vs2, state_vs2, groups);
  rep32(buf32_vs1, kw, groups);
  vset_sha256_groups(groups);
  asm volatile("vle32.v v8, (%0)" ::"r"(buf32_vd) : "memory");
  asm volatile("vle32.v v16, (%0)" ::"r"(buf32_vs2) : "memory");
  asm volatile("vle32.v v24, (%0)" ::"r"(buf32_vs1) : "memory");
  asm volatile("vsha2ch.vv v8, v16, v24");
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check32(expected, groups);
}

static void test_sha512_schedule(int groups) {
  uint64_t expected[4];

  start_case("vsha2ms.vv SHA-512", groups);
  sha512_schedule_ref(expected, k_sha512_sched_vd, k_sha512_sched_vs2,
                      k_sha512_sched_vs1);
  rep64(buf64_vd, k_sha512_sched_vd, groups);
  rep64(buf64_vs2, k_sha512_sched_vs2, groups);
  rep64(buf64_vs1, k_sha512_sched_vs1, groups);
  vset_sha512_groups(groups);
  asm volatile("vle64.v v8, (%0)" ::"r"(buf64_vd) : "memory");
  asm volatile("vle64.v v16, (%0)" ::"r"(buf64_vs2) : "memory");
  asm volatile("vle64.v v24, (%0)" ::"r"(buf64_vs1) : "memory");
  asm volatile("vsha2ms.vv v8, v16, v24");
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check64(expected, groups);
}

static void test_sha512_compress_low(int groups) {
  const uint64_t state_vd[4] = {
      k_sha512_h[7], k_sha512_h[6], k_sha512_h[3], k_sha512_h[2],
  };
  const uint64_t state_vs2[4] = {
      k_sha512_h[5], k_sha512_h[4], k_sha512_h[1], k_sha512_h[0],
  };
  const uint64_t kw[4] = {
      k_sha512_k[0] + k_sha512_sched_vd[0], k_sha512_k[1],
      0x89abcdef01234567ull, 0xfedcba9876543210ull,
  };
  uint64_t expected[4];

  start_case("vsha2cl.vv SHA-512", groups);
  sha512_compress_ref(expected, state_vd, state_vs2, kw[0], kw[1]);
  rep64(buf64_vd, state_vd, groups);
  rep64(buf64_vs2, state_vs2, groups);
  rep64(buf64_vs1, kw, groups);
  vset_sha512_groups(groups);
  asm volatile("vle64.v v8, (%0)" ::"r"(buf64_vd) : "memory");
  asm volatile("vle64.v v16, (%0)" ::"r"(buf64_vs2) : "memory");
  asm volatile("vle64.v v24, (%0)" ::"r"(buf64_vs1) : "memory");
  asm volatile("vsha2cl.vv v8, v16, v24");
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check64(expected, groups);
}

static void test_sha512_compress_high(int groups) {
  const uint64_t state_vd[4] = {
      k_sha512_h[7], k_sha512_h[6], k_sha512_h[3], k_sha512_h[2],
  };
  const uint64_t state_vs2[4] = {
      k_sha512_h[5], k_sha512_h[4], k_sha512_h[1], k_sha512_h[0],
  };
  const uint64_t kw[4] = {
      0xdeadbeefcafef00dull, 0x0123456789abcdefull, k_sha512_k[2],
      k_sha512_k[3],
  };
  uint64_t expected[4];

  start_case("vsha2ch.vv SHA-512", groups);
  sha512_compress_ref(expected, state_vd, state_vs2, kw[2], kw[3]);
  rep64(buf64_vd, state_vd, groups);
  rep64(buf64_vs2, state_vs2, groups);
  rep64(buf64_vs1, kw, groups);
  vset_sha512_groups(groups);
  asm volatile("vle64.v v8, (%0)" ::"r"(buf64_vd) : "memory");
  asm volatile("vle64.v v16, (%0)" ::"r"(buf64_vs2) : "memory");
  asm volatile("vle64.v v24, (%0)" ::"r"(buf64_vs1) : "memory");
  asm volatile("vsha2ch.vv v8, v16, v24");
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check64(expected, groups);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  for (unsigned i = 0; i < sizeof(k_sha256_groups) / sizeof(k_sha256_groups[0]);
       ++i) {
    const int groups = k_sha256_groups[i];
    printf("\n=== SHA-256 configuration: %d groups ===\n", groups);
    test_sha256_schedule(groups);
    test_sha256_compress_low(groups);
    test_sha256_compress_high(groups);
  }

  for (unsigned i = 0; i < sizeof(k_sha512_groups) / sizeof(k_sha512_groups[0]);
       ++i) {
    const int groups = k_sha512_groups[i];
    printf("\n=== SHA-512 configuration: %d groups ===\n", groups);
    test_sha512_schedule(groups);
    test_sha512_compress_low(groups);
    test_sha512_compress_high(groups);
  }

  EXIT_CHECK();
}
