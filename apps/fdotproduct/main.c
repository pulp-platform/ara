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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"

#include "kernel/fdotproduct.h"

// Threshold for FP comparisons
#define THRESHOLD_64b 0.0000000001
#define THRESHOLD_32b 0.0001
#define THRESHOLD_16b 1

// Run also the scalar benchmark
#define SCALAR 1

// Check the vector results against golden vectors
#define CHECK 1

// Macro to check similarity between two fp-values, wrt a threshold
#define fp_check(a, b, threshold) ((((a - b) < 0) ? b - a : a - b) < threshold)

// Run the program with maximum AVL only (AVL == N)
#define MAX_AVL_ONLY

#ifdef MAX_AVL_ONLY
#define START_AVL N
#else
#define START_AVL 1
#endif

// Vector size (#elements)
extern uint64_t N;
// Input vectors
extern double v64a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern double v64b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float v32a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float v32b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _Float16 v16a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern _Float16 v16b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
// Golden outputs
extern double gold64;
extern float gold32;
extern _Float16 gold16;
// Output vectors
extern double res64_v;
extern float res32_v;
extern _Float16 res16_v;
extern double res64_s;
extern float res32_s;
extern _Float16 res16_s;

int main() {
  printf("\n");
  printf("===========\n");
  printf("=  FDOTP  =\n");
  printf("===========\n");
  printf("\n");
  printf("\n");

  uint64_t runtime_s, runtime_v;

  for (uint64_t avl = START_AVL; avl <= N; avl *= 8) {
    printf("Calulating 64b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res64_v = fdotp_v64b(v64a, v64b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res64_s = fdotp_s64b(v64a, v64b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK) {
      if (SCALAR) {
        printf("Checking results: v = %f, s = %f, g = %f\n", res64_v, res64_s,
               gold64);
        if (!fp_check(res64_v, gold64, THRESHOLD_64b) ||
            !fp_check(res64_s, gold64, THRESHOLD_64b)) {
          printf("Error: v = %f, s = %f, g = %f\n", res64_v, res64_s, gold64);
          return -1;
        }
      } else {
        printf("Checking results: v = %f, g = %f\n", res64_v, gold64);
        if (!fp_check(res64_v, gold64, THRESHOLD_64b)) {
          printf("Error: v = %f, g = %f\n", res64_v, gold64);
          return -1;
        }
      }
    }
  }

  for (uint64_t avl = START_AVL; avl <= N; avl *= 8) {
    printf("Calulating 32b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res32_v = fdotp_v32b(v32a, v32b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res32_s = fdotp_s32b(v32a, v32b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK) {
      if (SCALAR) {
        printf("Checking results: v = %f, s = %f, g = %f\n", res32_v, res32_s,
               gold32);
        if (!fp_check(res32_v, gold32, THRESHOLD_32b) ||
            !fp_check(res32_s, gold32, THRESHOLD_32b)) {
          printf("Error: v = %f, s = %f, g = %f\n", res32_v, res32_s, gold32);
          return -1;
        }
      } else {
        printf("Checking results: v = %f, g = %f\n", res32_v, gold32);
        if (!fp_check(res32_v, gold32, THRESHOLD_32b)) {
          printf("Error: v = %f, g = %f\n", res32_v, gold32);
          return -1;
        }
      }
    }
  }

  for (uint64_t avl = START_AVL; avl <= N; avl *= 8) {
    // Dotp
    printf("Calulating 16b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res16_v = fdotp_v16b(v16a, v16b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res16_s = fdotp_s16b(v16a, v16b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);
    }

    if (CHECK) {
      if (SCALAR) {
        printf("Checking results: v = %x, s = %x, g = %x\n",
               *((uint16_t *)&res16_v), *((uint16_t *)&res16_s),
               *((uint16_t *)&gold16));
        if (!fp_check(res16_v, gold16, THRESHOLD_16b) ||
            !fp_check(res16_s, gold16, THRESHOLD_16b)) {
          printf("Error: v = %x, s = %x, g = %x\n", *((uint16_t *)&res16_v),
                 *((uint16_t *)&res16_s), *((uint16_t *)&gold16));
          return -1;
        }
      } else {
        printf("Checking results: v = %x, g = %x\n", *((uint16_t *)&res16_v),
               *((uint16_t *)&gold16));
        if (!fp_check(res16_v, gold16, THRESHOLD_16b)) {
          printf("Error: v = %x, g = %x\n", *((uint16_t *)&res16_v),
                 *((uint16_t *)&gold16));
          return -1;
        }
      }
    }
  }

  printf("SUCCESS.\n");

  return 0;
}
