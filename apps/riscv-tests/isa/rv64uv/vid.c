// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  __asm__ volatile("vid.v v1");
  VCMP_U8(1, v1, 0, 1, 2, 3, 4, 5, 6, 7);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v0, 85, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  __asm__ volatile("vid.v v1, v0.t");
  VCMP_U8(2, v1, 0, 0, 2, 0, 4, 0, 6, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
