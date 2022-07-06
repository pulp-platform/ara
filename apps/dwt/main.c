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

// Author: Matteo Perotti, ETH Zurich

#include <stdint.h>
#include <string.h>

#include "kernel/wavelet.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

#define CHECK
// #define DEBUG

// For benchmarking purposes
#define FILTER_COEFF 2

// Measure performance of the first run only
#define FIRST_ITER_ONLY 1
#undef FIRST_ITER_ONLY

#define THRESHOLD 0.01

extern uint64_t DWT_LEN;
extern float data_s[] __attribute__((aligned(4 * NR_LANES)));
extern float data_v[] __attribute__((aligned(4 * NR_LANES)));
extern float buf[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("=========\n");
  printf("=  DWT  =\n");
  printf("=========\n");
  printf("\n");
  printf("\n");

  int64_t runtime;
  float performance, max_performance, max_performance_stride_bw;
  float bw, stride_bw, dwt_eff_stride_bw;
  float arith_intensity;
  uint64_t num_ops, num_bytes;
  int error = 0;
  int first_iter_only;

#ifdef FIRST_ITER_ONLY
  first_iter_only = 1;
#else
  first_iter_only = 0;
#endif

  printf("Computing DWT with %u samples\n", DWT_LEN);

#ifdef DEBUG
  for (int i = 0; i < DWT_LEN; ++i) {
    printf("data_s[%d] = %f\n", i, data_s[i]);
    printf("data_v[%d] = %f\n", i, data_v[i]);
  }
#endif

  printf("Scalar DWT...\n");
  start_timer();
  gsl_wavelet_transform(data_s, DWT_LEN, buf, first_iter_only);
  stop_timer();

  runtime = get_timer();
  printf("The scalar DWT execution took %d cycles.\n", runtime);

  printf("Vector DWT...\n");
  start_timer();
  gsl_wavelet_transform_vector(data_v, DWT_LEN, buf, first_iter_only);
  stop_timer();

  // Number of cycles
  runtime = get_timer();
  // DWT iterates for log2(N) steps
  num_ops = 0;
#ifdef FIRST_ITER_ONLY
  for (int n = DWT_LEN; n > 0; n = 0) {
#else
  for (int n = DWT_LEN; n >= 2; n >>= 1) {
#endif
    num_ops += ((2 * FILTER_COEFF) - 1) * n;
  }
  // Bytes from/to memory
  // Account also for the n/2 memcpy (n mem ops because of it!)
  num_bytes = 0;
#ifdef FIRST_ITER_ONLY
  for (int n = DWT_LEN; n > 0; n = 0) {
#else
  for (int n = DWT_LEN; n >= 2; n >>= 1) {
#endif
    num_bytes += 2 * sizeof(float) * n + sizeof(float) * n;
  }
  // FLOP/cycle
  performance = (float)num_ops / runtime;
  // FLOP/B
  arith_intensity = (float)num_ops / num_bytes;
  // Max memory bandwidth
  bw = 4 * NR_LANES; // B/cycle
  // Reduced memory bandwidth with strided access
  stride_bw = sizeof(float);
  // n loads with stride BW, n/2 loads, n/2 stores, n stores with normal BW
  dwt_eff_stride_bw = (2 * bw + stride_bw) / 3;
  // Max ideal performance
  max_performance = (float)arith_intensity * bw;
  // Max real performance
  max_performance_stride_bw = (float)arith_intensity * dwt_eff_stride_bw;
  printf("The vector DWT execution took %d cycles.\n", runtime);
  printf("Max ideal performance is %f, max real performance is %f, actual "
         "performance is %f.\n",
         max_performance, max_performance_stride_bw, performance);
  printf("Performance over max real: %f%%.\n",
         (100 * performance) / max_performance_stride_bw);

#ifdef CHECK
  for (uint32_t i = 0; i < DWT_LEN; ++i) {
    if (!similarity_check(data_s[i], data_v[i], THRESHOLD)) {
      error = 1;
      printf("Error at index %d. %f != %f\n", i, data_v[i], data_s[i]);
    }
  }
  if (!error)
    printf("Test result: PASS. No errors.\n");
#endif

  return error;
}
