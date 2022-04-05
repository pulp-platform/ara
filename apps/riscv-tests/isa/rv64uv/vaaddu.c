// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  set_vxrm(0); // setting vxrm to rnu rounding mode
  VSET(4, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 5);
  VLOAD_8(v2, 1, 3, 8, 4);
  __asm__ volatile("vaaddu.vv v3, v1, v2" ::);
  VCMP_U8(1, v3, 1, 3, 6, 5);
}

void TEST_CASE2(void) {
  set_vxrm(1); // setting vxrm to rne rounding mode
  VSET(4, e8, m1);
  VLOAD_8(v1, 5, 8, 3, 7);
  VLOAD_8(v2, 7, 5, 3, 5);
  VLOAD_8(v0, 0x0A, 0x00, 0x00, 0x00);
  VCLEAR(v3);
  __asm__ volatile("vaaddu.vv v3, v1, v2, v0.t" ::);
  VCMP_U8(2, v3, 0, 6, 0, 6);
}

void TEST_CASE3(void) {
  set_vxrm(2); // setting vxrm to rdn rounding mode
  VSET(4, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4);
  const uint32_t scalar = 5;
  __asm__ volatile("vaaddu.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VCMP_U32(3, v3, 3, 3, 4, 4);
}

// Dont use VCLEAR here, it results in a glitch where are values are off by 1
void TEST_CASE4(void) {
  set_vxrm(3); // setting vxrm to rod rounding mode
  VSET(4, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4);
  const uint32_t scalar = 5;
  VLOAD_32(v0, 0xA, 0x0, 0x0, 0x0);
  VCLEAR(v3);
  __asm__ volatile("vaaddu.vx v3, v1, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(4, v3, 0, 3, 0, 5);
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
