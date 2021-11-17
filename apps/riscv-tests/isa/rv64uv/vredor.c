// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(12, e8, m1);
  VLOAD_8(v1, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01,
          0x00);
  VLOAD_8(v2, 0x10);
  asm volatile("vredor.vs v3, v1, v2");
  VCMP_U8(1, v3, 0x11);

  VSET(12, e16, m1);
  VLOAD_16(v1, 0x0000, 0x0301, 0x0100, 0x0000, 0x0101, 0x0700, 0x0000, 0x0701,
           0x0000, 0x0000, 0x0101, 0x0100);
  VLOAD_16(v2, 0xe000);
  asm volatile("vredor.vs v3, v1, v2");
  VCMP_U16(2, v3, 0xe701);

  VSET(12, e32, m1);
  VLOAD_32(v1, 0x00000000, 0x10000001, 0x00000000, 0x00000000, 0x10000001,
           0x00000000, 0x00000000, 0x10000001, 0x00000000, 0x00000000,
           0x10000001, 0x00000000);
  VLOAD_32(v2, 0x00001000);
  asm volatile("vredor.vs v3, v1, v2");
  VCMP_U32(3, v3, 0x10001001);

  VSET(12, e64, m1);
  VLOAD_64(v1, 0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000);
  VLOAD_64(v2, 0x0000000000000007);
  asm volatile("vredor.vs v3, v1, v2");
  VCMP_U64(4, v3, 0x1000000000000007);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(12, e8, m1);
  VLOAD_8(v0, 0x07, 0x00);
  VLOAD_8(v1, 0x00, 0x01, 0x00, 0xff, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01,
          0x00);
  VLOAD_8(v2, 0x00);
  VLOAD_8(v3, 1);
  asm volatile("vredor.vs v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 0x01);

  VSET(12, e16, m1);
  VLOAD_8(v0, 0x00, 0x08);
  VLOAD_16(v1, 0x0f00, 0x0301, 0x0100, 0x0000, 0x0101, 0x0700, 0x0000, 0x9701,
           0x0000, 0x0000, 0x0101, 0x0100);
  VLOAD_16(v2, 0xe000);
  VLOAD_16(v3, 1);
  asm volatile("vredor.vs v3, v1, v2, v0.t");
  VCMP_U16(6, v3, 0xe100);

  VSET(12, e32, m1);
  VLOAD_8(v0, 0x0e, 0x00);
  VLOAD_32(v1, 0xf0000fff, 0x10000001, 0x00000000, 0x00000000, 0x10000001,
           0x00000000, 0x00000000, 0x10000001, 0x00000000, 0x00000000,
           0x10000001, 0x00000000);
  VLOAD_32(v2, 0x00001000);
  VLOAD_32(v3, 1);
  asm volatile("vredor.vs v3, v1, v2, v0.t");
  VCMP_U32(7, v3, 0x10001001);

  VSET(12, e64, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v1, 0x0000000000000000, 0x1000000000000001, 0x0000f00000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000);
  VLOAD_64(v2, 0x0000000000000007);
  VLOAD_64(v3, 1);
  asm volatile("vredor.vs v3, v1, v2, v0.t");
  VCMP_U64(8, v3, 0x1000000000000007);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
