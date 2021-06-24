// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(8, e8, m1);
  VLOAD_U8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  __asm__ volatile("vmsbf.m v2, v3");
  VEC_CMP_U8(1, v2, 7, 0, 0, 0, 0, 0, 0, 0);
}

void TEST_CASE2() {
  VSET(8, e8, m1);
  VLOAD_U8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_U8(v0, 3, 0, 0, 0, 0, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vmsbf.m v2, v3, v0.t");
  VEC_CMP_U8(2, v2, 3, 0, 0, 0, 0, 0, 0, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
