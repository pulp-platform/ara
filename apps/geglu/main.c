// Copyright 2026 ETH Zurich and University of Bologna.
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

#include "kernel/geglu.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the vector results against the golden arrays in data.S
#ifndef CHECK
#define CHECK 1
#endif

#define THRESHOLD 0.0001
// Count all mismatches, print only the first few
#define MAX_ERR_PRINT 10

// exp (28 FLOP) + 3 vfmul, vfmadd (2), vfadd, vfmul, vfdiv
#define GEGLU_FLOPS 36

extern uint64_t N;
extern float g[] __attribute__((aligned(4 * NR_LANES)));
extern float u[] __attribute__((aligned(4 * NR_LANES)));
extern float o[] __attribute__((aligned(4 * NR_LANES)));
extern float gold_o[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("===========\n");
  printf("=  GEGLU  =\n");
  printf("===========\n");
  printf("\n");
  printf("\n");

  int64_t runtime;
  int error = 0;

  // Sweep the size; the last, full-size run leaves the result to check
#ifdef VCD_DUMP
  // Measure only the full size
  for (uint64_t avl = N; avl <= N; avl *= 2) {
#else
  for (uint64_t avl = 4; avl <= N; avl *= 2) {
#endif
    printf("Executing GeGLU on %lu 32-bit data...\n", avl);
    start_timer();
    geglu_vec(g, u, o, avl);
    stop_timer();

    runtime = get_timer();
    printf("The execution took %ld cycles.\n", runtime);
    float flop = (float)GEGLU_FLOPS * avl;
    float performance = flop / runtime;
    float utilization = 100 * performance / (4.0 * NR_LANES);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
  }

  if (CHECK) {
    for (uint64_t i = 0; i < N; ++i) {
      if (!similarity_check_32b(o[i], gold_o[i], THRESHOLD)) {
        if (error++ < MAX_ERR_PRINT)
          printf("Error at index %lu. %f != %f\n", i, o[i], gold_o[i]);
      }
    }
    if (error)
      printf("Error: %d mismatches\n", error);
    else
      printf("Check okay. No errors.\n");
  }

  return error;
}
