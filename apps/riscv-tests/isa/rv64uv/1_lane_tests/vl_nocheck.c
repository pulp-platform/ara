// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

// or add inp here
void TEST_CASE1(void) {
  VSET(4, e8, m1);
  volatile int8_t INP1[] = {0xff, 0x00, 0x0f, 0xf0}; // flush
  __asm__ volatile("fence");
  __asm__ volatile("vle8.v v1, (%0)" ::"r"(INP1));
  //  VEC_CMP_8(1,v1,0xff, 0x00, 0x0f,0xf0);
  //  __asm__ volatile ("fence");
}

void TEST_CASE2(void) {
  VSET(4, e16, m1);
  volatile int16_t INP1[] = {0xffff, 0x0000, 0x0f0f, 0xf0f0}; // flush
  __asm__ volatile("fence");
  __asm__ volatile("vle16.v v1, (%0)" ::"r"(INP1));
  //  VEC_CMP_16(2,v1,0xffff, 0x0000, 0x0f0f,0xf0f0);
  //  __asm__ volatile ("fence");
}

void TEST_CASE3(void) {
  VSET(4, e32, m1);
  volatile int32_t INP3[] = {0xffffffff, 0x00000000, 0x0f0f0f0f,
                             0xf0f0f0f0}; // flush
  __asm__ volatile("fence");
  __asm__ volatile("vle32.v v1, (%0)" ::"r"(INP3));
  //  VEC_CMP_32(3,v1,0xffffffff, 0x00000000, 0x0f0f0f0f,0xf0f0f0f0);
  //  __asm__ volatile ("fence");
}

void TEST_CASE4(void) {
  VSET(4, e64, m1);
  volatile int64_t INP1[] = {0xffffffffffffffff, 0x0000000000000000,
                             0x0f0f0f0f0f0f0f0f, 0xf0f0f0f0f0f0f0f0}; // flush
  __asm__ volatile("fence");
  __asm__ volatile("vle64.v v1, (%0)" ::"r"(INP1));
  //  VEC_CMP_64(4,v1,0xffffffffffffffff, 0x00000000000000000,
  //  0x0f0f0f0f0f0f0f0f,0xf0f0f0f0f0f0f0f0);
  //  __asm__ volatile ("fence");
}

/*  void TEST_CASE2(void) { */
/*    VSET(4,e8,m1); */
/*    volatile int8_t INP2[] = {0xff, 0x00, 0x0f, 0xf0}; */
/*    __asm__ volatile ("fence"); */
/*    VLOAD_8(v0,0x1,0x0,0x1,0x0); */
/*    VCLEAR_U8(v1); */
/*    __asm__ volatile ("vle8.v v1, (%0), v0.t"::"r" (INP2)); */
/*    VEC_CMP_8(2,v1,0xff, 0x00, 0x0f,0x00); */
/* } */

int main(void) {
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  EXIT_CHECK();
}
