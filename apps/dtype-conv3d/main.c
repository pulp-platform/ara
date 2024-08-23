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

#include "runtime.h"

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
    "Please explicitly define DTYPE and force-build with '-B'. Example command: make -B bin/dtype-conv3d ENV_DEFINES='-DDTYPE=FLOAT64' def_args_dtype-conv3d='112 7 float64'. Compiling now under the assumption of DTYPE == FLOAT64"
#define DTYPE FLOAT64
#endif

#if DTYPE == FLOAT64
typedef double _DTYPE;
#define _KERNEL dp_fconv3d_CHx7x7
#define _VERIFY dp_fconv3d_verify
#include "kernel/dp-fconv3d.h"
#elif DTYPE == FLOAT32
typedef float _DTYPE;
#define _KERNEL sp_fconv3d_CHx7x7
#define _VERIFY sp_fconv3d_verify
#include "kernel/sp-fconv3d.h"
#elif DTYPE == FLOAT16
typedef _Float16 _DTYPE;
#define _KERNEL hp_fconv3d_CHx7x7
#define _VERIFY hp_fconv3d_verify
#include "kernel/hp-fconv3d.h"
#elif DTYPE == INT64
typedef int64_t _DTYPE;
#define _KERNEL dp_iconv3d_CHx7x7
#define _VERIFY dp_iconv3d_verify
#include "kernel/dp-iconv3d.h"
#elif DTYPE == INT32
typedef int32_t _DTYPE;
#define _KERNEL sp_iconv3d_CHx7x7
#define _VERIFY sp_iconv3d_verify
#include "kernel/sp-iconv3d.h"
#elif DTYPE == INT16
typedef int16_t _DTYPE;
#define _KERNEL hp_iconv3d_CHx7x7
#define _VERIFY hp_iconv3d_verify
#include "kernel/hp-iconv3d.h"
#elif DTYPE == INT8
typedef int8_t _DTYPE;
#define _KERNEL bp_iconv3d_CHx7x7
#define _VERIFY bp_iconv3d_verify
#include "kernel/bp-iconv3d.h"
#else
#error "Unsupported data type"
#endif

// Define Matrix dimensions:
// o = i ° f, with i=[(M+F-1)x(N+f-1)xCH], f=[FxFxCH], o=[MxN]
// The filter is a square matrix, and F is odd

// Matrices defined in data.S
extern _DTYPE i[] __attribute__((
    aligned(4 * NR_LANES))); // [ (M+floor(F/2)) * (N+floor(F/2)) * CH ]
extern _DTYPE f[] __attribute__((aligned(4 * NR_LANES)));        // [ F*F*CH ]
extern _DTYPE o[] __attribute__((aligned(4 * NR_LANES)));        // [ M*N ]
extern _DTYPE golden_o[] __attribute__((aligned(4 * NR_LANES))); // [ M*N ]
// M, N, F defined in data.S
extern int64_t M;
extern int64_t N;
extern int64_t CH;
extern int64_t F;

int main() {
  printf("\n");
  printf("============\n");
  printf("=  CONV3D  =\n");
  printf("============\n");
  printf("\n");
  printf("\n");

  printf("Input Mtx size: %dx%d\n", M + F - 1, N + F - 1);
  printf("Output Mtx size: %dx%d\n", M, N);
  printf("Filter size: %dx%d\n", F, F);
  printf("Channels: %d\n", CH);
  printf("Data width: %s\n", DATA_WIDTH);

  // Call the main kernel, and measure cycles
  start_timer();
  if (F == 7)
    _KERNEL(o, i, f, M, N, CH, F);
  else
    printf("Error: the filter size is different from 7.\n");
  stop_timer();

  // Performance metrics
  int64_t runtime = get_timer();
  float performance = 2.0 * CH * F * F * M * N / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES * DTYPE_FACTOR);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f %s-OP/cycle (%f%% utilization).\n", performance,
         DTYPE_PREFIX, utilization);

  // Verify correctness
  printf("Verifying result...\n");
  int error = _VERIFY(o, golden_o, M, N, THRESHOLD);
  if (error != 0) {
    printf("Fail.\n");
  } else {
    printf("Passed.\n");
  }

  return error;
}
