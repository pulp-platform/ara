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

// Author: Hong Pang <hopang@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "runtime.h"
#include "util.h"

#include "kernel/faxpy.h"

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

// Whether to use the unrolled faxpy kernel
#define UNROLL 1

// Threshold for FP comparisons
#define THRESHOLD_64b 0.00001
#define THRESHOLD_32b 0.00001
#define THRESHOLD_16b 0.01
// Max number of printed mismatches
#define MAX_ERR_PRINT 10

// Macro to check similarity between two fp-values, wrt a threshold
static inline int fp_check(const double a, const double b,
                           const double threshold) {
  // Absolute value
  double comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

#if !(FP64 || FP32 || FP16)
#error "No precision selected: add e.g. FP64 to def_args_faxpy in common/default_args.mk"
#endif

// Vector size (Byte)
extern uint64_t vsize;
// Per precision: scalar a, x, y (updated in place), golden y
#if FP64
extern double a64;
extern double v64x[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern double v64y[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern double gold64[] __attribute__((aligned(8 * NR_LANES), section(".data")));
#endif
#if FP32
extern float a32;
extern float v32x[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern float v32y[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern float gold32[] __attribute__((aligned(8 * NR_LANES), section(".data")));
#endif
#if FP16
extern _Float16 a16;
extern _Float16 v16x[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern _Float16 v16y[] __attribute__((aligned(8 * NR_LANES), section(".data")));
extern _Float16 gold16[] __attribute__((aligned(8 * NR_LANES), section(".data")));
#endif

int main() {
  int errors = 0;

  printf("\n");
  printf("===========\n");
  printf("=  FAXPY  =\n");
  printf("===========\n");
  printf("\n");
  printf("\n");

  uint64_t runtime_v;

#if FP64
#if CHECK || defined(NETLIST)
  // Single point (y is updated in place, so a sweep breaks the check)
  for (uint64_t avl = vsize; avl >= vsize; avl /= 2) {
#else
  // The first point (4) warms the I-cache
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#endif
    printf("Calulating 64b faxpy with vectors with length = %lu\n", avl);
    start_timer();
    if (UNROLL)
      faxpy_v64b_unrl(a64, v64x, v64y, avl);
    else
      faxpy_v64b(a64, v64x, v64y, avl);
    stop_timer();

    // Metrics
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);
    printf("The execution took %d cycles.\n", runtime_v);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("faxpy", 64, avl, runtime_v, performance);

    if (CHECK && avl == vsize) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < vsize; i++) {
        if (fp_check((double)v64y[i], (double)gold64[i], THRESHOLD_64b)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)v64y[i], (float)gold64[i]);
        }
      }
    }
  }
#endif // FP64

#if FP32
#if CHECK || defined(NETLIST)
  // Single point (y is updated in place, so a sweep breaks the check)
  for (uint64_t avl = vsize; avl >= vsize; avl /= 2) {
#else
  // The first point (4) warms the I-cache
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#endif
    printf("Calulating 32b faxpy with vectors with length = %lu\n", avl);
    start_timer();
    if (UNROLL)
      faxpy_v32b_unrl(a32, v32x, v32y, avl);
    else
      faxpy_v32b(a32, v32x, v32y, avl);
    stop_timer();

    // Metrics
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);
    printf("The execution took %d cycles.\n", runtime_v);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("faxpy", 32, avl, runtime_v, performance);

    if (CHECK && avl == vsize) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < vsize; i++) {
        if (fp_check((double)v32y[i], (double)gold32[i], THRESHOLD_32b)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)v32y[i], (float)gold32[i]);
        }
      }
    }
  }
#endif // FP32

#if FP16
#if CHECK || defined(NETLIST)
  // Single point (y is updated in place, so a sweep breaks the check)
  for (uint64_t avl = vsize; avl >= vsize; avl /= 2) {
#else
  // The first point (4) warms the I-cache
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#endif
    printf("Calulating 16b faxpy with vectors with length = %lu\n", avl);
    start_timer();
    if (UNROLL)
      faxpy_v16b_unrl(a16, v16x, v16y, avl);
    else
      faxpy_v16b(a16, v16x, v16y, avl);
    stop_timer();

    // Metrics
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(16);
    printf("The execution took %d cycles.\n", runtime_v);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("faxpy", 16, avl, runtime_v, performance);

    if (CHECK && avl == vsize) {
      printf("Checking vector engine results...\n");
      for (unsigned int i = 0; i < vsize; i++) {
        if (fp_check((double)v16y[i], (double)gold16[i], THRESHOLD_16b)) {
          if (errors++ < MAX_ERR_PRINT)
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                   (float)v16y[i], (float)gold16[i]);
        }
      }
    }
  }
#endif // FP16

  if (errors) {
    printf("Error: %d mismatches\n", errors);
    return 1;
  }

  printf("SUCCESS.\n");

  return 0;
}
