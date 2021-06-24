// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

void TEST_CASE1() {
  double dscalar_16;
  //                            -0.9380
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);

  VSET(32, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_16(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1down.vf v1, v2, %[A]" ::[A] "f"(dscalar_16));
  VCMP_U16(1, v1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 0xbb81);

  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);

  VSET(32, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_32(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1down.vf v1, v2, %[A]" ::[A] "f"(dscalar_32));
  VCMP_U32(2, v1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
           0xbf75e762);

  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);

  VSET(32, e64, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e64, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_64(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1down.vf v1, v2, %[A]" ::[A] "f"(dscalar_64));
  VCMP_U64(3, v1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
           0x3fed25da5d7296fe);
}

void TEST_CASE2() {
  double dscalar_16;
  //                            -0.9380
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);

  VSET(32, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e16, m1);
  VLOAD_16(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_16(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0x55, 0x55);
  asm volatile("vfslide1down.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_16));
  VCMP_U16(6, v1, 2, -1, 4, -1, 6, -1, 8, -1, 10, -1, 12, -1, 14, -1, 16, -1);

  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);

  VSET(32, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e32, m1);
  VLOAD_32(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_32(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfslide1down.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_32));
  VCMP_U32(7, v1, -1, 3, -1, 5, -1, 7, -1, 9, -1, 11, -1, 13, -1, 15, -1,
           0xbf75e762);

  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);

  VSET(32, e64, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32);
  VSET(16, e64, m1);
  VLOAD_64(v2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_64(v1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0x55, 0x55);
  asm volatile("vfslide1down.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_64));
  VCMP_U64(8, v1, 2, -1, 4, -1, 6, -1, 8, -1, 10, -1, 12, -1, 14, -1, 16, -1);
}

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
