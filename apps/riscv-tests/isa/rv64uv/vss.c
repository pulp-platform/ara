// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(4,e8,m1);
  volatile uint32_t STRIDE = 1;
  volatile uint8_t OUP[] = {0xde, 0xad, 0xbe, 0xef};
  VLOAD_U8(v1,0xff,0x00,0xf0,0x0f);
  __asm__ volatile("vsse8.v v1, (%0), %[rs2]"::"r"(OUP), [rs2] "r" (STRIDE));
  VEC_EQUAL_U8_RAW(1,OUP,0xff,0x00,0xf0,0x0f);
}

// void TEST_CASE2(void) {
//   VSET(4,e8,m1);
//   volatile int STRIDE = 1;
//   volatile int8_t OUP[] = {0xef, 0xef, 0xef, 0xef};
//   VLOAD_8(v1,0xff,0x00,0xf0,0x0f);
//   VLOAD_8(v0,12,0,0,0);
//   __asm__ volatile("vsse8.v v1, (%0), %1, v0.t"::"r"(OUP), "r" (STRIDE));
//   VEC_EQUAL_8_RAW(2,OUP,0xef,0xef,0xf0,0x0f);
// }

void TEST_CASE3(void) {
  VSET(4,e16,m1);
  volatile uint32_t STRIDE = -2;
  volatile uint16_t OUP[] = {0xdead, 0xbeef, 0xdead, 0xbeef};
  VLOAD_U16(v1,0xffff,0x0000,0xf0f0,0x0f0f);
  __asm__ volatile("vsse16.v v1, (%0), %[rs2]"::"r"(&OUP[3]), [rs2] "r" (STRIDE));
  VEC_EQUAL_U16_RAW(3,OUP,0x0f0f,0xf0f0,0x0000,0xffff);
}

// void TEST_CASE4(void) {
//   VSET(4,e16,m1);
//   volatile int STRIDE = -2;
//   volatile int16_t OUP[] = {0xdead, 0xbeef, 0xdead, 0xbeef};
//   VLOAD_16(v1,0xffff,0x0000,0xf0f0,0x0f0f);
//   VLOAD_16(v0,12,0,0,0);
//   __asm__ volatile("vsse16.v v1, (%0), %1, v0.t"::"r"(&OUP[3]), "r" (STRIDE));
//   VEC_EQUAL_16_RAW(2,OUP,0x0f0f,0xf0f0,0xdead,0xbeef);
// }

void TEST_CASE5(void) {
  VSET(4,e32,m1);
  volatile uint32_t STRIDE = 4;
  volatile uint32_t OUP5[] = {0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef};
  VLOAD_U32(v1,0xffffffff,0x00000000,0xf0f0f0f0,0x0f0f0f0f);
  __asm__ volatile("vsse32.v v1, (%0), %[rs2]"::"r"(OUP5), [rs2] "r" (STRIDE));
  VEC_EQUAL_U32_RAW(5,OUP5,0xffffffff,0x00000000,0xf0f0f0f0,0x0f0f0f0f);
}

// void TEST_CASE6(void) {
//   VSET(4,e32,m1);
//   volatile int STRIDE = 4;
//   volatile int32_t OUP[] = {0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef};
//   VLOAD_32(v1,0xffffffff,0x00000000,0xf0f0f0f0,0x0f0f0f0f);
//   VLOAD_32(v0,12,0,0,0);
//   __asm__ volatile("vsse32.v v1, (%0), %1, v0.t"::"r"(OUP), "r" (STRIDE));
//   VEC_EQUAL_32_RAW(6,OUP,0xdeadbeef,0xdeadbeef,0xf0f0f0f0,0x0f0f0f0f);
// }

void TEST_CASE7(void) {
  VSET(4,e64,m1);
  volatile uint32_t STRIDE = 8;
  volatile uint64_t OUP[] = {0xdeadbeefdeadbeef,0xdeadbeefdeadbeef,0xdeadbeefdeadbeef,0xdeadbeefdeadbeef};
  VLOAD_U64(v1,0xdeadbeef00000000,0xdeadbeefffffffff,0xdeadbeeff0f0f0f0,0xdeadbeef0f0f0f0f);
  __asm__ volatile("vsse64.v v1, (%0), %[rs2]"::"r"(OUP), [rs2] "r" (STRIDE));
  VEC_EQUAL_U64_RAW(7,OUP,0xdeadbeef00000000,0xdeadbeefffffffff,0xdeadbeeff0f0f0f0,0xdeadbeef0f0f0f0f);
}


// void TEST_CASE8(void) {
//   VSET(4,e64,m1);
//   volatile int STRIDE = 8;
//   volatile int64_t OUP[] = {0xdeadbeefdeadbeef,0xdeadbeefdeadbeef,0xdeadbeefdeadbeef,0xdeadbeefdeadbeef};
//   VLOAD_64(v1,0xdeadbeef00000000,0xdeadbeefffffffff,0xdeadbeeff0f0f0f0,0xdeadbeef0f0f0f0f);
//   VLOAD_64(v0,0x6,0,0,0x0);
//   __asm__ volatile("vsse64.v v1, (%0), %1, v0.t"::"r"(OUP), "r" (STRIDE));
//   VEC_EQUAL_64_RAW(8,OUP,0xdeadbeefdeadbeef,0xdeadbeefffffffff,0xdeadbeeff0f0f0f0,0xdeadbeefdeadbeef);
// }


int main(void){
  INIT_CHECK();
  enable_vec();
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
