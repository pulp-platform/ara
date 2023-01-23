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

#include "imatmul.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))

void imatmul(int64_t *c, const int64_t *a, const int64_t *b,
             const unsigned long int M, const unsigned long int N,
             const unsigned long int P) {
  if (M <= 4) {
    imatmul_4x4(c, a, b, M, N, P);
  } else if (M <= 128) {
    imatmul_8x8(c, a, b, M, N, P);
  } else {
    // Vector length is 64 elements. With an 4x4 matmul,
    // we can use LMUL=4, having a vl of 256.
    imatmul_4x4(c, a, b, M, N, P);
  }
}

// ---------------
// 4x4
// ---------------

void imatmul_4x4(int64_t *c, const int64_t *a, const int64_t *b,
                 const unsigned long int M, const unsigned long int N,
                 const unsigned long int P) {
  // We work on 4 rows of the matrix at once
  const unsigned long int block_size = 4;
  unsigned long int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int64_t *b_ = b + p;
    int64_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int64_t *a_ = a + m * N;
      int64_t *c__ = c_ + m * P;

      imatmul_vec_4x4_slice_init();
      imatmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void imatmul_vec_4x4_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v12, 0");
}

void imatmul_vec_4x4(int64_t *c, const int64_t *a, const int64_t *b,
                     const unsigned long int N, const unsigned long int P) {
  // Temporary variables
  int64_t t0, t1, t2, t3;

  // Original pointer
  const int64_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle64.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  t0 = *a, a += N;
  t1 = *a, a += N;
  t2 = *a, a += N;
  t3 = *a;

  // Compute the multiplication
  unsigned long int n = 0;

  while (n < N) {
#ifdef VCD_DUMP
    // Start dumping VCD
    if (n == 8)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 12)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t1));
    t1 = *a, a += N;
    asm volatile("vmacc.vx v8, %0, v16" ::"r"(t2));
    t2 = *a, a += N;
    asm volatile("vmacc.vx v12, %0, v16" ::"r"(t3));
    t3 = *a;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
    t1 = *a, a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
    t2 = *a, a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
    t3 = *a;
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

void imatmul_8x8(int64_t *c, const int64_t *a, const int64_t *b,
                 const unsigned long int M, const unsigned long int N,
                 const unsigned long int P) {
  // We work on 4 rows of the matrix at once
  const unsigned long int block_size = 8;
  unsigned long int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m2, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int64_t *b_ = b + p;
    int64_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int64_t *a_ = a + m * N;
      int64_t *c__ = c_ + m * P;

      imatmul_vec_8x8_slice_init();
      imatmul_vec_8x8(c__, a_, b_, N, P);
    }
  }
}

void imatmul_vec_8x8_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v14, 0");
}

void imatmul_vec_8x8(int64_t *c, const int64_t *a, const int64_t *b,
                     const unsigned long int N, const unsigned long int P) {
  // Temporary variables
  int64_t t0, t1, t2, t3, t4, t5, t6, t7;

  // Original pointer
  const int64_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle64.v v18, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  t0 = *a, a += N;
  t1 = *a, a += N;
  t2 = *a, a += N;
  t3 = *a, a += N;
  t4 = *a, a += N;
  t5 = *a, a += N;
  t6 = *a, a += N;
  t7 = *a;

  // Compute the multiplication
  unsigned long int n = 0;

  while (n < N) {
#ifdef VCD_DUMP
    // Start dumping VCD
    if (n == 8)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 12)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v18" ::"r"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v18" ::"r"(t1));
    t1 = *a, a += N;
    asm volatile("vmacc.vx v4, %0, v18" ::"r"(t2));
    t2 = *a, a += N;
    asm volatile("vmacc.vx v6, %0, v18" ::"r"(t3));
    t3 = *a, a += N;
    asm volatile("vmacc.vx v8, %0, v18" ::"r"(t4));
    t4 = *a, a += N;
    asm volatile("vmacc.vx v10, %0, v18" ::"r"(t5));
    t5 = *a, a += N;
    asm volatile("vmacc.vx v12, %0, v18" ::"r"(t6));
    t6 = *a, a += N;
    asm volatile("vmacc.vx v14, %0, v18" ::"r"(t7));
    t7 = *a;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v18, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));
    t1 = *a, a += N;
    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t2));
    t2 = *a, a += N;
    asm volatile("vmacc.vx v6, %0, v20" ::"r"(t3));
    t3 = *a, a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t4));
    t4 = *a, a += N;
    asm volatile("vmacc.vx v10, %0, v20" ::"r"(t5));
    t5 = *a, a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t6));
    t6 = *a, a += N;
    asm volatile("vmacc.vx v14, %0, v20" ::"r"(t7));
    t7 = *a;
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
