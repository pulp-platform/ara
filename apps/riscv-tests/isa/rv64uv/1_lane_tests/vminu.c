// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_16(v6, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  asm volatile("vminu.vv v2, v4, v6");
  VCMP_U16(1, v2, 50, 80, 400, 19900, 50, 80, 400, 19900, 50, 80, 400, 19900,
           50, 80, 400, 19900);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_32(v12, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  asm volatile("vminu.vv v4, v8, v12");
  VCMP_U32(2, v4, 50, 80, 400, 19900, 50, 80, 400, 19900, 50, 80, 400, 19900,
           50, 80, 400, 19900);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_64(v24, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  asm volatile("vminu.vv v8, v16, v24");
  VCMP_U64(3, v8, 50, 80, 400, 19900, 50, 80, 400, 19900, 50, 80, 400, 19900,
           50, 80, 400, 19900);
};

void TEST_CASE2(void) {
  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_16(v6, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_16(v2, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef,
           0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef);
  asm volatile("vminu.vv v2, v4, v6, v0.t");
  VCMP_U16(4, v2, 0xbeef, 0xbeef, 400, 19900, 0xbeef, 0xbeef, 400, 19900,
           0xbeef, 0xbeef, 400, 19900, 0xbeef, 0xbeef, 400, 19900);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_32(v12, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_32(v4, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef);
  asm volatile("vminu.vv v4, v8, v12, v0.t");
  VCMP_U32(5, v4, 0xdeadbeef, 0xdeadbeef, 400, 19900, 0xdeadbeef, 0xdeadbeef,
           400, 19900, 0xdeadbeef, 0xdeadbeef, 400, 19900, 0xdeadbeef,
           0xdeadbeef, 400, 19900);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, 80, 2560, 19900, 12345, 80, 2560, 19900, 12345, 80, 2560,
           19900, 12345, 80, 2560, 19900);
  VLOAD_64(v24, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_64(v8, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef);
  asm volatile("vminu.vv v8, v16, v24, v0.t");
  VCMP_U64(6, v8, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 400, 19900,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 400, 19900,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 400, 19900,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 400, 19900);
};

void TEST_CASE3(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, 8, 25, 199, 123, 8, 25, 199, 123, 8, 25, 199, 123, 8, 25,
          199);
  asm volatile("vminu.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VCMP_U8(7, v1, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40);

  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  asm volatile("vminu.vx v2, v4, %[A]" ::[A] "r"(scalar));
  VCMP_U16(8, v2, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  asm volatile("vminu.vx v4, v8, %[A]" ::[A] "r"(scalar));
  VCMP_U32(9, v4, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  asm volatile("vminu.vx v8, v16, %[A]" ::[A] "r"(scalar));
  VCMP_U64(10, v8, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40, 40, 8, 25, 40);
};

void TEST_CASE4(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, 8, 25, 199, 123, 8, 25, 199, 123, 8, 25, 199, 123, 8, 25,
          199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_8(v1, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef, 0xef,
          0xef, 0xef, 0xef, 0xef, 0xef);
  asm volatile("vminu.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U8(11, v1, 0xef, 0xef, 25, 40, 0xef, 0xef, 25, 40, 0xef, 0xef, 25, 40,
          0xef, 0xef, 25, 40);

  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_16(v2, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef,
           0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef, 0xbeef);
  asm volatile("vminu.vx v2, v4, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U16(12, v2, 0xbeef, 0xbeef, 25, 40, 0xbeef, 0xbeef, 25, 40, 0xbeef,
           0xbeef, 25, 40, 0xbeef, 0xbeef, 25, 40);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_32(v4, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef,
           0xdeadbeef);
  asm volatile("vminu.vx v4, v8, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U32(13, v4, 0xdeadbeef, 0xdeadbeef, 25, 40, 0xdeadbeef, 0xdeadbeef, 25,
           40, 0xdeadbeef, 0xdeadbeef, 25, 40, 0xdeadbeef, 0xdeadbeef, 25, 40);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345, 8, 25, 199, 12345,
           8, 25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VLOAD_64(v8, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef);
  asm volatile("vminu.vx v8, v16, %[A], v0.t" ::[A] "r"(scalar));
  VCMP_U64(14, v8, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 25, 40,
           0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef, 25, 40, 0xdeadbeefdeadbeef,
           0xdeadbeefdeadbeef, 25, 40, 0xdeadbeefdeadbeef, 0xdeadbeefdeadbeef,
           25, 40);
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
