// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Muhammad Ijaz

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  VLOAD_8(v4, 7, 7, 7, 7);
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wv v1, v2, v4");
  VCMP_U8(1, v1, 6, 0xff, 0xff, 0);
}

void TEST_CASE2() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  VLOAD_8(v4, 7, 7, 7, 7);
  VLOAD_8(v0, 0x5, 0, 0, 0);
  VCLEAR(v1);
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wv v1, v2, v4, v0.t");
  VCMP_U8(2, v1, 6, 0, 0xff, 0);
}

void TEST_CASE3() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  int8_t scalar = 7;
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_U8(3, v1, 6, 0xff, 0xff, 0);
}

void TEST_CASE4() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  int8_t scalar = 7;
  VLOAD_8(v0, 0x5, 0, 0);
  VCLEAR(v1);
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U8(4, v1, 6, 0, 0xff, 0);
}

void TEST_CASE5() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wi v1, v2, 7");
  VCMP_U8(5, v1, 6, 0xff, 0xff, 0);
}

void TEST_CASE6() {
  VSET(4, e8, m1);
  VLOAD_16(v2, 800, 65535, -50, 25);
  VLOAD_8(v0, 0x5, 0, 0, 0);
  VCLEAR(v1);
  __asm__ volatile("csrw vxrm, 2");
  __asm__ volatile("vnclipu.wi v1, v2, 7, v0.t");
  VCMP_U8(6, v1, 6, 0, 0xff, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();
  EXIT_CHECK();
}
