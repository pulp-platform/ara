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
  __asm__ volatile("vfwsub.vv v2, v4, v6");
  VSET(4,e64,m1);
  VEC_CMP_F64(1,v2,_d(260.08111572265625).i,_d(-6.0510571002960205).i,_d(100.000244140625).i,_d(980.60009765625).i);
}

// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
//   VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwsub.vv v2, v4, v6, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(1,v2,_d(0).i,_d(-6.0510571002960205).i,_d(0).i,_d(980.60009765625).i);
// }

void TEST_CASE3() {
  VSET(4,e32,m1);
  VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
  FLOAD32(f10,_f(7.23432423).i);
  __asm__ volatile("vfwsub.vf v2, v4, f10");
  VSET(4,e64,m1);
  VEC_CMP_F64(3,v2,_d(305.07799243927002).i,_d(-4.0927317142486572).i,_d(-2319.5553693771362).i,_d(-1344.4342756271362).i);
}

// void TEST_CASE4() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(312.312312).i,_f(3.14159265).i,_f(-2312.321).i,_f(-1337.2).i);
//   FLOAD32(f10,_f(7.23432423).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwsub.vf v2, v4, f10, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(4,v2,_d(0).i,_d(-4.0927317142486572).i,_d(0).i,_d(-1344.4342756271362).i);
// }

void TEST_CASE5() {
  VSET(4,e64,m1);
  VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
  VSET(4,e32,m1);
  FLOAD32(f10,_f(7.23432423).i);
  __asm__ volatile("vfwsub.wf v2, v4, f10");
  VSET(4,e64,m1);
  VEC_CMP_F64(5,v2,_d(305.07798754473879).i,_d(-4.0927318052612307).i,_d(-2319.5553244552611).i,_d(-1344.4343244552613).i);
}

// void TEST_CASE6() {
//   VSET(4,e64,m1);
//   VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
//   VSET(4,e32,m1);
//   FLOAD32(f10,_f(7.23432423).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwsub.wf v2, v4, f10, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(6,v2,_d(0).i,_d(-4.0927318052612307).i,_d(0).i,_d(-1344.4343244552613).i);
// }

void TEST_CASE7() {
  VSET(4,e64,m1);
  VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
  VSET(4,e32,m1);
  VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
  __asm__ volatile("vfwsub.wv v2, v4, v6");
  VSET(4,e64,m1);
  VEC_CMP_F64(7,v2,_d(260.08111082812502).i,_d(-6.051057191308594).i,_d(100.00028906250009).i,_d(980.60004882812495).i);
}

// void TEST_CASE8() {
//   VSET(4,e64,m1);
//   VLOAD_F64(v4,_d(312.312312).i,_d(3.14159265).i,_d(-2312.321).i,_d(-1337.2).i);
//   VSET(4,e32,m1);
//   VLOAD_F32(v6,_f(52.2312).i,_f(9.19265).i,_f(-2412.32121).i,_f(-2317.8).i);
//   VLOAD_U32(v0,10,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile("vfwsub.wv v2, v4, v6, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(8,v2,_d(0).i,_d(-6.051057191308594).i,_d(0).i,_d(980.60004882812495).i);
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
