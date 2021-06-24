// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Positive-stride tests
void TEST_CASE1(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  uint64_t stride = 3;
  asm volatile("vlse8.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U8(1, v1, 0x9f, 0x20, 0x05, 0xaa);
}

void TEST_CASE2(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0,
                              0xf9aa, 0x71f0, 0xc394, 0xbbd3};
  uint64_t stride = 4;
  asm volatile("vlse16.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U16(2, v1, 0x9fe4, 0x8f2e, 0xf9aa, 0xc394);
}

void TEST_CASE3(void) {
  VSET(4, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0xa11a9384, 0xa7163840, 0x99991348, 0xa9f38cd1};
  uint64_t stride = 8;
  asm volatile("vlse32.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U32(3, v1, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348);
}

void TEST_CASE4(void) {
  VSET(4, e64, m1);
  volatile uint64_t INP1[] = {0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
                              0xa11a9384a7163840, 0x99991348a9f38cd1};
  uint64_t stride = 8;
  asm volatile("vlse64.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U64(4, v1, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
           0x99991348a9f38cd1);
}

// Zero-stride tests
// The implementation must perform all the memory accesses
void TEST_CASE5(void) {
  VSET(16, e8, m1);
  volatile uint8_t INP1[] = {0x9f};
  uint64_t stride = 0;
  asm volatile("vlse8.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U8(5, v1, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f,
          0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f);
}

// The implementation can also perform fewer accesses
void TEST_CASE6(void) {
  VSET(16, e8, m1);
  volatile uint8_t INP1[] = {0x9f};
  asm volatile("vlse8.v v1, (%0), x0" ::"r"(INP1));
  VCMP_U8(6, v1, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f,
          0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0x9f);
}

// Different LMUL
void TEST_CASE7(void) {
  VSET(8, e64, m2);
  volatile uint64_t INP1[] = {0x9fa831c7a11a9384};
  asm volatile("vlse64.v v2, (%0), x0" ::"r"(INP1));
  VCMP_U64(7, v2, 0x9fa831c7a11a9384, 0x9fa831c7a11a9384, 0x9fa831c7a11a9384,
           0x9fa831c7a11a9384, 0x9fa831c7a11a9384, 0x9fa831c7a11a9384,
           0x9fa831c7a11a9384, 0x9fa831c7a11a9384);
}

// Others
// Negative-stride test
void TEST_CASE8(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0,
                              0xf9aa, 0x71f0, 0xc394, 0xbbd3};
  uint64_t stride = -4;
  asm volatile("vlse16.v v1, (%0), %1" ::"r"(&INP1[7]), "r"(stride));
  VCMP_U16(8, v1, 0xbbd3, 0x71f0, 0x05e0, 0x1920);
}

// Stride greater than default Ara AXI width == 128-bit (4 lanes)
void TEST_CASE9(void) {
  VSET(2, e64, m1);
  volatile uint64_t INP1[] = {0x99991348a9f38cd1, 0x9fa831c7a11a9384,
                              0x9fa831c7a11a9384, 0x9fa831c7a11a9384,
                              0x9fa831c7a11a9384, 0x01015ac1309bb678};
  uint64_t stride = 40;
  asm volatile("vlse64.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U64(9, v1, 0x99991348a9f38cd1, 0x01015ac1309bb678);
}

// Fill Ara internal Load Buffer
void TEST_CASE10(void) {
  VSET(8, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
      0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
      0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
      0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
      0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
      0x8913984898951989};
  uint64_t stride = 16;
  asm volatile("vlse64.v v1, (%0), %1" ::"r"(INP1), "r"(stride));
  VCMP_U64(10, v1, 0x9fe419208f2e05e0, 0xa11a9384a7163840, 0x9fa831c7a11a9384,
           0x1893179501093489, 0x1874754791888188, 0x9013930148815808,
           0x9031850931584902, 0x8319599991911111);
}

// Masked stride loads
void TEST_CASE11(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  uint64_t stride = 3;
  VLOAD_8(v0, 0xAA);
  VCLEAR(v1);
  asm volatile("vlse8.v v1, (%0), %1, v0.t" ::"r"(INP1), "r"(stride));
  VCMP_U8(11, v1, 0x00, 0x20, 0x00, 0xaa);
}

void TEST_CASE12(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0,
                              0xf9aa, 0x71f0, 0xc394, 0xbbd3};
  uint64_t stride = 4;
  VLOAD_8(v0, 0xAA);
  VCLEAR(v1);
  asm volatile("vlse16.v v1, (%0), %1, v0.t" ::"r"(INP1), "r"(stride));
  VCMP_U16(12, v1, 0, 0x8f2e, 0, 0xc394);
}

void TEST_CASE13(void) {
  VSET(4, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0xa11a9384, 0xa7163840, 0x99991348, 0xa9f38cd1};
  uint64_t stride = 8;
  VLOAD_8(v0, 0xAA);
  VCLEAR(v1);
  asm volatile("vlse32.v v1, (%0), %1, v0.t" ::"r"(INP1), "r"(stride));
  VCMP_U32(13, v1, 0, 0xf9aa71f0, 0, 0x99991348);
}

void TEST_CASE14(void) {
  VSET(8, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
      0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
      0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
      0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
      0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
      0x8913984898951989};
  uint64_t stride = 16;
  VLOAD_8(v0, 0xAA);
  VCLEAR(v1);
  asm volatile("vlse64.v v1, (%0), %1, v0.t" ::"r"(INP1), "r"(stride));
  VCMP_U64(14, v1, 0, 0xa11a9384a7163840, 0, 0x1893179501093489, 0,
           0x9013930148815808, 0, 0x8319599991911111);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  TEST_CASE5();
  TEST_CASE6();
  TEST_CASE7();

  TEST_CASE8();
  TEST_CASE9();
  TEST_CASE10();

  TEST_CASE11();
  TEST_CASE12();
  TEST_CASE13();
  TEST_CASE14();

  EXIT_CHECK();
}
