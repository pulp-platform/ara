// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vv v3, v1, v2");
  VCMP_U8(1, v3, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vv v6, v2, v4");
  VCMP_U16(2, v6, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vv v12, v4, v8");
  VCMP_U32(3, v12, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vv v24, v8, v16");
  VCMP_U64(4, v24, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vadd.vv v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vadd.vv v6, v2, v4, v0.t");
  VCMP_U16(6, v6, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  asm volatile("vadd.vv v12, v4, v8, v0.t");
  VCMP_U32(7, v12, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  asm volatile("vadd.vv v24, v8, v16, v0.t");
  VCMP_U64(8, v24, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);
}

void TEST_CASE3(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vi v3, v1, 5");
  VCMP_U8(9, v3, 6, 7, 8, 9, 10, 11, 12, 13, 6, 7, 8, 9, 10, 11, 12, 13);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vi v4, v2, 5");
  VCMP_U16(10, v4, 6, 7, 8, 9, 10, 11, 12, 13, 6, 7, 8, 9, 10, 11, 12, 13);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vi v8, v4, 5");
  VCMP_U32(11, v8, 6, 7, 8, 9, 10, 11, 12, 13, 6, 7, 8, 9, 10, 11, 12, 13);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vadd.vi v16, v8, 5");
  VCMP_U64(12, v16, 6, 7, 8, 9, 10, 11, 12, 13, 6, 7, 8, 9, 10, 11, 12, 13);
}

void TEST_CASE4(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vadd.vi v3, v1, 5, v0.t");
  VCMP_U8(13, v3, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  asm volatile("vadd.vi v4, v2, 5, v0.t");
  VCMP_U16(14, v4, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  asm volatile("vadd.vi v8, v4, 5, v0.t");
  VCMP_U32(15, v8, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  asm volatile("vadd.vi v16, v8, 5, v0.t");
  VCMP_U64(16, v16, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);
}

void TEST_CASE5(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v1, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vadd.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VCMP_U8(17, v3, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vadd.vx v4, v2, %[A]" ::[A] "r"(scalar));
  VCMP_U16(18, v4, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vadd.vx v8, v4, %[A]" ::[A] "r"(scalar));
  VCMP_U32(19, v8, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vadd.vx v16, v8, %[A]" ::[A] "r"(scalar));
  VCMP_U64(20, v16, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20,
           -11);
}

void TEST_CASE6(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vadd.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U8(21, v3, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e16, m2);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  asm volatile("vadd.vx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U16(22, v4, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e32, m4);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  asm volatile("vadd.vx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(23, v8, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e64, m8);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  asm volatile("vadd.vx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U64(24, v16, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);
}

// Check that the addition also works when source register EEWs are changed
void TEST_CASE7(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET(8, e16, m1);
  asm volatile("vadd.vv v3, v1, v2");
  VSET(16, e8, m1);
  VCMP_U8(25, v3, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();
  TEST_CASE7();

  EXIT_CHECK();
}
