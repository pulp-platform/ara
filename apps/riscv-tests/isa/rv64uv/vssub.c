// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 0xfffffff0, 0x7FFFFFFC, 15, 20);
  VLOAD_32(v2, 0x7ffffff0, -500, 3, 25);
  __asm__ volatile("vssub.vv v3, v1, v2" ::);
  VEC_CMP_32(1, v3, 0x80000000, 0x7fffffff, 12, -5);
}

void TEST_CASE2(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 0xfffffff0, 0x7FFFFFFC, 15, 20);
  VLOAD_32(v2, 0x7ffffff0, -500, 3, 25);
  VLOAD_32(v0, 10, 0, 0, 0);
  CLEAR(v3);
  __asm__ volatile("vssub.vv v3, v1, v2, v0.t" ::);
  VEC_CMP_32(1, v3, 0, 0x7fffffff, 0, -5);
}

void TEST_CASE3(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 5, -2147483645, 15, 20);
  const int64_t scalar = 5;
  __asm__ volatile("vssub.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VEC_CMP_32(3, v3, 0, 0x80000000, 10, 15);
}

void TEST_CASE4(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 5, -2147483645, 15, 20);
  const int64_t scalar = 5;
  VLOAD_32(v0, 10, 0, 0, 0);
  CLEAR(v3);
  __asm__ volatile("vssub.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VEC_CMP_32(4, v3, 0, 0x80000000, 0, 15);
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
