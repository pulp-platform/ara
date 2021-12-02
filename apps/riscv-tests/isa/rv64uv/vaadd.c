// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(4, e8, m1);
  VLOAD_8(v1, 1, -2, -3, 4);
  VLOAD_8(v2, 1, 2, -3, 4);
  __asm__ volatile("vaadd.vv v3, v1, v2" ::);
  VCMP_U8(1, v3, 1, 0, -3, 4);
}

void TEST_CASE2(void) {
  VSET(4, e8, m1);
  VLOAD_8(v1, 1, -2, -3, 4);
  VLOAD_8(v2, 1, 2, -3, 4);
  VLOAD_8(v0, 0xA, 0x0, 0x0, 0x0);
  VCLEAR(v3);
  __asm__ volatile("vaadd.vv v3, v1, v2, v0.t" ::);
  VCMP_U8(2, v3, 0, 0, 0, 4);
}

void TEST_CASE3(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 1, -2, 3, -4);
  const uint32_t scalar = 5;
  __asm__ volatile("vaadd.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VCMP_U32(3, v3, 3, 2, 4, 1);
}

// Dont use VCLEAR here, it results in a glitch where are values are off by 1
void TEST_CASE4(void) {
  VSET(4, e32, m1);
  VLOAD_32(v1, 1, -2, 3, -4);
  const uint32_t scalar = 5;
  VLOAD_32(v0, 0xA, 0x0, 0x0, 0x0);
  VCLEAR(v3);
  __asm__ volatile("vaadd.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(4, v3, 0, 2, 0, 1);
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
