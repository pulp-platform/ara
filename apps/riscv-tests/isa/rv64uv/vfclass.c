// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e64, m1);
  VLOAD_F64(v2, _d(1).i, _d(-1).i, _d(3.14159265).i, _d(-3.14159265).i);
  __asm__ volatile("vfclass.v v1, v2");
  VEC_CMP_U64(1, v1, 64, 2, 64, 2);
}

void TEST_CASE3() {
  VSET(8, e32, m1);
  VLOAD_F32(v2, _f(1).i, _f(-1).i, _f(3.14159265).i, _f(-3.14159265).i, _f(1).i,
            _f(-1).i, _f(3.14159265).i, _f(-3.14159265).i);
  __asm__ volatile("vfclass.v v1, v2");
  VEC_CMP_U32(1, v1, 64, 2, 64, 2, 64, 2, 64, 2);
}

// void TEST_CASE2() {
//   VSET(4,e64,m1);
//   VLOAD_F64(v2,_d(1).i,_d(-1).i,_d(3.14159265).i,_d(-3.14159265).i);
//   VLOAD_U64(v0,12,0,0,0);
//   CLEAR(v1);
//   __asm__ volatile("vfclass.v v1, v2, v0.t");
//   VEC_CMP_U64(2,v1,0,0,64,2);
// }

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE3();
  // TEST_CASE2();
  EXIT_CHECK();
}
