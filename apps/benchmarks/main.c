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

#include "kernel/fmatmul.h"
#include "kernel/imatmul.h"
#include "printf.h"
#include "runtime.h"

// Define Matrix dimensions:
// C = AB with A=[MxN], B=[NxP], C=[MxP]
#define M 128
#define N 128
#define P 128

int64_t a[M * N] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int64_t b[N * P] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int64_t c[M * P] __attribute__((aligned(32 * NR_LANES), section(".l2")));

// Define the size of the matrix, and the kernel to call
#ifndef KERNEL
#define KERNEL imatmul
#endif

#ifndef SIZE
#define SIZE 16
#endif

int main() {
  // Measure runtime with a hot cache
  start_timer();
  KERNEL(c, a, b, SIZE, SIZE, SIZE);
  stop_timer();

  int64_t runtime = get_timer();
  float performance = 2.0 * SIZE * SIZE * SIZE / runtime;
  printf("[performance]: %d %f\n", SIZE, performance);

  return 0;
}
