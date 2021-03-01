// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"


void TEST_CASE1(void) {
  VSET(4,e8,m1);
  volatile uint8_t INP1[] = {0xff, 0x00, 0x0f, 0xf0}; //flush
  MEMBARRIER;
  __asm__ volatile ("vle8.v v1, (%0)"::"r" (INP1));
   VEC_CMP_U8(1,v1,0xff, 0x00, 0x0f,0xf0);
   __asm__ volatile ("fence");
}

// void TEST_CASE2(void) {
//   VSET(4,e8,m1);
//   volatile uint8_t INP1[] = {0xff, 0x00, 0x0f, 0xf0}; //flush
//   __asm__ volatile ("fence");
//   VLOAD_U8(v0,0x5,0x0,0x0,0x0);
//   CLEAR(v1);
//   __asm__ volatile ("vle8.v v1, (%0), v0.t"::"r" (INP1));
//   VEC_CMP_U8(2,v1,0xff, 0x00, 0x0f,0);
// }

void TEST_CASE3(void) {
  VSET(3,e16,m1);
  volatile uint16_t INP[] = {0xffff, 0x0000, 0x0f0f};
  MEMBARRIER;
  __asm__ volatile ("vle16.v v1, (%0)"::"r" (INP));
  VEC_CMP_U16(4,v1,0xffff, 0x0000, 0x0f0f);
}

// void TEST_CASE4(void) {
//   VSET(3,e16,m1);
//   volatile uint16_t INP[] = {0xffff, 0x0001, 0x0f0f, 0xf0f0};
//   VLOAD_U16(v0,0x5,0x0,0x0,0x0);
//   CLEAR(v1);
//   __asm__ volatile ("vle16.v v1, (%0), v0.t"::"r" (INP));
//   VEC_CMP_U16(4,v1,0xffff, 0x0000, 0x0f0f);
// }

void TEST_CASE5(void) {
  VSET(4,e32,m1);
  volatile uint32_t INP[] = {0xffffffff, 0x00000000, 0x0f0f0f0f, 0xf0f0f0f0};
  MEMBARRIER;
  __asm__ volatile ( "vle32.v v1, (%0)" :: "r" (INP));
  VEC_CMP_U32(5,v1,0xffffffff,0x00000000, 0x0f0f0f0f,0xf0f0f0f0);
}


// void TEST_CASE6(void) {
//   VSET(4,e32,m1);
//   volatile uint32_t INP[] = {0xffffffff, 0x80000000, 0x0f0f0f0f, 0xf0f0f0f0};
//   VLOAD_U32(v0,0x5,0x0,0x0,0x0);
//   CLEAR(v1);
//   __asm__ volatile (" vle32.v v1, (%0), v0.t \n"    :: "r" (INP));
//   VEC_CMP_U32(6,v1,0xffffffff, 0x0, 0x0f0f0f0f, 0x0);
// }

void TEST_CASE7(void) {
  VSET(4,e64,m1);
  volatile uint64_t INP[] = {0xdeadbeefffffffff,0xdeadbeef00000000,0xdeadbeef0f0f0f0f,0xdeadbeeff0f0f0f0};
  MEMBARRIER;
  __asm__ volatile ("vle64.v v1,(%0)"::"r" (INP));
  VEC_CMP_U64(7,v1,0xdeadbeefffffffff,0xdeadbeef00000000,0xdeadbeef0f0f0f0f,0xdeadbeeff0f0f0f0);
}

// void TEST_CASE8(void) {
//   VSET(4,e64,m1);
//   volatile uint64_t INP[] = {0xdeadbeefffffffff,0xdeadbeef00000000,0xdeadbeef0f0f0f0f,0xdeadbeeff0f0f0f0};
//   VLOAD_U64(v0,0x5,0x0,0x0,0x0);
//   CLEAR(v1);
//   __asm__ volatile ("vle64.v v1,(%0), v0.t"::"r" (INP));
//   VEC_CMP_U64(8,v1,0xdeadbeefffffffff,0x0000000000000000,0xdeadbeef0f0f0f0f,0x0000000000000000);
// }


int main(void){
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE3();
  TEST_CASE5();
  TEST_CASE7();
  // Masked tests
  // TEST_CASE2();
  // TEST_CASE4();
  // TEST_CASE6();
  // TEST_CASE8();
  EXIT_CHECK();
}
