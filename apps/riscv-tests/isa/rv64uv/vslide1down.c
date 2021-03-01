// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(6,e32,m1);
  VLOAD_32(v2,0,0,0,1,2,3);
  uint64_t scalar = 3;
  __asm__ volatile("vslide1down.vx v1, v2, %[A]":: [A] "r" (scalar));
  VEC_CMP_32(1,v1,0,0,1,2,3,3);
}

void TEST_CASE2() {
  VSET(6,e32,m1);
  VLOAD_32(v2,0,0,0,1,2,3);
  uint64_t scalar = 3;
  VLOAD_U32(v0,12,0,0,0,0,0);
  CLEAR(v2);
  __asm__ volatile("vslide1down.vx v1, v2, %[A], v0.t":: [A] "r" (scalar));
  VEC_CMP_32(2,v1,0,0,0,0,3,3);
}


int main(void){
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
