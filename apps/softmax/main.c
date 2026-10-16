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

#include "kernel/softmax.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Run the hand-assembly kernel (1) or the intrinsics kernel (0)
#define ASSEMBLY 1

// Check the vector results against the scalar reference
#ifndef CHECK
#define CHECK 1
#endif

// Sanity check to see that there are some precision differences
// between the two algorithms
// #define SANITY_CHECK

// Sanity check to see the results
// #define PRINT_RESULTS

#define THRESHOLD 0.0001
// Count all mismatches, print only the first few
#define MAX_ERR_PRINT 10

// exp: 22 FLOP (15 FP ops, the 7 fused ones counted twice)
// Per channel and inner element: vfsub + exp + vfadd + vfmul
#define EXP_FLOPS 22
#define SOFTMAX_FLOPS_PER_CH (EXP_FLOPS + 3)

#if !(FP32)
#error "No precision selected: add FP32 to def_args_softmax in common/default_args.mk"
#endif

extern uint64_t channels;
extern uint64_t innerSize;
extern float i[] __attribute__((aligned(4 * NR_LANES)));
extern float buf[] __attribute__((aligned(4 * NR_LANES)));
extern float o_s[] __attribute__((aligned(4 * NR_LANES)));
extern float o_v[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  SOFTMAX  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  printf("Channels: %lu\nInner Size: %lu\n", channels, innerSize);

  int64_t runtime;
  int error = 0;

  if (CHECK) {
    printf("Scalar Softmax...\n");
    start_timer();
    softmax(i, o_s, buf, channels, innerSize);
    stop_timer();

    runtime = get_timer();
    printf("The scalar SOFTMAX execution took %ld cycles.\n", runtime);
  }

  // Sweep the inner size. The small sizes warm up the I-cache, so only the
  // last, full-size iteration is worth quoting. innerSize is assumed to be a
  // power of two >= 8 so the sweep lands exactly on it (def_args_softmax).
#if defined(NETLIST) || defined(VCD_DUMP)
  // Full size only for netlist and VCD runs
  for (uint64_t isize = innerSize; isize <= innerSize; isize *= 2) {
#else
  for (uint64_t isize = 4; isize <= innerSize; isize *= 2) {
#endif
    printf("Vector Softmax, channels = %lu, innerSize = %lu...\n", channels,
           isize);
    start_timer();
    if (ASSEMBLY) {
      softmax_vec_asm(i, o_v, channels, isize);
    } else {
      softmax_vec(i, o_v, channels, isize);
    }
    stop_timer();

    runtime = get_timer();
    printf("The vector Softmax execution took %ld cycles.\n", runtime);

    // Plus (channels - 1) vfmax per inner element for the max
    float flop =
        (float)isize * (SOFTMAX_FLOPS_PER_CH * channels + (channels - 1));
    float performance = flop / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("softmax", 32, isize, runtime, performance);
  }

#ifdef PRINT_RESULTS
  for (uint64_t k = 0; k < channels * innerSize; ++k) {
    printf("%lu) Vector, Scalar: %x, %x\n", k, *((uint32_t *)&(o_v[k])),
           *((uint32_t *)&(o_s[k])));
  }
#endif

  if (CHECK) {
    // o_s is the scalar reference at the full inner size, which is what the
    // last sweep iteration left in o_v.
    for (uint64_t k = 0; k < channels * innerSize; ++k) {
#ifdef SANITY_CHECK
      if (o_s[k] != o_v[k]) {
#else
      if (!similarity_check(o_s[k], o_v[k], THRESHOLD)) {
#endif
        if (error++ < MAX_ERR_PRINT)
          printf("Error at index %d. %f != %f\n", k, o_v[k], o_s[k]);
      }
    }
    if (error)
      printf("Error: %d mismatches\n", error);
    else
      printf("Check okay. No errors.\n");
  }

  return error;
}
