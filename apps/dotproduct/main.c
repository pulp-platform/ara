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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "runtime.h"

#include "kernel/dotproduct.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

// Run also the scalar benchmark
#define SCALAR 1

// Check the vector results against golden vectors
#define CHECK 1

// Vector size (Byte)
extern uint64_t vsize;
// Vectors for benchmarks
extern int64_t v64a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int64_t v64b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int32_t v32a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int32_t v32b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int16_t v16a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int16_t v16b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int8_t v8a[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern int8_t v8b[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
// Output vectors
extern int64_t res64_v, res64_s;
extern int32_t res32_v, res32_s;
extern int16_t res16_v, res16_s;
extern int8_t res8_v, res8_s;

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  DOTP  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  int64_t runtime_s, runtime_v;

  for (uint64_t avl = 8; avl <= (vsize >> 3); avl *= 8) {
    // Dotp
    printf("Calulating 64b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res64_v = dotp_v64b(v64a, v64b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res64_s = dotp_s64b(v64a, v64b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (res64_v != res64_s) {
          printf("Error: v = %ld, g = %ld\n", res64_v, res64_s);
          return -1;
        }
      }
    }
  }

  for (uint64_t avl = 8; avl <= (vsize >> 2); avl *= 8) {
    // Dotp
    printf("Calulating 32b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res32_v = dotp_v32b(v32a, v32b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res32_s = dotp_s32b(v32a, v32b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (res32_v != res32_s) {
          printf("Error: v = %ld, g = %ld\n", res32_v, res32_s);
          return -1;
        }
      }
    }
  }

  for (uint64_t avl = 8; avl <= (vsize >> 1); avl *= 8) {
    // Dotp
    printf("Calulating 16b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res16_v = dotp_v16b(v16a, v16b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res16_s = dotp_s16b(v16a, v16b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (res16_v != res16_s) {
          printf("Error: v = %ld, g = %ld\n", res16_v, res16_s);
          return -1;
        }
      }
    }
  }

  for (uint64_t avl = 8; avl <= (vsize >> 0); avl *= 8) {
    // Dotp
    printf("Calulating 8b dotp with vectors with length = %lu\n", avl);
    start_timer();
    res8_v = dotp_v8b(v8a, v8b, avl);
    stop_timer();
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      start_timer();
      res8_s = dotp_s8b(v8a, v8b, avl);
      stop_timer();
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (res8_v != res8_s) {
          printf("Error: v = %ld, g = %ld\n", res8_v, res8_s);
          return -1;
        }
      }
    }
  }

  printf("SUCCESS.\n");

  return 0;
}
