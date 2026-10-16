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

// Check the result against the golden matrix (check=0 in make disables it)
#ifndef CHECK
#define CHECK 1
#endif

#define THRESHOLD_64b 0.001
#define THRESHOLD_32b 0.001
#define THRESHOLD_16b 0.01

#if !(FP64 || FP32 || FP16)
#error "No precision selected: add e.g. FP64 to def_args_fmatmul in common/default_args.mk"
#endif

// C = AB with A=[MxN], B=[NxP], C=[MxP]
extern uint64_t M;
extern uint64_t N;
extern uint64_t P;

#if FP64
extern double a64[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double b64[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double c64[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double g64[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
#endif
#if FP32
extern float a32[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float b32[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float c32[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float g32[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
#endif
#if FP16
extern _Float16 a16[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _Float16 b16[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _Float16 c16[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _Float16 g16[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
#endif

// Returns 0 on success, else the first mismatching index (-1 for index 0)
#define DEFINE_VERIFY(SUF, TY)                                                 \
  int verify_matrix##SUF(TY *result, TY *gold, size_t R, size_t C,             \
                         double threshold) {                                   \
    for (uint64_t i = 0; i < R; ++i) {                                         \
      for (uint64_t j = 0; j < C; ++j) {                                       \
        uint64_t idx = i * C + j;                                              \
        if (!similarity_check((double)result[idx], (double)gold[idx],          \
                              threshold)) {                                    \
          return (i + j) == 0 ? -1 : idx;                                      \
        }                                                                      \
      }                                                                        \
    }                                                                          \
    return 0;                                                                  \
  }
#if FP64
DEFINE_VERIFY(64, double)
#endif
#if FP32
DEFINE_VERIFY(32, float)
#endif
#if FP16
DEFINE_VERIFY(16, _Float16)
#endif

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  FMATMUL  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

#if FP64
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size matmul
  for (uint64_t p = P; p <= P; p *= 2) {
#else
  // Sweep p at full M and N (p = 4 warms the I-cache)
  for (uint64_t p = 4; p <= P; p *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 64-bit (%d x %d) x (%d x %d) matrix multiplication...\n",
           M, N, N, p);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    fmatmul(c64, a64, b64, M, N, p);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M * N * p / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(64);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fmatmul", 64, p, runtime, performance);

    // Verify only the full-size pass: smaller p alias rows of B and C
    if (CHECK && p == P) {
      printf("Verifying 64-bit result...\n");
      int error = verify_matrix64(c64, g64, M, P, THRESHOLD_64b);
      if (error != 0) {
        printf("Error code %d\n", error);
        printf("c[%d]=%f\n", error, (float)c64[error < 0 ? 0 : error]);
        return error;
      } else {
        printf("Passed.\n");
      }
    }
  }
#endif // FP64

#if FP32
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size matmul
  for (uint64_t p = P; p <= P; p *= 2) {
#else
  // Sweep p at full M and N (p = 4 warms the I-cache)
  for (uint64_t p = 4; p <= P; p *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 32-bit (%d x %d) x (%d x %d) matrix multiplication...\n",
           M, N, N, p);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    fmatmul32(c32, a32, b32, M, N, p);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M * N * p / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(32);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fmatmul", 32, p, runtime, performance);

    // Verify only the full-size pass: smaller p alias rows of B and C
    if (CHECK && p == P) {
      printf("Verifying 32-bit result...\n");
      int error = verify_matrix32(c32, g32, M, P, THRESHOLD_32b);
      if (error != 0) {
        printf("Error code %d\n", error);
        printf("c[%d]=%f\n", error, (float)c32[error < 0 ? 0 : error]);
        return error;
      } else {
        printf("Passed.\n");
      }
    }
  }
#endif // FP32

#if FP16
#if defined(NETLIST) || defined(VCD_DUMP)
  // Measure only the full-size matmul
  for (uint64_t p = P; p <= P; p *= 2) {
#else
  // Sweep p at full M and N (p = 4 warms the I-cache)
  for (uint64_t p = 4; p <= P; p *= 2) {
#endif
    printf("\n");
    printf("------------------------------------------------------------\n");
    printf("Calculating a 16-bit (%d x %d) x (%d x %d) matrix multiplication...\n",
           M, N, N, p);
    printf("------------------------------------------------------------\n");
    printf("\n");

    start_timer();
    fmatmul16(c16, a16, b16, M, N, p);
    stop_timer();

    // Metrics
    int64_t runtime = get_timer();
    float performance = 2.0 * M * N * p / runtime;
    float utilization = 100 * performance / PEAK_FLOP_CYCLE(16);

    printf("The execution took %d cycles.\n", runtime);
    printf("The performance is %f FLOP/cycle (%f%% utilization).\n",
           performance, utilization);
    PRINT_SWEEP("fmatmul", 16, p, runtime, performance);

    // Verify only the full-size pass: smaller p alias rows of B and C
    if (CHECK && p == P) {
      printf("Verifying 16-bit result...\n");
      int error = verify_matrix16(c16, g16, M, P, THRESHOLD_16b);
      if (error != 0) {
        printf("Error code %d\n", error);
        printf("c[%d]=%f\n", error, (float)c16[error < 0 ? 0 : error]);
        return error;
      } else {
        printf("Passed.\n");
      }
    }
  }
#endif // FP16

  return 0;
}
