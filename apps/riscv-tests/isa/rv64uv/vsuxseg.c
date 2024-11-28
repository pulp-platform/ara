// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

#define AXI_DWIDTH_MAX 512
#define MEM_VEC_SIZE 64

#define MEM_VCLEAR(vec)                                                        \
  {                                                                            \
    for (int i = 0; i < MEM_VEC_SIZE; ++i)                                     \
      vec[i] = 0;                                                              \
  }

static volatile uint8_t ALIGNED_O8[MEM_VEC_SIZE]
    __attribute__((aligned(AXI_DWIDTH_MAX))) = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

static volatile uint16_t ALIGNED_O16[MEM_VEC_SIZE]
    __attribute__((aligned(AXI_DWIDTH_MAX))) = {
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};

static volatile uint32_t ALIGNED_O32[MEM_VEC_SIZE]
    __attribute__((aligned(AXI_DWIDTH_MAX))) = {
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000};

static volatile uint64_t ALIGNED_O64[MEM_VEC_SIZE]
    __attribute__((aligned(AXI_DWIDTH_MAX))) = {
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
        0x0000000000000000};

// Segment-2
void TEST_CASE1_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};

  MEM_VCLEAR(ALIGNED_O8);
  VCLEAR(v1);
  VCLEAR(v2);
  VLOAD_8(v24, 1, 1, 0, 2);
  asm volatile("vluxseg2ei8.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg2ei8.v v1, (%0), v24" ::"r"(ALIGNED_O8));
  VVCMP_U8(1, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0, 0, 0, 0);
}

// Segment-3
void TEST_CASE2_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};

  MEM_VCLEAR(ALIGNED_O8);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VLOAD_16(v24, 0, 1, 0, 3);
  asm volatile("vluxseg3ei16.v v1, (%0), v24" ::"r"(INP1));
  VLOAD_16(v24, 3, 2, 1, 0);
  asm volatile("vsuxseg3ei16.v v1, (%0), v24" ::"r"(ALIGNED_O8));
  VVCMP_U8(2, ALIGNED_O8, 0x20, 0x8f, 0x2e, 0x19, 0x20, 0x19);
}

// Segment-4
void TEST_CASE3_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};

  MEM_VCLEAR(ALIGNED_O8);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VLOAD_64(v24, 1, 1, 0, 5);
  asm volatile("vluxseg4ei64.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg4ei64.v v1, (%0), v24" ::"r"(ALIGNED_O8));
  VVCMP_U8(3, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0, 0xf9);
}

// Segment-4 for 64-bit
void TEST_CASE3_64(void) {
  VSET(4, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
      0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
      0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
      0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
      0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
      0x987654321fedcba0};

  MEM_VCLEAR(ALIGNED_O64);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VLOAD_8(v24, 8, 8, 0, 40);
  asm volatile("vluxseg4ei8.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg4ei8.v v1, (%0), v24" ::"r"(ALIGNED_O64));
  VVCMP_U64(4, ALIGNED_O64, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
            0x123456789abcdef0, 0x13572468369b48ac, 0xdeadbeefcafebabe,
            0x0123456789abcdef, 0x55aa55aa77889900, 0xabcdef1234567890,
            0xfeedfacecafebabe, 0);
}

// Segment-8 for 64-bit
void TEST_CASE4_64_m(void) {
  VSET(2, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
      0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
      0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
      0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
      0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
      0x987654321fedcba0};

  MEM_VCLEAR(ALIGNED_O64);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  VLOAD_8(v0, 0xAF, 0xAA);
  VLOAD_8(v24, 8, 32);
  asm volatile("vluxseg8ei8.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg8ei8.v v1, (%0), v24, v0.t" ::"r"(ALIGNED_O64));
  VVCMP_U64(5, ALIGNED_O64, 0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
            0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
            0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
            0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef);

  MEM_VCLEAR(ALIGNED_O64);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_8(v24, 8, 32);
  asm volatile("vluxseg8ei8.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg8ei8.v v1, (%0), v24, v0.t" ::"r"(ALIGNED_O64));
  VVCMP_U64(6, ALIGNED_O64, 0, 0, 0, 0, 0xdeadbeefcafebabe, 0x0123456789abcdef,
            0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
            0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef);

  MEM_VCLEAR(ALIGNED_O64);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  VLOAD_8(v0, 0xA1, 0xAA);
  VLOAD_32(v24, 8, 32);
  asm volatile("vluxseg8ei32.v v1, (%0), v24" ::"r"(INP1));
  asm volatile("vsuxseg8ei32.v v1, (%0), v24, v0.t" ::"r"(ALIGNED_O64));
  VVCMP_U64(7, ALIGNED_O64, 0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
            0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
            0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe, 0, 0,
            0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1_8();
  TEST_CASE2_8();
  TEST_CASE3_8();

  TEST_CASE3_64();

  // Masked
  TEST_CASE4_64_m();

  EXIT_CHECK();
}
