// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsif.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(1, v2, 15, 0);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsif.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(2, v2, 0xff, 0xff);

  VSET(16, e8, m1);
  VLOAD_8(v3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsif.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(3, v2, 1, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VSET(16, e32, m1);
  asm volatile("vmsif.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(4, v2, 0x0F, 0x00);

  VSET(8, e64, m2);
  VLOAD_64(v4, 0, 0, 0, 0, 0, 1, 0, 0);
  VSET(512, e8, m2);
  asm volatile("vmsif.m v2, v4");
  VSET(16, e32, m2);
  VCMP_U32(5, v2, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
           0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 1, 0, 0,
           0, 0, 0);

  VSET(16, e64, m2);
  VLOAD_64(v4, 0, 0, 0, 0, 0, 1, 0, 0, 1685, 0, 0, 1, 0, 0, 0, 0);
  VSET(1024, e8, m4);
  asm volatile("vmsif.m v0, v4");
  VSET(32, e32, m2);
  VCMP_U32(6, v0, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
           0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 1, 0, 0,
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

void TEST_CASE3() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 11, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsif.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(7, v2, 11, 0, 0, 0, 0, 0, 0, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  EXIT_CHECK();
}
