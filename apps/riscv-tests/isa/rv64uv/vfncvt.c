// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.f.f.w v2, v4");
  VEC_CMP_F32(1, v2, _f(3.14159274).i, _f(123.123001).i, _f(321.542999).i,
              _f(99.1230011).i);
}

void TEST_CASE2() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.f.f.w v2, v4, v0.t");
  VEC_CMP_F32(2, v2, _f(0).i, _f(123.123001).i, _f(0).i, _f(99.1230011).i);
}

void TEST_CASE3() {
  VSET(4, e64, m1);
  VLOAD_64(v4, -3, 123, 321, 99);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.f.x.w v2, v4");
  VEC_CMP_F32(3, v2, _f(-3).i, _f(123).i, _f(321).i, _f(99).i);
}

void TEST_CASE4() {
  VSET(4, e64, m1);
  VLOAD_64(v4, 3, 123, 321, -99);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.f.x.w v2, v4, v0.t");
  VEC_CMP_F32(4, v2, _f(0).i, _f(123).i, _f(0).i, _f(-99).i);
}

void TEST_CASE5() {
  VSET(4, e64, m1);
  VLOAD_U64(v4, 3, 123, 321, 99);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.f.xu.w v2, v4");
  VEC_CMP_F32(5, v2, _f(3).i, _f(123).i, _f(321).i, _f(99).i);
}

void TEST_CASE6() {
  VSET(4, e64, m1);
  VLOAD_U64(v4, 3, 123, 321, 99);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.f.xu.w v2, v4, v0.t");
  VEC_CMP_F32(6, v2, _f(0).i, _f(123).i, _f(0).i, _f(99).i);
}

void TEST_CASE7() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.rod.f.f.w v2, v4");
  VEC_CMP_F32(7, v2, _f(3.14159274).i, _f(123.122993).i, _f(321.542999).i,
              _f(99.1229935).i);
}

void TEST_CASE8() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.rod.f.f.w v2, v4, v0.t");
  VEC_CMP_F32(8, v2, _f(0).i, _f(123.122993).i, _f(0).i, _f(99.1229935).i);
}

void TEST_CASE9() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(-123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.x.f.w v2, v4");
  VEC_CMP_32(9, v2, 3, -123, 322, 99);
}

void TEST_CASE10() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(-123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.x.f.w v2, v4, v0.t");
  VEC_CMP_32(10, v2, 0, -123, 0, 99);
}

void TEST_CASE11() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.xu.f.w v2, v4");
  VEC_CMP_U32(11, v2, 3, 123, 322, 99);
}

void TEST_CASE12() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.xu.f.w v2, v4, v0.t");
  VEC_CMP_U32(12, v2, 0, 123, 0, 99);
}

void TEST_CASE13() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  __asm__ volatile("vfncvt.rtz.xu.f.w v2, v4");
  VEC_CMP_U32(11, v2, 3, 123, 321, 99);
}

void TEST_CASE14() {
  VSET(4, e64, m1);
  VLOAD_F64(v4, _d(3.14159265).i, _d(123.123).i, _d(321.543).i, _d(99.123).i);
  VSET(4, e32, m1);
  VLOAD_U32(v0, 10, 0, 0, 0);
  CLEAR(v2);
  __asm__ volatile("vfncvt.rtz.xu.f.w v2, v4, v0.t");
  VEC_CMP_U32(12, v2, 0, 123, 0, 99);
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
  TEST_CASE13();
  TEST_CASE14();
  EXIT_CHECK();
}
