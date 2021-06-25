// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e32, m1);
  VLOAD_F32(v2, _f(9.812321).i, _f(3.14159265).i, _f(-6.432423).i,
            _f(-190.53).i);
  FLOAD32(f10, _f(7.34253).i);
  __asm__ volatile("vfrdiv.vf v1, v2, f10");
  VEC_CMP_F32(1, v1, _f(0.748296976).i, _f(2.33719969).i, _f(-1.14148736).i,
              _f(-0.0385373943).i);
}

// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v2,_f(9.812321).i,_f(3.14159265).i,_f(-6.432423).i,_f(-190.53).i);
//   VLOAD_U32(v0,13,0,0,0);
//   FLOAD32(f10,_f(7.34253).i);
//   CLEAR(v1);
//   __asm__ volatile ("vfrdiv.vf v1, v2, f10, v0.t");
//   VEC_CMP_F32(2,v1,_f(0.748296976).i,_f(0).i,_f(-1.14148736).i,_f(-0.0385373943).i);
// }

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  // TEST_CASE2();
  EXIT_CHECK();
}
