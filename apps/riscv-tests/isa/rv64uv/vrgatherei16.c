// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Muhammad Ijaz

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(5, e16, m2);
  VLOAD_16(v6, 1, 0, 4, 3, 2);
  VSET(5, e8, m1);
  VLOAD_8(v4, 10, 20, 30, 40, 50);
  __asm__ volatile("vrgatherei16.vv v2, v4, v6");
  VCMP_U8(1, v2, 20, 10, 50, 40, 30);
}
void TEST_CASE2() {
  VSET(5, e16, m2);
  VLOAD_16(v6, 1, 0, 4, 3, 2);
  VSET(5, e8, m1);
  VLOAD_8(v4, 10, 20, 30, 40, 50);
  VLOAD_8(v0, 26, 0, 0, 0, 0);
  VCLEAR(v2);
  __asm__ volatile("vrgatherei16.vv v2, v4, v6, v0.t");
  VCMP_U8(2, v2, 0, 10, 0, 40, 30);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
