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

// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

#include "faxpy.h"

// 64-bit AXPY: y = a * x + y
void faxpy_v64b(const double a, const double *x, const double *y,
                size_t avl) {
  unsigned int vl;

  // Stripmine and accumulate a partial vector
  do {
    // Set the vl
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

    // Load vectors
    asm volatile("vle64.v v0, (%0)" ::"r"(x));
    asm volatile("vle64.v v8, (%0)" ::"r"(y));

    // Multiply-accumulate
    asm volatile("vfmacc.vf v8, %0, v0" ::"f"(a));

    // Store results
    asm volatile("vse64.v v8, (%0)" ::"r"(y));

    // Bump pointers
    x += vl;
    y += vl;
    avl -= vl;
  } while (avl > 0);
}

// Unrolled 64-bit AXPY: y = a * x + y
void faxpy_v64b_unrl(const double a, const double *x, const double *y,
                     size_t avl) {
  unsigned int vl;
  double *y2;

  // Stripmine and accumulate a partial vector
  do {
    // Set the vl
    asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

    // Load vectors
    asm volatile("vle64.v v0, (%0)" ::"r"(x));
    asm volatile("vle64.v v8, (%0)" ::"r"(y));

    // Multiply-accumulate
    asm volatile("vfmacc.vf v8, %0, v0" ::"f"(a));
    avl -= vl;
    if (avl > 0) {
      // Set the vl
      asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));

      // Load vectors
      x += vl;
      asm volatile("vle64.v v16, (%0)" ::"r"(x));
      y2 = y + vl;
      asm volatile("vle64.v v24, (%0)" ::"r"(y2));

      // Multiply-accumulate
      asm volatile("vfmacc.vf v24, %0, v16" ::"f"(a));
    }

    // Store results
    asm volatile("vse64.v v8, (%0)" ::"r"(y));
    if (avl > 0) {
      // Store results
      y += vl;
      asm volatile("vse64.v v24, (%0)" ::"r"(y));
      avl -= vl;
    }

    // Bump pointers
    x += vl;
    y += vl;

  } while (avl > 0);

  asm volatile("vslidedown.vi v16, v24, 2");
}