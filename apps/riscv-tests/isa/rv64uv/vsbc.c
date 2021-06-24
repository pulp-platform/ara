// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v2, 8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vvm v3, v1, v2, v0");
  VCMP_U8(1, v3, -7, -6, -3, -2, 1, 2, 5, 6, 0, -1, 0, -1, 0, -1, 0, -1);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_16(v2, 8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vvm v3, v1, v2, v0");
  VCMP_U16(2, v3, -7, -6, -3, -2, 1, 2, 5, 6, 0, -1, 0, -1, 0, -1, 0, -1);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_32(v2, 8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vvm v3, v1, v2, v0");
  VCMP_U32(3, v3, -7, -6, -3, -2, 1, 2, 5, 6, 0, -1, 0, -1, 0, -1, 0, -1);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_64(v2, 8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vvm v3, v1, v2, v0");
  VCMP_U64(4, v3, -7, -6, -3, -2, 1, 2, 5, 6, 0, -1, 0, -1, 0, -1, 0, -1);
};

void TEST_CASE2(void) {
  const uint32_t scalar = 5;

  VSET(16, e8, m1);
  VLOAD_8(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U8(5, v3, -4, -4, -2, -2, 0, 0, 2, 2, -4, -4, -2, -2, 0, 0, 2, 2);

  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U16(6, v3, -4, -4, -2, -2, 0, 0, 2, 2, -4, -4, -2, -2, 0, 0, 2, 2);

  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U32(7, v3, -4, -4, -2, -2, 0, 0, 2, 2, -4, -4, -2, -2, 0, 0, 2, 2);

  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vsbc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VCMP_U64(8, v3, -4, -4, -2, -2, 0, 0, 2, 2, -4, -4, -2, -2, 0, 0, 2, 2);
};

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
