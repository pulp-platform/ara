// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e64, m1);
  VLOAD_64(v4, 1, 2, 3, 4);
  VLOAD_64(v0, 12, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vcompress.vm v2, v4, v0");
  DEBUG_64(v2);
  VEC_CMP_64(1, v2, 3, 4, 0, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  EXIT_CHECK();
}
