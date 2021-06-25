// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  VLOAD_8(v2, 4, 8, 12, 0x80, 4, 8, 12, 0x80, 4, 8, 12, 0x80, 4, 8, 12, 0x80);
  VLOAD_8(v0, 0xDD, 0xDD);
  asm volatile("vmadc.vvm v3, v1, v2, v0");
  VSET(2, e8, m1);
  VCMP_U8(1, v3, 0xAA, 0xAA);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  VLOAD_16(v2, 4, 8, 12, 0x8000, 4, 8, 12, 0x8000, 4, 8, 12, 0x8000, 4, 8, 12,
           0x8000);
  VLOAD_8(v0, 0xDD, 0xDD);
  asm volatile("vmadc.vvm v3, v1, v2, v0");
  VSET(2, e8, m1);
  VCMP_U8(2, v3, 0xAA, 0xAA);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  VLOAD_32(v2, 4, 8, 12, 0x80000000, 4, 8, 12, 0x80000000, 4, 8, 12, 0x80000000,
           4, 8, 12, 0x80000000);
  VLOAD_8(v0, 0xDD, 0xDD);
  asm volatile("vmadc.vvm v3, v1, v2, v0");
  VSET(2, e8, m1);
  VCMP_U8(3, v3, 0xAA, 0xAA);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  VLOAD_64(v2, 4, 8, 12, 0x8000000000000000, 4, 8, 12, 0x8000000000000000, 4, 8,
           12, 0x8000000000000000, 4, 8, 12, 0x8000000000000000);
  VLOAD_8(v0, 0xDD, 0xDD);
  asm volatile("vmadc.vvm v3, v1, v2, v0");
  VSET(2, e8, m1);
  VCMP_U8(4, v3, 0xAA, 0xAA);
};

void TEST_CASE2(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  VLOAD_8(v2, 4, 8, 12, 0x80, 4, 8, 12, 0x80, 4, 8, 12, 0x80, 4, 8, 12, 0x80);
  asm volatile("vmadc.vv v3, v1, v2");
  VSET(2, e8, m1);
  VCMP_U8(5, v3, 0xAA, 0xAA);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  VLOAD_16(v2, 4, 8, 12, 0x8000, 4, 8, 12, 0x8000, 4, 8, 12, 0x8000, 4, 8, 12,
           0x8000);
  asm volatile("vmadc.vv v3, v1, v2");
  VSET(2, e8, m1);
  VCMP_U8(6, v3, 0xAA, 0xAA);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  VLOAD_32(v2, 4, 8, 12, 0x80000000, 4, 8, 12, 0x80000000, 4, 8, 12, 0x80000000,
           4, 8, 12, 0x80000000);
  asm volatile("vmadc.vv v3, v1, v2");
  VSET(2, e8, m1);
  VCMP_U8(7, v3, 0xAA, 0xAA);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  VLOAD_64(v2, 4, 8, 12, 0x8000000000000000, 4, 8, 12, 0x8000000000000000, 4, 8,
           12, 0x8000000000000000, 4, 8, 12, 0x8000000000000000);
  asm volatile("vmadc.vv v3, v1, v2");
  VSET(2, e8, m1);
  VCMP_U8(8, v3, 0xAA, 0xAA);
};

void TEST_CASE3(void) {
  const uint64_t scalar = 0x8000000080008080;

  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  VLOAD_8(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(9, v3, 0xAA, 0xAA);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  VLOAD_16(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(10, v3, 0xAA, 0xAA);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  VLOAD_32(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(11, v3, 0xAA, 0xAA);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  VLOAD_64(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vxm v3, v1, %[A], v0" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(12, v3, 0xAA, 0xAA);
};

void TEST_CASE4(void) {
  const uint64_t scalar = 0x8000000080008080;

  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  asm volatile("vmadc.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(13, v3, 0xAA, 0xAA);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  asm volatile("vmadc.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(14, v3, 0xAA, 0xAA);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  asm volatile("vmadc.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(15, v3, 0xAA, 0xAA);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  asm volatile("vmadc.vx v3, v1, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(16, v3, 0xAA, 0xAA);
};

void TEST_CASE5(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  VLOAD_8(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vim v3, v1, 10, v0");
  VSET(2, e8, m1);
  VCMP_U8(17, v3, 0x22, 0x22);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  VLOAD_16(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vim v3, v1, 10, v0");
  VSET(2, e8, m1);
  VCMP_U8(18, v3, 0x22, 0x22);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  VLOAD_32(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vim v3, v1, 10, v0");
  VSET(2, e8, m1);
  VCMP_U8(19, v3, 0x22, 0x22);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  VLOAD_64(v0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1);
  asm volatile("vmadc.vim v3, v1, 10, v0");
  VSET(2, e8, m1);
  VCMP_U8(20, v3, 0x22, 0x22);
};

void TEST_CASE6(void) {
  VSET(16, e8, m1);
  VLOAD_8(v1, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff, 8, 0x81, 16, 0xff,
          8, 0x81);
  asm volatile("vmadc.vi v3, v1, 10");
  VSET(2, e8, m1);
  VCMP_U8(21, v3, 0x22, 0x22);

  VSET(16, e16, m1);
  VLOAD_16(v1, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8, 0x8001, 16, 0xffff, 8,
           0x8001, 16, 0xffff, 8, 0x8001);
  asm volatile("vmadc.vi v3, v1, 10");
  VSET(2, e8, m1);
  VCMP_U8(22, v3, 0x22, 0x22);

  VSET(16, e32, m1);
  VLOAD_32(v1, 16, 0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001, 16,
           0xffffffff, 8, 0x80000001, 16, 0xffffffff, 8, 0x80000001);
  asm volatile("vmadc.vi v3, v1, 10");
  VSET(2, e8, m1);
  VCMP_U8(23, v3, 0x22, 0x22);

  VSET(16, e64, m1);
  VLOAD_64(v1, 16, 0xffffffffffffffff, 8, 0x8000000000000001, 16,
           0xffffffffffffffff, 8, 0x8000000000000001, 16, 0xffffffffffffffff, 8,
           0x8000000000000001, 16, 0xffffffffffffffff, 8, 0x8000000000000001);
  asm volatile("vmadc.vi v3, v1, 10");
  VSET(2, e8, m1);
  VCMP_U8(24, v3, 0x22, 0x22);
};

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();

  EXIT_CHECK();
}
