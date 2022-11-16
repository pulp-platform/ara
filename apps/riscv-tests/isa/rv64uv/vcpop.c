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
  VCLEAR(v2);
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
  VLOAD_32(v2, 0xF, 0, 0, 0);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2 \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(2, OUP[0], 4);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
