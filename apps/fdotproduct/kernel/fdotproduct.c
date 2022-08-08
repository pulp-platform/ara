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
}

// 32-bit dot-product: a * b
float fdotp_v32b(const float *a, const float *b, size_t avl) {

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
}

// 16-bit dot-product: a * b
_Float16 fdotp_v16b(const _Float16 *a, const _Float16 *b, size_t avl) {

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
