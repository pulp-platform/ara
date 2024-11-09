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
  asm volatile("vmsbf.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(1, v2, 7, 0);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 4, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsbf.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(2, v2, 3, 0);
}

void TEST_CASE3() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsbf.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(3, v2, 0xff, 0xff);

  VSET(16, e8, m1);
  VLOAD_8(v3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  asm volatile("vmsbf.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(4, v2, 0, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  VSET(16, e32, m1);
  asm volatile("vmsbf.m v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(5, v2, 0x07, 0x00);

  VSET(8, e64, m2);
  VLOAD_64(v4, 0, 0, 0, 0, 0, 1, 0, 0);
  VSET(512, e8, m2);
  asm volatile("vmsbf.m v2, v4");
  VSET(16, e32, m2);
  VCMP_U32(6, v2, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
           0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0, 0, 0,
           0, 0, 0);

  VSET(16, e64, m2);
  VLOAD_64(v4, 0, 0, 0, 0, 0, 1, 0, 0, 1685, 0, 0, 1, 0, 0, 0, 0);
  VSET(1024, e8, m2);
  asm volatile("vmsbf.m v2, v4");
  VSET(32, e32, m2);
  VCMP_U32(7, v2, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
           0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0, 0, 0,
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

void TEST_CASE4() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 3, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  VSET(2, e8, m1);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VCMP_U8(8, v2, 3, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 5, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  VSET(16, e8, m1);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(9, v2, 5, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x18, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 0xf7, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(10, v2, 0x07, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x18, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 0xef, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(11, v2, 0x07, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 0xf7, 0xff, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(12, v2, 0xf7, 0xff);

  VSET(16, e8, m1);
  VLOAD_8(v3, 0x38, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 0xf7, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(13, v2, 0x7, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 5, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  VSET(16, e8, m1);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VCMP_U8(14, v2, 5, 0);
}

void TEST_CASE5() {
  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 11, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(15, v2, 3, 0);

  VSET(16, e8, m1);
  VLOAD_8(v3, 8, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 11, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR_AT_ONE(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(16, v2, 0xf7, 0xff);

  VSET(8, e8, m1);
  VLOAD_8(v3, 0x94, 0, 0, 0, 0, 0, 0, 0);
  VLOAD_8(v0, 0xC3, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v2);
  asm volatile("vmsbf.m v2, v3, v0.t");
  VSET(1, e8, m1);
  VCMP_U8(17, v2, 0x43);
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
