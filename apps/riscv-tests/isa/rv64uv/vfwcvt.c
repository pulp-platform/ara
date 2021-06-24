// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  __asm__ volatile("vfwcvt.f.f.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_F64(1, v2, _d(3.1415901184082031).i, _d(1337.1231689453125).i,
              _d(68.932098388671875).i);
}

void TEST_CASE2() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.f.f.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_F64(2, v2, _d(3.1415901184082031).i, _d(1337.1231689453125).i,
              _d(0).i);
}

void TEST_CASE3() {
  VSET(3, e32, m1);
  VLOAD_U32(v4, -3, 1337, 68);
  __asm__ volatile("vfwcvt.f.x.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_F64(3, v2, _d(-3).i, _d(1337).i, _d(68).i);
}

void TEST_CASE4() {
  VSET(3, e32, m1);
  VLOAD_U32(v4, -3, 1337, 68);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.f.x.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_F64(4, v2, _d(-3).i, _d(1337).i, _d(0).i);
}

void TEST_CASE5() {
  VSET(3, e32, m1);
  VLOAD_U32(v4, 3, 1337, 68);
  __asm__ volatile("vfwcvt.f.xu.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_F64(5, v2, _d(3).i, _d(1337).i, _d(68).i);
}

void TEST_CASE6() {
  VSET(3, e32, m1);
  VLOAD_U32(v4, 3, 1337, 68);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.f.xu.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_F64(6, v2, _d(3).i, _d(1337).i, _d(0).i);
}

void TEST_CASE7() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(-3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  __asm__ volatile("vfwcvt.x.f.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_U64(7, v2, -3, 1337, 69);
}

void TEST_CASE8() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(-3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.x.f.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_64(8, v2, -3, 1337, 0);
}

void TEST_CASE9() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  __asm__ volatile("vfwcvt.xu.f.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_U64(9, v2, 3, 1337, 69);
}

void TEST_CASE10() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.xu.f.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_U64(10, v2, 3, 1337, 0);
}

void TEST_CASE11() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  __asm__ volatile("vfwcvt.rtz.xu.f.v v2, v4");
  VSET(3, e64, m1);
  VEC_CMP_U64(11, v2, 3, 1337, 68);
}

void TEST_CASE12() {
  VSET(3, e32, m1);
  VLOAD_F32(v4, _f(3.14159).i, _f(1337.123213).i, _f(68.9321).i);
  VLOAD_U32(v0, 3, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfwcvt.rtz.xu.f.v v2, v4, v0.t");
  VSET(3, e64, m1);
  VEC_CMP_U64(12, v2, 3, 1337, 0);
}

int main(void) {
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
  TEST_CASE11();
  TEST_CASE12();
  EXIT_CHECK();
}
