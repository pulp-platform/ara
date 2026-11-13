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
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(1, v1, 0xAA, 0xAA);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(2, v1, 0xAA, 0xAA);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3");
  VSET(2, e8, m1);
  VCMP_U8(3, v1, 0xAA, 0xAA);
};

void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_16(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(4, v1, 0x88, 0x88);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_32(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(5, v1, 0x88, 0x88);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -80, 2560, -19900, 12345, -80, 2560, -19900, 12345, -80,
           2560, -19900, 12345, -80, 2560, -19900);
  VLOAD_64(v3, 50, 7000, 400, 19901, 50, 7000, 400, 19901, 50, 7000, 400, 19901,
           50, 7000, 400, 19901);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vv v1, v2, v3, v0.t");
  VSET(2, e8, m1);
  VCMP_U8(6, v1, 0x88, 0x88);
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

  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(8, v1, 0x66, 0x66);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(9, v1, 0x66, 0x66);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A]" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(10, v1, 0x66, 0x66);
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

  VSET(16, e16, m1);
  VLOAD_16(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(12, v1, 0x44, 0x44);

  VSET(16, e32, m1);
  VLOAD_32(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(13, v1, 0x44, 0x44);

  VSET(16, e64, m1);
  VLOAD_64(v2, 12345, -8, -25, 199, 12345, -8, -25, 199, 12345, -8, -25, 199,
           12345, -8, -25, 199);
  VLOAD_8(v0, 0xCC, 0xCC);
  VCLEAR(v1);
  asm volatile("vmslt.vx v1, v2, %[A], v0.t" ::[A] "r"(scalar));
  VSET(2, e8, m1);
  VCMP_U8(14, v1, 0x44, 0x44);
};

// Exercise the legitimate MaskB users before any scalar-move overlap.
void TEST_CASE5(void) {
  static const uint32_t source[4] __attribute__((aligned(16))) = {
      11, 22, 33, 44};
  static const uint32_t fma_a[3] __attribute__((aligned(16))) = {
      0x40000000, 0x40000000, 0x40000000}; // 2.0f
  static const uint32_t fma_b[3] __attribute__((aligned(16))) = {
      0x40400000, 0x40400000, 0x40400000}; // 3.0f
  static const uint32_t fma_old[3] __attribute__((aligned(16))) = {
      0x3f800000, 0x3f800000, 0x3f800000}; // 1.0f
  static const uint8_t compare_mask = 6;
  static const uint8_t old_mask = 5;
  static const uint8_t all_selected = 7;
  volatile uint32_t stored[3] __attribute__((aligned(16)));
  volatile uint8_t mask_out = 0xff;

  // With no scalar move, the inactive low bit must come from the old vd.
  asm volatile(
      "vsetivli zero, 3, e32, m1, tu, mu\n\t"
      "vle32.v v2, (%[source])\n\t"
      "vlm.v v0, (%[mask])\n\t"
      "vlm.v v10, (%[old])\n\t"
      "csrr t2, vl\n\t"
      "vmslt.vx v10, v2, zero, v0.t\n\t"
      "csrr t2, vl\n\t"
      "vsm.v v10, (%[out])\n\t"
      "fence\n\t"
      :
      : [source] "r"(source), [mask] "r"(&compare_mask),
        [old] "r"(&old_mask), [out] "r"(&mask_out)
      : "t2", "v0", "v2", "v10", "memory");
  XCMP(15, (mask_out & 7), 1);

  // A masked FMA reads its old vd through the MFPU, rather than MaskB.
  asm volatile(
      "vsetivli zero, 3, e32, m1, tu, mu\n\t"
      "vle32.v v2, (%[a])\n\t"
      "vle32.v v4, (%[b])\n\t"
      "vle32.v v8, (%[old])\n\t"
      "vlm.v v0, (%[mask])\n\t"
      "csrr t2, vl\n\t"
      "vfmacc.vv v8, v2, v4, v0.t\n\t"
      "csrr t2, vl\n\t"
      "vse32.v v8, (%[out])\n\t"
      "fence\n\t"
      :
      : [a] "r"(fma_a), [b] "r"(fma_b), [old] "r"(fma_old),
        [mask] "r"(&old_mask), [out] "r"(stored)
      : "t2", "v0", "v2", "v4", "v8", "memory");
  XCMP(16, stored[0], 0x40e00000);
  XCMP(17, stored[1], 0x3f800000);
  XCMP(18, stored[2], 0x40e00000);

  // CSR reads wait for Ara to become idle on this baseline. In particular,
  // the gather source is fully written before its ad-hoc reads can start.
  asm volatile(
      "vsetivli zero, 3, e32, m1, tu, mu\n\t"
      "vle32.v v2, (%[source])\n\t"
      "csrr t2, vl\n\t"
      "vrgather.vx v8, v2, zero\n\t"
      "csrr t2, vl\n\t"
      "vse32.v v8, (%[out])\n\t"
      "fence\n\t"
      :
      : [source] "r"(source), [out] "r"(stored)
      : "t2", "v2", "v8", "memory");
  XCMP(19, stored[0], 11);
  XCMP(20, stored[1], 11);
  XCMP(21, stored[2], 11);

  // Keep the last input selected: compress termination is a separate issue.
  asm volatile(
      "vsetivli zero, 3, e32, m1, tu, mu\n\t"
      "vle32.v v2, (%[source])\n\t"
      "vlm.v v6, (%[mask])\n\t"
      "csrr t2, vl\n\t"
      "vcompress.vm v8, v2, v6\n\t"
      "csrr t2, vl\n\t"
      "vse32.v v8, (%[out])\n\t"
      "fence\n\t"
      :
      : [source] "r"(source), [mask] "r"(&all_selected), [out] "r"(stored)
      : "t2", "v2", "v6", "v8", "memory");
  XCMP(22, stored[0], 11);
  XCMP(23, stored[1], 22);
  XCMP(24, stored[2], 33);
}

// Each call first leaves a completed, legitimate old-vd MASKU instruction in
// the issue fields. The CSR waits make MASKU idle, but do not clear its spills.
static void check_scalar_maskb(int casenum, unsigned vl, int floating_point,
                               unsigned group, unsigned repeat) {
  static const uint32_t source[4] __attribute__((aligned(16))) = {
      11, 22, 33, 44};
  static const uint32_t scalar_source[4] __attribute__((aligned(16))) = {
      0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000};
  static const uint8_t old_mask = 5;
  const uint8_t mask = (1u << vl) - 2;
  const unsigned active_bits = (1u << vl) - 1;
  volatile uint8_t mask_out = 0xff;
  uint64_t scalar;

  if (floating_point) {
    asm volatile(
        "vsetvli zero, %[vl], e32, m1, tu, mu\n\t"
        "vle32.v v2, (%[source])\n\t"
        "vle32.v v14, (%[scalar_source])\n\t"
        "vlm.v v0, (%[mask])\n\t"
        "vlm.v v10, (%[old])\n\t"
        "csrr t2, vl\n\t"
        "vmslt.vx v10, v2, zero, v0.t\n\t"
        "csrr t2, vl\n\t"
        "vlm.v v10, (%[old])\n\t"
        "csrr t2, vl\n\t"
        "vfmv.f.s ft1, v14\n\t"
        "fmv.x.w t1, ft1\n\t"
        "mv %[scalar], t1\n\t"
        "csrr t2, vl\n\t"
        "vmslt.vx v10, v2, zero, v0.t\n\t"
        "csrr t2, vl\n\t"
        "vsm.v v10, (%[out])\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [vl] "r"((uint64_t)vl), [source] "r"(source),
          [scalar_source] "r"(scalar_source), [mask] "r"(&mask),
          [old] "r"(&old_mask), [out] "r"(&mask_out)
        : "t1", "t2", "ft1", "v0", "v2", "v10", "v14", "memory");
  } else {
    asm volatile(
        "vsetvli zero, %[vl], e32, m1, tu, mu\n\t"
        "vle32.v v2, (%[source])\n\t"
        "vle32.v v14, (%[scalar_source])\n\t"
        "vlm.v v0, (%[mask])\n\t"
        "vlm.v v10, (%[old])\n\t"
        "csrr t2, vl\n\t"
        "vmslt.vx v10, v2, zero, v0.t\n\t"
        "csrr t2, vl\n\t"
        "vlm.v v10, (%[old])\n\t"
        "csrr t2, vl\n\t"
        "vmv.x.s t1, v14\n\t"
        "mv %[scalar], t1\n\t"
        "csrr t2, vl\n\t"
        "vmslt.vx v10, v2, zero, v0.t\n\t"
        "csrr t2, vl\n\t"
        "vsm.v v10, (%[out])\n\t"
        "fence\n\t"
        : [scalar] "=&r"(scalar)
        : [vl] "r"((uint64_t)vl), [source] "r"(source),
          [scalar_source] "r"(scalar_source), [mask] "r"(&mask),
          [old] "r"(&old_mask), [out] "r"(&mask_out)
        : "t1", "t2", "v0", "v2", "v10", "v14", "memory");
  }
  printf("[MASKB_CASE] group=%u scalar=%s vl=%u round=%u got=%x expected=1 "
         "scalar_got=%lx scalar_expected=3f800000\n",
         group + 1, floating_point ? "fp" : "int", vl, repeat + 1,
         (mask_out & active_bits), (unsigned long)scalar);
  XCMP(casenum, (scalar == 0x3f800000), 1);
  XCMP(casenum + 1, (mask_out & active_bits), 1);
}

void TEST_CASE6(void) {
  static const unsigned lengths[3] = {3, 1, 4};
  unsigned completed = 0;
  for (unsigned repeat = 0; repeat < 2; repeat++) {
    for (int floating_point = 0; floating_point < 2; floating_point++) {
      for (unsigned i = 0; i < 3; i++) {
        const int group = (repeat * 2 + floating_point) * 3 + i;
        check_scalar_maskb(25 + 2 * group, lengths[i], floating_point,
                           group, repeat);
        completed++;
      }
    }
  }
  printf("[MASKB_DONE] completed=%u expected=12\n", completed);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();

  EXIT_CHECK();
}
