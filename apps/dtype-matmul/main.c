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
#include <stdio.h>
#include <string.h>

#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#endif

// Define the different data types
#define FLOAT64 1
#define FLOAT32 2
#define FLOAT16 3
#define INT64 4
#define INT32 5
#define INT16 6
#define INT8 7

// Map DTYPE to the actual data type
#ifndef DTYPE
#warning                                                                       \
    "Please explicitly define DTYPE. Example command: make bin/dtype-matmul ENV_DEFINES='-DDTYPE=FLOAT64' def_args_dtype-matmul='float64 128 128 128'. Compiling now under the assumption of DTYPE == FLOAT64"
#define DTYPE FLOAT64
#endif

#if DTYPE == FLOAT64
typedef double _DTYPE;
#define _KERNEL dp_fmatmul
#define _VERIFY dp_fmatmul_verify
#include "kernel/dp-fmatmul.h"
#elif DTYPE == FLOAT32
typedef float _DTYPE;
#define _KERNEL sp_fmatmul
#define _VERIFY sp_fmatmul_verify
#include "kernel/sp-fmatmul.h"
#elif DTYPE == FLOAT16
typedef _Float16 _DTYPE;
#define _KERNEL hp_fmatmul
#define _VERIFY hp_fmatmul_verify
#include "kernel/hp-fmatmul.h"
#elif DTYPE == INT64
typedef int64_t _DTYPE;
#define _KERNEL dp_imatmul
#define _VERIFY dp_imatmul_verify
#include "kernel/dp-imatmul.h"
#elif DTYPE == INT32
typedef int32_t _DTYPE;
#define _KERNEL sp_imatmul
#define _VERIFY sp_imatmul_verify
#include "kernel/sp-imatmul.h"
#elif DTYPE == INT16
typedef int16_t _DTYPE;
#define _KERNEL hp_imatmul
#define _VERIFY hp_imatmul_verify
#include "kernel/hp-imatmul.h"
#elif DTYPE == INT8
typedef int8_t _DTYPE;
#define _KERNEL bp_imatmul
#define _VERIFY bp_imatmul_verify
#include "kernel/bp-imatmul.h"
#else
#error "Unsupported data type"
#endif

// Define Matrix dimensions:
// C = AB with A=[MxN], B=[NxP], C=[MxP]
extern uint64_t M;
extern uint64_t N;
extern uint64_t P;

extern _DTYPE a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _DTYPE b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _DTYPE c[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _DTYPE g[] __attribute__((aligned(32 * NR_LANES), section(".l2")));

int main() {
  printf("\n");
  printf("============\n");
  printf("=  MATMUL  =\n");
  printf("============\n");
  printf("\n");
  printf("\n");

  printf("\n");
  printf("------------------------------------------------------------\n");
  printf("Calculating a (%d x %d) x (%d x %d) matrix multiplication...\n", M, N,
         N, P);
  printf("------------------------------------------------------------\n");
  printf("\n");

  // Matrices are initialized --> Start calculating
  printf("Calculating matmul...\n");
  int unsigned loop_cont = 1;
  do {
    _KERNEL(c, a, b, M, N, P);
  } while (--loop_cont != 0);

  start_timer();
  _KERNEL(c, a, b, M, N, P);
  stop_timer();

  // Metrics
  int runtime = get_timer();
  float performance = 2.0 * M * N * P / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES * DTYPE_FACTOR);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f FLOP/cycle (%f%% utilization).\n", performance,
         utilization);

  // Verify the result
  printf("Verifying result...\n");
  int error = _VERIFY(c, g, M, P, THRESHOLD);
  if (error != 0) {
    unsigned int idx = error == -1 ? 0 : error;
    printf("Error code %d\n", error);
    printf("c[%d]=%d\n", idx, c[idx]);
    return 1;
  } else {
    printf("Passed.\n");
  }

  return 0;
}
