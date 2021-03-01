// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"


void TEST_CASE1() {
  VSET(4,e32,m1);
  FLOAD32(f10,_f(0.5).i);
  __asm__ volatile("vfmv.v.f v1, f10");
  VEC_CMP_F32(1,v1,_f(0.5).i,_f(0.5).i,_f(0.5).i,_f(0.5).i);
}

void TEST_CASE2() {
  VSET(1,e64,m1);
  FLOAD64(f10,_d(3.1415925).i);
  __asm__ volatile("vfmv.s.f v1, f10");
  VEC_CMP_F64(2,v1,_d(3.1415924999999998).i);
}

void TEST_CASE3() {
  VSET(1,e32,m1);
  VLOAD_F32(v1,_f(3.14159265).i);
  __asm__ volatile("vfmv.f.s f10, v1");
  FCMP32(3,f10,_f(3.14159265).i);
}


int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  EXIT_CHECK();
}
