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
  // vcpop interprets the vl as bits, not as e32 elements
  VSET(128, e32, m1);
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
  VSET(128, e32, m1);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2 \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 9);
}

// more elements, smaller elements, masked
void TEST_CASE3(void) {
  VSET(6, e8, m1);
  VLOAD_8(v2, 0xf, 0x0, 0xf, 0x0, 0x3, 0x0);
  VLOAD_8(v0, 0x1, 0x0, 0x0, 0x0, 0x7, 0x0);
  VSET(48, e8, m1);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2, v0.t \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 3);
}

// unmasked
void TEST_CASE4(void) {
  VSET(6, e8, m1);
  VLOAD_8(v2, 0xf, 0x0, 0xf, 0x0, 0x3, 0x0);
  VSET(48, e8, m1);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2 \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 10);
}

// no active elements
void TEST_CASE5(void) {
  VSET(2, e32, m1);
  VLOAD_32(v2, 0, 0);
  VSET(64, e32, m1);
  volatile uint32_t scalar = 1234;
  volatile uint32_t OUP[] = {0, 0};
  __asm__ volatile("vpopc.m %[A], v2 \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 0);
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
  EXIT_CHECK();
}
