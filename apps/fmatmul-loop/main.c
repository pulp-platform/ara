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
//         Matteo Perotti, ETH Zurich

#include <string.h>

#include "kernel/fmatmul.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Define Matrix dimensions:
// C = AB with A=[MxN], B=[NxP], C=[MxP]
extern uint64_t M;
extern uint64_t N;
extern uint64_t P;

extern double a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double c[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
// Gold results
extern double g[] __attribute__((aligned(32 * NR_LANES), section(".l2")));

#define THRESHOLD 0.001

// Verify the matrix
int verify_matrix(double *result, double *gold, size_t R, size_t C,
                  double threshold) {
  for (uint64_t i = 0; i < R; ++i) {
    for (uint64_t j = 0; j < C; ++j) {
      uint64_t idx = i * C + j;
      if (!similarity_check(result[idx], gold[idx], threshold)) {
        return (i + j) == 0 ? -1 : idx;
      }
    }
  }
  return 0;
}

int main(int argc, char **argv) {
  printf("\n");
  printf("==================\n");
  printf("=  FMATMUL LOOP  =\n");
  printf("==================\n");
  printf("\n");
  printf("\n");

  printf("Notes: verification possible only for matrices with dimensions (%d%d "
         "* %d%d)\n",
         M, N, N, P);

  uint64_t sizeM;
  uint64_t sizeN;
  uint64_t sizeK;
  uint64_t warm_iter;
  uint64_t check;

  if (argc != 6) {
    printf("Error: please, specify matrix size (MK * KN = MN, i.e., K is the "
           "reduction dim), number of warm-up iterations, and check.\n");
    printf("Usage: ./fmamtul ${sizeM} ${sizeN} ${sizeK} ${warm_up_iter} "
           "${check}\n");
    printf("Example: ./fmamtul-loop 128 128 128 3 1\n");
    return -1;
  } else {
#ifdef ARA_LINUX
    sizeM = atoi(argv[1]);
    sizeN = atoi(argv[2]);
    sizeK = atoi(argv[3]);
    warm_iter = atoi(argv[4]);
    check = atoi(argv[5]);
#else
    printf("Error: please, specify matrix size (MK * KN = MN, i.e., K is the "
           "reduction dim), number of warm-up iterations, and check.\n");
    sizeM = M;
    sizeN = P;
    sizeK = N;
    warm_iter = 3;
    check = 1;
#endif
  }

  // Measure only the full-size matmul
  printf("\n");
  printf("------------------------------------------------------------\n");
  printf("Calculating a (%d x %d) x (%d x %d) matrix multiplication...\n",
         sizeM, sizeK, sizeK, sizeN);
  printf("------------------------------------------------------------\n");
  printf("\n");

  // Matrices are initialized --> Start calculating
  printf("Calculating fmatmul with %d warm-up iterations...\n", warm_iter);

  // Warm-up
  for (int i = 0; i < warm_iter; ++i) {
    fmatmul(c, a, b, sizeM, sizeK, sizeN);
  }

  // Run kernel
  start_timer();
  fmatmul(c, a, b, sizeM, sizeK, sizeN);
  stop_timer();

  // Metrics
  int64_t runtime = get_timer();
  float performance = 2.0 * sizeM * sizeN * sizeK / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f FLOP/cycle (%f%% utilization).\n", performance,
         utilization);

  // Verify the result only for s == M (to keep it simple)
  if (check) {
    printf("Verifying result...\n");
    int error = verify_matrix(c, g, sizeM, sizeN, THRESHOLD);
    if (error != 0) {
      printf("Error code %d\n", error);
      printf("c[%d]=%d\n", error, c[error]);
      return error;
    } else {
      printf("Passed.\n");
    }
  }

  return 0;
}
