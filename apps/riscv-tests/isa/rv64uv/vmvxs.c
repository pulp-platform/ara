// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

int8_t scalar_8b;
int16_t scalar_16b;
int32_t scalar_32b;
int64_t scalar_64b;

void TEST_CASE1() {
  scalar_8b = 0;
  VSET(16, e8, m1);
  VLOAD_8(v1, 55 << 0, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_8b));
  XCMP(1, scalar_8b, 55 << 0);

  scalar_16b = 0;
  VSET(16, e16, m1);
  VLOAD_16(v1, 55 << 8, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_16b));
  XCMP(2, scalar_16b, 55 << 8);

  scalar_32b = 0;
  VSET(16, e32, m1);
  VLOAD_32(v1, 55 << 16, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_32b));
  XCMP(3, scalar_32b, 55 << 16);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 55 << 30, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_64b));
  XCMP(4, scalar_64b, 55 << 30);
}

// Check special cases
void TEST_CASE2() {
  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 55 << 30, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET(16, e64, m8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_64b));
  XCMP(5, scalar_64b, 55 << 30);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 55 << 30, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET_ZERO(e64, m1);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_64b));
  XCMP(6, scalar_64b, 55 << 30);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 55 << 30, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET_ZERO(e64, m8);
  asm volatile("vmv.x.s %0, v1" : "=r"(scalar_64b));
  XCMP(7, scalar_64b, 55 << 30);
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
        "vmv.x.s t1, v8\n\t"
        "mv %[scalar], t1\n\t"
        "vse32.v v8, (%[stored])\n\t"
        "vsm.v v10, (%[mask])\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [a] "r"(add_a), [b] "r"(add_b), [cmp_a] "r"(cmp_a),
          [cmp_b] "r"(cmp_b), [old_result] "r"(old_result),
          [old_mask] "r"(old_mask), [stored] "r"(stored), [mask] "r"(&mask)
        : "t1", "v2", "v4", "v8", "v10", "v12", "v14", "memory");
    XCMP(8 + repeat * 6, scalar, (uint64_t)0x40400000);
    // Mask tail bits are outside VL and do not contribute to this check.
    XCMP(9 + repeat * 6, (mask & 0x0f), 0x05);
    for (int i = 0; i < 4; i++) {
      XCMP(10 + repeat * 6 + i, stored[i], expected[i]);
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
        "vmv.x.s t1, v8\n\t"
        "mv %[scalar], t1\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [a] "r"(add_a), [b] "r"(add_b), [cmp_a] "r"(cmp_a),
          [cmp_b] "r"(cmp_b), [old_result] "r"(old_result),
          [old_mask] "r"(old_mask), [stored] "r"(stored), [mask] "r"(&mask)
        : "t1", "v2", "v4", "v8", "v10", "v12", "v14", "memory");
    XCMP(32 + repeat * 4, scalar, (uint64_t)0x4008000000000000);
    // Mask tail bits are outside VL and do not contribute to this check.
    XCMP(33 + repeat * 4, (mask & 0x03), 0x01);
    for (int i = 0; i < 2; i++) {
      XCMP(34 + repeat * 4 + i, stored[i], expected[i]);
    }
  }
}

// Dedicated MASKU results must still return while the mask unit is active.
// Clear the whole source register so no nonzero tail bits affect the result.
void TEST_CASE5() {
  uint64_t population, first, empty_first, empty_population;
  asm volatile("vsetvli t0, zero, e8, m1, tu, mu\n\t"
               "vmv.v.i v2, 0\n\t"
               "li t1, 5\n\t"
               "vmv.s.x v2, t1\n\t"
               "vsetivli zero, 8, e8, m1, tu, mu\n\t"
               "vcpop.m t1, v2\n\t"
               "mv %[population], t1\n\t"
               "vfirst.m t1, v2\n\t"
               "mv %[first], t1\n\t"
               "vmv.v.i v2, 0\n\t"
               "vfirst.m t1, v2\n\t"
               "mv %[empty_first], t1\n\t"
               "vcpop.m t1, v2\n\t"
               "mv %[empty_population], t1\n\t"
               : [population] "=&r"(population), [first] "=&r"(first),
                 [empty_first] "=&r"(empty_first),
                 [empty_population] "=&r"(empty_population)
               :
               : "t0", "t1", "v2", "memory");
  XCMP(48, population, 2);
  XCMP(49, first, 0);
  XCMP(50, empty_first, (uint64_t)-1);
  XCMP(51, empty_population, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  EXIT_CHECK();
}
