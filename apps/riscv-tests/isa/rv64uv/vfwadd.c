// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4,e32,m1);
  VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
  VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
  __asm__ volatile("vfwadd.vv v2, v4, v6");
  VSET(4,e64,m1);
  VEC_CMP_F64(1,v2,_d(364.54351806640625).i,_d(12.334242582321167).i,_d(-4724.642333984375).i,_d(-3655).i);
}

// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
//   VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwadd.vv v2, v4, v6, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(2,v2,_d(0).i,_d(12.334242582321167).i,_d(0).i,_d(-3655).i);
// }

void TEST_CASE3() {
  VSET(4,e32,m1);
  VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
  FLOAD32(f10,_f(7.23432423).i);
  __asm__ volatile("vfwadd.vf v2, v4, f10");
  VSET(4,e64,m1);
  VEC_CMP_F64(3,v2,_d(319.54664134979248).i,_d(10.375917196273804).i,_d(-2305.0867204666138).i,_d(-1329.9656267166138).i);
}

// void TEST_CASE4() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
//   FLOAD32(f10,_f(7.23432423).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwadd.vf v2, v4, f10, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(4,v2,_d(0).i,_d(10.375917196273804).i,_d(0).i,_d(-1329.9656267166138).i);
// }

void TEST_CASE5() {
  VSET(4,e64,m1);
  VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
  VSET(4,e32,m1);
  FLOAD32(f10,_f(7.23432423).i);
  __asm__ volatile("vfwadd.wf v2, v4, f10");
  VSET(4,e64,m1);
  VEC_CMP_F64(5,v2,_d(319.54663645526125).i,_d(10.37591710526123).i,_d(-2305.0866755447387).i,_d(-1329.9656755447388).i);
}

// void TEST_CASE6() {
//   VSET(4,e64,m1);
//   VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
//   VSET(4,e32,m1);
//   FLOAD32(f10,_f(7.23432423).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwadd.wf v2, v4, f10, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(6,v2,_d(0).i,_d(10.37591710526123).i,_d(0).i,_d(-1329.9656755447388).i);
// }

void TEST_CASE7() {
  VSET(4,e64,m1);
  VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
  VSET(4,e32,m1);
  VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
  __asm__ volatile("vfwadd.wv v2, v4, v6");
  VSET(4,e64,m1);
  VEC_CMP_F64(7,v2,_d(364.54351317187502).i,_d(12.334242491308594).i,_d(-4724.6422890624999).i,_d(-3655.0000488281248).i);
}

// void TEST_CASE8() {
//   VSET(4,e64,m1);
//   VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
//   VSET(4,e32,m1);
//   VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwadd.wv v2, v4, v6, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(8,v2,_d(0).i,_d(12.334242491308594).i,_d(0).i,_d(-3655.0000488281248).i);
// }


int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE3();
  TEST_CASE5();
  TEST_CASE7();
  // TEST_CASE2();
  // TEST_CASE4();
  // TEST_CASE6();
  // TEST_CASE8();
  EXIT_CHECK();
}
