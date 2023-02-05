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
  asm volatile("vwsubu.vv v6, v2, v4");
  VSET(16, e16, m2);
  VCMP_U16(1, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsubu.vv v12, v4, v8");
  VSET(16, e32, m4);
  VCMP_U32(2, v12, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsubu.vv v24, v8, v16");
  VSET(16, e64, m8);
  VCMP_U64(3, v24, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);
}

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  VCLEAR(v7);
  asm volatile("vwsubu.vv v6, v2, v4, v0.t");
  VSET(16, e16, m2);
  VCMP_U16(4, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  VCLEAR(v14);
  asm volatile("vwsubu.vv v12, v4, v8, v0.t");
  VSET(16, e32, m4);
  VCMP_U32(5, v12, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  VCLEAR(v28);
  asm volatile("vwsubu.vv v24, v8, v16, v0.t");
  VSET(16, e64, m8);
  VCMP_U64(6, v24, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);
}

void TEST_CASE3(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.vx v6, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(7, v6, -4, 249, -2, 247, 0, 245, 2, 243, 4, 241, 6, 239, 8, 237, 10,
           235);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.vx v8, v4, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(8, v8, -4, 65529, -2, 65527, 0, 65525, 2, 65523, 4, 65521, 6, 65519,
           8, 65517, 10, 65515);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.vx v16, v8, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(9, v16, -4, 4294967289, -2, 4294967287, 0, 4294967285, 2, 4294967283,
           4, 4294967281, 6, 4294967279, 8, 4294967277, 10, 4294967275);
}

void TEST_CASE4(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  VCLEAR(v7);
  asm volatile("vwsubu.vx v6, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(10, v6, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  VCLEAR(v10);
  asm volatile("vwsubu.vx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(11, v8, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  VCLEAR(v20);
  asm volatile("vwsubu.vx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(12, v16, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);
}

void TEST_CASE5(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsubu.wv v6, v2, v4");
  VSET(16, e16, m2);
  VCMP_U16(13, v6, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsubu.wv v12, v4, v8");
  VSET(16, e32, m4);
  VCMP_U32(14, v12, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  asm volatile("vwsubu.wv v24, v8, v16");
  VSET(16, e64, m8);
  VCMP_U64(15, v24, -7, -5, -3, -1, 1, 3, 5, 7, -7, -5, -3, -1, 1, 3, 5, 7);
}

void TEST_CASE6(void) {
  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v4, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v6);
  VCLEAR(v7);
  asm volatile("vwsubu.wv v6, v2, v4, v0.t");
  VSET(16, e16, m2);
  VCMP_U16(16, v6, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v8, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v12);
  VCLEAR(v14);
  asm volatile("vwsubu.wv v12, v4, v8, v0.t");
  VSET(16, e32, m4);
  VCMP_U32(17, v12, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v16, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v24);
  VCLEAR(v28);
  asm volatile("vwsubu.wv v24, v8, v16, v0.t");
  VSET(16, e64, m8);
  VCMP_U64(18, v24, 0, -5, 0, -1, 0, 3, 0, 7, 0, -5, 0, -1, 0, 3, 0, 7);
}

void TEST_CASE7(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.wx v4, v2, %[A]" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(19, v4, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.wx v8, v4, %[A]" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(20, v8, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16);
  asm volatile("vwsubu.wx v16, v8, %[A]" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(21, v16, -4, -7, -2, -9, 0, -11, 2, -13, 4, -15, 6, -17, 8, -19, 10,
           -21);
}

void TEST_CASE8(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v4);
  VCLEAR(v5);
  asm volatile("vwsubu.wx v4, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e16, m2);
  VCMP_U16(22, v4, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e16, m2);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v8);
  VCLEAR(v10);
  asm volatile("vwsubu.wx v8, v4, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e32, m4);
  VCMP_U32(23, v8, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);

  VSET(16, e32, m4);
  VLOAD_64(v8, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v16);
  VCLEAR(v20);
  asm volatile("vwsubu.wx v16, v8, %[A], v0.t" ::[A] "r"(scalar));
  VSET(16, e64, m8);
  VCMP_U64(24, v16, 0, -3, 0, -1, 0, 1, 0, 3, 0, -3, 0, -1, 0, 1, 0, 3);
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
