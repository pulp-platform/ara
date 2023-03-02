// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  asm volatile("vid.v v1");
  VCMP_U8(1, v1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

  VSET(16, e16, m1);
  asm volatile("vid.v v1");
  VCMP_U16(2, v1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

  VSET(16, e32, m1);
  asm volatile("vid.v v1");
  VCMP_U32(3, v1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

  VSET(16, e64, m1);
  asm volatile("vid.v v1");
  VCMP_U64(4, v1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v0, 85, 85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  asm volatile("vid.v v1, v0.t");
  VCMP_U8(5, v1, 0, 0, 2, 0, 4, 0, 6, 0, 8, 0, 10, 0, 12, 0, 14, 0);

  VSET(16, e16, m1);
  VLOAD_8(v0, 85, 85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  asm volatile("vid.v v1, v0.t");
  VCMP_U16(6, v1, 0, 0, 2, 0, 4, 0, 6, 0, 8, 0, 10, 0, 12, 0, 14, 0);

  VSET(16, e32, m1);
  VLOAD_8(v0, 85, 85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  asm volatile("vid.v v1, v0.t");
  VCMP_U32(7, v1, 0, 0, 2, 0, 4, 0, 6, 0, 8, 0, 10, 0, 12, 0, 14, 0);

  VSET(16, e64, m1);
  VLOAD_8(v0, 85, 85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  asm volatile("vid.v v1, v0.t");
  VCMP_U64(8, v1, 0, 0, 2, 0, 4, 0, 6, 0, 8, 0, 10, 0, 12, 0, 14, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
