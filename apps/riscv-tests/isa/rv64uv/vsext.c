// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf2 v2, v1");
  VCMP_U16(1, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);

  VSET(16, e32, m1);
  VLOAD_16(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf2 v2, v1");
  VCMP_U32(2, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);

  VSET(16, e64, m1);
  VLOAD_32(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf2 v2, v1");
  VCMP_U64(3, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
}

void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf2 v2, v1, v0.t");
  VCMP_U16(4, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);

  VSET(16, e32, m1);
  VLOAD_16(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf2 v2, v1, v0.t");
  VCMP_U32(5, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);

  VSET(16, e64, m1);
  VLOAD_32(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf2 v2, v1, v0.t");
  VCMP_U64(6, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);
}

void TEST_CASE3(void) {
  VSET(16, e32, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf4 v2, v1");
  VCMP_U32(7, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);

  VSET(16, e64, m1);
  VLOAD_16(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf4 v2, v1");
  VCMP_U64(8, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
}

void TEST_CASE4(void) {
  VSET(16, e32, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf4 v2, v1, v0.t");
  VCMP_U32(9, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);

  VSET(16, e64, m1);
  VLOAD_16(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf4 v2, v1, v0.t");
  VCMP_U64(10, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);
}

void TEST_CASE5(void) {
  VSET(16, e64, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf8 v2, v1");
  VCMP_U64(11, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
}

void TEST_CASE6(void) {
  VSET(16, e64, m1);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v2);
  asm volatile("vsext.vf8 v2, v1, v0.t");
  VCMP_U64(12, v2, 0, 2, 0, -4, 0, 6, 0, -8, 0, -2, 0, 4, 0, -6, 0, 8);
}

void TEST_CASE7(void) {
  VSET(16, e16, m2);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf2 v2, v1");
  VCMP_U16(13, v2, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);

  VSET(16, e32, m4);
  VLOAD_8(v3, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf4 v4, v3");
  VCMP_U32(14, v4, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);

  VSET(16, e64, m8);
  VLOAD_8(v1, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
  asm volatile("vsext.vf8 v8, v1");
  VCMP_U64(15, v8, 1, 2, -3, -4, 5, 6, -7, -8, -1, -2, 3, 4, -5, -6, 7, 8);
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
