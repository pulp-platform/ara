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
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.vv v6, v2, v4");
  VSET(16, e16, m1);
  VCMP_U16(1, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.vv v6, v2, v4");
  VSET(16, e32, m1);
  VCMP_U32(2, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.vv v6, v2, v4");
  VSET(16, e64, m1);
  VCMP_U64(3, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vv v6, v2, v4, v0.t");
  VSET(16, e16, m1);
  VCMP_U16(4, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vv v6, v2, v4, v0.t");
  VSET(16, e32, m1);
  VCMP_U32(5, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vv v6, v2, v4, v0.t");
  VSET(16, e64, m1);
  VCMP_U64(6, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);
}

void TEST_CASE3(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.vx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m1);
  VCMP_U16(7, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e16, m1);
  VLOAD_16(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.vx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m1);
  VCMP_U32(8, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e32, m1);
  VLOAD_32(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.vx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m1);
  VCMP_U64(9, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);
}

void TEST_CASE4(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m1);
  VCMP_U16(10, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m1);
  VCMP_U32(11, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.vx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m1);
  VCMP_U64(12, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);
}

void TEST_CASE5(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.wv v6, v2, v4");
  VSET(16, e16, m1);
  VCMP_U16(13, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e16, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.wv v6, v2, v4");
  VSET(16, e32, m1);
  VCMP_U32(14, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e32, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsub.wv v6, v2, v4");
  VSET(16, e64, m1);
  VCMP_U64(15, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);
}

void TEST_CASE6(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wv v6, v2, v4, v0.t");
  VSET(16, e16, m1);
  VCMP_U16(16, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e16, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wv v6, v2, v4, v0.t");
  VSET(16, e32, m1);
  VCMP_U32(17, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e32, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wv v6, v2, v4, v0.t");
  VSET(16, e64, m1);
  VCMP_U64(18, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);
}

void TEST_CASE7(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.wx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m1);
  VCMP_U16(19, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e16, m1);
  VLOAD_32(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.wx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m1);
  VCMP_U32(20, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e32, m1);
  VLOAD_64(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsub.wx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m1);
  VCMP_U64(21, v6, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);
}

void TEST_CASE8(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m1);
  VCMP_U16(22, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e16, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m1);
  VCMP_U32(23, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e32, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  asm volatile("vwsub.wx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m1);
  VCMP_U64(24, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);
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
