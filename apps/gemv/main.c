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

// Author: Chi Zhang, ETH Zurich <chizhang@iis.ee.ethz.ch>
//         Hong Pang, ETH Zurich <hopang@iis.ee.ethz.ch>

// Attention: the matrix width (M_COL) should be a multiple of NrLanes

#include <stdint.h>
#include <string.h>

#include "runtime.h"
#include "util.h"

#include "kernel/gemv.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the vector results against golden vectors (check=0 in make disables it)
#ifndef CHECK
#define CHECK 1
#endif
#define THRESHOLD 0.05
// Looser for FP16: its ulp grows with the sum
#define THRESHOLD_16b 0.1
// Max number of printed mismatches
#define MAX_ERR_PRINT 10

// Macro to check similarity between two fp-values, wrt a threshold
static inline int fp_check(const double a, const double b, const double thr) {
  // Absolute value
  double comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > thr;
}

#if !(FP64 || FP32 || FP16)
#error "No precision selected: add e.g. FP64 to def_args_gemv in common/default_args.mk"
#endif

// res[M_COL] = vec[M_ROW] * mat[M_ROW][M_COL]
// M_ROW must be even (the kernel unrolls by 2)
extern uint64_t M_ROW;
extern uint64_t M_COL;

#if FP64
extern double mat64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double vec64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double res64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double gold64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
#endif
#if FP32
extern float mat32[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern float vec32[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern float res32[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern float gold32[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
#endif
#if FP16
extern _Float16 mat16[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern _Float16 vec16[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern _Float16 res16[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern _Float16 gold16[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
#endif

int main() {
  int errors = 0;

  printf("\n");
  printf("==========\n");
  printf("=  GEMV  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

#if FP64
#ifndef NETLIST
  // Sweep the width, also the row stride; the first point warms the I-cache
  for (uint64_t s = 4; s <= M_COL; s *= 2) {
#else
  for (uint64_t s = M_COL; s <= M_COL; s *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 64-bit %d x (%d x %d) vector-matrix multiplication...\n",
           M_ROW, M_ROW, s);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    gemv_v64b_m8(mat64, vec64, res64, s, s, M_ROW);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M_ROW * s / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization) at %d lanes.\n",
           performance, utilization, NR_LANES);
    PRINT_SWEEP("gemv", 64, s, runtime, performance);

    // Verify the result
    if (CHECK && s == M_COL) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < M_COL; i++) {
        if (fp_check((double)res64[i], (double)gold64[i], THRESHOLD)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)res64[i], (float)gold64[i]);
        }
      }
    }
  }
#endif // FP64

#if FP32
#ifndef NETLIST
  // Sweep the width, also the row stride; the first point warms the I-cache
  for (uint64_t s = 4; s <= M_COL; s *= 2) {
#else
  for (uint64_t s = M_COL; s <= M_COL; s *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 32-bit %d x (%d x %d) vector-matrix multiplication...\n",
           M_ROW, M_ROW, s);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    gemv_v32b_m8(mat32, vec32, res32, s, s, M_ROW);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M_ROW * s / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization) at %d lanes.\n",
           performance, utilization, NR_LANES);
    PRINT_SWEEP("gemv", 32, s, runtime, performance);

    // Verify the result
    if (CHECK && s == M_COL) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < M_COL; i++) {
        if (fp_check((double)res32[i], (double)gold32[i], THRESHOLD)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)res32[i], (float)gold32[i]);
        }
      }
    }
  }
#endif // FP32

#if FP16
#ifndef NETLIST
  // Sweep the width, also the row stride; the first point warms the I-cache
  for (uint64_t s = 4; s <= M_COL; s *= 2) {
#else
  for (uint64_t s = M_COL; s <= M_COL; s *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 16-bit %d x (%d x %d) vector-matrix multiplication...\n",
           M_ROW, M_ROW, s);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    gemv_v16b_m8(mat16, vec16, res16, s, s, M_ROW);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M_ROW * s / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(16);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization) at %d lanes.\n",
           performance, utilization, NR_LANES);
    PRINT_SWEEP("gemv", 16, s, runtime, performance);

    // Verify the result
    if (CHECK && s == M_COL) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < M_COL; i++) {
        if (fp_check((double)res16[i], (double)gold16[i], THRESHOLD_16b)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)res16[i], (float)gold16[i]);
        }
      }
    }
  }
#endif // FP16

  if (errors) {
    printf("Error: %d mismatches\n", errors);
    return 1;
  }

  printf("Done!\n");
  return 0;
}
