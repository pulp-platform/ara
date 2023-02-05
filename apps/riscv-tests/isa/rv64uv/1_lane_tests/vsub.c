// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vsub.vv v3, v1, v2");
  VCMP_U8(1, v3, 4, 8, 12, 16, 20, 24, 28, 32, 4, 8, 12, 16, 20, 24, 28, 32);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vsub.vv v6, v2, v4");
  VCMP_U16(2, v6, 4, 8, 12, 16, 20, 24, 28, 32, 4, 8, 12, 16, 20, 24, 28, 32);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vsub.vv v12, v4, v8");
  VCMP_U32(3, v12, 4, 8, 12, 16, 20, 24, 28, 32, 4, 8, 12, 16, 20, 24, 28, 32);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_64(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vsub.vv v24, v8, v16");
  VCMP_U64(4, v24, 4, 8, 12, 16, 20, 24, 28, 32, 4, 8, 12, 16, 20, 24, 28, 32);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vsub.vv v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 0, 8, 0, 16, 0, 24, 0, 32, 0, 8, 0, 16, 0, 24, 0, 32);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vsub.vv v6, v2, v4, v0.t");
  VCMP_U16(6, v6, 0, 8, 0, 16, 0, 24, 0, 32, 0, 8, 0, 16, 0, 24, 0, 32);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  asm volatile("vsub.vv v12, v4, v8, v0.t");
  VCMP_U32(7, v12, 0, 8, 0, 16, 0, 24, 0, 32, 0, 8, 0, 16, 0, 24, 0, 32);

  VSET(16, e32, m8);
  VLOAD_32(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_32(v16, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  asm volatile("vsub.vv v24, v8, v16, v0.t");
  VCMP_U32(8, v24, 0, 8, 0, 16, 0, 24, 0, 32, 0, 8, 0, 16, 0, 24, 0, 32);
}

void TEST_CASE3(void) {
  const uint64_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vsub.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VCMP_U8(9, v3, 0, 5, 10, 15, 20, 25, 30, 35, 0, 5, 10, 15, 20, 25, 30, 35);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vsub.vx v4, v2, %[A]" ::[A] "r"(scalar));
  VCMP_U16(10, v4, 0, 5, 10, 15, 20, 25, 30, 35, 0, 5, 10, 15, 20, 25, 30, 35);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vsub.vx v8, v4, %[A]" ::[A] "r"(scalar));
  VCMP_U32(11, v8, 0, 5, 10, 15, 20, 25, 30, 35, 0, 5, 10, 15, 20, 25, 30, 35);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vsub.vx v16, v8, %[A]" ::[A] "r"(scalar));
  VCMP_U64(12, v16, 0, 5, 10, 15, 20, 25, 30, 35, 0, 5, 10, 15, 20, 25, 30, 35);
}

void TEST_CASE4(void) {
  const uint64_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vsub.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U8(13, v3, 0, 5, 0, 15, 0, 25, 0, 35, 0, 5, 0, 15, 0, 25, 0, 35);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  asm volatile("vsub.vx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U16(14, v4, 0, 5, 0, 15, 0, 25, 0, 35, 0, 5, 0, 15, 0, 25, 0, 35);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  asm volatile("vsub.vx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(15, v8, 0, 5, 0, 15, 0, 25, 0, 35, 0, 5, 0, 15, 0, 25, 0, 35);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  asm volatile("vsub.vx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U64(16, v16, 0, 5, 0, 15, 0, 25, 0, 35, 0, 5, 0, 15, 0, 25, 0, 35);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  EXIT_CHECK();
}
