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

// Author: Matheus Cavalcante, ETH Zurich
//         Samuel Riedel, ETH Zurich

#include "matmul.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))

void matmul(int64_t *c, const int64_t *a, const int64_t *b, int64_t M,
            int64_t N, int64_t P) {
  if (M <= 4) {
    matmul_4x4(c, a, b, M, N, P);
  } else {
    matmul_8x8(c, a, b, M, N, P);
  }
}

// ---------------
// 4x4
// ---------------

void matmul_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t M,
                int64_t N, int64_t P) {
  // We work on 4 rows of the matrix at once
  int64_t block_size = 4;
  int64_t block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (int64_t p = 0; p < P; p += block_size_p) {
    // Set the vector length
    int64_t p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int64_t *b_ = b + p;
    int64_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (int64_t m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int64_t *a_ = a + m * N;
      int64_t *c__ = c_ + m * P;

      matmul_vec_4x4_slice_init();
      matmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void matmul_vec_4x4_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v12, 0");
}

void matmul_vec_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t N,
                    int64_t P) {
  // Temporary variables
  int64_t t0, t1, t2, t3;

  // Original pointer
  const int64_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle64.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));

  // Compute the multiplication
  int64_t n = 0;

  while (n < N) {
    // Calculate pointer to the matrix A
    a = (const int64_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t1));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v16" ::"r"(t2));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v16" ::"r"(t3));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));

    if (n == N - 1)
      break;

    a = (const int64_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
  asm volatile("vse64.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
  asm volatile("vse64.v v12, (%0);" ::"r"(c));
}

// ---------------
// 8x8
// ---------------

void matmul_8x8(int64_t *c, const int64_t *a, const int64_t *b, int64_t M,
                int64_t N, int64_t P) {
  // We work on 4 rows of the matrix at once
  int64_t block_size = 8;
  int64_t block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m2, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (int64_t p = 0; p < P; p += block_size_p) {
    // Set the vector length
    int64_t p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int64_t *b_ = b + p;
    int64_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (int64_t m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int64_t *a_ = a + m * N;
      int64_t *c__ = c_ + m * P;

      matmul_vec_8x8_slice_init();
      matmul_vec_8x8(c__, a_, b_, N, P);
    }
  }
}

void matmul_vec_8x8_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v14, 0");
}

void matmul_vec_8x8(int64_t *c, const int64_t *a, const int64_t *b, int64_t N,
                    int64_t P) {
  // Temporary variables
  int64_t t0, t1, t2, t3, t4, t5, t6, t7;

  // Original pointer
  const int64_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle64.v v18, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t4) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t5) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t6) : [ a ] "r"(a));
  a += N;
  asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t7) : [ a ] "r"(a));

  // Compute the multiplication
  int64_t n = 0;

  while (n < N) {
    // Calculate pointer to the matrix A
    a = (const int64_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v18" ::"r"(t0));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v18" ::"r"(t1));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v18" ::"r"(t2));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v18" ::"r"(t3));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v18" ::"r"(t4));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t4) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v18" ::"r"(t5));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t5) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v18" ::"r"(t6));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t6) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v18" ::"r"(t7));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t7) : [ a ] "r"(a));

    if (n == N - 1)
      break;

    a = (const int64_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t0) : [ a ] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle64.v v18, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t1) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t2));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t2) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v20" ::"r"(t3));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t3) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t4));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t4) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v20" ::"r"(t5));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t5) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t6));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t6) : [ a ] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v20" ::"r"(t7));
    asm volatile("ld %[t], (%[a])" : [ t ] "=r"(t7) : [ a ] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));
  asm volatile("vse64.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v4, %0, v20" ::"r"(t2));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v6, %0, v20" ::"r"(t3));
  asm volatile("vse64.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v8, %0, v20" ::"r"(t4));
  asm volatile("vse64.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v10, %0, v20" ::"r"(t5));
  asm volatile("vse64.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v12, %0, v20" ::"r"(t6));
  asm volatile("vse64.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v14, %0, v20" ::"r"(t7));
  asm volatile("vse64.v v14, (%0);" ::"r"(c));
}
