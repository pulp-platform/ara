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
  BOX_HALF_IN_DOUBLE(scalar_16b, 0xbb1e);
  VSET(16, e16, m1);
  VLOAD_16(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_16b));
  VCMP_U16(1, v1, *((uint16_t *)&scalar_16b));

  scalar_32b = 0xbe9451b0;
  VSET(16, e32, m1);
  VLOAD_32(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_32b));
  VCMP_U32(2, v1, *((uint32_t *)&scalar_32b));

  scalar_64b = 0xbfe8d9d3f67536d2;
  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_64b));
  VCMP_U64(3, v1, *((uint64_t *)&scalar_64b));
}

// Check special cases
void TEST_CASE2() {
  scalar_64b = 0xbfe8d9d3f67536d2;
  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET(16, e64, m8);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_64b));
  VSET(1, e64, m1);
  VCMP_U64(4, v1, *((uint64_t *)&scalar_64b));

  scalar_64b = 0xbfe8d9d3f67536d2;
  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET_ZERO(e64, m1);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_64b));
  VSET(1, e64, m1);
  VCMP_U64(5, v1, 1);

  scalar_64b = 0xbfe8d9d3f67536d2;
  VSET(16, e64, m1);
  VLOAD_64(v1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8);
  VSET_ZERO(e64, m8);
  asm volatile("vfmv.s.f v1, %0" ::"f"(scalar_64b));
  VSET(1, e64, m1);
  VCMP_U64(6, v1, 1);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
