// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e32, m1);
  VLOAD_F32(v2, _f(9).i, _f(3).i, _f(3.14159265).i, _f(1337.34).i);
  __asm__ volatile("vfsqrt.v v1,v2");
  VEC_CMP_F32(1, v1, _f(3).i, _f(1.73205078).i, _f(1.7724539).i,
              _f(36.5696602).i);
}

// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v2,_f(9).i,_f(3).i,_f(3.14159265).i,_f(1337.34).i);
//   VLOAD_U32(v0,5,0,0,0);
//   VLOAD_F32(v1,_f(1337).i,_f(1337).i,_f(1337).i,_f(1337).i);
//   __asm__ volatile("vfsqrt.v v1,v2, v0.t");
//   VEC_CMP_F32(2,v1,_f(3).i,_f(1337).i,_f(1.7724539).i,_f(1337).i);
// }

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  // TEST_CASE2();
  EXIT_CHECK();
}
