// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(3,e64,m1);
  VLOAD_U64(v2,-3,1337,68);
  __asm__ volatile("vfcvt.f.x.v v1, v2");
  VEC_CMP_F64(1,v1,_d(-3).i,_d(1337).i,_d(68).i);
}

void TEST_CASE2() {
  VSET(3,e64,m1);
  VLOAD_U64(v2,-3,1337,68);
  VLOAD_U64(v0,3,0,0);
  CLEAR(v1);
  __asm__ volatile("vfcvt.f.x.v v1, v2, v0.t");
  VEC_CMP_F64(2,v1,_d(-3).i,_d(1337).i,_d(0).i);
}

void TEST_CASE3() {
  VSET(3,e64,m1);
  VLOAD_U64(v2,3,1337,68);
  __asm__ volatile("vfcvt.f.xu.v v1, v2");
  VEC_CMP_F64(3,v1,_d(3).i,_d(1337).i,_d(68).i);
}

void TEST_CASE4() {
  VSET(3,e64,m1);
  VLOAD_U64(v2,3,1337,68);
  VLOAD_U64(v0,3,0,0);
  CLEAR(v1);
  __asm__ volatile("vfcvt.f.xu.v v1, v2, v0.t");
  VEC_CMP_F64(4,v1,_d(3).i,_d(1337).i,_d(0).i);
}

void TEST_CASE5() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(-3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  __asm__ volatile("vfcvt.x.f.v v1, v2");
  VEC_CMP_U64(5,v1,-3,1337,69);
}

void TEST_CASE6() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(-3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  VLOAD_U64(v0,3,0,0);
  CLEAR(v1);
  __asm__ volatile("vfcvt.x.f.v v1, v2, v0.t");
  VEC_CMP_64(6,v1,-3,1337,0);
}

void TEST_CASE7() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  __asm__ volatile("vfcvt.xu.f.v v1, v2");
  VEC_CMP_U64(7,v1,3,1337,69);
}

void TEST_CASE8() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  VLOAD_U64(v0,3,0,0);
  CLEAR(v1);
  __asm__ volatile("vfcvt.xu.f.v v1, v2, v0.t");
  VEC_CMP_U64(8,v1,3,1337,0);
}

void TEST_CASE9() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  __asm__ volatile("vfcvt.rtz.xu.f.v v1, v2");
  VEC_CMP_U64(9,v1,3,1337,68);
}

void TEST_CASE10() {
  VSET(3,e64,m1);
  VLOAD_F64(v2,_d(3.14159).i,_d(1337.123213).i,_d(68.9321).i);
  VLOAD_U64(v0,3,0,0);
  CLEAR(v1);
  __asm__ volatile("vfcvt.rtz.xu.f.v v1, v2, v0.t");
  VEC_CMP_U64(10,v1,3,1337,0);
}

int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();
  TEST_CASE7();
  TEST_CASE8();
  TEST_CASE9();
  TEST_CASE10();
  EXIT_CHECK();
}
