// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvbb instruction tests.

#include "vector_macros.h"

#define kElems 12

static const uint8_t kSrc8[kElems] = {0x00, 0x01, 0x5a, 0x80, 0xff, 0x3c,
                                      0xc3, 0x69, 0x96, 0x0f, 0xf0, 0xa5};
static const uint8_t kAux8[kElems] = {0xff, 0x55, 0x0f, 0x01, 0x33, 0xaa,
                                      0x3c, 0x81, 0x10, 0xf0, 0x7e, 0x5a};
static const uint16_t kSrc16[kElems] = {0x0001, 0x1234, 0xabcd, 0x00ff,
                                        0xff00, 0x5aa5, 0x1357, 0x2468,
                                        0x8001, 0x7ffe, 0xc33c, 0xdead};
static const uint16_t kAux16[kElems] = {0xffff, 0x0f0f, 0x3333, 0x00f0,
                                        0xf00f, 0xa55a, 0x1111, 0x8888,
                                        0x0001, 0x7fff, 0x3cc3, 0xbeef};
static const uint32_t kSrc32[kElems] = {0x00000001u, 0x12345678u, 0x89abcdefu,
                                        0x00ff00ffu, 0xff00ff00u, 0x5aa55aa5u,
                                        0x13579bdfu, 0x2468ace0u, 0x80000001u,
                                        0x7ffffffeu, 0xc33cc33cu, 0xdeadbeefu};
static const uint32_t kAux32[kElems] = {0xffffffffu, 0x0f0f0f0fu, 0x33333333u,
                                        0x00f000f0u, 0xf00ff00fu, 0xa55aa55au,
                                        0x11111111u, 0x88888888u, 0x00000001u,
                                        0x7fffffffu, 0x3cc33cc3u, 0xbeefcafeu};
static const uint64_t kSrc64[kElems] = {
    0x0000000000000001ull, 0x1234567890abcdefull, 0xfedcba9876543210ull,
    0x00ff00ff00ff00ffull, 0xff00ff00ff00ff00ull, 0x5aa55aa55aa55aa5ull,
    0x13579bdf2468ace0ull, 0x2468ace013579bdfull, 0x8000000000000001ull,
    0x7ffffffffffffffeull, 0xc33cc33cc33cc33cull, 0xdeadbeefcafebabeull};

static volatile uint8_t buf8_a[kElems] __attribute__((aligned(128)));
static volatile uint8_t buf8_b[kElems] __attribute__((aligned(128)));
static volatile uint8_t buf8_out[kElems] __attribute__((aligned(128)));
static uint8_t exp8[kElems];

static volatile uint16_t buf16_a[kElems] __attribute__((aligned(128)));
static volatile uint16_t buf16_b[kElems] __attribute__((aligned(128)));
static volatile uint16_t buf16_out[kElems] __attribute__((aligned(128)));
static uint16_t exp16[kElems];

static volatile uint32_t buf32_a[kElems] __attribute__((aligned(128)));
static volatile uint32_t buf32_b[kElems] __attribute__((aligned(128)));
static volatile uint32_t buf32_out[kElems] __attribute__((aligned(128)));
static uint32_t exp32[kElems];

static volatile uint64_t buf64_a[kElems] __attribute__((aligned(128)));
static volatile uint64_t buf64_out[kElems] __attribute__((aligned(128)));
static uint64_t exp64[kElems];

static void start_case(const char *name) {
  ++test_case;
  printf("Test %d: %s\n", test_case, name);
}

static void load_mask(void) { VLOAD_8(v0, 0x6D, 0x0B); }

static inline void vset8_m1(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e8, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset16_m1(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e16, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset16_m2(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e16, m2, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset32_m1(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset32_m2(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e32, m2, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset64_m1(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset64_m2(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(avl) : "memory");
}

static uint64_t bit_mask(int bits) {
  return bits == 64 ? ~0ull : ((1ull << bits) - 1);
}

static uint8_t bitrev8(uint8_t x) {
  x = (uint8_t)(((x & 0xaa) >> 1) | ((x & 0x55) << 1));
  x = (uint8_t)(((x & 0xcc) >> 2) | ((x & 0x33) << 2));
  x = (uint8_t)(((x & 0xf0) >> 4) | ((x & 0x0f) << 4));
  return x;
}

static uint64_t vbrev_ref(uint64_t x, int bits) {
  uint64_t out = 0;
  for (int i = 0; i < bits / 8; ++i)
    out |= (uint64_t)bitrev8((uint8_t)(x >> (i * 8))) << ((bits - 8) - i * 8);
  return out & bit_mask(bits);
}

static uint64_t clz_ref(uint64_t x, int bits) {
  uint64_t mask = bit_mask(bits);
  x &= mask;
  for (int i = 0; i < bits; ++i)
    if ((x >> (bits - 1 - i)) & 1ull)
      return (uint64_t)i;
  return (uint64_t)bits;
}

static uint64_t ctz_ref(uint64_t x, int bits) {
  uint64_t mask = bit_mask(bits);
  x &= mask;
  for (int i = 0; i < bits; ++i)
    if ((x >> i) & 1ull)
      return (uint64_t)i;
  return (uint64_t)bits;
}

static uint64_t cpop_ref(uint64_t x, int bits) {
  uint64_t mask = bit_mask(bits);
  uint64_t count = 0;
  x &= mask;
  for (int i = 0; i < bits; ++i)
    count += (x >> i) & 1ull;
  return count;
}

static uint64_t vwsll_ref(uint64_t x, uint64_t sh, int src_bits) {
  int dst_bits = src_bits * 2;
  uint64_t mask = bit_mask(dst_bits);
  unsigned amt = (unsigned)(sh & (uint64_t)(dst_bits - 1));
  return ((x & bit_mask(src_bits)) << amt) & mask;
}

static int mask_active(int idx) {
  static const uint8_t mask_bits[2] = {0x6D, 0x0B};
  return (mask_bits[idx / 8] >> (idx % 8)) & 1;
}

static void copy_u8(volatile uint8_t *dst, const uint8_t *src) {
  for (int i = 0; i < kElems; ++i)
    dst[i] = src[i];
}

static void copy_u16(volatile uint16_t *dst, const uint16_t *src) {
  for (int i = 0; i < kElems; ++i)
    dst[i] = src[i];
}

static void copy_u32(volatile uint32_t *dst, const uint32_t *src) {
  for (int i = 0; i < kElems; ++i)
    dst[i] = src[i];
}

static void copy_u64(volatile uint64_t *dst, const uint64_t *src) {
  for (int i = 0; i < kElems; ++i)
    dst[i] = src[i];
}

static int check_u8(const uint8_t *expected) {
  for (int i = 0; i < kElems; ++i) {
    if (buf8_out[i] != expected[i]) {
      printf("  FAILED at element %d: got 0x%02x expected 0x%02x\n", i,
             buf8_out[i], expected[i]);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static int check_u16(const uint16_t *expected) {
  for (int i = 0; i < kElems; ++i) {
    if (buf16_out[i] != expected[i]) {
      printf("  FAILED at element %d: got 0x%04x expected 0x%04x\n", i,
             buf16_out[i], expected[i]);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static int check_u32(const uint32_t *expected) {
  for (int i = 0; i < kElems; ++i) {
    if (buf32_out[i] != expected[i]) {
      printf("  FAILED at element %d: got 0x%08x expected 0x%08x\n", i,
             buf32_out[i], expected[i]);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static int check_u64(const uint64_t *expected) {
  for (int i = 0; i < kElems; ++i) {
    if (buf64_out[i] != expected[i]) {
      printf("  FAILED at element %d: got 0x%016llx expected 0x%016llx\n", i,
             (unsigned long long)buf64_out[i], (unsigned long long)expected[i]);
      ++num_failed;
      return 0;
    }
  }
  printf("  PASSED.\n");
  return 1;
}

static void test_u8(void) {
  const uint64_t scalar = 13;

  start_case("vbrev.v masked e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = mask_active(i) ? (uint8_t)vbrev_ref(kSrc8[i], 8) : 0xeeu;
  vset8_m1();
  load_mask();
  asm volatile("vle8.v v1, (%0)" ::"r"(exp8) : "memory");
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vbrev.v v1, v2, v0.t");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vclz.v e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)clz_ref(kSrc8[i], 8);
  vset8_m1();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vclz.v v1, v2");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vctz.v masked e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = mask_active(i) ? (uint8_t)ctz_ref(kSrc8[i], 8) : 0xeeu;
  vset8_m1();
  load_mask();
  asm volatile("vle8.v v1, (%0)" ::"r"(exp8) : "memory");
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vctz.v v1, v2, v0.t");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vcpop.v e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)cpop_ref(kSrc8[i], 8);
  vset8_m1();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vcpop.v v1, v2");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vwsll.vv e8->e16");
  copy_u8(buf8_a, kSrc8);
  copy_u8(buf8_b, kAux8);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)vwsll_ref(kSrc8[i], kAux8[i], 8);
  vset8_m1();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vle8.v v4, (%0)" ::"r"(buf8_b) : "memory");
  asm volatile("vwsll.vv v8, v2, v4");
  vset16_m2();
  asm volatile("vse16.v v8, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vwsll.vx masked e8->e16");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp16[i] =
        mask_active(i) ? (uint16_t)vwsll_ref(kSrc8[i], scalar, 8) : 0xbeefu;
  vset16_m2();
  load_mask();
  asm volatile("vle16.v v8, (%0)" ::"r"(exp16) : "memory");
  vset8_m1();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vwsll.vx v8, v2, %[S], v0.t" ::[S] "r"(scalar));
  vset16_m2();
  asm volatile("vse16.v v8, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vwsll.vi e8->e16");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)vwsll_ref(kSrc8[i], 11, 8);
  vset8_m1();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vwsll.vi v8, v2, 11");
  vset16_m2();
  asm volatile("vse16.v v8, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);
}

static void test_u16(void) {
  const uint64_t scalar = 29;

  start_case("vbrev.v e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)vbrev_ref(kSrc16[i], 16);
  vset16_m1();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vbrev.v v1, v2");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vclz.v masked e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = mask_active(i) ? (uint16_t)clz_ref(kSrc16[i], 16) : 0xbeefu;
  vset16_m1();
  load_mask();
  asm volatile("vle16.v v1, (%0)" ::"r"(exp16) : "memory");
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vclz.v v1, v2, v0.t");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vctz.v e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)ctz_ref(kSrc16[i], 16);
  vset16_m1();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vctz.v v1, v2");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vcpop.v masked e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = mask_active(i) ? (uint16_t)cpop_ref(kSrc16[i], 16) : 0xbeefu;
  vset16_m1();
  load_mask();
  asm volatile("vle16.v v1, (%0)" ::"r"(exp16) : "memory");
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vcpop.v v1, v2, v0.t");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vwsll.vv e16->e32");
  copy_u16(buf16_a, kSrc16);
  copy_u16(buf16_b, kAux16);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)vwsll_ref(kSrc16[i], kAux16[i], 16);
  vset16_m1();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vle16.v v4, (%0)" ::"r"(buf16_b) : "memory");
  asm volatile("vwsll.vv v8, v2, v4");
  vset32_m2();
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vwsll.vx e16->e32");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)vwsll_ref(kSrc16[i], scalar, 16);
  vset16_m1();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vwsll.vx v8, v2, %[S]" ::[S] "r"(scalar));
  vset32_m2();
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vwsll.vi masked e16->e32");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp32[i] =
        mask_active(i) ? (uint32_t)vwsll_ref(kSrc16[i], 21, 16) : 0xdeadbeefu;
  vset32_m2();
  load_mask();
  asm volatile("vle32.v v8, (%0)" ::"r"(exp32) : "memory");
  vset16_m1();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vwsll.vi v8, v2, 21, v0.t");
  vset32_m2();
  asm volatile("vse32.v v8, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);
}

static void test_u32(void) {
  const uint64_t scalar = 37;

  start_case("vbrev.v e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)vbrev_ref(kSrc32[i], 32);
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vbrev.v v1, v2");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vclz.v e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)clz_ref(kSrc32[i], 32);
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vclz.v v1, v2");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vctz.v masked e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = mask_active(i) ? (uint32_t)ctz_ref(kSrc32[i], 32) : 0xdeadbeefu;
  vset32_m1();
  load_mask();
  asm volatile("vle32.v v1, (%0)" ::"r"(exp32) : "memory");
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vctz.v v1, v2, v0.t");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vcpop.v e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)cpop_ref(kSrc32[i], 32);
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vcpop.v v1, v2");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vwsll.vv e32->e64");
  copy_u32(buf32_a, kSrc32);
  copy_u32(buf32_b, kAux32);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = vwsll_ref(kSrc32[i], kAux32[i], 32);
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vle32.v v4, (%0)" ::"r"(buf32_b) : "memory");
  asm volatile("vwsll.vv v8, v2, v4");
  vset64_m2();
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vwsll.vx masked e32->e64");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = mask_active(i) ? vwsll_ref(kSrc32[i], scalar, 32)
                              : 0xdeadbeefdeadbeefull;
  vset64_m2();
  load_mask();
  asm volatile("vle64.v v8, (%0)" ::"r"(exp64) : "memory");
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vwsll.vx v8, v2, %[S], v0.t" ::[S] "r"(scalar));
  vset64_m2();
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vwsll.vi e32->e64");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = vwsll_ref(kSrc32[i], 21, 32);
  vset32_m1();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vwsll.vi v8, v2, 21");
  vset64_m2();
  asm volatile("vse64.v v8, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);
}

static void test_u64(void) {
  start_case("vbrev.v e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = vbrev_ref(kSrc64[i], 64);
  vset64_m1();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vbrev.v v1, v2");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vclz.v masked e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = mask_active(i) ? clz_ref(kSrc64[i], 64) : 0xdeadbeefdeadbeefull;
  vset64_m1();
  load_mask();
  asm volatile("vle64.v v1, (%0)" ::"r"(exp64) : "memory");
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vclz.v v1, v2, v0.t");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vctz.v e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = ctz_ref(kSrc64[i], 64);
  vset64_m1();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vctz.v v1, v2");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vcpop.v masked e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = mask_active(i) ? cpop_ref(kSrc64[i], 64) : 0xdeadbeefdeadbeefull;
  vset64_m1();
  load_mask();
  asm volatile("vle64.v v1, (%0)" ::"r"(exp64) : "memory");
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vcpop.v v1, v2, v0.t");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  test_u8();
  test_u16();
  test_u32();
  test_u64();

  EXIT_CHECK();
}
