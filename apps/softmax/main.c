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
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "kernel/softmax.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Check the results using a threshold
#define CHECK

// Sanity check to see that there are some precision differences
// between the two algorithms
// #define SANITY_CHECK

// Sanity check to see the results
#define PRINT_RESULTS

#define THRESHOLD 0.0001

extern uint64_t channels;
extern uint64_t innerSize;
#define T double

extern T i[] __attribute__((aligned(4 * NR_LANES)));
extern T buf[] __attribute__((aligned(4 * NR_LANES)));
extern T o_s[] __attribute__((aligned(4 * NR_LANES)));
extern T o_v[] __attribute__((aligned(4 * NR_LANES)));
extern T o_g[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  SOFTMAX  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  printf("Channels: %lu\nInner Size: %lu\n", channels, innerSize);

  int64_t runtime;
  int error = 0;

  /*printf("Scalar Softmax...\n");
  start_timer();
  softmax(i, o_s, buf, channels, innerSize);
  stop_timer();

  runtime = get_timer();
  printf("The scalar SOFTMAX execution took %d cycles.\n", runtime);*/

  printf("Vector Softmax...\n");
  start_timer();
  // softmax_vec_reduction(i, o_v, channels, innerSize);
  softmax_vec_reduction_3(i, o_v, innerSize);
  stop_timer();

  runtime = get_timer();
  printf("The vector Softmax execution took %d cycles.\n", runtime);

#ifdef PRINT_RESULTS
  for (uint64_t k = 0; k < channels * innerSize; ++k) {
    printf("%lu) Vector, Scalar: %lf, %lf\n", k, o_v[k], o_g[k]);
  }
#endif

#ifdef CHECK
  for (uint64_t k = 0; k < channels * innerSize; ++k) {
#ifdef SANITY_CHECK
    if (o_g[k] != o_v[k]) {
#else
    if (!similarity_check(o_g[k], o_v[k], THRESHOLD)) {
#endif
      error = 1;
      printf("Error at index %d. %lf != %lf\n", k, o_v[k], o_g[k]);
    }
  }
  if (!error)
    printf("Check okay. No errors.\n");
#endif

  return error;
}
