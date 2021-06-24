// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

#define AXI_DWIDTH 128

static volatile uint8_t ALIGNED_O8[16] __attribute__((aligned(AXI_DWIDTH))) = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

static volatile uint16_t ALIGNED_O16[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};

static volatile uint32_t ALIGNED_O32[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000};

static volatile uint64_t ALIGNED_O64[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000};

// Misaligned access wrt 128-bit
void TEST_CASE1(void) {
  VSET(15, e8, m1);
  VLOAD_8(v1, 0xe4, 0x19, 0x20, 0x9f, 0xe4, 0x19, 0x20, 0x9f, 0xe4, 0x19, 0x20,
          0x9f, 0xe4, 0x19, 0x20);
  asm volatile("vse8.v v1, (%0)" ::"r"(&ALIGNED_O8[1]));
  VVCMP_U8(1, ALIGNED_O8, 0x00, 0xe4, 0x19, 0x20, 0x9f, 0xe4, 0x19, 0x20, 0x9f,
           0xe4, 0x19, 0x20, 0x9f, 0xe4, 0x19, 0x20);
}

void TEST_CASE2(void) {
  VSET(15, e16, m1);
  VLOAD_16(v1, 0xe478, 0x1549, 0x3240, 0x2f11, 0xe448, 0x1546, 0x3220, 0x9f11,
           0xe478, 0x1549, 0x3240, 0x2f11, 0xe448, 0x1546, 0x3220);
  asm volatile("vse16.v v1, (%0)" ::"r"(&ALIGNED_O16[1]));
  VVCMP_U16(2, ALIGNED_O16, 0x0000, 0xe478, 0x1549, 0x3240, 0x2f11, 0xe448,
            0x1546, 0x3220, 0x9f11, 0xe478, 0x1549, 0x3240, 0x2f11, 0xe448,
            0x1546, 0x3220);
}

void TEST_CASE3(void) {
  VSET(15, e32, m1);
  VLOAD_32(v1, 0xe1356784, 0x13241139, 0x20862497, 0x9f872456, 0xe1356784,
           0x13241139, 0x20862497, 0x9f872456, 0xe1356784, 0x13241139,
           0x20862497, 0x9f872456, 0xe1356784, 0x13241139, 0x20862497);
  asm volatile("vse32.v v1, (%0)" ::"r"(&ALIGNED_O32[1]));
  VVCMP_U32(3, ALIGNED_O32, 0x00000000, 0xe1356784, 0x13241139, 0x20862497,
            0x9f872456, 0xe1356784, 0x13241139, 0x20862497, 0x9f872456,
            0xe1356784, 0x13241139, 0x20862497, 0x9f872456, 0xe1356784,
            0x13241139, 0x20862497);
}

void TEST_CASE4(void) {
  VSET(15, e64, m1);
  VLOAD_64(v1, 0xe135578794246784, 0x1315345345241139, 0x2086252110062497,
           0x1100229933847136, 0xaaffaaffaaffaaff, 0xaf87245315434136,
           0xa135578794246784, 0x2315345345241139, 0x1086252110062497,
           0x1100229933847134, 0xaaffaaffaaffaaf4, 0x9315345345241139,
           0x9086252110062497, 0x9100229933847134, 0x9affaaffaaffaaf4);
  asm volatile("vse64.v v1, (%0)" ::"r"(&ALIGNED_O64[1]));
  VVCMP_U64(4, ALIGNED_O64, 0x0000000000000000, 0xe135578794246784,
            0x1315345345241139, 0x2086252110062497, 0x1100229933847136,
            0xaaffaaffaaffaaff, 0xaf87245315434136, 0xa135578794246784,
            0x2315345345241139, 0x1086252110062497, 0x1100229933847134,
            0xaaffaaffaaffaaf4, 0x9315345345241139, 0x9086252110062497,
            0x9100229933847134, 0x9affaaffaaffaaf4);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  EXIT_CHECK();
}
