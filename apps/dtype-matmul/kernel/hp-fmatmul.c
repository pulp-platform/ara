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

#include "hp-fmatmul.h"

// Verify the matrix
int hp_fmatmul_verify(_Float16 *result, _Float16 *gold, size_t R, size_t C,
                      _Float16 threshold) {
  for (uint64_t i = 0; i < R; ++i) {
    for (uint64_t j = 0; j < C; ++j) {
      uint64_t idx = i * C + j;
      if (!similarity_check(result[idx], gold[idx], threshold)) {
        return (i + j) == 0 ? -1 : idx;
      }
    }
  }
  return 0;
}

void hp_fmatmul(_Float16 *c, const _Float16 *a, const _Float16 *b,
                const unsigned int M, const unsigned int N,
                const unsigned int P) {
  if (M <= 4) {
    hp_fmatmul_4x4(c, a, b, M, N, P);
  } else if (M <= 8) {
    hp_fmatmul_8x8(c, a, b, M, N, P);
  } else if (M <= 64) {
    hp_fmatmul_16x16(c, a, b, M, N, P);
  } else if (M <= 128) {
    // Vector length is 64 elements. With an 8x8 hp_fmatmul,
    // we can use LMUL=2, having a vl of 128.
    hp_fmatmul_8x8(c, a, b, M, N, P);
  } else {
    // Vector length is 64 elements. With an 4x4 hp_fmatmul,
    // we can use LMUL=4, having a vl of 256.
    hp_fmatmul_4x4(c, a, b, M, N, P);
  }
}

// ---------------
// 4x4
// ---------------

void hp_fmatmul_4x4(_Float16 *c, const _Float16 *a, const _Float16 *b,
                    const unsigned int M, const unsigned int N,
                    const unsigned int P) {
  // We work on 4 rows of the matrix at once
  unsigned int block_size = 4;
  unsigned int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e16, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    unsigned int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const _Float16 *b_ = b + p;
    _Float16 *c_ = c + p;

    asm volatile("vsetvli zero, %0, e16, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const _Float16 *a_ = a + m * N;
      _Float16 *c__ = c_ + m * P;

      hp_fmatmul_vec_4x4_slice_init();
      hp_fmatmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void hp_fmatmul_vec_4x4_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v12, 0");
}

void hp_fmatmul_vec_4x4(_Float16 *c, const _Float16 *a, const _Float16 *b,
                        const unsigned int N, const unsigned int P) {
  // Temporary variables
  _Float16 t0, t1, t2, t3;

  // Original pointer
  const _Float16 *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle16.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));

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
    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle16.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v16" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v16" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v16" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle16.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse16.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
  asm volatile("vse16.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t2));
  asm volatile("vse16.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t3));
  asm volatile("vse16.v v12, (%0);" ::"r"(c));
}

// ---------------
// 8x8
// ---------------

void hp_fmatmul_8x8(_Float16 *c, const _Float16 *a, const _Float16 *b,
                    const unsigned int M, const unsigned int N,
                    const unsigned int P) {
  // We work on 4 rows of the matrix at once
  unsigned int block_size = 8;
  unsigned int block_size_p;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e16, m2, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    unsigned int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const _Float16 *b_ = b + p;
    _Float16 *c_ = c + p;

    asm volatile("vsetvli zero, %0, e16, m2, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const _Float16 *a_ = a + m * N;
      _Float16 *c__ = c_ + m * P;

      hp_fmatmul_vec_8x8_slice_init();
      hp_fmatmul_vec_8x8(c__, a_, b_, N, P);
    }
  }
}

void hp_fmatmul_vec_8x8_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v14, 0");
}

void hp_fmatmul_vec_8x8(_Float16 *c, const _Float16 *a, const _Float16 *b,
                        const unsigned int N, const unsigned int P) {
  // Temporary variables
  _Float16 t0, t1, t2, t3, t4, t5, t6, t7;

  // Original pointer
  const _Float16 *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle16.v v18, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));

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
    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v18" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle16.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v2, %0, v18" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v4, %0, v18" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v6, %0, v18" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v18" ::"f"(t4));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v10, %0, v18" ::"f"(t5));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v18" ::"f"(t6));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v14, %0, v18" ::"f"(t7));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle16.v v18, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v2, %0, v20" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v6, %0, v20" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t4));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v10, %0, v20" ::"f"(t5));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t6));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v14, %0, v20" ::"f"(t7));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse16.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v2, %0, v20" ::"f"(t1));
  asm volatile("vse16.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t2));
  asm volatile("vse16.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v6, %0, v20" ::"f"(t3));
  asm volatile("vse16.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t4));
  asm volatile("vse16.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v10, %0, v20" ::"f"(t5));
  asm volatile("vse16.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t6));
  asm volatile("vse16.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v14, %0, v20" ::"f"(t7));
  asm volatile("vse16.v v14, (%0);" ::"r"(c));
}

// ---------------
// 16x16
// ---------------

void hp_fmatmul_16x16(_Float16 *c, const _Float16 *a, const _Float16 *b,
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
    const _Float16 *b_ = b + p;
    _Float16 *c_ = c + p;

    asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const _Float16 *a_ = a + m * N;
      _Float16 *c__ = c_ + m * P;

      hp_fmatmul_vec_16x16_slice_init();
      hp_fmatmul_vec_16x16(c__, a_, b_, N, P);
    }
  }
}

void hp_fmatmul_vec_16x16_slice_init() {
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

void hp_fmatmul_vec_16x16(_Float16 *c, const _Float16 *a, const _Float16 *b,
                          const unsigned int N, const unsigned int P) {
  // Temporary variables
  _Float16 t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15;

  // Original pointer
  const _Float16 *a_ = a;

  // Prefetch one row of matrix B
  asm volatile("vle32.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t8) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t9) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t10) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t11) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t12) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t13) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t14) : [a] "r"(a));
  a += N;
  asm volatile("flh %[t], (%[a])" : [t] "=f"(t15) : [a] "r"(a));

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
    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v17, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v1, %0, v16" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v2, %0, v16" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v3, %0, v16" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v4, %0, v16" ::"f"(t4));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v5, %0, v16" ::"f"(t5));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v6, %0, v16" ::"f"(t6));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v7, %0, v16" ::"f"(t7));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v16" ::"f"(t8));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t8) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v9, %0, v16" ::"f"(t9));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t9) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v10, %0, v16" ::"f"(t10));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t10) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v11, %0, v16" ::"f"(t11));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t11) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v16" ::"f"(t12));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t12) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v13, %0, v16" ::"f"(t13));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t13) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v14, %0, v16" ::"f"(t14));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t14) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v15, %0, v16" ::"f"(t15));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t15) : [a] "r"(a));

    if (n == N - 1)
      break;

    a = (const _Float16 *)a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v17" ::"f"(t0));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t0) : [a] "r"(a));
    a += N;

    // Load one row of B
    asm volatile("vle32.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v1, %0, v17" ::"f"(t1));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t1) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v2, %0, v17" ::"f"(t2));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t2) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v3, %0, v17" ::"f"(t3));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t3) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v4, %0, v17" ::"f"(t4));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t4) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v5, %0, v17" ::"f"(t5));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t5) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v6, %0, v17" ::"f"(t6));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t6) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v7, %0, v17" ::"f"(t7));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t7) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v8, %0, v17" ::"f"(t8));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t8) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v9, %0, v17" ::"f"(t9));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t9) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v10, %0, v17" ::"f"(t10));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t10) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v11, %0, v17" ::"f"(t11));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t11) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v12, %0, v17" ::"f"(t12));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t12) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v13, %0, v17" ::"f"(t13));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t13) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v14, %0, v17" ::"f"(t14));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t14) : [a] "r"(a));
    a += N;
    asm volatile("vfmacc.vf v15, %0, v17" ::"f"(t15));
    asm volatile("flh %[t], (%[a])" : [t] "=f"(t15) : [a] "r"(a));
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v17" ::"f"(t0));
  asm volatile("vse32.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v1, %0, v17" ::"f"(t1));
  asm volatile("vse32.v v1, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v2, %0, v17" ::"f"(t2));
  asm volatile("vse32.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v3, %0, v17" ::"f"(t3));
  asm volatile("vse32.v v3, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v17" ::"f"(t4));
  asm volatile("vse32.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v5, %0, v17" ::"f"(t5));
  asm volatile("vse32.v v5, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v6, %0, v17" ::"f"(t6));
  asm volatile("vse32.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v7, %0, v17" ::"f"(t7));
  asm volatile("vse32.v v7, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v17" ::"f"(t8));
  asm volatile("vse32.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v9, %0, v17" ::"f"(t9));
  asm volatile("vse32.v v9, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v10, %0, v17" ::"f"(t10));
  asm volatile("vse32.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v11, %0, v17" ::"f"(t11));
  asm volatile("vse32.v v11, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v17" ::"f"(t12));
  asm volatile("vse32.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v13, %0, v17" ::"f"(t13));
  asm volatile("vse32.v v13, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v14, %0, v17" ::"f"(t14));
  asm volatile("vse32.v v14, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v15, %0, v17" ::"f"(t15));
  asm volatile("vse32.v v15, (%0);" ::"r"(c));
}
