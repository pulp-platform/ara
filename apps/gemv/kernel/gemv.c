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

// Author: Navaneeth Kunhi Purayil, ETH Zurich <nkunhi@iis.ee.ethz.ch>

#include "gemv.h"

void gemv_v64b_m4(double *a, double* b, double* c, int M, int M_core, int N) {
  unsigned int vl, avl = M_core;
  double *a_, *a_start = a;
  double *b_ = b;
  double *c_ = c;

  do {
    a_ = a_start;
    asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(vl) : "r"(avl));
    for (int col=0; col < N; col+=2) {
      // Load chunk a
      asm volatile("vle64.v v0, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vfmul.vf v4, v0, %0" ::"f"(*b_));
      } else {
        asm volatile("vfmacc.vf v4, %0, v0" ::"f"(*b_));
      }
      b_++;

      // Load chunk a
      asm volatile("vle64.v v8, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vfmul.vf v12, v8, %0" ::"f"(*b_));
      } else {
        asm volatile("vfmacc.vf v12, %0, v8" ::"f"(*b_));
      }
      b_++;
    }
    asm volatile("vfadd.vv v4, v4, v12");
    asm volatile("vse64.v v4, (%0)" ::"r"(c_));
    avl -= vl;
    c_ += vl;
    b_ = b;
    a_start += vl;
  } while (avl > 0);

}

void gemv_v32b_m4(float *a, float* b, float* c, int M, int M_core, int N) {
  unsigned int vl, avl = M_core;
  float *a_, *a_start = a;
  float *b_ = b;
  float *c_ = c;

  do {
    a_ = a_start;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));
    for (int col=0; col < N; col+=2) {
      // Load chunk a
      asm volatile("vle32.v v0, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vfmul.vf v4, v0, %0" ::"f"(*b_));
      } else {
        asm volatile("vfmacc.vf v4, %0, v0" ::"f"(*b_));
      }
      b_++;

      // Load chunk a
      asm volatile("vle32.v v8, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      if (col == 0) {
        asm volatile("vfmul.vf v12, v8, %0" ::"f"(*b_));
      } else {
        asm volatile("vfmacc.vf v12, %0, v8" ::"f"(*b_));
      }
      b_++;

    }
    asm volatile("vfadd.vv v12, v12, v4");
    asm volatile("vse32.v v12, (%0)" ::"r"(c_));
    avl -= vl;
    c_ += vl;
    b_ = b;
    a_start += vl;
  } while (avl > 0);

}

void gemv_v16b_m4(_Float16 *a, _Float16* b, _Float16* c, int M, int M_core, int N) {
  unsigned int vl, avl = M_core;
  _Float16 *a_, *a_start = a;
  _Float16 *b_ = b;
  _Float16 *c_ = c;

  do {
    a_ = a_start;
    asm volatile("vsetvli %0, %1, e16, m4, ta, ma" : "=r"(vl) : "r"(avl));
    for (int col=0; col < N; col+=2) {
      // Load chunk a
      asm volatile("vle16.v v0, (%0)" ::"r"(a_));
      a_ += M;

      // Load chunk a
      asm volatile("vle16.v v8, (%0)" ::"r"(a_));
      a_ += M;

      // Multiply and accumulate
      float t0;
      asm volatile("flh %[t], 0(%[b])" : [t] "=f"(t0) : [b] "r"(b_));
      if (col == 0) {
        asm volatile("vfmul.vf v4, v0, %0" ::"f"(t0));
      } else {
        asm volatile("vfmacc.vf v4, %0, v0" ::"f"(t0));
      }
      b_++;

      // Multiply and accumulate
      float t1;
      asm volatile("flh %[t], 0(%[b])" : [t] "=f"(t1) : [b] "r"(b_));
      if (col == 0) {
        asm volatile("vfmul.vf v12, v8, %0" ::"f"(t1));
      } else {
        asm volatile("vfmacc.vf v12, %0, v8" ::"f"(t1));
      }
      b_++;

    }
    asm volatile("vfadd.vv v12, v12, v4");
    asm volatile("vse16.v v12, (%0)" ::"r"(c_));
    avl -= vl;
    c_ += vl;
    b_ = b;
    a_start += vl;
  } while (avl > 0);

}