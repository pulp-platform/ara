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
  asm volatile("vrsub.vi v3, v1, 10");
  VCMP_U8(1, v3, 5, 0, -5, -10, -15, -20, -25, -30, 5, 0, -5, -10, -15, -20,
          -25, -30);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vi v4, v2, 10");
  VCMP_U16(2, v4, 5, 0, -5, -10, -15, -20, -25, -30, 5, 0, -5, -10, -15, -20,
           -25, -30);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vi v8, v4, 10");
  VCMP_U32(3, v8, 5, 0, -5, -10, -15, -20, -25, -30, 5, 0, -5, -10, -15, -20,
           -25, -30);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vi v16, v8, 10");
  VCMP_U64(4, v16, 5, 0, -5, -10, -15, -20, -25, -30, 5, 0, -5, -10, -15, -20,
           -25, -30);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v3);
  asm volatile("vrsub.vi v3, v1, 10, v0.t");
  VCMP_U8(5, v3, 5, 0, 0, 0, -15, -20, 0, 0, 5, 0, 0, 0, -15, -20, 0, 0);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v4);
  asm volatile("vrsub.vi v4, v2, 10, v0.t");
  VCMP_U16(6, v4, 5, 0, 0, 0, -15, -20, 0, 0, 5, 0, 0, 0, -15, -20, 0, 0);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v8);
  asm volatile("vrsub.vi v8, v4, 10, v0.t");
  VCMP_U32(7, v8, 5, 0, 0, 0, -15, -20, 0, 0, 5, 0, 0, 0, -15, -20, 0, 0);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v16);
  asm volatile("vrsub.vi v16, v8, 10, v0.t");
  VCMP_U64(8, v16, 5, 0, 0, 0, -15, -20, 0, 0, 5, 0, 0, 0, -15, -20, 0, 0);
}

void TEST_CASE3(void) {
  const uint64_t scalar = 25;

  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VCMP_U8(9, v3, 20, 15, 10, 5, 0, -5, -10, -15, 20, 15, 10, 5, 0, -5, -10,
          -15);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vx v4, v2, %[A]" ::[A] "r"(scalar));
  VCMP_U16(10, v4, 20, 15, 10, 5, 0, -5, -10, -15, 20, 15, 10, 5, 0, -5, -10,
           -15);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vx v8, v4, %[A]" ::[A] "r"(scalar));
  VCMP_U32(11, v8, 20, 15, 10, 5, 0, -5, -10, -15, 20, 15, 10, 5, 0, -5, -10,
           -15);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  asm volatile("vrsub.vx v16, v8, %[A]" ::[A] "r"(scalar));
  VCMP_U64(12, v16, 20, 15, 10, 5, 0, -5, -10, -15, 20, 15, 10, 5, 0, -5, -10,
           -15);
}

void TEST_CASE4(void) {
  const uint64_t scalar = 25;

  VSET(16, e8, m1);
  VLOAD_8(v1, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v3);
  asm volatile("vrsub.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U8(13, v3, 20, 15, 0, 0, 0, -5, 0, 0, 20, 15, 0, 0, 0, -5, 0, 0);

  VSET(16, e16, m2);
  VLOAD_16(v2, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v4);
  asm volatile("vrsub.vx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U16(14, v4, 20, 15, 0, 0, 0, -5, 0, 0, 20, 15, 0, 0, 0, -5, 0, 0);

  VSET(16, e32, m4);
  VLOAD_32(v4, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v8);
  asm volatile("vrsub.vx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(15, v8, 20, 15, 0, 0, 0, -5, 0, 0, 20, 15, 0, 0, 0, -5, 0, 0);

  VSET(16, e64, m8);
  VLOAD_64(v8, 5, 10, 15, 20, 25, 30, 35, 40, 5, 10, 15, 20, 25, 30, 35, 40);
  VLOAD_8(v0, 0x33, 0x33);
  VCLEAR(v16);
  asm volatile("vrsub.vx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U64(16, v16, 20, 15, 0, 0, 0, -5, 0, 0, 20, 15, 0, 0, 0, -5, 0, 0);
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
