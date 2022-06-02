// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

// masked
void TEST_CASE1(void) {
  VSET(4, e32, m1);
  VLOAD_32(v2, 7, 0, 0, 0);
  VLOAD_32(v0, 5, 0, 0, 0);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2, v0.t \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 2);
}

// unmasked
void TEST_CASE2(void) {
  VSET(4, e32, m1);
  VLOAD_32(v2, 9, 7, 5, 3);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2 \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 9);
}

// vector that requires 2 beats in a 4-lane configuration
void TEST_CASE3(void) {
  VSET(6, e64, m1);
  VLOAD_32(v2, 0xf, 0x0, 0xf, 0x0, 0x3, 0x0);
  VLOAD_32(v0, 0x11);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2, v0.t \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 6);
}

// TODO: more test cases
//    - DONE: without mask
//    - longer vectors with shorter element size
//    - DONE: very long vector that does not fit in one beat

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  // TEST_CASE2();
  // TEST_CASE3();
  EXIT_CHECK();
}
