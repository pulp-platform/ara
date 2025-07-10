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
#ifdef SOL_VSETVLI

#include "printf.h"
#include <stdint.h>
#include <riscv_vector.h>

//#define PRINTF

#define N 8

uint64_t a[N];
uint64_t b[N];
uint64_t c[N];

void vsetvli() {

  size_t avl = N;
  size_t vl;

  // VLEN
  asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(vl) : "r"(-1));
  uint64_t vlen = vl * 64;

  // Max vl (LMUL = 1 and SEW = 64)
  asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(vl) : "r"(-1));


  // Max vl (with LMUL > 1 and SEW = 8)
  asm volatile ("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(vl) : "r"(-1));
}

#endif
