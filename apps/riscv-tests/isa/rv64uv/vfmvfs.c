// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

double scalar_16b;
float scalar_32b;
double scalar_64b;

void TEST_CASE1() {
  BOX_HALF_IN_DOUBLE(scalar_16b, 0);
  VSET(16, e16, m1);
  VLOAD_16(v1, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_16b));
  XCMP(1, *((uint16_t *)&scalar_16b), 0xbb1e);

  scalar_32b = 0;
  VSET(16, e32, m1);
  VLOAD_32(v1, 0xbe9451b0, 0x3ece4bf7, 0x3eadc098, 0x3f09f4f0, 0x3ecc80cc,
           0xbe8a42c5, 0x3f47fd31, 0xbe201365, 0xbeffeb17, 0xbf314e2e,
           0xbd0a9c78, 0xbf1fb51f, 0x3b5e1209, 0x3eac9a73, 0xbeb187b6,
           0x3dea828d);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_32b));
  XCMP(2, *((uint32_t *)&scalar_32b), 0xbe9451b0);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(3, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);
}

// Check special cases
void TEST_CASE2() {
  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET(16, e64, m8);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(4, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET_ZERO(e64, m1);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(5, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET_ZERO(e64, m8);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(6, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);
}

// Read the scalar result while a mask comparison is still pending.
// The scalar destination register differs from both vector source numbers.
void TEST_CASE3() {
  static const uint32_t add_a[4] __attribute__((aligned(16))) = {
      0x3f800000, 0xbf800000, 0x3f800000, 0xbf800000};
  static const uint32_t add_b[4] __attribute__((aligned(16))) = {
      0x40000000, 0xc0000000, 0x40000000, 0xc0000000};
  static const uint32_t cmp_a[4] __attribute__((aligned(16))) = {
      0x3f800000, 0x40000000, 0x40400000, 0x40800000};
  static const uint32_t cmp_b[4]
      __attribute__((aligned(16))) = {0x3f800000, 0, 0x40400000, 0};
  static const uint32_t old_result[4] __attribute__((aligned(16))) = {
      0x44800000, 0x44800000, 0x44800000, 0x44800000};
  static const uint32_t old_mask[4] __attribute__((aligned(16))) = {0, 0, 0, 0};
  static const uint32_t expected[4] = {0x40400000, 0xc0400000, 0x40400000,
                                       0xc0400000};
  volatile uint32_t stored[4] __attribute__((aligned(16)));
  volatile uint8_t mask;
  uint64_t scalar;

  for (int repeat = 0; repeat < 4; repeat++) {
    for (int i = 0; i < 4; i++)
      stored[i] = ~((uint32_t)0);
    mask = 0xff;
    asm volatile(
        "vsetivli zero, 4, e32, m1, tu, mu\n\t"
        "vle32.v v2, (%[a])\n\t"
        "vle32.v v4, (%[b])\n\t"
        "vle32.v v12, (%[cmp_a])\n\t"
        "vle32.v v14, (%[cmp_b])\n\t"
        "vle32.v v8, (%[old_result])\n\t"
        "vle32.v v10, (%[old_mask])\n\t"
        "vmv.x.s t1, v14\n\t"
        "vfadd.vv v8, v2, v4\n\t"
        "vmfeq.vv v10, v12, v14\n\t"
        "vfmv.f.s ft1, v8\n\t"
        "fmv.x.w %[scalar], ft1\n\t"
        "vse32.v v8, (%[stored])\n\t"
        "vsm.v v10, (%[mask])\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [a] "r"(add_a), [b] "r"(add_b), [cmp_a] "r"(cmp_a),
          [cmp_b] "r"(cmp_b), [old_result] "r"(old_result),
          [old_mask] "r"(old_mask), [stored] "r"(stored), [mask] "r"(&mask)
        : "t1", "ft1", "v2", "v4", "v8", "v10", "v12", "v14", "memory");
    XCMP(7 + repeat * 6, scalar, (uint64_t)0x40400000);
    // Mask tail bits are outside VL and do not contribute to this check.
    XCMP(8 + repeat * 6, (mask & 0x0f), 0x05);
    for (int i = 0; i < 4; i++) {
      XCMP(9 + repeat * 6 + i, stored[i], expected[i]);
    }
  }
}

// Keep the scalar response behind a pending mask result and vector stores.
// The scalar destination register differs from both vector source numbers.
void TEST_CASE4() {
  static const uint64_t add_a[2]
      __attribute__((aligned(16))) = {0x3ff0000000000000, 0xbff0000000000000};
  static const uint64_t add_b[2]
      __attribute__((aligned(16))) = {0x4000000000000000, 0xc000000000000000};
  static const uint64_t cmp_a[2]
      __attribute__((aligned(16))) = {0x3ff0000000000000, 0x4000000000000000};
  static const uint64_t cmp_b[2]
      __attribute__((aligned(16))) = {0x3ff0000000000000, 0};
  static const uint64_t old_result[2]
      __attribute__((aligned(16))) = {0x4090000000000000, 0x4090000000000000};
  static const uint64_t old_mask[2] __attribute__((aligned(16))) = {0, 0};
  static const uint64_t expected[2] = {0x4008000000000000, 0xc008000000000000};
  volatile uint64_t stored[2] __attribute__((aligned(16)));
  volatile uint8_t mask;
  uint64_t scalar;

  for (int repeat = 0; repeat < 4; repeat++) {
    for (int i = 0; i < 2; i++)
      stored[i] = ~((uint64_t)0);
    mask = 0xff;
    asm volatile(
        "vsetivli zero, 2, e64, m1, tu, mu\n\t"
        "vle64.v v2, (%[a])\n\t"
        "vle64.v v4, (%[b])\n\t"
        "vle64.v v12, (%[cmp_a])\n\t"
        "vle64.v v14, (%[cmp_b])\n\t"
        "vle64.v v8, (%[old_result])\n\t"
        "vle64.v v10, (%[old_mask])\n\t"
        "vmv.x.s t1, v14\n\t"
        "vfadd.vv v8, v2, v4\n\t"
        "vmfeq.vv v10, v12, v14\n\t"
        "vse64.v v8, (%[stored])\n\t"
        "vsm.v v10, (%[mask])\n\t"
        "vfmv.f.s ft1, v8\n\t"
        "fmv.x.d %[scalar], ft1\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [a] "r"(add_a), [b] "r"(add_b), [cmp_a] "r"(cmp_a),
          [cmp_b] "r"(cmp_b), [old_result] "r"(old_result),
          [old_mask] "r"(old_mask), [stored] "r"(stored), [mask] "r"(&mask)
        : "t1", "ft1", "v2", "v4", "v8", "v10", "v12", "v14", "memory");
    XCMP(31 + repeat * 4, scalar, (uint64_t)0x4008000000000000);
    // Mask tail bits are outside VL and do not contribute to this check.
    XCMP(32 + repeat * 4, (mask & 0x03), 0x01);
    for (int i = 0; i < 2; i++) {
      XCMP(33 + repeat * 4 + i, stored[i], expected[i]);
    }
  }
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  EXIT_CHECK();
}
