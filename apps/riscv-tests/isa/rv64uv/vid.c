// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(16, e8, m1);
  __asm__ volatile("vid.v v1");
  VCMP_U8(1, v1, 0, 1, 2, 3, 4, 5, 6, 7);
  VSET(10, e8, m1);

  VLOAD_8(v1, 0b00001110, 0b00000111, 0b00010000, 0b01001011, 0b00110100,
          0b01111101, 0b11001100, 0b00011000, 0b01000111, 0b00010100);
  VSET(77, e8, m1);
  asm volatile("vid.v v2");
  VCMP_U8(2, v2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
          18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
          35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
          52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68,
          69, 70, 71, 72, 73, 74, 75, 76);
}

void TEST_CASE2() {
  VSET(16, e8, m1);
  VLOAD_8(v0, 85, 0, 0, 0, 0, 0, 0, 0);
  VCLEAR(v1);
  __asm__ volatile("vid.v v1, v0.t");
  VCMP_U8(3, v1, 0, 0, 2, 0, 4, 0, 6, 0);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
