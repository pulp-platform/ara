// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

double scalar_16b;
float scalar_32b;
double scalar_64b;

void TEST_CASE1() {
  BOX_HALF_IN_DOUBLE(scalar_16b, 0);
  VSET(16, e16, m1);
  VLOAD_16(v1, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_16b));
  XCMP(1, *((uint16_t *)&scalar_16b), 0xbb1e);

  scalar_32b = 0;
  VSET(16, e32, m1);
  VLOAD_32(v1, 0xbe9451b0, 0x3ece4bf7, 0x3eadc098, 0x3f09f4f0, 0x3ecc80cc,
           0xbe8a42c5, 0x3f47fd31, 0xbe201365, 0xbeffeb17, 0xbf314e2e,
           0xbd0a9c78, 0xbf1fb51f, 0x3b5e1209, 0x3eac9a73, 0xbeb187b6,
           0x3dea828d);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_32b));
  XCMP(2, *((uint32_t *)&scalar_32b), 0xbe9451b0);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(3, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);
}

// Check special cases
void TEST_CASE2() {
  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET(16, e64, m8);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(4, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET_ZERO(e64, m1);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(5, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);

  scalar_64b = 0;
  VSET(16, e64, m1);
  VLOAD_64(v1, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VSET_ZERO(e64, m8);
  asm volatile("vfmv.f.s %0, v1" : "=f"(scalar_64b));
  XCMP(6, *((uint64_t *)&scalar_64b), 0xbfe8d9d3f67536d2);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
