// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U8(1, v3, 73);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U16(2, v3, 73);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U32(3, v3, 73);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U64(4, v3, 73);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1);
  VLOAD_8(v3, 1);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 37);

  VSET(16, e16, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1);
  VLOAD_16(v3, 1);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U16(6, v3, 37);

  VSET(16, e32, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1);
  VLOAD_32(v3, 1);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U32(7, v3, 37);

  VSET(16, e64, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1);
  VLOAD_64(v3, 1);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U64(8, v3, 37);
}

// Are we respecting the undisturbed tail policy?
void TEST_CASE3(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U8(9, v3, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U16(10, v3, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U32(11, v3, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U64(12, v3, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
}

// Odd number of elements, undisturbed policy
void TEST_CASE4(void) {
  VSET(15, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U8(13, v3, 65, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(1, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U16(14, v3, 2, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(3, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U32(15, v3, 7, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(7, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U64(16, v3, 29, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(15, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2");
  VCMP_U64(17, v3, 65, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
}

// Odd number of elements, undisturbed policy, and mask
void TEST_CASE5(void) {
  VSET(15, e8, m1);
  VLOAD_8(v0, 0x00, 0x40);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 100, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U8(18, v3, 107, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(1, e16, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U16(19, v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(3, e32, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vredsum.vs v3, v1, v2, v0.t");
  VCMP_U32(20, v3, 3, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
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
