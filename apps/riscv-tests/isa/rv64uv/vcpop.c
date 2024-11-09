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
  asm volatile("vpopc.m %[A], v2, v0.t \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(1, OUP[0], 2);

  VSET(32, e32, m1);
  VLOAD_32(v8, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88,
           0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF,
           0x88, 0x1, 0x1F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_32(v0, 0xffffffffffffffff, 0xfffffffffffffff7, 0xffffffffffffffff,
           0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
           0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
           0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
           0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
           0xefffffffffffffff, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VSET(1024, e8, m8);
  asm volatile("vpopc.m %[A], v8, v0.t \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(2, OUP[0], 159);
}

// unmasked
void TEST_CASE2(void) {
  VSET(4, e32, m1);
  VLOAD_32(v2, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F);
  volatile uint32_t scalar = 1337;
  volatile uint32_t OUP[] = {0, 0, 0, 0};
  VSET(128, e32, m2);
  asm volatile("vpopc.m %[A], v2 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(3, OUP[0], 40);

  VSET(8, e32, m1);
  VLOAD_32(v0, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88,
           0x1, 0x1F);
  VSET(256, e8, m8);
  asm volatile("vpopc.m %[A], v0 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(4, OUP[0], 80);

  VSET(16, e32, m1);
  VLOAD_32(v0, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88,
           0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF,
           0x88, 0x1, 0x1F);
  VSET(1024, e8, m8);
  asm volatile("vpopc.m %[A], v0 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(5, OUP[0], 160);

  VSET(8, e32, m1);
  VLOAD_32(v2, 0xFFFFFFF7FFFFFFFF, 0x88, 0x1, 0x1F, 0xFFFFFFF7FFFFFFFF, 0x88,
           0x1, 0x1F);
  VSET(256, e8, m1);
  asm volatile("vpopc.m %[A], v2 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(6, OUP[0], 80);

  VSET(2, e32, m1);
  VLOAD_8(v2, 0xFF, 0x88);
  VSET(16, e16, m1);
  asm volatile("vcpop.m %[A], v2 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(7, OUP[0], 10);

  VSET(4, e32, m1);
  VLOAD_32(v2, 0xF, 0, 0, 0);
  asm volatile("vpopc.m %[A], v2 \n"
               "sw %[A], (%1) \n"
               :
               : [A] "r"(scalar), "r"(OUP));
  XCMP(8, OUP[0], 4);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
