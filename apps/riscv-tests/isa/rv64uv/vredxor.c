// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(4, e8, m1);
  VLOAD_8(v1, 0x00, 0x01, 0x01, 0x00);
  VLOAD_8(v2, 0x11);
  asm volatile("vredxor.vs v3, v1, v2");
  VCMP_U8(1, v3, 0x11);

  VSET(4, e16, m1);
  VLOAD_16(v1, 0x8000, 0x0301, 0x0101, 0x0001);
  VLOAD_16(v2, 0xe001);
  asm volatile("vredxor.vs v3, v1, v2");
  VCMP_U16(2, v3, 0x6200);

  VSET(4, e32, m1);
  VLOAD_32(v1, 0x00000001, 0x10000001, 0x00000000, 0x00000000);
  VLOAD_32(v2, 0x00001000);
  asm volatile("vredxor.vs v3, v1, v2");
  VCMP_U32(3, v3, 0x10001000);

  VSET(4, e64, m1);
  VLOAD_64(v1, 0x0000000000000000, 0x1000000000000001, 0x0000000000000000,
           0x0000000000000000);
  VLOAD_64(v2, 0x0000000000000007);
  asm volatile("vredxor.vs v3, v1, v2");
  VCMP_U64(4, v3, 0x1000000000000006);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();

  EXIT_CHECK();
}
