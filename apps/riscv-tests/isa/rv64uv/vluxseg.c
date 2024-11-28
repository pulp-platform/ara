// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"

// Segment-2
void TEST_CASE1_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  VCLEAR(v1);
  VCLEAR(v2);
  VLOAD_8(v24, 1, 1, 0, 2);
  asm volatile("vluxseg2ei8.v v1, (%0), v24" ::"r"(INP1));
  VCMP_U8(1, v1, 0xe4, 0xe4, 0x9f, 0x19);
  VCMP_U8(2, v2, 0x19, 0x19, 0xe4, 0x20);
}

// Segment-3
void TEST_CASE2_8(void) {
  VSET(4, e8, m1);
  volatile uint8_t INP1[] = {0x9f, 0xe4, 0x19, 0x20, 0x8f, 0x2e, 0x05, 0xe0,
                             0xf9, 0xaa, 0x71, 0xf0, 0xc3, 0x94, 0xbb, 0xd3};
  VCLEAR(v1);
  VCLEAR(v2);
  VCLEAR(v3);
  VLOAD_16(v24, 0, 1, 0, 3);
  asm volatile("vluxseg3ei16.v v1, (%0), v24" ::"r"(INP1));
  VCMP_U8(3, v1, 0x9f, 0xe4, 0x9f, 0x20);
  VCMP_U8(4, v2, 0xe4, 0x19, 0xe4, 0x8f);
  VCMP_U8(5, v3, 0x19, 0x20, 0x19, 0x2e);
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
  VLOAD_64(v24, 1, 1, 0, 5);
  asm volatile("vluxseg4ei64.v v1, (%0), v24" ::"r"(INP1));
  VCMP_U8(6, v1, 0xe4, 0xe4, 0x9f, 0x2e);
  VCMP_U8(7, v2, 0x19, 0x19, 0xe4, 0x05);
  VCMP_U8(8, v3, 0x20, 0x20, 0x19, 0xe0);
  VCMP_U8(9, v4, 0x8f, 0x8f, 0x20, 0xf9);
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
  VLOAD_8(v24, 8, 8, 0, 40);
  asm volatile("vluxseg4ei8.v v1, (%0), v24" ::"r"(INP1));
  VCMP_U64(10, v1, 0xf9aa71f0c394bbd3, 0xf9aa71f0c394bbd3, 0x9fe419208f2e05e0,
           0x0123456789abcdef);
  VCMP_U64(11, v2, 0x123456789abcdef0, 0x123456789abcdef0, 0xf9aa71f0c394bbd3,
           0x55aa55aa77889900);
  VCMP_U64(12, v3, 0x13572468369b48ac, 0x13572468369b48ac, 0x123456789abcdef0,
           0xabcdef1234567890);
  VCMP_U64(13, v4, 0xdeadbeefcafebabe, 0xdeadbeefcafebabe, 0x13572468369b48ac,
           0xfeedfacecafebabe);
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
  asm volatile("vluxseg8ei8.v v1, (%0), v24, v0.t" ::"r"(INP1));
  VCMP_U64(14, v1, 0, 0xdeadbeefcafebabe);
  VCMP_U64(15, v2, 0, 0x0123456789abcdef);
  VCMP_U64(16, v3, 0, 0x55aa55aa77889900);
  VCMP_U64(17, v4, 0, 0xabcdef1234567890);
  VCMP_U64(18, v5, 0, 0xfeedfacecafebabe);
  VCMP_U64(19, v6, 0, 0x123456789abcdef0);
  VCMP_U64(20, v7, 0, 0x1357246855aa55aa);
  VCMP_U64(21, v8, 0, 0x369b48acdeadbeef);

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
  asm volatile("vluxseg8ei32.v v1, (%0), v24, v0.t" ::"r"(INP1));
  VCMP_U64(22, v1, 0xf9aa71f0c394bbd3, 0);
  VCMP_U64(23, v2, 0x123456789abcdef0, 0);
  VCMP_U64(24, v3, 0x13572468369b48ac, 0);
  VCMP_U64(25, v4, 0xdeadbeefcafebabe, 0);
  VCMP_U64(26, v5, 0x0123456789abcdef, 0);
  VCMP_U64(27, v6, 0x55aa55aa77889900, 0);
  VCMP_U64(28, v7, 0xabcdef1234567890, 0);
  VCMP_U64(29, v8, 0xfeedfacecafebabe, 0);
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
