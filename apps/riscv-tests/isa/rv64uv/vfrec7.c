// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//y
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

void TEST_CASE1(void) {

 VSET(16, e16, m1);
  VLOAD_16(v2, mInfh, pInfh, qNaNh, sNaNh,
               pZero, mZeroh, 0xba72,0x3a12,
               0x3af7, 0x00fe,0x01e6,0x75e6,
               0x80fe,0xb5fd, 0xb4e7, 0x7bc0);
  asm volatile("vfrec7.v v1, v2");
  VCMP_U16(1, v1,mZeroh,pZero,qNaNh,qNaNh,
              pInfh,mInfh, 0xbcf8,0x3d40,
              0x3c98,pInfh,0x7838,0x02b8,
              mInfh,0xc158,0xc288,0x0108);

  VSET(16, e32, m1);
  VLOAD_32(v2, mInff, pInff, qNaNf, sNaNf,
               pZero, mZerof,0xfe7fca13,0x00800000,
                 0x807ee93e, 0x803ee93e,0x00200000,0x00400000,
                 0x00800000, 0xff787a12,0xff000005,0x800dd27e);
  asm volatile("vfrec7.v v1, v2");
  VCMP_U32(2, v1,mZerof,pZero,qNaNf,qNaNf,
                pInff,mInff,0x80800000,0x7e7f0000,
                0xfe810000,0xff020000,0x7f7f0000,0x7eff0000,
                0x7e7f0000,0x80210000,0x803fc000,mInff);
  VSET(16, e64, m1);
  VLOAD_64(v2, mInfd, pInfd, qNaNd, sNaNd,
              pZero, mZerod,0xffee384e0c3fbf7c,0xffdfa4dc68d2ae1a,
              0xffcf49b8d1aa1fda,0x800f47ea9ea8e436,0x800747ea961ff344,0x00060000005e7fcf,
              0x000bffffd07b5869,0x7fbfffff9bfec946,0x7fdc709c2bde6967,0x000347ea91db7acb);
  asm volatile("vfrec7.v v1, v2");
  VCMP_U64(3, v1,mZerod,pZero,qNaNd,qNaNd,
              pInfd,mInfd,0x8004400000000000,0x8008100000000000,
              0x8010600000000000,0xffd0c00000000000, 0xffe1a00000000000,0x7fe5400000000000,
              0x7fd5600000000000,0x0020000000000000,0x0009000000000000, pInfd);


};

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();

  EXIT_CHECK();


}
