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

  VSET(12, e16, m2);
  VLOAD_16(v2, 0x0000, 0x0301, 0x0100, 0x0000, 0x0101, 0x0700, 0x0000, 0x0701,
           0x0000, 0x0000, 0x0101, 0x0100);
  VLOAD_16(v4, 0xe000);
  asm volatile("vredor.vs v6, v2, v4");
  VCMP_U16(2, v6, 0xe701);

  VSET(12, e32, m4);
  VLOAD_32(v4, 0x00000000, 0x10000001, 0x00000000, 0x00000000, 0x10000001,
           0x00000000, 0x00000000, 0x10000001, 0x00000000, 0x00000000,
           0x10000001, 0x00000000);
  VLOAD_32(v8, 0x00001000);
  asm volatile("vredor.vs v12, v4, v8");
  VCMP_U32(3, v12, 0x10001001);

  VSET(12, e64, m8);
  VLOAD_64(v8, 0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000);
  VLOAD_64(v16, 0x0000000000000007);
  asm volatile("vredor.vs v24, v8, v16");
  VCMP_U64(4, v24, 0x1000000000000007);
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

  VSET(12, e16, m2);
  VLOAD_8(v0, 0x00, 0x08);
  VLOAD_16(v2, 0x0f00, 0x0301, 0x0100, 0x0000, 0x0101, 0x0700, 0x0000, 0x9701,
           0x0000, 0x0000, 0x0101, 0x0100);
  VLOAD_16(v4, 0xe000);
  VLOAD_16(v6, 1);
  asm volatile("vredor.vs v6, v2, v4, v0.t");
  VCMP_U16(6, v6, 0xe100);

  VSET(12, e32, m4);
  VLOAD_8(v0, 0x0e, 0x00);
  VLOAD_32(v4, 0xf0000fff, 0x10000001, 0x00000000, 0x00000000, 0x10000001,
           0x00000000, 0x00000000, 0x10000001, 0x00000000, 0x00000000,
           0x10000001, 0x00000000);
  VLOAD_32(v8, 0x00001000);
  VLOAD_32(v12, 1);
  asm volatile("vredor.vs v12, v4, v8, v0.t");
  VCMP_U32(7, v12, 0x10001001);

  VSET(12, e64, m8);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v8, 0x0000000000000000, 0x1000000000000001, 0x0000f00000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000, 0x1000000000000001, 0x0000000000000000);
  VLOAD_64(v16, 0x0000000000000007);
  VLOAD_64(v24, 1);
  asm volatile("vredor.vs v24, v8, v16, v0.t");
  VCMP_U64(8, v24, 0x1000000000000007);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
