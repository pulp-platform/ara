// Copyright 2020 ETH Zurich and University of Bologna.
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

#include "dotproduct.h"

int64_t dotp_v64b(int64_t *a, int64_t *b, uint64_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e64m8(avl);

  vint64m8_t acc, buf_a, buf_b;
  vint64m1_t red;

  int64_t *a_ = (int64_t *)a;
  int64_t *b_ = (int64_t *)b;

  // Clean the accumulator
  red = vmv_s_x_i64m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e64m8(avl);
    // Load chunk a and b
    buf_a = vle64_v_i64m8(a_, vl);
    buf_b = vle64_v_i64m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vmul_vv_i64m8(buf_a, buf_b, vl);
    } else {
      acc = vmacc_vv_i64m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  red = vredsum_vs_i64m8_i64m1(red, acc, red, vl);
  return vmv_x_s_i64m1_i64(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

  int64_t red;

  int64_t *a_ = (int64_t *)a;
  int64_t *b_ = (int64_t *)b;

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));
    // Load chunk a and b
    asm volatile("vle64.v v8,  (%0)" ::"r"(a_));
    asm volatile("vle64.v v16, (%0)" ::"r"(b_));
    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vmul.vv v24, v8, v16");
    } else {
      asm volatile("vmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;

#endif
}

int32_t dotp_v32b(int32_t *a, int32_t *b, uint64_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e32m8(avl);

  vint32m8_t acc, buf_a, buf_b;
  vint32m1_t red;

  int32_t *a_ = (int32_t *)a;
  int32_t *b_ = (int32_t *)b;

  // Clean the accumulator
  red = vmv_s_x_i32m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e32m8(avl);
    // Load chunk a and b
    buf_a = vle32_v_i32m8(a_, vl);
    buf_b = vle32_v_i32m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vmul_vv_i32m8(buf_a, buf_b, vl);
    } else {
      acc = vmacc_vv_i32m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  red = vredsum_vs_i32m8_i32m1(red, acc, red, vl);
  return vmv_x_s_i32m1_i32(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));

  int32_t red;

  int32_t *a_ = (int32_t *)a;
  int32_t *b_ = (int32_t *)b;

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
      asm volatile("vmul.vv v24, v8, v16");
    } else {
      asm volatile("vmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;

#endif
}

int16_t dotp_v16b(int16_t *a, int16_t *b, uint64_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e16m8(avl);

  vint16m8_t acc, buf_a, buf_b;
  vint16m1_t red;

  int16_t *a_ = (int16_t *)a;
  int16_t *b_ = (int16_t *)b;

  // Clean the accumulator
  red = vmv_s_x_i16m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e16m8(avl);
    // Load chunk a and b
    buf_a = vle16_v_i16m8(a_, vl);
    buf_b = vle16_v_i16m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vmul_vv_i16m8(buf_a, buf_b, vl);
    } else {
      acc = vmacc_vv_i16m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and store
  red = vredsum_vs_i16m8_i16m1(red, acc, red, vl);
  return vmv_x_s_i16m1_i16(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(vl) : "r"(avl));

  int16_t red;

  int16_t *a_ = (int16_t *)a;
  int16_t *b_ = (int16_t *)b;

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
      asm volatile("vmul.vv v24, v8, v16");
    } else {
      asm volatile("vmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;

#endif
}

int8_t dotp_v8b(int8_t *a, int8_t *b, uint64_t avl) {
#ifdef INTRINSICS

  size_t orig_avl = avl;
  size_t vl = vsetvl_e8m8(avl);

  vint8m8_t acc, buf_a, buf_b;
  vint8m1_t red;

  int8_t *a_ = (int8_t *)a;
  int8_t *b_ = (int8_t *)b;

  // Clean the accumulator
  red = vmv_s_x_i8m1(red, 0, vl);
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    vl = vsetvl_e8m8(avl);
    // Load chunk a and b
    buf_a = vle8_v_i8m8(a_, vl);
    buf_b = vle8_v_i8m8(b_, vl);
    // Multiply and accumulate
    if (avl == orig_avl) {
      acc = vmul_vv_i8m8(buf_a, buf_b, vl);
    } else {
      acc = vmacc_vv_i8m8(acc, buf_a, buf_b, vl);
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and store
  red = vredsum_vs_i8m8_i8m1(red, acc, red, vl);
  return vmv_x_s_i8m1_i8(red);

#else

  size_t orig_avl = avl;
  size_t vl;
  asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(vl) : "r"(avl));

  int8_t red;

  int8_t *a_ = (int8_t *)a;
  int8_t *b_ = (int8_t *)b;

  // Clean the accumulator
  asm volatile("vmv.s.x v0, zero");
  // Stripmine and accumulate a partial reduced vector
  for (; avl > 0; avl -= vl) {
    asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(vl) : "r"(avl));
    // Load chunk a and b
    asm volatile("vle8.v v8,  (%0)" ::"r"(a_));
    asm volatile("vle8.v v16, (%0)" ::"r"(b_));
    // Multiply and accumulate
    if (avl == orig_avl) {
      asm volatile("vmul.vv v24, v8, v16");
    } else {
      asm volatile("vmacc.vv v24, v8, v16");
    }
    // Bump pointers
    a_ += vl;
    b_ += vl;
  }

  // Reduce and return
  asm volatile("vredsum.vs v0, v24, v0");
  asm volatile("vmv.x.s %0, v0" : "=r"(red));
  return red;

#endif
}

int64_t dotp_s64b(int64_t *a, int64_t *b, uint64_t avl) {
  int64_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

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

int32_t dotp_s32b(int32_t *a, int32_t *b, uint64_t avl) {
  int32_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

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

int16_t dotp_s16b(int16_t *a, int16_t *b, uint64_t avl) {
  int16_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

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

int8_t dotp_s8b(int8_t *a, int8_t *b, uint64_t avl) {
  int8_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

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
