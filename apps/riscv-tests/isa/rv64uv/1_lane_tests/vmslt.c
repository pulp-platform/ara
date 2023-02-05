// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_16(v6, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VCLEAR(v2);
  asm volatile("vmslt.vv v2, v4, v6");
  VSET(2, e8, m1);
  VCMP_U8(1, v2, 0xAA, 0xAA);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v12, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VCLEAR(v4);
  asm volatile("vmslt.vv v4, v8, v12");
  VSET(2, e8, m1);
  VCMP_U8(2, v4, 0xAA, 0xAA);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v24, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VCLEAR(v8);
  asm volatile("vmslt.vv v8, v16, v24");
  VSET(2, e8, m8);
  VCMP_U8(3, v8, 0xAA, 0xAA);
};

void TEST_CASE2(void) {
  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_16(v6, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v2);
  asm volatile("vmslt.vv v2, v4, v6, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(4, v2, 0x88, 0x88);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v12, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v4);
  asm volatile("vmslt.vv v4, v8, v12, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(5, v4, 0x88, 0x88);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v24, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400,
           19901, 50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v8);
  asm volatile("vmslt.vv v8, v16, v24, v0.t");
  VSET(2, e8, m8);
  VCMP_U8(6, v8, 0x88, 0x88);
};

void TEST_CASE3(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8,
          -25, 99);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(7, v1, 0x66, 0x66);

  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v2);
  asm volatile("vmslt.vx v2, v4, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(8, v2, 0x66, 0x66);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v4);
  asm volatile("vmslt.vx v4, v8, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(9, v4, 0x66, 0x66);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v8);
  asm volatile("vmslt.vx v8, v16, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m8);
  VCMP_U8(10, v8, 0x66, 0x66);
};

void TEST_CASE4(void) {
  const uint64_t scalar = 40;

  VSET(16, e8, m1);
  VLOAD_8(v2, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8, -25, 99, 123, -8,
          -25, 99);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(11, v1, 0x44, 0x44);

  VSET(16, e16, m2);
  VLOAD_16(v4, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v2);
  asm volatile("vmslt.vx v2, v4, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(12, v2, 0x44, 0x44);

  VSET(16, e32, m4);
  VLOAD_32(v8, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v4);
  asm volatile("vmslt.vx v4, v8, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(13, v4, 0x44, 0x44);

  VSET(16, e64, m8);
  VLOAD_64(v16, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v8);
  asm volatile("vmslt.vx v8, v16, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m8);
  VCMP_U8(14, v8, 0x44, 0x44);
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
