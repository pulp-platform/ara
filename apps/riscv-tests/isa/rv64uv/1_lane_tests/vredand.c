// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(12, e8, m1);
  VLOAD_8(v1, 0xff, 0xf1, 0xf0, 0xff, 0xf1, 0xf0, 0xff, 0xf1, 0xf0, 0xff, 0xf1,
          0xf0);
  VLOAD_8(v2, 0xf0);
  asm volatile("vredand.vs v3, v1, v2");
  VCMP_U8(1, v3, 0xf0);

  VSET(12, e16, m2);
  VLOAD_16(v2, 0xffff, 0x0301, 0xf1f0, 0xffff, 0x0101, 0xf7f0, 0xffff, 0x0701,
           0xfff0, 0xffff, 0x0101, 0xf1f0);
  VLOAD_16(v4, 0xefff);
  asm volatile("vredand.vs v6, v2, v4");
  VCMP_U16(2, v6, 0x0100);

  VSET(12, e32, m4);
  VLOAD_32(v4, 0xffffffff, 0x100ff001, 0xf0f0f0f0, 0xffffffff, 0x100ff001,
           0xf0f0f0f0, 0xffffffff, 0x100ff001, 0xf0f0f0f0, 0xffffffff,
           0x100ff001, 0xf0f0f0f0);
  VLOAD_32(v8, 0x00f010f0);
  asm volatile("vredand.vs v12, v4, v8");
  VCMP_U32(3, v12, 0x00001000);

  VSET(12, e64, m8);
  VLOAD_64(v8, 0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0);
  VLOAD_64(v16, 0xfffffffffffffff7);
  asm volatile("vredand.vs v24, v8, v16");
  VCMP_U64(4, v24, 0x1000000000000000);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(12, e8, m1);
  VLOAD_8(v0, 0xf7, 0xff);
  VLOAD_8(v1, 0xff, 0xf1, 0xff, 0x00, 0xf1, 0xf0, 0xff, 0xf1, 0xf0, 0xff, 0xf1,
          0xf0);
  VLOAD_8(v2, 0xf0);
  VLOAD_8(v3, 1);
  asm volatile("vredand.vs v3, v1, v2, v0.t");
  VCMP_U8(5, v3, 0xf0);

  VSET(12, e16, m2);
  VLOAD_8(v0, 0x00, 0x08);
  VLOAD_16(v2, 0xffff, 0x0301, 0xf1f0, 0xffff, 0x0101, 0xf7f0, 0xffff, 0x9701,
           0xfff0, 0xffff, 0x0101, 0xf1f0);
  VLOAD_16(v4, 0xefff);
  VLOAD_16(v6, 1);
  asm volatile("vredand.vs v6, v2, v4, v0.t");
  VCMP_U16(6, v6, 0xe1f0);

  VSET(12, e32, m4);
  VLOAD_8(v0, 0xfe, 0xff);
  VLOAD_32(v4, 0x00000000, 0x100ff001, 0xf0f0f0f0, 0xffffffff, 0x100ff001,
           0xf0f0f0f0, 0xffffffff, 0x100ff001, 0xf0f0f0f0, 0xffffffff,
           0x100ff001, 0xf0f0f0f0);
  VLOAD_32(v8, 0x00f010f0);
  VLOAD_32(v12, 1);
  asm volatile("vredand.vs v12, v4, v8, v0.t");
  VCMP_U32(7, v12, 0x00001000);

  VSET(12, e64, m8);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v8, 0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0,
           0xffffffffffffffff, 0x1000000000000001, 0xf0f0f0f0f0f0f0f0);
  VLOAD_64(v16, 0xfffffffffffffff7);
  VLOAD_64(v24, 1);
  asm volatile("vredand.vs v24, v8, v16, v0.t");
  VCMP_U64(8, v24, 0x1000000000000000);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
