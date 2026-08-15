// Copyright 2022 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "fdotproduct.h"

// 64-bit dot-product: a * b
double fdotp_v64b(const double *a, const double *b, size_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e64m8(avl);

  vfloat64m8_t acc, buf_a, buf_b;
  vfloat64m1_t red;

  double *a_ = (double *)a;
  double *b_ = (double *)b;

  // Clean the accumulator
  red = vfmv_s_f_f64m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e64m8(avl);
    // Load chunk a and b
    buf_a = vle64_v_f64m8(a_, vl);
    buf_b = vle64_v_f64m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vfmul_vv_f64m8(buf_a, buf_b, vl);
    } else {
      acc = vfmacc_vv_f64m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  red = vfredusum_vs_f64m8_f64m1(red, acc, red, vl);
  return vfmv_f_s_f64m1_f64(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

  double red;

  double *a_ = (double *)a;
  double *b_ = (double *)b;

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");

#ifdef VCD_DUMP
  // One stripmine iteration consumes VLMAX = LMUL * VLEN / SEW
  // = 8 * VLEN / 64 elements, i.e. 512 elements for VLEN = 4096.
  // The trigger below is checked at the top of the loop body, so the stop
  // condition needs one more iteration than its value to be reached: the
  // 8..24 window requires at least 25 iterations, i.e. avl >= 12800.
  int vcd_iter = 0;
#endif

  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
#ifdef VCD_DUMP
    // Start dumping VCD (skip the prologue)
    if (vcd_iter == 8)
      *(volatile int64_t *)&event_trigger = +1;
    // Stop dumping VCD, after 16 steady-state iterations (8..23)
    if (vcd_iter == 24)
      *(volatile int64_t *)&event_trigger = -1;
    vcd_iter++;
#endif
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));
    // Load chunk a and b
    asm volatile("vle64.v v8,  (%0)" ::"r"(a_));
    asm volatile("vle64.v v16, (%0)" ::"r"(b_));
    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vfmul.vv v24, v8, v16");
    } else {
      asm volatile("vfmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vfredusum.vs v0, v24, v0");
  asm volatile("vfmv.f.s %0, v0" : "=f"(red));

  // // VCD dump does not include reduction, so we also need to measure the utilization roofline without reduction
  // asm volatile("vfmv.f.s %0, v24" : "=f"(red));

  return red;

#endif
}

// 64-bit dot-product: a * b
// m8 allows only for partial register re-allocation with factor-2 unrolling
double fdotp_v64b_m8_unrl(const double *a, const double *b, unsigned int avl) {
  const unsigned int orig_avl = avl;
  unsigned int vl;

  double red;

#ifdef VCD_DUMP
  int vcd_iter = 0;
#endif

  // Stripmine and accumulate a partial reduced vector
  do {
#ifdef VCD_DUMP
    // Three stages per iteration, so one iteration consumes 3 * VLMAX = 1536
    // elements for VLEN = 4096. The 3..8 window is 5 iterations = 7680 elements and requires avl >= 13824.
    if (vcd_iter == 3)
      *(volatile int64_t *)&event_trigger = +1;
    if (vcd_iter == 8)
      *(volatile int64_t *)&event_trigger = -1;
    vcd_iter++;
#endif
    // Set the vl
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

    // Load chunk a and b
    asm volatile("vle64.v v8,  (%0)" ::"r"(a));
    asm volatile("vle64.v v16, (%0)" ::"r"(b));

    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vfmul.vv v24, v8, v16");
    } else {
      asm volatile("vfmacc.vv v24, v8, v16");
    }

    // Bump pointers
    a += vl;
    b += vl;
    avl -= vl;

    if (avl <= 0)
      break;

    // Set the vl
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

    // Load chunk a and b
    asm volatile("vle64.v v0, (%0)" ::"r"(a));
    asm volatile("vle64.v v8, (%0)" ::"r"(b));

    // Multiply and accumulate
    asm volatile("vfmacc.vv v24, v0, v8");

    // Bump pointers
    a += vl;
    b += vl;
    avl -= vl;

    if (avl <= 0)
      break;

    // Set the vl
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

    // Load chunk a and b
    asm volatile("vle64.v v16, (%0)" ::"r"(a));
    asm volatile("vle64.v v0, (%0)" ::"r"(b));

    // Multiply and accumulate
    asm volatile("vfmacc.vv v24, v0, v16");

    // Bump pointers
    a += vl;
    b += vl;
    avl -= vl;
  } while (avl > 0);

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");

  // // Reduce and return
  // asm volatile("vfredusum.vs v0, v24, v0");
  // asm volatile("vfmv.f.s %0, v0" : "=f"(red));

  // VCD dump does not include reduction, so we also need to measure the utilization roofline without reduction
  asm volatile("vfmv.f.s %0, v24" : "=f"(red));

  return red;
}


// 32-bit dot-product: a * b
float fdotp_v32b(const float *a, const float *b, size_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e32m8(avl);

  vfloat32m8_t acc, buf_a, buf_b;
  vfloat32m1_t red;

  float *a_ = (float *)a;
  float *b_ = (float *)b;

  // Clean the accumulator
  red = vfmv_s_f_f32m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e32m8(avl);
    // Load chunk a and b
    buf_a = vle32_v_f32m8(a_, vl);
    buf_b = vle32_v_f32m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vfmul_vv_f32m8(buf_a, buf_b, vl);
    } else {
      acc = vfmacc_vv_f32m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  red = vfredusum_vs_f32m8_f32m1(red, acc, red, vl);
  return vfmv_f_s_f32m1_f32(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));

  float red;

  float *a_ = (float *)a;
  float *b_ = (float *)b;

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    // Load chunk a and b
    asm volatile("vle32.v v8,  (%0)" ::"r"(a_));
    asm volatile("vle32.v v16, (%0)" ::"r"(b_));
    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vfmul.vv v24, v8, v16");
    } else {
      asm volatile("vfmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vfredusum.vs v0, v24, v0");
  asm volatile("vfmv.f.s %0, v0" : "=f"(red));
  return red;

#endif
}

// 16-bit dot-product: a * b
_Float16 fdotp_v16b(const _Float16 *a, const _Float16 *b, size_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e16m8(avl);

  vfloat16m8_t acc, buf_a, buf_b;
  vfloat16m1_t red;

  _Float16 *a_ = (_Float16 *)a;
  _Float16 *b_ = (_Float16 *)b;

  // Clean the accumulator
  red = vfmv_s_f_f16m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e16m8(avl);
    // Load chunk a and b
    buf_a = vle16_v_f16m8(a_, vl);
    buf_b = vle16_v_f16m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vfmul_vv_f16m8(buf_a, buf_b, vl);
    } else {
      acc = vfmacc_vv_f16m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and store
  red = vfredusum_vs_f16m8_f16m1(red, acc, red, vl);
  return vfmv_f_s_f16m1_f16(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(vl) : "r"(avl));

  _Float16 red;

  _Float16 *a_ = (_Float16 *)a;
  _Float16 *b_ = (_Float16 *)b;

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(vl) : "r"(avl));
    // Load chunk a and b
    asm volatile("vle16.v v8,  (%0)" ::"r"(a_));
    asm volatile("vle16.v v16, (%0)" ::"r"(b_));
    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vfmul.vv v24, v8, v16");
    } else {
      asm volatile("vfmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vfredusum.vs v0, v24, v0");
  asm volatile("vfmv.f.s %0, v0" : "=f"(red));
  return red;

#endif
}

double fdotp_s64b(const double *a, const double *b, size_t avl) {
  double acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;

  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += a[i + 0] * b[i + 0];
    acc1 += a[i + 1] * b[i + 1];
    acc2 += a[i + 2] * b[i + 2];
    acc3 += a[i + 3] * b[i + 3];
    acc4 += a[i + 4] * b[i + 4];
    acc5 += a[i + 5] * b[i + 5];
    acc6 += a[i + 6] * b[i + 6];
    acc7 += a[i + 7] * b[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;

  return acc0;
}

float fdotp_s32b(const float *a, const float *b, size_t avl) {
  float acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;

  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += a[i + 0] * b[i + 0];
    acc1 += a[i + 1] * b[i + 1];
    acc2 += a[i + 2] * b[i + 2];
    acc3 += a[i + 3] * b[i + 3];
    acc4 += a[i + 4] * b[i + 4];
    acc5 += a[i + 5] * b[i + 5];
    acc6 += a[i + 6] * b[i + 6];
    acc7 += a[i + 7] * b[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;

  return acc0;
}

_Float16 fdotp_s16b(const _Float16 *a, const _Float16 *b, size_t avl) {
  _Float16 acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;

  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += a[i + 0] * b[i + 0];
    acc1 += a[i + 1] * b[i + 1];
    acc2 += a[i + 2] * b[i + 2];
    acc3 += a[i + 3] * b[i + 3];
    acc4 += a[i + 4] * b[i + 4];
    acc5 += a[i + 5] * b[i + 5];
    acc6 += a[i + 6] * b[i + 6];
    acc7 += a[i + 7] * b[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;

  return acc0;
}
