// Copyright 2025 ETH Zurich and University of Bologna.
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

// Add two vectors with N elements on 64 bits
#ifdef SOL_RESHUFFLE

#include "printf.h"
#include <stdint.h>
#include <riscv_vector.h>

//#define PRINTF

#define N 8

uint16_t a[N] = {0, 1, 2, 3, 4, 5, 6, 7};
uint16_t b[N] = {0, 1, 2, 3, 4, 5, 6, 7};
uint16_t c[N];

void reshuffle() {
  // Setup vector length to operate on 2*N
  asm volatile ("vsetvli x0, %0, e8, m1, ta, ma" :: "r"(2*N));
  // Load the whole a (2*N byte packets)
  asm volatile ("vle8.v v0, (%0)" :: "r"(a));

  // Setup vector length
  asm volatile ("vsetvli x0, %0, e16, m1, ta, ma" :: "r"(N));
  // Load the whole b (N 2-byte packets)
  asm volatile ("vle16.v v1, (%0)" :: "r"(b));

  // Perform "c = a + b" and save result into the VRF
  asm volatile ("vadd.vv v2, v0, v1");

  // Store c into memory
  asm volatile ("vse16.v v2, (%0)" :: "r"(c));

  // Print
  for (int i = 0; i < N; ++i) printf(" %u ", c[i]);
}

#endif
