// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4,e32,m1);
  VLOAD_F32(v2,_f(3.14159265).i,_f(-2.75343).i,_f(-3.14159265).i,_f(2.7).i);
  VLOAD_F32(v3,_f(-1).i,_f(-1).i,_f(1).i,_f(1).i);
  __asm__ volatile("vfsgnjx.vv v1, v2, v3");
  VEC_CMP_F32(1,v1,_f(-3.14159265).i,_f(2.75343).i,_f(-3.14159265).i,_f(2.7).i);
}

// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v2,_f(3.14159265).i,_f(-2.75343).i,_f(-3.14159265).i,_f(2.7).i);
//   VLOAD_F32(v3,_f(-1).i,_f(-1).i,_f(1).i,_f(1).i);
//   VLOAD_U32(v0,12,0,0,0);
//   CLEAR(v1);
//   __asm__ volatile("vfsgnjx.vv v1, v2, v3, v0.t");
//   VEC_CMP_F32(2,v1,_f(0).i,_f(0).i,_f(-3.14159265).i,_f(2.7).i);
// }

void TEST_CASE3() {
  VSET(4,e32,m1);
  VLOAD_F32(v2,_f(3.14159265).i,_f(-2.75343).i,_f(-3.14159265).i,_f(2.7).i);
  FLOAD32(f10,_f(-1).i);
  __asm__ volatile("vfsgnjx.vf v1, v2, f10");
  VEC_CMP_F32(3,v1,_f(-3.14159265).i,_f(2.75343).i,_f(3.14159265).i,_f(-2.7).i);
}

// void TEST_CASE4() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v2,_f(3.14159265).i,_f(-2.75343).i,_f(-3.14159265).i,_f(2.7).i);
//   FLOAD32(f10,_f(-1).i);
//   VLOAD_U32(v0,12,0,0,0);
//   CLEAR(v1);
//   __asm__ volatile("vfsgnjx.vf v1, v2, f10, v0.t");
//   VEC_CMP_F32(4,v1,_f(0).i,_f(0).i,_f(3.14159265).i,_f(-2.7).i);
// }


int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE3();
  // TEST_CASE2();
  // TEST_CASE4();
  EXIT_CHECK();
}
