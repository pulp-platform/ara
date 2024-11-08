// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  VLOAD_8(v2, 0xCD, 0xEF);
  VLOAD_8(v3, 0x84, 0x21);
  asm volatile("vmxor.mm v1, v2, v3");
  VSET(16, e8, m1);
  VCMP_U8(1, v1, 0x49, 0xCE);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v2, 0xCD, 0xEF);
  VLOAD_8(v3, 0xFF, 0xFF);
  asm volatile("vmxor.mm v1, v2, v3");
  VSET(16, e8, m1);
  VCMP_U8(2, v1, 0x32, 0x10);
}

void TEST_CASE3() {
  VSET(16, e8, m1);
  VLOAD_8(v2, 0xCD, 0xEF);
  VLOAD_8(v3, 0x00, 0x00);
  asm volatile("vmxor.mm v1, v2, v3");
  VSET(16, e8, m1);
  VCMP_U8(3, v1, 0xCD, 0xEF);
}

void TEST_CASE4() {
  VSET(16, e8, m1);
  VLOAD_8(v2, 0xCD, 0xEF);
  VLOAD_8(v3, 0x0F, 0xF0);
  asm volatile("vmxor.mm v1, v2, v3");
  VSET(16, e8, m1);
  VCMP_U8(4, v1, 0xC2, 0x1F);
}

void TEST_CASE5() {
  VSET(16, e8, m1);
  VLOAD_8(v1, 0xFF, 0xFF);
  VLOAD_8(v2, 0xCD, 0xEF);
  VLOAD_8(v3, 0x84, 0x21);
  VSET(16, e8, m1);
  asm volatile("vmxor.mm v1, v2, v3");
  VSET(16, e8, m1);
  VCMP_U8(5, v1, 0x49, 0xCE);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  EXIT_CHECK();
}
