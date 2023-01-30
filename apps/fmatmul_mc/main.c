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

// Measure from the kernel call to the kernel to the kernel end
#if   defined VCD_DUMP && ((defined MM_1 || defined MM_2 || defined MM_4) || (defined MM_8 && NR_CORES < 8) || (defined MM_16 && NR_CORES < 4))
#define VCD_DUMP_WHOLE
#pragma message("VCD_DUMP_WHOLE successfully initialized")
#elif defined VCD_DUMP && (defined MM_32 && NR_CORES == 1)
#define VCD_DUMP_MID_KERNEL
#pragma message("VCD_DUMP_MID_KERNEL successfully initialized")
#elif defined VCD_DUMP && ((defined MM_64 || defined MM_128 || defined MM_256) || (defined MM_32 && NR_CORES > 1) || (defined MM_16 && NR_CORES > 2) || (defined MM_8 && NR_CORES > 4))
#define VCD_DUMP_IN_KERNEL
#pragma message("VCD_DUMP_IN_KERNEL successfully initialized")
#endif

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "kernel/fmatmul.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#endif

#define WARM_UP_CYCLES 1

// Define Matrix dimensions:
// C = AB with A=[MxN], B=[NxP], C=[MxP]
extern uint64_t M;
extern uint64_t N;
extern uint64_t P;

extern double a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double c[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
// Gold results
extern double g[] __attribute__((aligned(32 * NR_LANES), section(".l2")));

// Define half of the range for FP comparison on the results
#define THRESHOLD 0.001

// ---------------
// 1x1
// ---------------

inline void fmatmul_1x1(double *c, const double *a, const double *b,
                        const unsigned long int M, const unsigned long int N,
                        const unsigned long int P, int core_id) {
  // We work on 1 rows of the matrix at once
  const unsigned long int block_size = 1;
  unsigned long int block_size_p;

#ifdef VCD_DUMP_WHOLE
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_1x1_slice_init();
      fmatmul_vec_1x1(c__, a_, b_, N, P, core_id);
    }
  }
}

inline void fmatmul_vec_1x1_slice_init() {
  asm volatile("vmv.v.i v0,  0");
}

inline void fmatmul_vec_1x1(double *c, const double *a, const double *b,
                            const unsigned long int N,
                            const unsigned long int P, int core_id) {
  // Temporary variables
  double t0;

  // Original pointer
  const double *a_ = a;

#ifdef VCD_DUMP_MID_KERNEL
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Prefetch one row of matrix B
  asm volatile("vle64.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  t0 = *a;

  // Compute the multiplication
  unsigned long int n = 0;

  while (n != N) {
#ifdef VCD_DUMP_IN_KERNEL
    // Start dumping VCD
    if (n == 12 && !core_id)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 16 && !core_id)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));

#ifdef VCD_DUMP_MID_KERNEL
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif
}

// ---------------
// 2x2
// ---------------

inline void fmatmul_2x2(double *c, const double *a, const double *b,
                        const unsigned long int M, const unsigned long int N,
                        const unsigned long int P, int core_id) {
  // We work on 2 rows of the matrix at once
  const unsigned long int block_size = 2;
  unsigned long int block_size_p;

#ifdef VCD_DUMP_WHOLE
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_2x2_slice_init();
      fmatmul_vec_2x2(c__, a_, b_, N, P, core_id);
    }
  }
}

inline void fmatmul_vec_2x2_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
}

inline void fmatmul_vec_2x2(double *c, const double *a, const double *b,
                            const unsigned long int N,
                            const unsigned long int P, int core_id) {
  // Temporary variables
  double t0, t1;

  // Original pointer
  const double *a_ = a;

#ifdef VCD_DUMP_MID_KERNEL
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Prefetch one row of matrix B
  asm volatile("vle64.v v16, (%0);" ::"r"(b));
  b += P;

  // Prefetch one row of scalar values
  t0 = *a, a += N;
  t1 = *a;

  // Compute the multiplication
  unsigned long int n = 0;

  while (n != N) {
#ifdef VCD_DUMP_IN_KERNEL
    // Start dumping VCD
    if (n == 12 && !core_id)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 16 && !core_id)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v16" ::"f"(t1));
    t1 = *a, a += N;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
    t1 = *a, a += N;
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));

#ifdef VCD_DUMP_MID_KERNEL
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif
}

// ---------------
// 4x4
// ---------------

inline void fmatmul_4x4(double *c, const double *a, const double *b,
                        const unsigned long int M, const unsigned long int N,
                        const unsigned long int P, int core_id) {
  // We work on 4 rows of the matrix at once
  const unsigned long int block_size = 4;
  unsigned long int block_size_p;

#ifdef VCD_DUMP_WHOLE
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_4x4_slice_init();
      fmatmul_vec_4x4(c__, a_, b_, N, P, core_id);
    }
  }
}

inline void fmatmul_vec_4x4_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v12, 0");
}

inline void fmatmul_vec_4x4(double *c, const double *a, const double *b,
                            const unsigned long int N,
                            const unsigned long int P, int core_id) {
  // Temporary variables
  double t0, t1, t2, t3;

  // Original pointer
  const double *a_ = a;

#ifdef VCD_DUMP_MID_KERNEL
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

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

  while (n != N) {
#ifdef VCD_DUMP_IN_KERNEL
    // Start dumping VCD
    if (n == 12 && !core_id)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 16 && !core_id)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v16" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v16" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v16" ::"f"(t3));
    t3 = *a;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t3));
    t3 = *a;
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t1));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t2));
  asm volatile("vse64.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t3));
  asm volatile("vse64.v v12, (%0);" ::"r"(c));

#ifdef VCD_DUMP_MID_KERNEL
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif
}

// ---------------
// 8x8
// ---------------

inline void fmatmul_8x8(double *c, const double *a, const double *b,
                 const unsigned long int M, const unsigned long int N,
                 const unsigned long int P, int core_id) {
  // We work on 4 rows of the matrix at once
  const unsigned long int block_size = 8;
  unsigned long int block_size_p;

#ifdef VCD_DUMP_WHOLE
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m2, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_8x8_slice_init();
      fmatmul_vec_8x8(c__, a_, b_, N, P, core_id);
    }
  }
}

inline void fmatmul_vec_8x8_slice_init() {
  asm volatile("vmv.v.i v0,  0");
  asm volatile("vmv.v.i v2,  0");
  asm volatile("vmv.v.i v4,  0");
  asm volatile("vmv.v.i v6,  0");
  asm volatile("vmv.v.i v8,  0");
  asm volatile("vmv.v.i v10, 0");
  asm volatile("vmv.v.i v12, 0");
  asm volatile("vmv.v.i v14, 0");
}

inline void fmatmul_vec_8x8(double *c, const double *a, const double *b,
                     const unsigned long int N, const unsigned long int P,
                     int core_id) {
  // Temporary variables
  double t0, t1, t2, t3, t4, t5, t6, t7;

  // Original pointer
  const double *a_ = a;

#ifdef VCD_DUMP_MID_KERNEL
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

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

  while (n != N) {
#ifdef VCD_DUMP_IN_KERNEL
    // Start dumping VCD
    if (n == 8 && !core_id)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 12 && !core_id)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v18" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v20, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v2, %0, v18" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v4, %0, v18" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v6, %0, v18" ::"f"(t3));
    t3 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v18" ::"f"(t4));
    t4 = *a, a += N;
    asm volatile("vfmacc.vf v10, %0, v18" ::"f"(t5));
    t5 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v18" ::"f"(t6));
    t6 = *a, a += N;
    asm volatile("vfmacc.vf v14, %0, v18" ::"f"(t7));
    t7 = *a;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v18, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v2, %0, v20" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v6, %0, v20" ::"f"(t3));
    t3 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t4));
    t4 = *a, a += N;
    asm volatile("vfmacc.vf v10, %0, v20" ::"f"(t5));
    t5 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t6));
    t6 = *a, a += N;
    asm volatile("vfmacc.vf v14, %0, v20" ::"f"(t7));
    t7 = *a;
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v20" ::"f"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v2, %0, v20" ::"f"(t1));
  asm volatile("vse64.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v20" ::"f"(t2));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v6, %0, v20" ::"f"(t3));
  asm volatile("vse64.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v20" ::"f"(t4));
  asm volatile("vse64.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v10, %0, v20" ::"f"(t5));
  asm volatile("vse64.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v20" ::"f"(t6));
  asm volatile("vse64.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v14, %0, v20" ::"f"(t7));
  asm volatile("vse64.v v14, (%0);" ::"r"(c));

#ifdef VCD_DUMP_MID_KERNEL
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif
}

// ---------------
// 16x16
// ---------------

inline void fmatmul_16x16(double *c, const double *a, const double *b,
                   unsigned long int M, unsigned long int N,
                   unsigned long int P, int core_id) {
  // We work on 4 rows of the matrix at once
  const unsigned long int block_size = 16;
  unsigned long int block_size_p;

#ifdef VCD_DUMP_WHOLE
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(block_size_p) : "r"(P));

  // Slice the matrix into a manageable number of columns p_
  for (unsigned long int p = 0; p < P; p += block_size_p) {
    // Set the vector length
    const unsigned long int p_ = MIN(P - p, block_size_p);

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_16x16_slice_init();
      fmatmul_vec_16x16(c__, a_, b_, N, P, core_id);
    }
  }
}

inline void fmatmul_vec_16x16_slice_init() {
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

inline void fmatmul_vec_16x16(double *c, const double *a, const double *b,
                       const unsigned long int N, const unsigned long int P,
                       int core_id) {
  // Temporary variables
  double t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15;

  // Original pointer
  const double *a_ = a;

#ifdef VCD_DUMP_MID_KERNEL
    // Start dumping VCD
    if (!core_id)
      event_trigger = +1;
#endif

  // Prefetch one row of scalar values
  t0 = *a, a += N;
  t1 = *a, a += N;
  t2 = *a, a += N;
  t3 = *a, a += N;
  t4 = *a, a += N;
  t5 = *a, a += N;
  t6 = *a, a += N;
  t7 = *a, a += N;
  t8 = *a, a += N;
  t9 = *a, a += N;
  t10 = *a, a += N;
  t11 = *a, a += N;
  t12 = *a, a += N;
  t13 = *a, a += N;
  t14 = *a, a += N;
  t15 = *a;

  // Prefetch one row of matrix B
  asm volatile("vle64.v v16, (%0);" ::"r"(b));
  b += P;

  // Compute the multiplication
  unsigned long int n = 0;

  while (n != N) {
#ifdef VCD_DUMP_IN_KERNEL
    // Start dumping VCD
    if (n == 4 && !core_id)
      event_trigger = +1;
    // Stop dumping VCD
    if (n == 8 && !core_id)
      event_trigger = -1;
#endif

    // Calculate pointer to the matrix A
    a = a_ + ++n;

    asm volatile("vfmacc.vf v0, %0, v16" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v17, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v1, %0, v16" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v2, %0, v16" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v3, %0, v16" ::"f"(t3));
    t3 = *a, a += N;
    asm volatile("vfmacc.vf v4, %0, v16" ::"f"(t4));
    t4 = *a, a += N;
    asm volatile("vfmacc.vf v5, %0, v16" ::"f"(t5));
    t5 = *a, a += N;
    asm volatile("vfmacc.vf v6, %0, v16" ::"f"(t6));
    t6 = *a, a += N;
    asm volatile("vfmacc.vf v7, %0, v16" ::"f"(t7));
    t7 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v16" ::"f"(t8));
    t8 = *a, a += N;
    asm volatile("vfmacc.vf v9, %0, v16" ::"f"(t9));
    t9 = *a, a += N;
    asm volatile("vfmacc.vf v10, %0, v16" ::"f"(t10));
    t10 = *a, a += N;
    asm volatile("vfmacc.vf v11, %0, v16" ::"f"(t11));
    t11 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v16" ::"f"(t12));
    t12 = *a, a += N;
    asm volatile("vfmacc.vf v13, %0, v16" ::"f"(t13));
    t13 = *a, a += N;
    asm volatile("vfmacc.vf v14, %0, v16" ::"f"(t14));
    t14 = *a, a += N;
    asm volatile("vfmacc.vf v15, %0, v16" ::"f"(t15));
    t15 = *a;

    a = a_ + ++n;

    if (n == N)
      break;

    asm volatile("vfmacc.vf v0, %0, v17" ::"f"(t0));
    t0 = *a, a += N;

    // Load one row of B
    asm volatile("vle64.v v16, (%0);" ::"r"(b));
    b += P;

    asm volatile("vfmacc.vf v1, %0, v17" ::"f"(t1));
    t1 = *a, a += N;
    asm volatile("vfmacc.vf v2, %0, v17" ::"f"(t2));
    t2 = *a, a += N;
    asm volatile("vfmacc.vf v3, %0, v17" ::"f"(t3));
    t3 = *a, a += N;
    asm volatile("vfmacc.vf v4, %0, v17" ::"f"(t4));
    t4 = *a, a += N;
    asm volatile("vfmacc.vf v5, %0, v17" ::"f"(t5));
    t5 = *a, a += N;
    asm volatile("vfmacc.vf v6, %0, v17" ::"f"(t6));
    t6 = *a, a += N;
    asm volatile("vfmacc.vf v7, %0, v17" ::"f"(t7));
    t7 = *a, a += N;
    asm volatile("vfmacc.vf v8, %0, v17" ::"f"(t8));
    t8 = *a, a += N;
    asm volatile("vfmacc.vf v9, %0, v17" ::"f"(t9));
    t9 = *a, a += N;
    asm volatile("vfmacc.vf v10, %0, v17" ::"f"(t10));
    t10 = *a, a += N;
    asm volatile("vfmacc.vf v11, %0, v17" ::"f"(t11));
    t11 = *a, a += N;
    asm volatile("vfmacc.vf v12, %0, v17" ::"f"(t12));
    t12 = *a, a += N;
    asm volatile("vfmacc.vf v13, %0, v17" ::"f"(t13));
    t13 = *a, a += N;
    asm volatile("vfmacc.vf v14, %0, v17" ::"f"(t14));
    t14 = *a, a += N;
    asm volatile("vfmacc.vf v15, %0, v17" ::"f"(t15));
    t15 = *a;
  }

  // Last iteration: store results
  asm volatile("vfmacc.vf v0, %0, v17" ::"f"(t0));
  asm volatile("vse64.v v0, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v1, %0, v17" ::"f"(t1));
  asm volatile("vse64.v v1, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v2, %0, v17" ::"f"(t2));
  asm volatile("vse64.v v2, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v3, %0, v17" ::"f"(t3));
  asm volatile("vse64.v v3, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v4, %0, v17" ::"f"(t4));
  asm volatile("vse64.v v4, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v5, %0, v17" ::"f"(t5));
  asm volatile("vse64.v v5, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v6, %0, v17" ::"f"(t6));
  asm volatile("vse64.v v6, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v7, %0, v17" ::"f"(t7));
  asm volatile("vse64.v v7, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v8, %0, v17" ::"f"(t8));
  asm volatile("vse64.v v8, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v9, %0, v17" ::"f"(t9));
  asm volatile("vse64.v v9, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v10, %0, v17" ::"f"(t10));
  asm volatile("vse64.v v10, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v11, %0, v17" ::"f"(t11));
  asm volatile("vse64.v v11, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v12, %0, v17" ::"f"(t12));
  asm volatile("vse64.v v12, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v13, %0, v17" ::"f"(t13));
  asm volatile("vse64.v v13, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v14, %0, v17" ::"f"(t14));
  asm volatile("vse64.v v14, (%0);" ::"r"(c));
  c += P;
  asm volatile("vfmacc.vf v15, %0, v17" ::"f"(t15));
  asm volatile("vse64.v v15, (%0);" ::"r"(c));

#ifdef VCD_DUMP_MID_KERNEL
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif
}

// Verify the matrix
int verify_matrix(double *result, double *gold, size_t R, size_t C,
                  double threshold) {
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

int main(int core_id) {

  if (!core_id) {
    printf("\n");
    printf("=============\n");
    printf("=  FMATMUL  =\n");
    printf("=============\n");
    printf("\n");
    printf("\n");

    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a (%d x %d) x (%d x %d) matrix multiplication...\n",
           M, N, N, P);
    printf("------------------------------------------------------------\n");
    printf("\n");

    printf("Synch and start the kernel...\n");
  }

  // Divide the input matrix
  uint64_t m_priv = (M >> LOG2_NR_CORES);
  double *a_priv = a + core_id * (m_priv * N);
  double *c_priv = c + core_id * (m_priv * P);

  primitive_synch(core_id);

#ifndef VCD_DUMP
  for (int i = 0; i < WARM_UP_CYCLES; ++i) {
#if   defined(MM_1)
  fmatmul_1x1(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_2)
  fmatmul_2x2(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_4)
    fmatmul_4x4(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_8)
    fmatmul_8x8(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_16)
    fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_32)
    fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_64)
    fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_128)
    fmatmul_8x8(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_256)
    fmatmul_4x4(c_priv, a_priv, b, m_priv, N, P, core_id);
#endif
  }

  primitive_synch(core_id);
#endif

  // Matrices are initialized --> Start calculating
#ifndef VCD_DUMP
  start_timer();
#endif

#if   defined(MM_1)
  fmatmul_1x1(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_2)
  fmatmul_2x2(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_4)
  fmatmul_4x4(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_8)
  fmatmul_8x8(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_16)
  fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_32)
  fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_64)
  fmatmul_16x16(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_128)
  fmatmul_8x8(c_priv, a_priv, b, m_priv, N, P, core_id);
#elif defined(MM_256)
  fmatmul_4x4(c_priv, a_priv, b, m_priv, N, P, core_id);
#endif

  primitive_synch(core_id);

#ifdef VCD_DUMP_WHOLE
    // Stop dumping VCD
    if (!core_id)
      event_trigger = -1;
#endif

  stop_timer();

  primitive_synch(core_id);

  if (!core_id) {
    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M * N * P / runtime;
    float utilization = 100 * performance / (2.0 * NR_LANES * NR_CORES);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);

    // Verify the result
    printf("Verifying result...\n");
    int error = verify_matrix(c, g, M, P, THRESHOLD);
    if (error != 0) {
      printf("Error code %d\n", error);
      printf("c[%d]=%d\n", error, c[error]);
      return error;
    } else {
      printf("Passed.\n");
    }
  }

  primitive_synch(core_id);

  return 0;
}
