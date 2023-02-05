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

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_16(v2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1up.vf v2, v4, %[A]" ::[A] "f"(dscalar_16));
  VCMP_U16(1, v2, 0xbb81, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_32(v4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1up.vf v4, v8, %[A]" ::[A] "f"(dscalar_32));
  VCMP_U32(2, v4, 0xbf75e762, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
           15);

  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);

  VSET(16, e64, m8);
  VLOAD_64(v16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_64(v8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  asm volatile("vfslide1up.vf v8, v16, %[A]" ::[A] "f"(dscalar_64));
  VCMP_U64(3, v8, 0x3fed25da5d7296fe, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
           14, 15);
}

void TEST_CASE2() {
  double dscalar_16;
  //                            -0.9380
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);

  VSET(16, e16, m2);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_16(v2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0x55, 0x55);
  asm volatile("vfslide1up.vf v2, v4, %[A], v0.t" ::[A] "f"(dscalar_16));
  VCMP_U16(4, v2, 0xbb81, -1, 2, -1, 4, -1, 6, -1, 8, -1, 10, -1, 12, -1, 14,
           -1);

  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);

  VSET(16, e32, m4);
  VLOAD_32(v8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_32(v4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfslide1up.vf v4, v8, %[A], v0.t" ::[A] "f"(dscalar_32));
  VCMP_U32(5, v4, -1, 1, -1, 3, -1, 5, -1, 7, -1, 9, -1, 11, -1, 13, -1, 15);

  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);

  VSET(16, e64, m8);
  VLOAD_64(v16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_64(v8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  VLOAD_8(v0, 0x55, 0x55);
  asm volatile("vfslide1up.vf v8, v16, %[A], v0.t" ::[A] "f"(dscalar_64));
  VCMP_U64(6, v8, 0x3fed25da5d7296fe, -1, 2, -1, 4, -1, 6, -1, 8, -1, 10, -1,
           12, -1, 14, -1);
}

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
