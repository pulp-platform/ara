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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "runtime.h"
#include "util.h"

#include "kernel/fdotproduct.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Threshold for FP comparisons
#define THRESHOLD_64b 0.0000000001
#define THRESHOLD_32b 0.01
// FP16 is checked with a relative threshold (its ulp grows with the sum)
#define REL_THRESHOLD_16b 0.01

// Run also the scalar benchmark
#define SCALAR 0

// Check the vector results against golden vectors (check=0 in make disables it)
#ifndef CHECK
#define CHECK 1
#endif

// Whether to use the unrolling fdotp kernel
#define UNROLL 1

#if FP16
static inline int rel_check(double a, double b, double rel) {
  double d = a - b, m = b < 0 ? -b : b;
  return (d < 0 ? -d : d) <= rel * m;
}
#endif

#if !(FP64 || FP32 || FP16)
#error "No precision selected: add e.g. FP64 to def_args_fdotproduct in common/default_args.mk"
#endif

// Vector size (Byte)
extern uint64_t vsize;
#if FP64
extern double v64a[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern double v64b[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern double gold64;
extern double res64_v, res64_s;
#endif
#if FP32
extern float v32a[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern float v32b[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern float gold32;
extern float res32_v, res32_s;
#endif
#if FP16
extern _Float16 v16a[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern _Float16 v16b[] __attribute__((aligned(64 * NR_LANES), section(".l2")));
extern _Float16 gold16;
extern _Float16 res16_v, res16_s;
#endif

int main() {
  printf("\n");
  printf("===========\n");
  printf("=  FDOTP  =\n");
  printf("===========\n");
  printf("\n");
  printf("\n");

  uint64_t runtime_s, runtime_v;
  (void)runtime_s;

  // The first point (4) warms the I-cache
#if FP64
#ifndef NETLIST
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#else
  for (uint64_t avl = vsize; avl <= vsize; avl *= 2) {
#endif
    if (UNROLL) {
      printf("Calulating 64b unrolled dotp with vectors with length = %lu\n", avl);
      start_timer();
      res64_v = fdotp_v64b_m8_unrl(v64a, v64b, avl);
      stop_timer();
    } else {
      printf("Calulating 64b dotp with vectors with length = %lu\n", avl);
      start_timer();
      res64_v = fdotp_v64b(v64a, v64b, avl);
      stop_timer();
    }

    // Metrics - Vector core execution
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fdotproduct", 64, avl, runtime_v, performance);

    if (SCALAR) {
      start_timer();
      res64_s = fdotp_s64b(v64a, v64b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK && avl == vsize) {
      if (SCALAR) {
        printf("Checking results: v = %f, s = %f\n", res64_v, res64_s);
        if (!similarity_check(res64_v, res64_s, THRESHOLD_64b)) {
          printf("Error: v = %f, s = %f\n", res64_v, res64_s);
          return -1;
        }
      } else {
        // gold64 is the dot product over the WHOLE vector, so it is only a
        // valid reference for the full-length iteration.
        printf("Checking results: v = %f, gold = %f\n", res64_v, gold64);
        if (!similarity_check(res64_v, gold64, THRESHOLD_64b)) {
          printf("Error: v = %f, gold = %f\n", res64_v, gold64);
          return -1;
        }
      }
    }
  }
#endif // FP64

#if FP32
#ifndef NETLIST
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#else
  for (uint64_t avl = vsize; avl <= vsize; avl *= 2) {
#endif
    printf("Calulating 32b dotp with vectors with length = %lu\n", avl);
    start_timer();
    if (UNROLL)
      res32_v = fdotp_v32b_m8_unrl(v32a, v32b, avl);
    else
      res32_v = fdotp_v32b(v32a, v32b, avl);
    stop_timer();

    // Metrics - Vector core execution
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fdotproduct", 32, avl, runtime_v, performance);

    if (SCALAR) {
      start_timer();
      res32_s = fdotp_s32b(v32a, v32b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK && avl == vsize) {
      if (SCALAR) {
        printf("Checking results: v = %f, s = %f\n", res32_v, res32_s);
        if (!similarity_check(res32_v, res32_s, THRESHOLD_32b)) {
          printf("Error: v = %f, s = %f\n", res32_v, res32_s);
          return -1;
        }
      } else {
        printf("Checking results: v = %f, gold = %f\n", res32_v, gold32);
        if (!similarity_check(res32_v, gold32, THRESHOLD_32b)) {
          printf("Error: v = %f, gold = %f\n", res32_v, gold32);
          return -1;
        }
      }
    }
  }
#endif // FP32

#if FP16
#ifndef NETLIST
  for (uint64_t avl = 4; avl <= vsize; avl *= 2) {
#else
  for (uint64_t avl = vsize; avl <= vsize; avl *= 2) {
#endif
    printf("Calulating 16b dotp with vectors with length = %lu\n", avl);
    start_timer();
    if (UNROLL)
      res16_v = fdotp_v16b_m8_unrl(v16a, v16b, avl);
    else
      res16_v = fdotp_v16b(v16a, v16b, avl);
    stop_timer();

    // Metrics - Vector core execution
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(16);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fdotproduct", 16, avl, runtime_v, performance);

    if (SCALAR) {
      start_timer();
      res16_s = fdotp_s16b(v16a, v16b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK && avl == vsize) {
      if (SCALAR) {
        printf("Checking results: v = %x, s = %x\n", *((uint16_t *)&res16_v),
               *((uint16_t *)&res16_s));
        if (!rel_check(res16_v, res16_s, REL_THRESHOLD_16b)) {
          printf("Error: v = %x, s = %x\n", *((uint16_t *)&res16_v),
                 *((uint16_t *)&res16_s));
          return -1;
        }
      } else {
        printf("Checking results: v = %x, gold = %x\n", *((uint16_t *)&res16_v),
               *((uint16_t *)&gold16));
        if (!rel_check(res16_v, gold16, REL_THRESHOLD_16b)) {
          printf("Error: v = %x, gold = %x\n", *((uint16_t *)&res16_v),
                 *((uint16_t *)&gold16));
          return -1;
        }
      }
    }
  }
#endif // FP16

  printf("SUCCESS.\n");

  return 0;
}
