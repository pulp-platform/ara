// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vvm v3, v1, v2, v0");
  VCMP_U8(1, v3, 1, 7, 3, 5, 5, 3, 7, 1, 8, 2, 6, 4, 4, 6, 2, 8);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vvm v3, v1, v2, v0");
  VCMP_U16(2, v3, 1, 7, 3, 5, 5, 3, 7, 1, 8, 2, 6, 4, 4, 6, 2, 8);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vvm v3, v1, v2, v0");
  VCMP_U32(3, v3, 1, 7, 3, 5, 5, 3, 7, 1, 8, 2, 6, 4, 4, 6, 2, 8);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vvm v3, v1, v2, v0");
  VCMP_U64(4, v3, 1, 7, 3, 5, 5, 3, 7, 1, 8, 2, 6, 4, 4, 6, 2, 8);
}

void TEST_CASE2() {
  const uint64_t scalar = 0x00000000deadbeef;

  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U8(5, v3, 1, 0xef, 3, 0xef, 5, 0xef, 7, 0xef, 0xef, 2, 0xef, 4, 0xef, 6,
          0xef, 8);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U16(6, v3, 1, 0xbeef, 3, 0xbeef, 5, 0xbeef, 7, 0xbeef, 0xbeef, 2, 0xbeef,
           4, 0xbeef, 6, 0xbeef, 8);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U32(7, v3, 1, 0xdeadbeef, 3, 0xdeadbeef, 5, 0xdeadbeef, 7, 0xdeadbeef,
           0xdeadbeef, 2, 0xdeadbeef, 4, 0xdeadbeef, 6, 0xdeadbeef, 8);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U64(8, v3, 1, 0x00000000deadbeef, 3, 0x00000000deadbeef, 5,
           0x00000000deadbeef, 7, 0x00000000deadbeef, 0x00000000deadbeef, 2,
           0x00000000deadbeef, 4, 0x00000000deadbeef, 6, 0x00000000deadbeef, 8);
}

void TEST_CASE3() {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vim v3, v1, -1, v0");
  VCMP_U8(9, v3, 1, 0xff, 3, 0xff, 5, 0xff, 7, 0xff, 0xff, 2, 0xff, 4, 0xff, 6,
          0xff, 8);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vim v3, v1, -1, v0");
  VCMP_U16(10, v3, 1, 0xffff, 3, 0xffff, 5, 0xffff, 7, 0xffff, 0xffff, 2,
           0xffff, 4, 0xffff, 6, 0xffff, 8);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vim v3, v1, -1, v0");
  VCMP_U32(11, v3, 1, 0xffffffff, 3, 0xffffffff, 5, 0xffffffff, 7, 0xffffffff,
           0xffffffff, 2, 0xffffffff, 4, 0xffffffff, 6, 0xffffffff, 8);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0x55);
  asm volatile("vmerge.vim v3, v1, -1, v0");
  VCMP_U64(12, v3, 1, 0xffffffffffffffff, 3, 0xffffffffffffffff, 5,
           0xffffffffffffffff, 7, 0xffffffffffffffff, 0xffffffffffffffff, 2,
           0xffffffffffffffff, 4, 0xffffffffffffffff, 6, 0xffffffffffffffff, 8);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();

  EXIT_CHECK();
}
