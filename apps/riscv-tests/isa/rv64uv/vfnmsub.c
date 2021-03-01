// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(0.1).i,_d(-0.2).i,_d(3.14159265).i);
  VLOAD_F64(v3,_d(0.1).i, _d(0.2).i,_d(3.14159265).i);
  VLOAD_F64(v1,_d(0.7).i,_d(0.9).i,_d(1.124).i);
  __asm__ volatile("vfnmsub.vv v1, v2, v3");
  VEC_CMP_F64(1,v1,_d(0.03).i,_d(0.38).i,_d(-0.3895574886).i);
}

// void TEST_CASE2() {
//   VSET(3,e64,m1);
//   VLOAD_F64(v2,_d(0.1).i,_d(-0.2).i,_d(3.14159265).i);
//   VLOAD_F64(v3,_d(0.1).i, _d(0.2).i,_d(3.14159265).i);
//   VLOAD_F64(v1,_d(0.7).i,_d(0.9).i,_d(1.124).i);
//   VLOAD_U64(v0,6,0,0);
//   __asm__ volatile("vfnmsub.vv v1, v2, v3, v0.t");
//   VEC_CMP_F64(1,v1,_d(0.7).i,_d(0.38).i,_d(-0.3895574886).i);
// }

void TEST_CASE3() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(0.1).i,_d(-0.2).i,_d(3.14159265).i);
  FLOAD64(f10,_d(1.67).i);
  VLOAD_F64(v1,_d(0.7).i,_d(0.9).i,_d(1.124).i);
  __asm__ volatile("vfnmsub.vf v1, f10, v2");
  VEC_CMP_F64(3,v1,_d(-1.069).i,_d(-1.703).i,_d(1.26451265).i);
}

// void TEST_CASE4() {
//   VSET(3,e64,m1);
//   VLOAD_F64(v2,_d(0.1).i,_d(-0.2).i,_d(3.14159265).i);
//   FLOAD64(f10,_d(1.67).i);
//   VLOAD_F64(v1,_d(0.7).i,_d(0.9).i,_d(1.124).i);
//   VLOAD_U64(v0,6,0,0);
//   __asm__ volatile("vfnmsub.vf v1, f10, v2, v0.t");
//   VEC_CMP_F64(4,v1,_d(0.7).i,_d(-1.703).i,_d(1.26451265).i);
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
