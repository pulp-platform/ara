// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

#define AXI_DWIDTH 128

static volatile uint8_t ALIGNED_I8[16] __attribute__((aligned(AXI_DWIDTH))) = {
    0xe0, 0xd3, 0x40, 0xd1, 0x84, 0x48, 0x89, 0x88,
    0x88, 0xae, 0x08, 0x91, 0x02, 0x59, 0x11, 0x89};

static volatile uint16_t ALIGNED_I16[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
        0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989};

static volatile uint32_t ALIGNED_I32[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7, 0x38197598,
        0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee, 0x90139301, 0xab8b9148,
        0x90318509, 0x31897598, 0x83195999, 0x89139848};

static volatile uint64_t ALIGNED_I64[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
        0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
        0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
        0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
        0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
        0x8913984898951989};

// Misaligned access wrt 128-bit
void TEST_CASE1(void) {
  VSET(15, e8, m1);
  asm volatile("vle8.v v1, (%0)" ::"r"(&ALIGNED_I8[1]));
  VCMP_U8(1, v1, 0xd3, 0x40, 0xd1, 0x84, 0x48, 0x89, 0x88, 0x88, 0xae, 0x08,
          0x91, 0x02, 0x59, 0x11, 0x89);
}

void TEST_CASE2(void) {
  VSET(15, e16, m1);
  asm volatile("vle16.v v1, (%0)" ::"r"(&ALIGNED_I16[1]));
  VCMP_U16(2, v1, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
}

void TEST_CASE3(void) {
  VSET(15, e32, m1);
  asm volatile("vle32.v v1, (%0)" ::"r"(&ALIGNED_I32[1]));
  VCMP_U32(3, v1, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7, 0x38197598,
           0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee, 0x90139301,
           0xab8b9148, 0x90318509, 0x31897598, 0x83195999, 0x89139848);
}

void TEST_CASE4(void) {
  VSET(15, e64, m1);
  asm volatile("vle64.v v1, (%0)" ::"r"(&ALIGNED_I64[1]));
  VCMP_U64(4, v1, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840, 0x99991348a9f38cd1,
           0x9fa831c7a11a9384, 0x3819759853987548, 0x1893179501093489,
           0x81937598aa819388, 0x1874754791888188, 0x3eeeeeeee33111ae,
           0x9013930148815808, 0xab8b914891484891, 0x9031850931584902,
           0x3189759837598759, 0x8319599991911111, 0x8913984898951989);
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
