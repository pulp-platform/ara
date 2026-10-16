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
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "kernel/log.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the vector results against the golden arrays (check=0 disables it)
#ifndef CHECK
#define CHECK 1
#endif

// f64 uses the f32 Cephes coefficients too (~1e-7 at best)
#define THRESHOLD_64b 0.0001
#define THRESHOLD_32b 0.0001
// Count all mismatches, print only the first few
#define MAX_ERR_PRINT 10

// 30 FLOP per log: 21 FP ops, the 9 fused ones counted twice
// (clamps, conversions, masks and integer ops are not counted)
#define LOG_FLOPS 30

#if !(FP64 || FP32)
#error "No precision selected: add FP64 and/or FP32 to def_args_log in common/default_args.mk"
#endif

#if FP64
extern size_t N_f64;
extern double args_f64[] __attribute__((aligned(8 * NR_LANES)));
extern double results_f64[] __attribute__((aligned(8 * NR_LANES)));
extern double gold_results_f64[] __attribute__((aligned(8 * NR_LANES)));
#endif
#if FP32
extern size_t N_f32;
extern float args_f32[] __attribute__((aligned(8 * NR_LANES)));
extern float results_f32[] __attribute__((aligned(8 * NR_LANES)));
extern float gold_results_f32[] __attribute__((aligned(8 * NR_LANES)));
#endif

// Natural logarithm (base e)
int main() {
  printf("\n");
  printf("==========\n");
  printf("=  FLOG  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  int errors = 0;
  int64_t runtime;

#if FP64
  // Sweep the length; the last, full-size run leaves the result to check
#if defined(NETLIST) || defined(VCD_DUMP)
  // Full size only for netlist and VCD runs
  for (uint64_t avl = N_f64; avl <= N_f64; avl *= 2) {
#else
  for (uint64_t avl = 4; avl <= N_f64; avl *= 2) {
#endif
    printf("Executing natural log (base e) on %lu 64-bit data...\n", avl);
    start_timer();
    log_1xf64_bmark(args_f64, results_f64, avl);
    stop_timer();

    runtime = get_timer();
    printf("The execution took %ld cycles.\n", runtime);
    float performance = (float)LOG_FLOPS * avl / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("log", 64, avl, runtime, performance);
  }

  if (CHECK) {
    printf("Checking 64-bit results:\n");
    for (uint64_t i = 0; i < N_f64; ++i) {
      if (!similarity_check(results_f64[i], gold_results_f64[i], THRESHOLD_64b)) {
        if (errors++ < MAX_ERR_PRINT)
          printf("64-bit error at index %lu. %f != %f\n", i, results_f64[i],
                 gold_results_f64[i]);
      }
    }
  }
#endif // FP64

#if FP32
  // Sweep the length; the last, full-size run leaves the result to check
#if defined(NETLIST) || defined(VCD_DUMP)
  // Full size only for netlist and VCD runs
  for (uint64_t avl = N_f32; avl <= N_f32; avl *= 2) {
#else
  for (uint64_t avl = 4; avl <= N_f32; avl *= 2) {
#endif
    printf("Executing natural log (base e) on %lu 32-bit data...\n", avl);
    start_timer();
    log_2xf32_bmark(args_f32, results_f32, avl);
    stop_timer();

    runtime = get_timer();
    printf("The execution took %ld cycles.\n", runtime);
    float performance = (float)LOG_FLOPS * avl / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("log", 32, avl, runtime, performance);
  }

  if (CHECK) {
    printf("Checking 32-bit results:\n");
    for (uint64_t i = 0; i < N_f32; ++i) {
      if (!similarity_check_32b(results_f32[i], gold_results_f32[i], THRESHOLD_32b)) {
        if (errors++ < MAX_ERR_PRINT)
          printf("32-bit error at index %lu. %f != %f\n", i, results_f32[i],
                 gold_results_f32[i]);
      }
    }
  }
#endif // FP32

  if (errors) {
    printf("Error: %d mismatches\n", errors);
    return 1;
  }
  if (CHECK)
    printf("Test result: PASS. No errors found.\n");

  return 0;
}
