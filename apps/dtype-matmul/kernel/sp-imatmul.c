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

#include "sp-imatmul.h"

// Verify the matrix
int sp_imatmul_verify(int32_t *result, int32_t *gold, size_t R, size_t C) {
  for (uint64_t i = 0; i < R; ++i) {
    for (uint64_t j = 0; j < C; ++j) {
      uint64_t idx = i * C + j;
      if (result[idx] != gold[idx]) {
        return (i + j) == 0 ? -1 : idx;
      }
    }
  }
  return 0;
}

void sp_imatmul(int32_t *c, const int32_t *a, const int32_t *b,
                const unsigned int M, const unsigned int N,
                const unsigned int P) {
  if (M <= 4) {
    sp_imatmul_4x4(c, a, b, M, N, P);
  } else if (M <= 8) {
    sp_imatmul_8x8(c, a, b, M, N, P);
  } else if (M <= 64) {
    sp_imatmul_16x16(c, a, b, M, N, P);
  } else if (M <= 128) {
    // Vector length is 64 elements. With an 8x8 sp_imatmul,
    // we can use LMUL=2, having a vl of 128.
    sp_imatmul_8x8(c, a, b, M, N, P);
  } else {
    // Vector length is 64 elements. With an 4x4 sp_imatmul,
    // we can use LMUL=4, having a vl of 256.
    sp_imatmul_4x4(c, a, b, M, N, P);
  }
}

// ---------------
// 4x4
// ---------------

void sp_imatmul_4x4(int32_t *c, const int32_t *a, const int32_t *b,
                    const unsigned int M, const unsigned int N,
                    const unsigned int P) {
  // We work on 4 rows of the matrix at once
  unsigned int block_size = 4;
  unsigned int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    unsigned int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int32_t *b_ = b + p;
    int32_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e32, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int32_t *a_ = a + m * N;
      int32_t *c__ = c_ + m * P;

      sp_imatmul_vec_4x4_slice_init();
      sp_imatmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void sp_imatmul_vec_4x4_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v12, 0");
}

void sp_imatmul_vec_4x4(int32_t *c, const int32_t *a, const int32_t *b,
                        const unsigned int N, const unsigned int P) {
  // Temporary variables
  int64_t t0, t1, t2, t3;

  // Original pointer
  const int32_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle32.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));

  // Compute the multiplication
  unsigned int n = 0;

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
    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v16" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v16" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
  asm volatile("vse32.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v4, %0, v20" ::"r"(t1));
  asm volatile("vse32.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v8, %0, v20" ::"r"(t2));
  asm volatile("vse32.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v12, %0, v20" ::"r"(t3));
  asm volatile("vse32.v v12, (%0);" ::"r"(c));
}

// ---------------
// 8x8
// ---------------

void sp_imatmul_8x8(int32_t *c, const int32_t *a, const int32_t *b,
                    const unsigned int M, const unsigned int N,
                    const unsigned int P) {
  // We work on 4 rows of the matrix at once
  unsigned int block_size = 8;
  unsigned int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    unsigned int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int32_t *b_ = b + p;
    int32_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e32, m2, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int32_t *a_ = a + m * N;
      int32_t *c__ = c_ + m * P;

      sp_imatmul_vec_8x8_slice_init();
      sp_imatmul_vec_8x8(c__, a_, b_, N, P);
    }
  }
}

void sp_imatmul_vec_8x8_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v14, 0");
}

void sp_imatmul_vec_8x8(int32_t *c, const int32_t *a, const int32_t *b,
                        const unsigned int N, const unsigned int P) {
  // Temporary variables
  uint64_t t0, t1, t2, t3, t4, t5, t6, t7;

  // Original pointer
  const int32_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle32.v v18, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));

  // Compute the multiplication
  unsigned int n = 0;

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
    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v18" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v18" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v18" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v18" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v18" ::"r"(t4));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v18" ::"r"(t5));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v18" ::"r"(t6));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v18" ::"r"(t7));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v18, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v20" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v20" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v20" ::"r"(t4));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v20" ::"r"(t5));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v20" ::"r"(t6));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v20" ::"r"(t7));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));
  asm volatile("vse32.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));
  asm volatile("vse32.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v4, %0, v20" ::"r"(t2));
  asm volatile("vse32.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v6, %0, v20" ::"r"(t3));
  asm volatile("vse32.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v8, %0, v20" ::"r"(t4));
  asm volatile("vse32.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v10, %0, v20" ::"r"(t5));
  asm volatile("vse32.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v12, %0, v20" ::"r"(t6));
  asm volatile("vse32.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v14, %0, v20" ::"r"(t7));
  asm volatile("vse32.v v14, (%0);" ::"r"(c));
}

// ---------------
// 16x16
// ---------------

void sp_imatmul_16x16(int32_t *c, const int32_t *a, const int32_t *b,
                      const unsigned int M, const unsigned int N,
                      const unsigned int P) {
  // We work on 4 rows of the matrix at once
  const unsigned int block_size = 16;
  unsigned int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const int32_t *b_ = b + p;
    int32_t *c_ = c + p;

    asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int32_t *a_ = a + m * N;
      int32_t *c__ = c_ + m * P;

      sp_imatmul_vec_16x16_slice_init();
      sp_imatmul_vec_16x16(c__, a_, b_, N, P);
    }
  }
}

void sp_imatmul_vec_16x16_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v1,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v3,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v5,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v7,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v9,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v11, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v13, 0");
  asm volatile("vmv.v.i v14, 0");
  asm volatile("vmv.v.i v15, 0");
}

void sp_imatmul_vec_16x16(int32_t *c, const int32_t *a, const int32_t *b,
                          const unsigned int N, const unsigned int P) {
  // Temporary variables
  int32_t t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15;

  // Original pointer
  const int32_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle32.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t8) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t9) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t10) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t11) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t12) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t13) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t14) : [a] "r"(a));
  a += N;
  asm volatile("lwu %[t], (%[a])" : [t] "=r"(t15) : [a] "r"(a));

  // Compute the multiplication
  unsigned int n = 0;

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
    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v17, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v1, %0, v16" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v2, %0, v16" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v3, %0, v16" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t4));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v5, %0, v16" ::"r"(t5));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v16" ::"r"(t6));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v7, %0, v16" ::"r"(t7));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v16" ::"r"(t8));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t8) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v9, %0, v16" ::"r"(t9));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t9) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v16" ::"r"(t10));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t10) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v11, %0, v16" ::"r"(t11));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t11) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v16" ::"r"(t12));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t12) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v13, %0, v16" ::"r"(t13));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t13) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v16" ::"r"(t14));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t14) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v15, %0, v16" ::"r"(t15));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t15) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const int32_t *)a_ + ++n;

    asm volatile("vmacc.vx v0, %0, v17" ::"r"(t0));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vmacc.vx v1, %0, v17" ::"r"(t1));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v2, %0, v17" ::"r"(t2));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v3, %0, v17" ::"r"(t3));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v4, %0, v17" ::"r"(t4));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v5, %0, v17" ::"r"(t5));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v6, %0, v17" ::"r"(t6));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v7, %0, v17" ::"r"(t7));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t7) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v8, %0, v17" ::"r"(t8));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t8) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v9, %0, v17" ::"r"(t9));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t9) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v10, %0, v17" ::"r"(t10));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t10) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v11, %0, v17" ::"r"(t11));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t11) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v12, %0, v17" ::"r"(t12));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t12) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v13, %0, v17" ::"r"(t13));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t13) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v14, %0, v17" ::"r"(t14));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t14) : [a] "r"(a));
    a += N;
    asm volatile("vmacc.vx v15, %0, v17" ::"r"(t15));
    asm volatile("lwu %[t], (%[a])" : [t] "=r"(t15) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vmacc.vx v0, %0, v17" ::"r"(t0));
  asm volatile("vse32.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v1, %0, v17" ::"r"(t1));
  asm volatile("vse32.v v1, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v2, %0, v17" ::"r"(t2));
  asm volatile("vse32.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v3, %0, v17" ::"r"(t3));
  asm volatile("vse32.v v3, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v4, %0, v17" ::"r"(t4));
  asm volatile("vse32.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v5, %0, v17" ::"r"(t5));
  asm volatile("vse32.v v5, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v6, %0, v17" ::"r"(t6));
  asm volatile("vse32.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v7, %0, v17" ::"r"(t7));
  asm volatile("vse32.v v7, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v8, %0, v17" ::"r"(t8));
  asm volatile("vse32.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v9, %0, v17" ::"r"(t9));
  asm volatile("vse32.v v9, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v10, %0, v17" ::"r"(t10));
  asm volatile("vse32.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v11, %0, v17" ::"r"(t11));
  asm volatile("vse32.v v11, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v12, %0, v17" ::"r"(t12));
  asm volatile("vse32.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v13, %0, v17" ::"r"(t13));
  asm volatile("vse32.v v13, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v14, %0, v17" ::"r"(t14));
  asm volatile("vse32.v v14, (%0);" ::"r"(c));
  c += P;
  asm volatile("vmacc.vx v15, %0, v17" ::"r"(t15));
  asm volatile("vse32.v v15, (%0);" ::"r"(c));
}
