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

  VSET(16, e16, m2);
  VLOAD_16(v2, -1, 2, -3, 4, 5, 6, 7, 8, 1, 2, 3, -4, 5, 6, 7, 8);
  VLOAD_16(v4, 9);
  asm volatile("vredmax.vs v6, v2, v4");
  VCMP_U16(2, v6, 9);

  VSET(16, e32, m4);
  VLOAD_32(v4, 9, 2, 3, -4, 5, 6, 7, 8, 1, 2, 3, 4, -5, 6, 7, 8);
  VLOAD_32(v8, 1);
  asm volatile("vredmax.vs v12, v4, v8");
  VCMP_U32(3, v12, 9);

  VSET(16, e64, m8);
  VLOAD_64(v8, -1, 2, 3, -4, 5, 6, 7, 9, 1, 2, 3, 4, 5, 6, 7, -8);
  VLOAD_64(v16, -1);
  asm volatile("vredmax.vs v24, v8, v16");
  VCMP_U64(4, v24, 9);
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

  VSET(16, e16, m2);
  VLOAD_8(v0, 0x00, 0xc0);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, -7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v4, 9);
  VLOAD_16(v6, 1);
  asm volatile("vredmax.vs v6, v2, v4, v0.t");
  VCMP_U16(6, v6, 9);

  VSET(16, e32, m4);
  VLOAD_8(v0, 0x00, 0xc0);
  VLOAD_32(v4, -1, 2, 3, 4, 5, 6, 7, -8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v8, 1);
  VLOAD_32(v12, 1);
  asm volatile("vredmax.vs v12, v4, v8, v0.t");
  VCMP_U32(7, v12, 8);

  VSET(16, e64, m8);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v8, 1, -2, 3, 4, 5, 6, -7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v16, 4);
  VLOAD_64(v24, 1);
  asm volatile("vredmax.vs v24, v8, v16, v0.t");
  VCMP_U64(8, v24, 8);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
