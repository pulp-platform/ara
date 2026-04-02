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

// Run also the scalar benchmark
#define SCALAR 0

// Check the vector results against golden vectors
#define CHECK 0

// Macro to check similarity between two fp-values, wrt a threshold
static inline int fp_check(const double a, const double b) {
  const double threshold = 0.00001;

  // Absolute value
  double comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

// Vector size (Byte)
extern uint64_t vsize;
// Scalar input
extern double a;
// Input vectors
extern double v64x[] __attribute__((aligned(4 * NR_LANES), section(".vector")));
// Output vectors
extern double v64y[] __attribute__((aligned(4 * NR_LANES), section(".vector")));
// Golden outputs
extern double gold64[] __attribute__((aligned(4 * NR_LANES), section(".vector")));;

int main() {
// *********** NMAra Testing *********** //

  printf("\n");
  printf("===========\n");
  printf("=  FAXPY  =\n");
  printf("===========\n");
  printf("\n");
  printf("\n");

  uint64_t runtime_s, runtime_v;

  for (uint64_t avl = 8; avl <= vsize; avl *= 2) {
    printf("Calulating 64b faxpy with vectors with length = %lu\n", avl);
    start_timer();
    faxpy_v64b_unrl(a, v64x, v64y, avl);
    stop_timer();
    runtime_v = get_timer();
    // 2 FLOP per element (mul + add)
    float performance = 2.0 * avl / runtime_v;
    float utilization = 100 * performance / (2.0 * NR_LANES);
    printf("Vector runtime: %ld cycles, perf: %f FLOP/cycle (%f%% utilization)\n",
           runtime_v, performance, utilization);
  }

  printf("SUCCESS.\n");

  return 0;
}
