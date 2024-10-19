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

#include <stdint.h>
#include <string.h>

#include "kernel/gemv.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#define M_ROW 1024
#define V_LEN 1024
double GEMV_M[M_ROW * V_LEN]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
double GEMV_D[M_ROW] __attribute__((aligned(4 * NR_LANES), section(".l2")));
double GEMV_V[V_LEN] __attribute__((aligned(4 * NR_LANES), section(".l2")));

#define VERIFY 1

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  GEMV  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  for (int s = 4; s <= M_ROW; s *= 2) {
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a (%d x %d) x %d matrix vector multiplication...\n", s,
           s, s);
    printf("------------------------------------------------------------\n");
    printf("\n");

    // Initialize Matrices
    printf("Initializing matrix and vector...\n");
    init_gemv_data(s, s, GEMV_M, GEMV_V, 1, 2, 3);

    // Start GEMV calculating
    printf("calculating ... \n");
    start_timer();
    gemv_rowwise(s, s, GEMV_M, GEMV_V, GEMV_D);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * s * s / runtime;
    float utilization = 100 * performance / (2.0 * NR_LANES);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization) at %d lanes.\n",
           performance, utilization, NR_LANES);

    // Verify the result
    if (VERIFY) {
      printf("Verifying ...\n");
      if (gemv_verify(s, s, GEMV_M, GEMV_V, GEMV_D)) {
        return 1;
      } else {
        printf("Passed.\n");
      }
    }
  }

  printf("Done!\n");
  return 0;
}
