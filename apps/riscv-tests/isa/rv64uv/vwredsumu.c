// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 255);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U16(1, v4, 327);

  VSET(16, e16, m1);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U32(2, v4, 73);

  VSET(16, e32, m1);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U64(3, v4, 73);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 255);
  VLOAD_16(v4, 1);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U16(4, v4, 291);

  VSET(16, e16, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1);
  VLOAD_32(v4, 1);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U32(5, v4, 37);

  VSET(16, e32, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1);
  VLOAD_64(v4, 1);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U64(6, v4, 37);
}

// Are we respecting the undisturbed tail policy?
void TEST_CASE3(void) {
  VSET(16, e8, m1);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U16(7, v4, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(16, e16, m1);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U32(8, v4, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(16, e32, m1);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U64(9, v4, 73, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
}

// Odd number of elements, undisturbed policy
void TEST_CASE4(void) {
  VSET(15, e8, m1);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U16(10, v4, 65, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(1, e16, m1);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U32(11, v4, 2, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(3, e32, m1);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U64(12, v4, 7, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
}

// Odd number of elements, undisturbed policy, and mask
void TEST_CASE5(void) {
  VSET(15, e8, m1);
  VLOAD_8(v0, 0x00, 0x40);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 100, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U16(13, v4, 107, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(1, e16, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U32(14, v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);

  VSET(3, e32, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vwredsumu.vs v4, v6, v2, v0.t");
  VCMP_U64(15, v4, 3, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
}

// Test difference from vwredsumu
void TEST_CASE6(void) {
  VSET(16, e8, m1);
  VLOAD_8(v6, 1, 2, 3, 4, 5, 6, 7, 8, 255, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 255);
  asm volatile("vwredsumu.vs v4, v6, v2");
  VCMP_U16(16, v4, 581);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();

  EXIT_CHECK();
}
