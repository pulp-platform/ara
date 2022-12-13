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

inline void fmatmul(double *c, const double *a, const double *b,
                    const unsigned long int M, const unsigned long int N,
                    const unsigned long int P) {
  if (M <= 4) {
    fmatmul_4x4(c, a, b, M, N, P);
  } else if (M <= 8) {
    fmatmul_8x8(c, a, b, M, N, P);
  } else if (M <= 64) {
    fmatmul_16x16(c, a, b, M, N, P);
  } else if (M <= 128) {
    // Vector length is 64 elements. With an 8x8 matmul,
    // we can use LMUL=2, having a vl of 128.
    fmatmul_8x8(c, a, b, M, N, P);
  } else {
    // Vector length is 64 elements. With an 4x4 matmul,
    // we can use LMUL=4, having a vl of 256.
    fmatmul_4x4(c, a, b, M, N, P);
  }
}

// ---------------
// 4x4
// ---------------

inline void fmatmul_4x4(double *c, const double *a, const double *b,
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
    const double *b_ = b + p;
    double *c_ = c + p;

    asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(p_));

    // Iterate over the rows
    for (unsigned long int m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m * N;
      double *c__ = c_ + m * P;

      fmatmul_vec_4x4_slice_init();
      fmatmul_vec_4x4(c__, a_, b_, N, P);
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
                            const unsigned long int P) {
  // Temporary variables
  double t0, t1, t2, t3;

  // Original pointer
  const double *a_ = a;

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

  for (int i = 0; i < WARM_UP_CYCLES; ++i) {
    fmatmul(c_priv, a_priv, b, m_priv, N, P);
  }

  primitive_synch(core_id);

  // Matrices are initialized --> Start calculating
  start_timer();
  fmatmul(c_priv, a_priv, b, m_priv, N, P);
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
