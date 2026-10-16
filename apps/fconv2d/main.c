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

// Author: Matteo Perotti

#include <stdint.h>
#include <string.h>

#include "fconv2d.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the result against the golden output
#ifndef CHECK
#define CHECK 1
#endif

#define THRESHOLD_64b 0.0000000001
#define THRESHOLD_32b 0.01
#define THRESHOLD_16b 0.1

#if !(FP64 || FP32 || FP16)
#error "No precision selected: add e.g. FP64 to def_args_fconv2d in common/default_args.mk"
#endif

#if FP64
extern double i64[] __attribute__((aligned(8 * NR_LANES))); // [ (M+F-1) * (N+F-1) ]
extern double f64[] __attribute__((aligned(8 * NR_LANES))); // [ F*F ]
extern double o64[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
extern double golden_o64[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
#endif
#if FP32
extern float i32[] __attribute__((aligned(8 * NR_LANES))); // [ (M+F-1) * (N+F-1) ]
extern float f32[] __attribute__((aligned(8 * NR_LANES))); // [ F*F ]
extern float o32[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
extern float golden_o32[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
#endif
#if FP16
extern _Float16 i16[] __attribute__((aligned(8 * NR_LANES))); // [ (M+F-1) * (N+F-1) ]
extern _Float16 f16[] __attribute__((aligned(8 * NR_LANES))); // [ F*F ]
extern _Float16 o16[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
extern _Float16 golden_o16[] __attribute__((aligned(8 * NR_LANES))); // [ M*N ]
#endif
extern int64_t M;
extern int64_t N;
extern int64_t F;

// Verify the matrices
#define DEFINE_VERIFY(SUF, TY)                                                 \
  int verify_matrix##SUF(TY *matrix, TY *golden_matrix, int64_t R, int64_t C,  \
                         double threshold) {                                   \
    for (int r = 0; r < R; ++r)                                                \
      for (int c = 0; c < C; ++c)                                              \
        if (!similarity_check((double)matrix[c + C * r],                       \
                              (double)golden_matrix[c + C * r], threshold)) {  \
          printf("Error: o[%d][%d] = %lf, instead of %lf\n", r, c,             \
                 (double)matrix[c + C * r], (double)golden_matrix[c + C * r]); \
          return 1;                                                            \
        }                                                                      \
    return 0;                                                                  \
  }
#if FP64
DEFINE_VERIFY(64, double)
#endif
#if FP32
DEFINE_VERIFY(32, float)
#endif
#if FP16
DEFINE_VERIFY(16, _Float16)
#endif

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  FCONV2D  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  int error = 0;
  int64_t runtime;

#if FP64
  // Sweep the columns (4, 8, ..., N); only the last, full-size run is checked
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size convolution
  for (int64_t cols = N;; cols *= 2) {
#else
  for (int64_t cols = 4;; cols *= 2) {
#endif
    if (cols > N)
      cols = N;
    printf("64-bit: %ldx%ld convolution with a %ldx%ld filter...\n", M, cols, F,
           F);
    start_timer();
    if (F == 3)
      fconv2d_3x3(o64, i64, f64, M, cols, F);
    else if (F == 7)
      fconv2d_7x7(o64, i64, f64, M, cols, F);
    else
      printf("Error: the filter size is different from 3 or 7.\n");
    stop_timer();

    // Performance metrics
    runtime = get_timer();
    float performance = 2.0 * F * F * M * cols / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);
    printf("The execution took %ld cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fconv2d", 64, cols, runtime, performance);
    if (cols == N)
      break;
  }

  if (CHECK) {
    printf("Verifying 64-bit result...\n");
    if (verify_matrix64(o64, golden_o64, M, N, THRESHOLD_64b)) {
      error = 1;
      printf("Fail.\n");
    } else {
      printf("Passed.\n");
    }
  }
#endif // FP64

#if FP32
  // Sweep the columns (4, 8, ..., N); only the last, full-size run is checked
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size convolution
  for (int64_t cols = N;; cols *= 2) {
#else
  for (int64_t cols = 4;; cols *= 2) {
#endif
    if (cols > N)
      cols = N;
    printf("32-bit: %ldx%ld convolution with a %ldx%ld filter...\n", M, cols, F,
           F);
    start_timer();
    if (F == 3)
      fconv2d32_3x3(o32, i32, f32, M, cols, F);
    else if (F == 7)
      fconv2d32_7x7(o32, i32, f32, M, cols, F);
    else
      printf("Error: the filter size is different from 3 or 7.\n");
    stop_timer();

    // Performance metrics
    runtime = get_timer();
    float performance = 2.0 * F * F * M * cols / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);
    printf("The execution took %ld cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fconv2d", 32, cols, runtime, performance);
    if (cols == N)
      break;
  }

  if (CHECK) {
    printf("Verifying 32-bit result...\n");
    if (verify_matrix32(o32, golden_o32, M, N, THRESHOLD_32b)) {
      error = 1;
      printf("Fail.\n");
    } else {
      printf("Passed.\n");
    }
  }
#endif // FP32

#if FP16
  // Sweep the columns (4, 8, ..., N); only the last, full-size run is checked
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size convolution
  for (int64_t cols = N;; cols *= 2) {
#else
  for (int64_t cols = 4;; cols *= 2) {
#endif
    if (cols > N)
      cols = N;
    printf("16-bit: %ldx%ld convolution with a %ldx%ld filter...\n", M, cols, F,
           F);
    start_timer();
    if (F == 3)
      fconv2d16_3x3(o16, i16, f16, M, cols, F);
    else if (F == 7)
      fconv2d16_7x7(o16, i16, f16, M, cols, F);
    else
      printf("Error: the filter size is different from 3 or 7.\n");
    stop_timer();

    // Performance metrics
    runtime = get_timer();
    float performance = 2.0 * F * F * M * cols / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(16);
    printf("The execution took %ld cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fconv2d", 16, cols, runtime, performance);
    if (cols == N)
      break;
  }

  if (CHECK) {
    printf("Verifying 16-bit result...\n");
    if (verify_matrix16(o16, golden_o16, M, N, THRESHOLD_16b)) {
      error = 1;
      printf("Fail.\n");
    } else {
      printf("Passed.\n");
    }
  }
#endif // FP16

  return error;
}
