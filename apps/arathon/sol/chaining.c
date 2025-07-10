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
#ifdef SOL_CHAINING

#include "printf.h"
#include <stdint.h>
#include <riscv_vector.h>

#define N 256

uint64_t a[N];
uint64_t c[N];

void chaining() {

  size_t avl = N;
  size_t vl = 0;

  uint64_t *a_ = a;
  uint64_t *c_ = c;

  for (; avl > 0; avl -= vl) {
    // Setup vector length
    asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(vl) : "r"(avl));

    // Load vector a and b into the Vector Register File (VRF)
    asm volatile ("vle64.v v0, (%0)" :: "r"(a_));

    // Perform "c = a + b" and save result into the VRF
    asm volatile ("vadd.vi v2, v0, 1");

    // Store c into memory
    asm volatile ("vse64.v v2, (%0)" :: "r"(c_));

    // Bump pointers
    a_ += vl;
    c_ += vl;
  }
}

#endif
