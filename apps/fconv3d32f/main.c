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
#include <stdio.h>
#include <string.h>

#include "fconv3d.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#endif

// Define Matrix dimensions:
// o = i ° f, with i=[(M+F-1)x(N+f-1)xCH], f=[FxFxCH], o=[MxN]
// The filter is a square matrix, and F is odd

// Matrices defined in data.S
extern float i[] __attribute__((
    aligned(4 * NR_LANES))); // [ (M+floor(F/2)) * (N+floor(F/2)) * CH ]
extern float f[] __attribute__((aligned(4 * NR_LANES)));        // [ F*F*CH ]
extern float o[] __attribute__((aligned(4 * NR_LANES)));        // [ M*N ]
extern float golden_o[] __attribute__((aligned(4 * NR_LANES))); // [ M*N ]
// M, N, F defined in data.S
extern int64_t M;
extern int64_t N;
extern int64_t CH;
extern int64_t F;

int verify_matrix(float *matrix, float *golden_matrix, int64_t R, int64_t C, float threshold) {
  for (int64_t r = 0; r < R; ++r) {
    for (int64_t c = 0; c < C; ++c) {
      // if (1) {
      if (!similarity_check(matrix[c + C * r], golden_matrix[c + C * r], threshold)) {
        // Convert double to integer parts for matrix value
        int32_t mat_integer_part = (int32_t)matrix[c + C * r];
        int32_t mat_fractional_part = (int32_t)((matrix[c + C * r] - mat_integer_part) * 1000000);
        if (mat_fractional_part < 0) mat_fractional_part = -mat_fractional_part;

        // Convert double to integer parts for golden matrix value
        int32_t gold_integer_part = (int32_t)golden_matrix[c + C * r];
        int32_t gold_fractional_part = (int32_t)((golden_matrix[c + C * r] - gold_integer_part) * 1000000);
        if (gold_fractional_part < 0) gold_fractional_part = -gold_fractional_part;

        printf("Error: o[%lld][%lld] = %lld.%06lld, instead of %lld.%06lld\n",
               r, c, mat_integer_part, mat_fractional_part, gold_integer_part, gold_fractional_part);
        return 1;
      }
    }
  }
  return 0;
}


void print_matrix(float const *matrix, uint64_t num_rows,
                  uint64_t num_columns) {
  printf("0x%8X\n", (uint64_t)matrix);
  for (uint64_t i = 0; i < num_rows; ++i) {
    for (uint64_t j = 0; j < num_columns; ++j) {
      printf("%10f ", matrix[i * num_columns + j]);
    }
    printf("\n");
  }
}

// This one works as it omits %f. %f does not work as the format specifier apparently is not properly implemented.
void print_matrix_simple(float const *matrix, uint64_t num_rows, uint64_t num_columns) {
    for (uint64_t i = 0; i < num_rows; ++i) {
        for (uint64_t j = 0; j < num_columns; ++j) {
            // Convert double to integer parts
            int32_t integer_part = (int32_t)matrix[i * num_columns + j];
            int32_t fractional_part = (int32_t)((matrix[i * num_columns + j] - integer_part) * 1000000);
            if (fractional_part < 0) fractional_part = -fractional_part;
            
            // Print as integer and fractional parts
            printf("%d.%06d ", integer_part, fractional_part);
        }
        printf("\n");
    }
}

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  FCONV3D  =\n");
  printf("=  NOW 32f  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  printf("Input Mtx size: %dx%d\n", M + F - 1, N + F - 1);
  printf("Output Mtx size: %dx%d\n", M, N);
  printf("Filter size: %dx%d\n", F, F);
  printf("Channels: %d\n", CH);

  // Call the main kernel, and measure cycles
  start_timer();
  if (F == 7)
    fconv3d_CHx7x7(o, i, f, M, N, CH, F);
  else
    printf("Error: the filter size is different from 7.\n");
  stop_timer();

  // Performance metrics
  int64_t runtime = get_timer();
  float performance = 2.0f * CH * F * F * M * N / runtime;
  float utilization = 100 * performance / (4.0f * NR_LANES);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f DPFLOP/cycle (%f%% utilization).\n",
         performance, utilization);

  // Verify correctness
  printf("Verifying result...\n");
  int error = verify_matrix(o, golden_o, M, N, THRESHOLD);
  if (error != 0) {
    printf("Fail.\n");
  } else {
    printf("Passed.\n");
  }

  return error;
}
