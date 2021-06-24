// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e32, m1);
  VLOAD_F32(v2, _f(14159265).i, _f(-0.778).i, _f(1024).i, _f(-5667.2346).i);
  FLOAD32(f10, _f(3.14159264).i);
  CLEAR(v1);
  __asm__ volatile("vmfge.vf v1, v2, f10");
  VEC_CMP_U32(1, v1, 5, 0, 0, 0);
}

void TEST_CASE2() {
  VSET(4, e32, m1);
  VLOAD_F32(v2, _f(3.14159265).i, _f(-0.778).i, _f(1024).i, _f(-5667.2346).i);
  FLOAD32(f10, _f(3.14159264).i);
  VLOAD_U32(v0, 5, 0, 0, 0);
  CLEAR(v1);
  __asm__ volatile("vmfge.vf v1, v2, f10, v0.t");
  VEC_CMP_U32(2, v1, 5, 0, 0, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
