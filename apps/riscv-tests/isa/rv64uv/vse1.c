// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//
// For simplicity, this test depends on vle1

#include "vector_macros.h"

#define AXI_DWIDTH 128

static volatile uint8_t ALIGNED_I8_GOLD[16]
    __attribute__((aligned(AXI_DWIDTH))) = {0xe0, 0xd3, 0x40, 0xd1, 0x84, 0x48,
                                            0x89, 0x88, 0x88, 0xae, 0x08, 0x91,
                                            0x02, 0x59, 0x11, 0x89};

static volatile uint8_t ALIGNED_I8_BUF[16]
    __attribute__((aligned(AXI_DWIDTH))) = {0x00, 0x00, 0x00, 0x0,  0x00, 0x00,
                                            0x00, 0x0,  0x00, 0x00, 0x00, 0x0,
                                            0x00, 0x00, 0x00, 0x0};

void TEST_CASE1(void) {
  VSET(32, e8, m1);
  asm volatile("vle1.v v0, (%0)" ::"r"(ALIGNED_I8_GOLD));
  asm volatile("vse1.v v0, (%0)" ::"r"(ALIGNED_I8_BUF));
  VMCMP(uint8_t, % hhu, 1, ALIGNED_I8_BUF, ALIGNED_I8_GOLD, 4);

  VSET(29, e8, m1);
  asm volatile("vle1.v v0, (%0)" ::"r"(ALIGNED_I8_GOLD));
  asm volatile("vse1.v v0, (%0)" ::"r"(ALIGNED_I8_BUF));
  VMCMP(uint8_t, % hhu, 2, ALIGNED_I8_BUF, ALIGNED_I8_GOLD, 4);

  VSET(29, e64, m1);
  asm volatile("vle1.v v0, (%0)" ::"r"(ALIGNED_I8_GOLD));
  asm volatile("vse1.v v0, (%0)" ::"r"(ALIGNED_I8_BUF));
  VMCMP(uint8_t, % hhu, 3, ALIGNED_I8_BUF, ALIGNED_I8_GOLD, 4);

  VSET(29, e64, m8);
  asm volatile("vle1.v v0, (%0)" ::"r"(ALIGNED_I8_GOLD));
  asm volatile("vse1.v v0, (%0)" ::"r"(ALIGNED_I8_BUF));
  VMCMP(uint8_t, % hhu, 4, ALIGNED_I8_BUF, ALIGNED_I8_GOLD, 4);

  VSET(29, e64, m8);
  asm volatile("vle1.v v1, (%0)" ::"r"(ALIGNED_I8_GOLD));
  asm volatile("vse1.v v1, (%0)" ::"r"(ALIGNED_I8_BUF));
  VMCMP(uint8_t, % hhu, 5, ALIGNED_I8_BUF, ALIGNED_I8_GOLD, 4);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();

  EXIT_CHECK();
}
