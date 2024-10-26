// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

#define AXI_DWIDTH_MAX 512
#define MEM_VEC_SIZE 16

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
  VCLEAR(v1);
  VCLEAR(v2);
  asm volatile("vlseg2e8.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg2e8.v v1, (%0)" ::"r"(ALIGNED_O8));
  VVCMP_U8(1, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0);
}

// Segment-3
void TEST_CASE2_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  asm volatile("vlseg3e8.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg3e8.v v1, (%0)" ::"r"(ALIGNED_O8));
  VVCMP_U8(2, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0, 0xf9,
           0xaa, 0x71, 0xf0);
}

// Segment-4
void TEST_CASE3_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  asm volatile("vlseg4e8.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg4e8.v v1, (%0)" ::"r"(ALIGNED_O8));
  VVCMP_U8(3, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0, 0xf9,
           0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3);
}

// Segment-8
void TEST_CASE4_8(void) {
  VSET(2, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  asm volatile("vlseg8e8.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg8e8.v v1, (%0)" ::"r"(ALIGNED_O8));
  VVCMP_U8(4, ALIGNED_O8, 0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0, 0xf9,
           0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3);
}

// Segment-2 for 16-bit
void TEST_CASE1_16(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
                              0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0,
                              0x1357, 0x2468, 0x369b, 0x48ac};
  VCLEAR(v1);
  VCLEAR(v2);
  asm volatile("vlseg2e16.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg2e16.v v1, (%0)" ::"r"(ALIGNED_O16));
  VVCMP_U16(5, ALIGNED_O16, 0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
            0xc394, 0xbbd3);
}

// Segment-3 for 16-bit
void TEST_CASE2_16(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
                              0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0,
                              0x1357, 0x2468, 0x369b, 0x48ac};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  asm volatile("vlseg3e16.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg3e16.v v1, (%0)" ::"r"(ALIGNED_O16));
  VVCMP_U16(6, ALIGNED_O16, 0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
            0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0);
}

// Segment-4 for 16-bit
void TEST_CASE3_16(void) {
  VSET(4, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
                              0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0,
                              0x1357, 0x2468, 0x369b, 0x48ac};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  asm volatile("vlseg4e16.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg4e16.v v1, (%0)" ::"r"(ALIGNED_O16));
  VVCMP_U16(7, ALIGNED_O16, 0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
            0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0, 0x1357, 0x2468,
            0x369b, 0x48ac);
}

// Segment-8 for 16-bit
void TEST_CASE4_16(void) {
  VSET(2, e16, m1);
  volatile uint16_t INP1[] = {0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
                              0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0,
                              0x1357, 0x2468, 0x369b, 0x48ac};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  asm volatile("vlseg8e16.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg8e16.v v1, (%0)" ::"r"(ALIGNED_O16));
  VVCMP_U16(8, ALIGNED_O16, 0x9fe4, 0x1920, 0x8f2e, 0x05e0, 0xf9aa, 0x71f0,
            0xc394, 0xbbd3, 0x1234, 0x5678, 0x9abc, 0xdef0, 0x1357, 0x2468,
            0x369b, 0x48ac);
}

// Segment-2 for 32-bit
void TEST_CASE1_32(void) {
  VSET(4, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac,
                              0xdeadbeef, 0xcafebabe, 0x01234567, 0x89abcdef,
                              0x55aa55aa, 0x77889900, 0xabcdef12, 0x34567890};
  VCLEAR(v1);
  VCLEAR(v2);
  asm volatile("vlseg2e32.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg2e32.v v1, (%0)" ::"r"(ALIGNED_O32));
  VVCMP_U32(9, ALIGNED_O32, 0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
            0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac);
}

// Segment-3 for 32-bit
void TEST_CASE2_32(void) {
  VSET(4, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac,
                              0xdeadbeef, 0xcafebabe, 0x01234567, 0x89abcdef,
                              0x55aa55aa, 0x77889900, 0xabcdef12, 0x34567890};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  asm volatile("vlseg3e32.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg3e32.v v1, (%0)" ::"r"(ALIGNED_O32));
  VVCMP_U32(10, ALIGNED_O32, 0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
            0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac, 0xdeadbeef,
            0xcafebabe, 0x01234567, 0x89abcdef);
}

// Segment-4 for 32-bit
void TEST_CASE3_32(void) {
  VSET(4, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac,
                              0xdeadbeef, 0xcafebabe, 0x01234567, 0x89abcdef,
                              0x55aa55aa, 0x77889900, 0xabcdef12, 0x34567890};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  asm volatile("vlseg4e32.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg4e32.v v1, (%0)" ::"r"(ALIGNED_O32));
  VVCMP_U32(11, ALIGNED_O32, 0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
            0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac, 0xdeadbeef,
            0xcafebabe, 0x01234567, 0x89abcdef, 0x55aa55aa, 0x77889900,
            0xabcdef12, 0x34567890);
}

// Segment-8 for 32-bit
void TEST_CASE4_32(void) {
  VSET(2, e32, m1);
  volatile uint32_t INP1[] = {0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
                              0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac,
                              0xdeadbeef, 0xcafebabe, 0x01234567, 0x89abcdef,
                              0x55aa55aa, 0x77889900, 0xabcdef12, 0x34567890};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  asm volatile("vlseg8e32.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg8e32.v v1, (%0)" ::"r"(ALIGNED_O32));
  VVCMP_U32(12, ALIGNED_O32, 0x9fe41920, 0x8f2e05e0, 0xf9aa71f0, 0xc394bbd3,
            0x12345678, 0x9abcdef0, 0x13572468, 0x369b48ac, 0xdeadbeef,
            0xcafebabe, 0x01234567, 0x89abcdef, 0x55aa55aa, 0x77889900,
            0xabcdef12, 0x34567890);
}

// Segment-2 for 64-bit
void TEST_CASE1_64(void) {
  VSET(4, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
      0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
      0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
      0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
      0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
      0x987654321fedcba0};
  VCLEAR(v1);
  VCLEAR(v2);
  asm volatile("vlseg2e64.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg2e64.v v1, (%0)" ::"r"(ALIGNED_O64));
  VVCMP_U64(13, ALIGNED_O64, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
            0x123456789abcdef0, 0x13572468369b48ac);
}

// Segment-3 for 64-bit
void TEST_CASE2_64(void) {
  VSET(4, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
      0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
      0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
      0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
      0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
      0x987654321fedcba0};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  asm volatile("vlseg3e64.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg3e64.v v1, (%0)" ::"r"(ALIGNED_O64));
  VVCMP_U64(14, ALIGNED_O64, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
            0x123456789abcdef0, 0x13572468369b48ac, 0xdeadbeefcafebabe,
            0x0123456789abcdef, 0x55aa55aa77889900, 0xabcdef1234567890);
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
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  asm volatile("vlseg4e64.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg4e64.v v1, (%0)" ::"r"(ALIGNED_O64));
  VVCMP_U64(15, ALIGNED_O64, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
            0x123456789abcdef0, 0x13572468369b48ac, 0xdeadbeefcafebabe,
            0x0123456789abcdef, 0x55aa55aa77889900, 0xabcdef1234567890,
            0xfeedfacecafebabe, 0x123456789abcdef0, 0x1357246855aa55aa,
            0x369b48acdeadbeef, 0xcafebabe12345678, 0xabcdef0987654321,
            0x012345670abcdef1, 0x987654321fedcba0);
}

// Segment-8 for 64-bit
void TEST_CASE4_64(void) {
  VSET(2, e64, m1);
  volatile uint64_t INP1[] = {
      0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0x123456789abcdef0,
      0x13572468369b48ac, 0xdeadbeefcafebabe, 0x0123456789abcdef,
      0x55aa55aa77889900, 0xabcdef1234567890, 0xfeedfacecafebabe,
      0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
      0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
      0x987654321fedcba0};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  asm volatile("vlseg8e64.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg8e64.v v1, (%0)" ::"r"(ALIGNED_O64));
  VVCMP_U64(16, ALIGNED_O64, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3,
            0x123456789abcdef0, 0x13572468369b48ac, 0xdeadbeefcafebabe,
            0x0123456789abcdef, 0x55aa55aa77889900, 0xabcdef1234567890,
            0xfeedfacecafebabe, 0x123456789abcdef0, 0x1357246855aa55aa,
            0x369b48acdeadbeef, 0xcafebabe12345678, 0xabcdef0987654321,
            0x012345670abcdef1, 0x987654321fedcba0);
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

  VCLEAR(v0);
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VCLEAR(v4);
  VCLEAR(v5);
  VCLEAR(v6);
  VCLEAR(v7);
  VCLEAR(v8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vlseg8e64.v v1, (%0)" ::"r"(INP1));
  asm volatile("vsseg8e64.v v1, (%0), v0.t" ::"r"(ALIGNED_O64));
  VVCMP_U64(17, ALIGNED_O64, 0, 0, 0, 0, 0, 0, 0, 0, 0xfeedfacecafebabe,
            0x123456789abcdef0, 0x1357246855aa55aa, 0x369b48acdeadbeef,
            0xcafebabe12345678, 0xabcdef0987654321, 0x012345670abcdef1,
            0x987654321fedcba0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1_8();
  MEM_VCLEAR(ALIGNED_O8);
  TEST_CASE2_8();
  MEM_VCLEAR(ALIGNED_O8);
  TEST_CASE3_8();
  MEM_VCLEAR(ALIGNED_O8);
  TEST_CASE4_8();
  MEM_VCLEAR(ALIGNED_O8);

  TEST_CASE1_16();
  MEM_VCLEAR(ALIGNED_O16);
  TEST_CASE2_16();
  MEM_VCLEAR(ALIGNED_O16);
  TEST_CASE3_16();
  MEM_VCLEAR(ALIGNED_O16);
  TEST_CASE4_16();
  MEM_VCLEAR(ALIGNED_O16);

  TEST_CASE1_32();
  MEM_VCLEAR(ALIGNED_O32);
  TEST_CASE2_32();
  MEM_VCLEAR(ALIGNED_O32);
  TEST_CASE3_32();
  MEM_VCLEAR(ALIGNED_O32);
  TEST_CASE4_32();
  MEM_VCLEAR(ALIGNED_O32);

  TEST_CASE1_64();
  MEM_VCLEAR(ALIGNED_O64);
  TEST_CASE2_64();
  MEM_VCLEAR(ALIGNED_O64);
  TEST_CASE3_64();
  MEM_VCLEAR(ALIGNED_O64);
  TEST_CASE4_64();
  MEM_VCLEAR(ALIGNED_O64);

  TEST_CASE4_64_m();
  MEM_VCLEAR(ALIGNED_O64);

  EXIT_CHECK();
}
