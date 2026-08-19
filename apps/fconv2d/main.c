// Copyright 2020 ETH Zurich and University of Bologna.
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

// Author: Matteo Perotti

#include <stdint.h>
#include <string.h>

#include "fconv2d.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the result against the golden output
#define CHECK 1

// Define Matrix dimensions:
// o = i ° f, with i=[MxN], f=[FxF], o=[MxN]
// The filter is a square matrix, and F is odd

// Matrices defined in data.S
extern double i[] __attribute__((
    aligned(4 * NR_LANES))); // [ (M+floor(F/2)) * (N+floor(F/2)) ]
extern double f[] __attribute__((aligned(4 * NR_LANES)));        // [ F*F ]
extern double o[] __attribute__((aligned(4 * NR_LANES)));        // [ M*N ]
extern double golden_o[] __attribute__((aligned(4 * NR_LANES))); // [ M*N ]
// M, N, F defined in data.S
extern int64_t M;
extern int64_t N;
extern int64_t F;

// Verify the matrices
int verify_matrix(double *matrix, double *golden_matrix, int64_t R, int64_t C,
                  double threshold) {
  for (int r = 0; r < R; ++r)
    for (int c = 0; c < C; ++c)
      if (!similarity_check(matrix[c + C * r], golden_matrix[c + C * r],
                            threshold)) {
        printf("Error: o[%d][%d] = %lf, instead of %lf\n", r, c,
               matrix[c + C * r], golden_matrix[c + C * r]);
        return 1;
      }
  return 0;
}

void print_matrix(double const *matrix, uint64_t num_rows,
                  uint64_t num_columns) {
  printf("0x%8X\n", (uint64_t)matrix);
  for (uint64_t i = 0; i < num_rows; ++i) {
    for (uint64_t j = 0; j < num_columns; ++j) {
      printf("%10f ", matrix[i * num_columns + j]);
    }
    printf("\n");
  }
}

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  FCONV2D  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  int error = 0;
  int64_t runtime;

  // Sweep the number of output rows. The small sizes warm up the I-cache, so
  // only the last, full-size iteration is worth quoting. Every swept size must
  // be a multiple of the kernel's 4-row output block, so M must be divisible
  // by 16 (M = 112 for def_args_fconv2d).
  for (int64_t rows = M / 4; rows <= M; rows *= 2) {
    printf("Calculating a %ldx%ld convolution with a %ldx%ld filter...\n", rows,
           N, F, F);
    start_timer();
    if (F == 3)
      fconv2d_3x3(o, i, f, rows, N, F);
    else if (F == 7)
      fconv2d_7x7(o, i, f, rows, N, F);
    else
      printf("Error: the filter size is different from 3 or 5 or 7.\n");
    stop_timer();

    // Performance metrics
    runtime = get_timer();
    float performance = 2.0 * F * F * rows * N / runtime;
    float utilization = 100 * performance / (2.0 * NR_LANES);

    printf("The execution took %ld cycles.\n", runtime);
    printf("The performance is %f DPFLOP/cycle (%f%% utilization).\n",
           performance, utilization);
  }

  if (CHECK) {
    // golden_o is the reference at the full size, which is what the last sweep
    // iteration left in o.
    printf("Verifying result...\n");
    error = verify_matrix(o, golden_o, M, N, THRESHOLD);
    if (error != 0) {
      printf("Fail.\n");
    } else {
      printf("Passed.\n");
    }
  }

  return error;
}
