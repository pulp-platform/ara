// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4, e32, m1);
  VLOAD_U32(v2, 7, 0, 0, 0);
  VLOAD_U32(v0, 5, 0, 0, 0);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  __asm__ volatile("vpopc.m %[A], v2, v0.t \n"
                   "sw %[A], (%1) \n"
                   :
                   : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 2);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  EXIT_CHECK();
}
