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
#ifdef SOL_MASK

#include "printf.h"
#include <stdint.h>
#include <riscv_vector.h>

//#define PRINTF

#define N 8

uint64_t a[N] = {0, 1, 2, 3, 4, 5, 6, 7};
uint64_t b[N] = {7, 0, 6, 1, 5, 2, 4, 3};
uint64_t c[N];
// Expected after sum: c = {0, 1, 0, 4, 0, 7, 10, 10}

void mask_scalar() {
  for (int i = 0; i < N; ++i) {
    if (a[i] > b[i])
      c[i] = a[i] + b[i];
  }
}

void mask_vector() {

  size_t avl = N;
  size_t vl = 0;

  uint64_t *a_ = a;
  uint64_t *b_ = b;
  uint64_t *c_ = c;

  for (; avl > 0; avl -= vl) {
    // Setup vector length
    asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(vl) : "r"(avl));

    // Initialize output vector to zero
    asm volatile ("vmv.v.i v3, 0");

    // Load vector a and b into the Vector Register File (VRF)
    asm volatile ("vle64.v v1, (%0)" :: "r"(a_));
    asm volatile ("vle64.v v2, (%0)" :: "r"(b_));

    // Create the mask
    asm volatile ("vmsgt.vv v0, v1, v2");

    // Perform "c = a + b" and save result into the VRF
    asm volatile ("vadd.vv v3, v2, v1, v0.t");

    // Store c into memory
    asm volatile ("vse64.v v3, (%0)" :: "r"(c_));

    // Bump pointers
    a_ += vl;
    c_ += vl;
  }
#ifdef PRINTF
  printf("c = {");
  for (int i = 0; i < N; ++i) printf(" %u ", c[i]);
  printf("}\n");
#endif
}

#endif
