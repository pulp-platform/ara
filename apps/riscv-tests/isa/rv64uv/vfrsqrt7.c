// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>
//         Shafiullah Khan <shafi.ullah@10xengineers.ai>

#include "float_macros.h"
#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, mInfh, pInfh, qNaNh, sNaNh, pZero, mZeroh, 0x3a12, 0x0001,
           0x3af7, 0x00fe, 0x01e6, 0x75e6, 0x80fe, 0x35fd, 0x20a7, 0x7bc0);
  asm volatile("vfrsqrt7.v v1, v2");
  VCMP_U16(1, v1, qNaNh, pZero, qNaNh, qNaNh, pInfh, mInfh, 0x3c98, 0x6bf8,
           0x3c48, 0x5c00, 0x59d0, 0x1e98, qNaNh, 0x3e90, 0x4940, 0x1c10);
  VSET(16, e32, m1);
  VLOAD_32(v2, mInff, pInff, qNaNf, 0xfe7fca13, 0x00800000, 0x00200000,
           0x003f3cde, 0x00400000, 0x7f787a12, 0x7f000005, 0x7ef0f42d,
           0x7f765432, 0x00718abc, 0x00e50000, 0x001ee941, 0x00000001);
  asm volatile("vfrsqrt7.v v1, v2");
  VCMP_U32(2, v1, qNaNf, pZero, qNaNf, qNaNf, 0x5eff0000, 0x5f7f0000,
           0x5f360000, 0x5f340000, 0x1f820000, 0x1fb40000, 0x1fbb0000,
           0x1f820000, 0x5f080000, 0x5ebf0000, 0x5f820000, 0x64b40000);
  VSET(16, e64, m1);
  VLOAD_64(v2, mInfd, pInfd, qNaNd, sNaNd, pZero, mZerod, 0xffee384e0c3fbf7c,
           0x00060000005e7fcf, 0x000bffffd07b5869, 0x7fbfffff9bfec946,
           0x7fdc709c2bde6967, 0x000347ea91db7acb, 0x7fd5600000000000,
           0x000000000000001, 0x000000000000ded, 0x7fdc000000006967);
  asm volatile("vfrsqrt7.v v1, v2");
  VCMP_U64(3, v1, qNaNd, pZero, qNaNd, qNaNd, pInfd, mInfd, qNaNd,
           0x5fea000000000000, 0x5fe2800000000000, 0x2006a00000000000,
           0x1ff8000000000000, 0x5ff1c00000000000, 0x1ffba00000000000,
           0x617fe00000000000, 0x6121200000000000, 0x1ff8200000000000);
};
// Exceptions check
void TEST_CASE2(void) {
  // Invalid operation
  CLEAR_FFLAGS;
  VSET(16, e16, m1);
  CHECK_FFLAGS(0);
  VLOAD_16(v2, mInfh, sNaNh, 0xba12, 0x8001, 0xbaf7, 0x80fe, 0x81e6, 0xf5e6,
           0x80ff, 0xb5fd, 0xa0a7, 0xfbc0, mInfh, sNaNh, mInfh, sNaNh);
  asm volatile("vfrsqrt7.v v1, v2");
  VCMP_U16(4, v1, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh,
           qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh, qNaNh);
  CHECK_FFLAGS(NV);

  // Divide by zero
  CLEAR_FFLAGS;
  VSET(16, e32, m1);
  CHECK_FFLAGS(0);
  VLOAD_32(v2, pZero, mZerof, pZero, mZerof, pZero, mZerof, pZero, mZerof,
           pZero, mZerof, pZero, mZerof, pZero, mZerof, pZero, mZerof);
  asm volatile("vfrsqrt7.v v1, v2");
  VCMP_U32(5, v1, pInff, mInff, pInff, mInff, pInff, mInff, pInff, mInff, pInff,
           mInff, pInff, mInff, pInff, mInff, pInff, mInff);
  CHECK_FFLAGS(DZ);
};

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
