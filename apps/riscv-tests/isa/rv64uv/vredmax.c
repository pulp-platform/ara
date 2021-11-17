// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, -7, 8, 1, 9, 3, 4, 5, -6, 7, 8);
  VLOAD_8(v2, -1);
  asm volatile("vredmax.vs v3, v1, v2");
  VCMP_U8(1, v3, 9);

  VSET(16, e16, m1);
  VLOAD_16(v1, -1, 2, -3, 4, 5, 6, 7, 8, 1, 2, 3, -4, 5, 6, 7, 8);
  VLOAD_16(v2, 9);
  asm volatile("vredmax.vs v3, v1, v2");
  VCMP_U16(2, v3, 9);

  VSET(16, e32, m1);
  VLOAD_32(v1, 9, 2, 3, -4, 5, 6, 7, 8, 1, 2, 3, 4, -5, 6, 7, 8);
  VLOAD_32(v2, 1);
  asm volatile("vredmax.vs v3, v1, v2");
  VCMP_U32(3, v3, 9);

  VSET(16, e64, m1);
  VLOAD_64(v1, -1, 2, 3, -4, 5, 6, 7, 9, 1, 2, 3, 4, 5, 6, 7, -8);
  VLOAD_64(v2, -1);
  asm volatile("vredmax.vs v3, v1, v2");
  VCMP_U64(4, v3, 9);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v0, 0x03, 0x00);
  VLOAD_8(v1, -1, 2, 3, -4, 5, 6, 7, 9, 1, -2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 1);
  VLOAD_8(v3, 1);
  asm volatile("vredmax.vs v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 2);

  VSET(16, e16, m1);
  VLOAD_8(v0, 0x00, 0xc0);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, -7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 9);
  VLOAD_16(v3, 1);
  asm volatile("vredmax.vs v3, v1, v2, v0.t");
  VCMP_U16(6, v3, 9);

  VSET(16, e32, m1);
  VLOAD_8(v0, 0x00, 0xc0);
  VLOAD_32(v1, -1, 2, 3, 4, 5, 6, 7, -8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 1);
  VLOAD_32(v3, 1);
  asm volatile("vredmax.vs v3, v1, v2, v0.t");
  VCMP_U32(7, v3, 8);

  VSET(16, e64, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v1, 1, -2, 3, 4, 5, 6, -7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 4);
  VLOAD_64(v3, 1);
  asm volatile("vredmax.vs v3, v1, v2, v0.t");
  VCMP_U64(8, v3, 8);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
