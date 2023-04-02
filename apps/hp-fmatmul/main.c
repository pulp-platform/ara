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

// Author: Matheus Cavalcante, ETH Zurich
//         Samuel Riedel, ETH Zurich

#include <stdint.h>
#include <string.h>

#include "data/data_gemm.h"
#include "kernel/matmul.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#endif

// Initialize the matrices
void init_matrix(_Float16 *matrix, const _Float16 *src,
                 const unsigned int rows_start, const unsigned int rows_end,
                 const unsigned int num_columns) {
  for (unsigned int i = rows_start; i < rows_end; ++i) {
    for (unsigned int j = 0; j < num_columns; ++j) {
      matrix[i * num_columns + j] = src[i * num_columns + j];
    }
  }
}

// Verify the matrices
int verify_matrix(_Float16 *matrix, const _Float16 *checksum,
                  const unsigned int num_rows, const unsigned int num_columns) {
  for (unsigned int i = 0; i < num_rows; ++i) {
    _Float16 sum = 0;
    for (unsigned int j = 0; j < num_columns; ++j) {
      sum += *((_Float16 *)matrix + i * num_columns + j);
    }

    _Float16 diff = sum - *((_Float16 *)checksum + i);
    if (diff < 0)
      diff = -diff;
    if (diff > 0.001) {
      return i == 0 ? -1 : (int)i;
    }
  }
  return 0;
}

int main() {
  printf("\n");
  printf("============\n");
  printf("=  MATMUL  =\n");
  printf("============\n");
  printf("\n");
  printf("\n");

  const _Float16 *a = gemm_A_dram;
  const _Float16 *b = gemm_B_dram;
  _Float16 *c = gemm_C_dram;

  const unsigned int M = gemm_l.M;
  const unsigned int N = gemm_l.N;
  const unsigned int P = gemm_l.K;

  printf("\n");
  printf("------------------------------------------------------------\n");
  printf("Calculating a (%d x %d) x (%d x %d) matrix multiplication...\n", M, P,
         P, N);
  printf("------------------------------------------------------------\n");
  printf("\n");

  // Matrices are initialized --> Start calculating
  printf("Calculating matmul...\n");
  int unsigned loop_cont = 1;
  do {
    matmul(c, a, b, M, P, N);
  } while (--loop_cont != 0);

  start_timer();
  matmul(c, a, b, M, P, N);
  stop_timer();

  // Metrics
  int runtime = get_timer();
  float performance = 2.0 * M * N * P / runtime;
  float utilization = 100 * performance / (2.0 * 4 * NR_LANES);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f OP/cycle (%f%% utilization).\n", performance,
         utilization);

  // Contaminate the next runs
  for (unsigned int i = 0; i < M; ++i) {
    gemm_A_dram[i] = 0;
  }

  // Verify the result
  printf("Verifying result...\n");
  int error = verify_matrix(c, (const _Float16 *)gemm_checksum, M, N);
  if (error != 0) {
    printf("Error code %d\n", error);
    printf("c[%d]=%d\n", error, c[error]);
    return error;
  } else {
    printf("Passed.\n");
  }

  return 0;
}
