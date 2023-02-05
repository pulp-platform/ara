// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(4, e8, m1);
  volatile int8_t INP[] = {0xff, 0x00, 0x0f, 0xf0};
  __asm__ volatile("vle8ff.v v1, (%0)" ::"r"(INP));
  VEC_CMP_8(1, v1, 0xff, 0x00, 0x0f, 0xf0);
}

void TEST_CASE2(void) {
  VSET(4, e8, m1);
  volatile int8_t INP[] = {0xff, 0x00, 0x0f, 0xf0};
  VLOAD_8(v0, 0x5, 0x0, 0x0, 0x0);
  CLEAR(v1);
  __asm__ volatile("vle8ff.v v1, (%0), v0.t" ::"r"(INP));
  VEC_CMP_8(2, v1, 0xff, 0x00, 0x0f, 0x00);
}

void TEST_CASE3(void) {
  VSET(3, e16, m1);
  volatile int16_t INP[] = {0xffff, 0x0000, 0x0f0f, 0xf0f0};
  __asm__ volatile("vle16ff.v v1, (%0)" ::"r"(INP));
  VEC_CMP_16(3, v1, 0xffff, 0x0000, 0x0f0f);
}

void TEST_CASE4(void) {
  VSET(3, e16, m1);
  volatile int16_t INP[] = {0xffff, 0x0001, 0x0f0f, 0xf0f0};
  VLOAD_16(v0, 0x5, 0x0, 0x0, 0x0);
  CLEAR(v1);
  __asm__ volatile("vle16ff.v v1, (%0), v0.t" ::"r"(INP));
  VEC_CMP_16(4, v1, 0xffff, 0x0000, 0x0f0f);
}

void TEST_CASE5(void) {
  VSET(4, e32, m1);
  volatile int32_t INP[] = {0xffffffff, 0x00000000, 0x0f0f0f0f, 0xf0f0f0f0};
  __asm__ volatile("vle32ff.v v1, (%0)" ::"r"(INP));
  VEC_CMP_32(5, v1, 0xffffffff, 0x00000000, 0x0f0f0f0f, 0xf0f0f0f0);
}

void TEST_CASE6(void) {
  VSET(4, e32, m1);
  volatile int32_t INP[] = {0xffffffff, 0x80000000, 0x0f0f0f0f, 0xf0f0f0f0};
  VLOAD_32(v0, 0x5, 0x0, 0x0, 0x0);
  CLEAR(v1);
  __asm__ volatile(" vle32ff.v v1, (%0), v0.t \n" ::"r"(INP));
  VEC_CMP_32(6, v1, 0xffffffff, 0x0, 0x0f0f0f0f, 0x0);
}

void TEST_CASE7(void) {
  VSET(4, e64, m1);
  volatile int64_t INP[] = {0xdeadbeefffffffff, 0xdeadbeef00000000,
                            0xdeadbeef0f0f0f0f, 0xdeadbeeff0f0f0f0};
  __asm__ volatile("vle64ff.v v1,(%0)" ::"r"(INP));
  VEC_CMP_64(7, v1, 0xdeadbeefffffffff, 0xdeadbeef00000000, 0xdeadbeef0f0f0f0f,
             0xdeadbeeff0f0f0f0);
}

void TEST_CASE8(void) {
  VSET(4, e64, m1);
  volatile int64_t INP[] = {0xdeadbeefffffffff, 0xdeadbeef00000000,
                            0xdeadbeef0f0f0f0f, 0xdeadbeeff0f0f0f0};
  VLOAD_64(v0, 0x5, 0x0, 0x0, 0x0);
  CLEAR(v1);
  __asm__ volatile("vle64ff.v v1,(%0), v0.t" ::"r"(INP));
  VEC_CMP_64(8, v1, 0xdeadbeefffffffff, 0x0000000000000000, 0xdeadbeef0f0f0f0f,
             0x0000000000000000);
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
  EXIT_CHECK();
}
