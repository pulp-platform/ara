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

// Attention: Now the matrix size (exactly V_LEN) should be multiplies of NrLanes

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

#define VERIFY 1
#define THRESHOLD 0.001

// Macro to check similarity between two fp-values, wrt a threshold
static inline int fp_check(const double a, const double b) {
  const double threshold = 0.00001;

  // Absolute value
  double comp = a - b;
  if (comp < 0)
    comp = -comp;

  return comp > threshold;
}

// Define Matrix dimensions:
// C = AB with A=[M_ROWxV_LEN], B=[V_LENx1], C=[M_ROWx1]
extern uint64_t M_ROW;
extern uint64_t V_LEN;

extern double mat64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double vec64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double res64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));
extern double gold64[] __attribute__((aligned(8 * NR_LANES), section(".l2")));

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  GEMV  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  for (int s = M_ROW; s <= M_ROW; s *= 2) {
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a (%d x %d) x %d matrix vector multiplication...\n", s,
           s, s);
    printf("------------------------------------------------------------\n");
    printf("\n");

    // // Initialize Matrices
    // printf("Initializing matrix and vector...\n");
    // init_gemv_data(s, s, mat64, GEMV_V, 1, 2, 3);

    // Load-store test: load first row of mat64 into v0 (m4), store back to res64
    {
      unsigned int vl_test;
      asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(vl_test) : "r"(s));
      asm volatile("vle64.v v0, (%0)" ::"r"(mat64));
      asm volatile("vse64.v v0, (%0)" ::"r"(res64));
      printf("Load-store test (vl=%d):\n", vl_test);
      int load_err = 0;
      for (unsigned int i = 0; i < (unsigned int)s && i < vl_test; i++) {
        if (fp_check(res64[i], mat64[i])) {
          if (load_err < 5)
            printf("  LD err: idx %d -> got %f, exp %f\n", i, (float)res64[i], (float)mat64[i]);
          load_err++;
        }
      }
      if (load_err == 0) printf("  Load-store: PASS\n");
      else printf("  Load-store: %d errors\n", load_err);
      // Clear res64
      for (unsigned int i = 0; i < (unsigned int)s; i++) res64[i] = 0.0;
    }

    // Start GEMV calculating
    printf("calculating ... \n");
    start_timer();
    gemv_v64b_m4(mat64, vec64, res64, s, s, s);
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
      if (s == M_ROW) {
        printf("Checking vector engine results...\n");
        for (unsigned int i = 0; i < M_ROW; i++) {
          if (fp_check(res64[i], gold64[i])) {
            printf("Error: Index %d -> Result = %f, Expected = %f\n", i,
                  (float)res64[i], (float)gold64[i]);
          }
        }
      }
    }
  }

  printf("Done!\n");
  return 0;
}
