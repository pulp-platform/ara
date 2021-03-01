// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(2,e64,m1);
  VLOAD_F64(v2,_d(0.05).i,_d(3.14159265).i);
  VSET(2,e32,m1);
  VLOAD_F32(v4,_f(-0.7).i,_f(2.451).i);
  VLOAD_F32(v6,_f(-231.7865).i,_f(1.432).i);
  __asm__ volatile("vfwnmsac.vv v2, v4, v6");
  VSET(2,e64,m1);
  VEC_CMP_F64(1,v2,_d(-162.20054655329585).i,_d(-0.36823941500339386).i);
}

// void TEST_CASE2() {
//   VSET(2,e64,m1);
//   VLOAD_F64(v2,_d(0.05).i,_d(3.14159265).i);
//   VSET(2,e32,m1);
//   VLOAD_F32(v4,_f(-0.7).i,_f(2.451).i);
//   VLOAD_F32(v6,_f(-231.7865).i,_f(1.432).i);
//   VLOAD_U32(v0,1,0);
//   __asm__ volatile("vfwnmsac.vv v2, v4, v6, v0.t");
//   VSET(2,e64,m1);
//   VEC_CMP_F64(2,v2,_d(-162.20054655329585).i,_d(3.14159265).i);
// }

void TEST_CASE3() {
  VSET(2,e64,m1);
  VLOAD_F64(v2,_d(0.05).i,_d(3.14159265).i);
  VSET(2,e32,m1);
  FLOAD32(f10,_f(2.659).i);
  VLOAD_F32(v6,_f(-231.7865).i,_f(1.432).i);
  __asm__ volatile("vfwnmsac.vf v2, f10, v6");
  VSET(2,e64,m1);
  VEC_CMP_F64(3,v2,_d(616.37028233521846).i,_d(-0.66609534432468065).i);
}

// void TEST_CASE4() {
//   VSET(2,e64,m1);
//   VLOAD_F64(v2,_d(0.05).i,_d(3.14159265).i);
//   VSET(2,e32,m1);
//   FLOAD32(f10,_f(2.659).i);
//   VLOAD_F32(v6,_f(-231.7865).i,_f(1.432).i);
//   VLOAD_U32(v0,1,0);
//   __asm__ volatile("vfwnmsac.vf v2, f10, v6, v0.t");
//   VSET(2,e64,m1);
//   VEC_CMP_F64(4,v2,_d(616.37028233521846).i,_d(3.14159265).i);
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
