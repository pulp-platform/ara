// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.vv v6, v2, v4");
  VSET(16, e16, m2);
  VCMP_U16(1, v6, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.vv v12, v4, v8");
  VSET(16, e32, m4);
  VCMP_U32(2, v12, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.vv v24, v8, v16");
  VSET(16, e64, m8);
  VCMP_U64(3, v24, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  VCLEAR(v7);
  asm volatile("vwadd.vv v6, v2, v4, v0.t");
  VSET(16, e16, m2);
  VCMP_U16(4, v6, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  VCLEAR(v14);
  asm volatile("vwadd.vv v12, v4, v8, v0.t");
  VSET(16, e32, m4);
  VCMP_U32(5, v12, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  VCLEAR(v28);
  asm volatile("vwadd.vv v24, v8, v16, v0.t");
  VSET(16, e64, m8);
  VCMP_U64(6, v24, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);
}

void TEST_CASE3(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.vx v4, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(7, v4, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.vx v8, v4, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(8, v8, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.vx v16, v8, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(9, v16, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);
}

void TEST_CASE4(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  VCLEAR(v5);
  asm volatile("vwadd.vx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(10, v4, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  VCLEAR(v10);
  asm volatile("vwadd.vx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(11, v8, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  VCLEAR(v20);
  asm volatile("vwadd.vx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(12, v16, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);
}

void TEST_CASE5(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.wv v6, v2, v4");
  VSET(16, e16, m2);
  VCMP_U16(13, v6, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.wv v12, v4, v8");
  VSET(16, e32, m4);
  VCMP_U32(14, v12, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwadd.wv v24, v8, v16");
  VSET(16, e64, m8);
  VCMP_U64(15, v24, 2, 4, 6, 8, 10, 12, 14, 16, 2, 4, 6, 8, 10, 12, 14, 16);
}

void TEST_CASE6(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  VCLEAR(v7);
  asm volatile("vwadd.wv v6, v2, v4, v0.t");
  VSET(16, e16, m2);
  VCMP_U16(16, v6, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  VCLEAR(v14);
  asm volatile("vwadd.wv v12, v4, v8, v0.t");
  VSET(16, e32, m4);
  VCMP_U32(17, v12, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  VCLEAR(v28);
  asm volatile("vwadd.wv v24, v8, v16, v0.t");
  VSET(16, e64, m8);
  VCMP_U64(18, v24, 0, 4, 0, 8, 0, 12, 0, 16, 0, 4, 0, 8, 0, 12, 0, 16);
}

void TEST_CASE7(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.wx v4, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(19, v4, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.wx v8, v4, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(20, v8, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20, -11);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwadd.wx v16, v8, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(21, v16, 6, 3, 8, 1, 10, -1, 12, -3, 14, -5, 16, -7, 18, -9, 20,
           -11);
}

void TEST_CASE8(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  VCLEAR(v5);
  asm volatile("vwadd.wx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(22, v4, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  VCLEAR(v10);
  asm volatile("vwadd.wx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(23, v8, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  VCLEAR(v20);
  asm volatile("vwadd.wx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(24, v16, 0, 7, 0, 9, 0, 11, 0, 13, 0, 7, 0, 9, 0, 11, 0, 13);
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
  TEST_CASE8();

  EXIT_CHECK();
}
