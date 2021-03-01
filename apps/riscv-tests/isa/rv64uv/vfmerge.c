// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"


void TEST_CASE1() {
  VSET(4,e32,m1);
  VLOAD_F32(v2,_f(1.1).i,_f(2.1).i,_f(3.1).i,_f(4.1).i);
  FLOAD32(f10,_f(0.5).i);
  VLOAD_U32(v0,5,0,0,0);
  __asm__ volatile("vfmerge.vfm v1, v2 , f10, v0");
  VEC_CMP_F32(1,v1,_f(0.5).i,_f(2.1).i,_f(0.5).i,_f(4.1).i);
}


int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  EXIT_CHECK();
}
