// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_16(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  asm volatile("vmax.vv v1, v2, v3");
  VCMP_I16(1, v1, 12345, 7000, 2560, 19901, 12345, 7000, 2560, 19901, 12345,
           7000, 2560, 19901, 12345, 7000, 2560, 19901);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  asm volatile("vmax.vv v1, v2, v3");
  VCMP_I32(2, v1, 12345, 7000, 2560, 19901, 12345, 7000, 2560, 19901, 12345,
           7000, 2560, 19901, 12345, 7000, 2560, 19901);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  asm volatile("vmax.vv v1, v2, v3");
  VCMP_I64(3, v1, 12345, 7000, 2560, 19901, 12345, 7000, 2560, 19901, 12345,
           7000, 2560, 19901, 12345, 7000, 2560, 19901);
};

void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_16(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_16(v1, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef,
           0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef);
  asm volatile("vmax.vv v1, v2, v3, v0.t");
  VCMP_I16(4, v1, 0xbeef, 0xbeef, 2560, 19901, 0xbeef, 0xbeef, 2560, 19901,
           0xbeef, 0xbeef, 2560, 19901, 0xbeef, 0xbeef, 2560, 19901);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_32(v1, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef);
  asm volatile("vmax.vv v1, v2, v3, v0.t");
  VCMP_I32(5, v1, 0xdeadbeef, 0xdeadbeef, 2560, 19901, 0xdeadbeef, 0xdeadbeef,
           2560, 19901, 0xdeadbeef, 0xdeadbeef, 2560, 19901, 0xdeadbeef,
           0xdeadbeef, 2560, 19901);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_64(v1, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef);
  asm volatile("vmax.vv v1, v2, v3, v0.t");
  VCMP_I64(6, v1, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 2560, 19901,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 2560, 19901,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 2560, 19901,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 2560, 19901);
};

void TEST_CASE3(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8,
          -25, 99);
  asm volatile("vmax.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_I8(7, v1, 123, 40, 40, 99, 123, 40, 40, 99, 123, 40, 40, 99, 123, 40, 40,
          99);

  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  asm volatile("vmax.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_I16(8, v1, 12345, 40, 40, 199, 12345, 40, 40, 199, 12345, 40, 40, 199,
           12345, 40, 40, 199);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  asm volatile("vmax.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_I32(9, v1, 12345, 40, 40, 199, 12345, 40, 40, 199, 12345, 40, 40, 199,
           12345, 40, 40, 199);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  asm volatile("vmax.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_I64(10, v1, 12345, 40, 40, 199, 12345, 40, 40, 199, 12345, 40, 40, 199,
           12345, 40, 40, 199);
};

void TEST_CASE4(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8,
          -25, 99);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_8(v1, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef,
          0xef, 0xef, 0xef, 0xef, 0xef);
  asm volatile("vmax.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_I8(11, v1, 0xef, 0xef, 40, 99, 0xef, 0xef, 40, 99, 0xef, 0xef, 40, 99,
          0xef, 0xef, 40, 99);

  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_16(v1, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef,
           0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef);
  asm volatile("vmax.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_I16(12, v1, 0xbeef, 0xbeef, 40, 199, 0xbeef, 0xbeef, 40, 199, 0xbeef,
           0xbeef, 40, 199, 0xbeef, 0xbeef, 40, 199);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_32(v1, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef);
  asm volatile("vmax.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_I32(13, v1, 0xdeadbeef, 0xdeadbeef, 40, 199, 0xdeadbeef, 0xdeadbeef, 40,
           199, 0xdeadbeef, 0xdeadbeef, 40, 199, 0xdeadbeef, 0xdeadbeef, 40,
           199);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_64(v1, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef);
  asm volatile("vmax.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_I64(14, v1, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 40, 199,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 40, 199, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 40, 199, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           40, 199);
};

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  EXIT_CHECK();
}
