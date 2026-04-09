// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Zvkb instruction tests.

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
static const uint64_t kAux64[kElems] = {
    0xffffffffffffffffull, 0x0f0f0f0f0f0f0f0full, 0x3333333333333333ull,
    0x00f000f000f000f0ull, 0xf00ff00ff00ff00full, 0xa55aa55aa55aa55aull,
    0x1111111111111111ull, 0x8888888888888888ull, 0x0000000000000001ull,
    0x7fffffffffffffffull, 0x3cc33cc33cc33cc3ull, 0xbeefcafedeadfaceull};

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
static volatile uint64_t buf64_b[kElems] __attribute__((aligned(128)));
static volatile uint64_t buf64_out[kElems] __attribute__((aligned(128)));
static uint64_t exp64[kElems];

static void start_case(const char *name) {
  ++test_case;
  printf("Test %d: %s\n", test_case, name);
}

static void load_mask(void) { VLOAD_8(v0, 0x6D, 0x0B); }

static inline void vset8(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e8, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset16(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e16, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset32(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(avl) : "memory");
}

static inline void vset64(void) {
  long avl = kElems;
  asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(avl) : "memory");
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

static uint64_t vbrev8_ref(uint64_t x, int bits) {
  uint64_t out = 0;
  for (int i = 0; i < bits / 8; ++i)
    out |= (uint64_t)bitrev8((uint8_t)(x >> (i * 8))) << (i * 8);
  return out;
}

static uint64_t vrev8_ref(uint64_t x, int bits) {
  uint64_t out = 0;
  int bytes = bits / 8;
  for (int i = 0; i < bytes; ++i)
    out |= ((x >> (i * 8)) & 0xffull) << ((bytes - 1 - i) * 8);
  return out & bit_mask(bits);
}

static uint64_t rol_ref(uint64_t x, uint64_t sh, int bits) {
  uint64_t mask = bit_mask(bits);
  unsigned rot = (unsigned)(sh & (bits - 1));
  x &= mask;
  if (rot == 0)
    return x;
  return ((x << rot) | (x >> (bits - rot))) & mask;
}

static uint64_t ror_ref(uint64_t x, uint64_t sh, int bits) {
  uint64_t mask = bit_mask(bits);
  unsigned rot = (unsigned)(sh & (bits - 1));
  x &= mask;
  if (rot == 0)
    return x;
  return ((x >> rot) | (x << (bits - rot))) & mask;
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
  const uint64_t imm = 45;

  start_case("vandn.vv e8");
  copy_u8(buf8_a, kSrc8);
  copy_u8(buf8_b, kAux8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)(kSrc8[i] & (uint8_t)~kAux8[i]);
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vle8.v v3, (%0)" ::"r"(buf8_b) : "memory");
  asm volatile("vandn.vv v1, v2, v3");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vandn.vx masked e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = mask_active(i) ? (uint8_t)(kSrc8[i] & (uint8_t)~scalar) : 0xeeu;
  vset8();
  load_mask();
  asm volatile("vle8.v v1, (%0)" ::"r"(exp8) : "memory");
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vandn.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vbrev8.v masked e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = mask_active(i) ? bitrev8(kSrc8[i]) : 0xeeu;
  vset8();
  load_mask();
  asm volatile("vle8.v v1, (%0)" ::"r"(exp8) : "memory");
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vbrev8.v v1, v2, v0.t");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vrev8.v e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = kSrc8[i];
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vrev8.v v1, v2");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vrol.vv e8");
  copy_u8(buf8_a, kSrc8);
  copy_u8(buf8_b, kAux8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)rol_ref(kSrc8[i], kAux8[i], 8);
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vle8.v v3, (%0)" ::"r"(buf8_b) : "memory");
  asm volatile("vrol.vv v1, v2, v3");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vrol.vx masked e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = mask_active(i) ? (uint8_t)rol_ref(kSrc8[i], scalar, 8) : 0xeeu;
  vset8();
  load_mask();
  asm volatile("vle8.v v1, (%0)" ::"r"(exp8) : "memory");
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vrol.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vror.vv e8");
  copy_u8(buf8_a, kSrc8);
  copy_u8(buf8_b, kAux8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)ror_ref(kSrc8[i], kAux8[i], 8);
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vle8.v v3, (%0)" ::"r"(buf8_b) : "memory");
  asm volatile("vror.vv v1, v2, v3");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vror.vx e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)ror_ref(kSrc8[i], scalar, 8);
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vror.vx v1, v2, %[S]" ::[S] "r"(scalar));
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);

  start_case("vror.vi e8");
  copy_u8(buf8_a, kSrc8);
  for (int i = 0; i < kElems; ++i)
    exp8[i] = (uint8_t)ror_ref(kSrc8[i], imm, 8);
  vset8();
  asm volatile("vle8.v v2, (%0)" ::"r"(buf8_a) : "memory");
  asm volatile("vror.vi v1, v2, 45");
  asm volatile("vse8.v v1, (%0)" ::"r"(buf8_out) : "memory");
  check_u8(exp8);
}

static void test_u16(void) {
  const uint64_t scalar = 13;
  const uint64_t imm = 45;

  start_case("vandn.vv e16");
  copy_u16(buf16_a, kSrc16);
  copy_u16(buf16_b, kAux16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)(kSrc16[i] & (uint16_t)~kAux16[i]);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vle16.v v3, (%0)" ::"r"(buf16_b) : "memory");
  asm volatile("vandn.vv v1, v2, v3");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vandn.vx masked e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] =
        mask_active(i) ? (uint16_t)(kSrc16[i] & (uint16_t)~scalar) : 0xbeefu;
  vset16();
  load_mask();
  asm volatile("vle16.v v1, (%0)" ::"r"(exp16) : "memory");
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vandn.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vbrev8.v masked e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = mask_active(i) ? (uint16_t)vbrev8_ref(kSrc16[i], 16) : 0xbeefu;
  vset16();
  load_mask();
  asm volatile("vle16.v v1, (%0)" ::"r"(exp16) : "memory");
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vbrev8.v v1, v2, v0.t");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vrev8.v e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)vrev8_ref(kSrc16[i], 16);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vrev8.v v1, v2");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vrol.vv e16");
  copy_u16(buf16_a, kSrc16);
  copy_u16(buf16_b, kAux16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)rol_ref(kSrc16[i], kAux16[i], 16);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vle16.v v3, (%0)" ::"r"(buf16_b) : "memory");
  asm volatile("vrol.vv v1, v2, v3");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vrol.vx masked e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] =
        mask_active(i) ? (uint16_t)rol_ref(kSrc16[i], scalar, 16) : 0xbeefu;
  vset16();
  load_mask();
  asm volatile("vle16.v v1, (%0)" ::"r"(exp16) : "memory");
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vrol.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vror.vv e16");
  copy_u16(buf16_a, kSrc16);
  copy_u16(buf16_b, kAux16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)ror_ref(kSrc16[i], kAux16[i], 16);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vle16.v v3, (%0)" ::"r"(buf16_b) : "memory");
  asm volatile("vror.vv v1, v2, v3");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vror.vx e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)ror_ref(kSrc16[i], scalar, 16);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vror.vx v1, v2, %[S]" ::[S] "r"(scalar));
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);

  start_case("vror.vi e16");
  copy_u16(buf16_a, kSrc16);
  for (int i = 0; i < kElems; ++i)
    exp16[i] = (uint16_t)ror_ref(kSrc16[i], imm, 16);
  vset16();
  asm volatile("vle16.v v2, (%0)" ::"r"(buf16_a) : "memory");
  asm volatile("vror.vi v1, v2, 45");
  asm volatile("vse16.v v1, (%0)" ::"r"(buf16_out) : "memory");
  check_u16(exp16);
}

static void test_u32(void) {
  const uint64_t scalar = 13;
  const uint64_t imm = 45;

  start_case("vandn.vv e32");
  copy_u32(buf32_a, kSrc32);
  copy_u32(buf32_b, kAux32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = kSrc32[i] & ~kAux32[i];
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vle32.v v3, (%0)" ::"r"(buf32_b) : "memory");
  asm volatile("vandn.vv v1, v2, v3");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vandn.vx masked e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = mask_active(i) ? (kSrc32[i] & ~(uint32_t)scalar) : 0xdeadbeefu;
  vset32();
  load_mask();
  asm volatile("vle32.v v1, (%0)" ::"r"(exp32) : "memory");
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vandn.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vbrev8.v masked e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] =
        mask_active(i) ? (uint32_t)vbrev8_ref(kSrc32[i], 32) : 0xdeadbeefu;
  vset32();
  load_mask();
  asm volatile("vle32.v v1, (%0)" ::"r"(exp32) : "memory");
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vbrev8.v v1, v2, v0.t");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vrev8.v e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)vrev8_ref(kSrc32[i], 32);
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vrev8.v v1, v2");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vrol.vv e32");
  copy_u32(buf32_a, kSrc32);
  copy_u32(buf32_b, kAux32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)rol_ref(kSrc32[i], kAux32[i], 32);
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vle32.v v3, (%0)" ::"r"(buf32_b) : "memory");
  asm volatile("vrol.vv v1, v2, v3");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vrol.vx masked e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] =
        mask_active(i) ? (uint32_t)rol_ref(kSrc32[i], scalar, 32) : 0xdeadbeefu;
  vset32();
  load_mask();
  asm volatile("vle32.v v1, (%0)" ::"r"(exp32) : "memory");
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vrol.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vror.vv e32");
  copy_u32(buf32_a, kSrc32);
  copy_u32(buf32_b, kAux32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)ror_ref(kSrc32[i], kAux32[i], 32);
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vle32.v v3, (%0)" ::"r"(buf32_b) : "memory");
  asm volatile("vror.vv v1, v2, v3");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vror.vx e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)ror_ref(kSrc32[i], scalar, 32);
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vror.vx v1, v2, %[S]" ::[S] "r"(scalar));
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);

  start_case("vror.vi e32");
  copy_u32(buf32_a, kSrc32);
  for (int i = 0; i < kElems; ++i)
    exp32[i] = (uint32_t)ror_ref(kSrc32[i], imm, 32);
  vset32();
  asm volatile("vle32.v v2, (%0)" ::"r"(buf32_a) : "memory");
  asm volatile("vror.vi v1, v2, 45");
  asm volatile("vse32.v v1, (%0)" ::"r"(buf32_out) : "memory");
  check_u32(exp32);
}

static void test_u64(void) {
  const uint64_t scalar = 13;
  const uint64_t imm = 45;

  start_case("vandn.vv e64");
  copy_u64(buf64_a, kSrc64);
  copy_u64(buf64_b, kAux64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = kSrc64[i] & ~kAux64[i];
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vle64.v v3, (%0)" ::"r"(buf64_b) : "memory");
  asm volatile("vandn.vv v1, v2, v3");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vandn.vx masked e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = mask_active(i) ? (kSrc64[i] & ~scalar) : 0xdeadbeefdeadbeefull;
  vset64();
  load_mask();
  asm volatile("vle64.v v1, (%0)" ::"r"(exp64) : "memory");
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vandn.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vbrev8.v masked e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] =
        mask_active(i) ? vbrev8_ref(kSrc64[i], 64) : 0xdeadbeefdeadbeefull;
  vset64();
  load_mask();
  asm volatile("vle64.v v1, (%0)" ::"r"(exp64) : "memory");
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vbrev8.v v1, v2, v0.t");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vrev8.v e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = vrev8_ref(kSrc64[i], 64);
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vrev8.v v1, v2");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vrol.vv e64");
  copy_u64(buf64_a, kSrc64);
  copy_u64(buf64_b, kAux64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = rol_ref(kSrc64[i], kAux64[i], 64);
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vle64.v v3, (%0)" ::"r"(buf64_b) : "memory");
  asm volatile("vrol.vv v1, v2, v3");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vrol.vx masked e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] =
        mask_active(i) ? rol_ref(kSrc64[i], scalar, 64) : 0xdeadbeefdeadbeefull;
  vset64();
  load_mask();
  asm volatile("vle64.v v1, (%0)" ::"r"(exp64) : "memory");
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vrol.vx v1, v2, %[S], v0.t" ::[S] "r"(scalar));
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vror.vv e64");
  copy_u64(buf64_a, kSrc64);
  copy_u64(buf64_b, kAux64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = ror_ref(kSrc64[i], kAux64[i], 64);
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vle64.v v3, (%0)" ::"r"(buf64_b) : "memory");
  asm volatile("vror.vv v1, v2, v3");
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vror.vx e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = ror_ref(kSrc64[i], scalar, 64);
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vror.vx v1, v2, %[S]" ::[S] "r"(scalar));
  asm volatile("vse64.v v1, (%0)" ::"r"(buf64_out) : "memory");
  check_u64(exp64);

  start_case("vror.vi e64");
  copy_u64(buf64_a, kSrc64);
  for (int i = 0; i < kElems; ++i)
    exp64[i] = ror_ref(kSrc64[i], imm, 64);
  vset64();
  asm volatile("vle64.v v2, (%0)" ::"r"(buf64_a) : "memory");
  asm volatile("vror.vi v1, v2, 45");
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
