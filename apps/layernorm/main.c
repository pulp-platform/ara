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

#include "kernel/layernorm.h"

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

#define EPS 1e-5f

extern uint64_t R;
extern uint64_t D;
extern float x[] __attribute__((aligned(4 * NR_LANES)));
extern float gamma_v[] __attribute__((aligned(4 * NR_LANES)));
extern float beta_v[] __attribute__((aligned(4 * NR_LANES)));
extern float y[] __attribute__((aligned(4 * NR_LANES)));
extern float gold_y[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("===============\n");
  printf("=  LAYERNORM  =\n");
  printf("===============\n");
  printf("\n");
  printf("\n");

  printf("Rows: %lu\nHidden size: %lu\n", R, D);

  int64_t runtime;
  int error = 0;
  uint64_t vlmax = __riscv_vsetvlmax_e32m8();

  // Sweep the size; the last, full-size run leaves the result to check
#ifdef VCD_DUMP
  // Measure only the full size
  for (uint64_t d = D; d <= D; d *= 2) {
#else
  for (uint64_t d = 4; d <= D; d *= 2) {
#endif
    printf("Vector LayerNorm, rows = %lu, d = %lu...\n", R, d);
    start_timer();
    layernorm_vec(x, gamma_v, beta_v, y, R, d, EPS);
    stop_timer();

    runtime = get_timer();
    printf("The vector LayerNorm execution took %ld cycles.\n", runtime);

    // Per row: vfadd (1), vfsub + vfmacc (3), two vfmadd (4) and two
    // vfredusum over min(d, VLMAX)
    float flop = (float)R * (8 * d + 2 * (d < vlmax ? d : vlmax));
    float performance = flop / runtime;
    float utilization = 100 * performance / (4.0 * NR_LANES);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
  }

  if (CHECK) {
    for (uint64_t k = 0; k < R * D; ++k) {
      if (!similarity_check_32b(y[k], gold_y[k], THRESHOLD)) {
        if (error++ < MAX_ERR_PRINT)
          printf("Error at index %lu. %f != %f\n", k, y[k], gold_y[k]);
      }
    }
    if (error)
      printf("Error: %d mismatches\n", error);
    else
      printf("Check okay. No errors.\n");
  }

  return error;
}
