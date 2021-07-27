// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

#define AXI_DWIDTH 128

static volatile uint8_t ALIGNED_I8[16] __attribute__((aligned(AXI_DWIDTH))) = {
    0xe0, 0xd3, 0x40, 0xd1, 0x84, 0x48, 0x89, 0x88,
    0x88, 0xae, 0x08, 0x91, 0x02, 0x59, 0x11, 0x89};

// All the accesses are misaligned wrt AXI DATA WIDTH

void TEST_CASE1(void) {
  VSET(9, e8, m1);
  asm volatile("vle1.v v1, (%0)" ::"r"(&ALIGNED_I8[1]));
  VCMP_U8(1, v1, 0xd3, 0x40);

  VSET(9, e64, m2);
  asm volatile("vle1.v v1, (%0)" ::"r"(&ALIGNED_I8[1]));
  VCMP_U8(2, v1, 0xd3, 0x40);

  VSET(16, e64, m8);
  asm volatile("vle1.v v1, (%0)" ::"r"(&ALIGNED_I8[1]));
  VCMP_U8(3, v1, 0xd3, 0x40);

  VSET(17, e64, m8);
  asm volatile("vle1.v v1, (%0)" ::"r"(&ALIGNED_I8[1]));
  // The vector used by VCMP_U8 is actually 16 elements long
  // Don't store more if you don't want to overflow
  VSET(16, e64, m8);
  VCMP_U8(4, v1, 0xd3, 0x40, 0xd1);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();

  EXIT_CHECK();
}
