// Copyright 2026 ETH Zurich and University of Bologna.
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

// Author: Hong Pang <hopang@iis.ee.ethz.ch>
//
// Adapted from ncnn src/layer/riscv/layernorm_riscv.cpp (BSD 3-Clause, see
// LICENSE), as extracted by VecIntrinBench. The mean and variance go through
// the scalar core instead of a vrgather broadcast.

#include <math.h>

#include "layernorm.h"

// VCD window trigger
extern int64_t event_trigger;

// Fixed registers: Ara requires the reduction destination to be aligned to
// LMUL (v24 at m8). v0 shift b, v8 accumulator, v16 data, v24 gamma /
// reduction, v8 beta in the last pass.
void layernorm_vec(const float *x, const float *gamma, const float *beta,
                   float *y, uint64_t rows, uint64_t d, float eps) {
  size_t vlmax, vl;
  asm volatile("vsetvli %0, zero, e32, m8, ta, ma" : "=r"(vlmax));
  size_t rvl = d < vlmax ? d : vlmax;

  for (uint64_t r = 0; r < rows; ++r) {
#ifdef VCD_DUMP
    // VCD window: one whole row, the fifth (needs rows >= 6)
    if (r == 4)
      *(volatile int64_t *)&event_trigger = +1;
    if (r == 5)
      *(volatile int64_t *)&event_trigger = -1;
#endif
    // Mean
    asm volatile("vsetvli zero, %0, e32, m8, ta, ma" ::"r"(vlmax));
    asm volatile("vmv.v.i v8, 0");
    const float *p = x;
    for (size_t n = d; n > 0; n -= vl, p += vl) {
      asm volatile("vsetvli %0, %1, e32, m8, tu, ma" : "=r"(vl) : "r"(n));
      asm volatile("vle32.v v16, (%0)" ::"r"(p));
      asm volatile("vfadd.vv v8, v8, v16");
    }
    float sum;
    asm volatile("vsetvli zero, %0, e32, m8, ta, ma" ::"r"(rvl));
    asm volatile("vmv.s.x v24, zero");
    asm volatile("vfredusum.vs v24, v8, v24");
    asm volatile("vfmv.f.s %0, v24" : "=f"(sum));
    float mean = sum / d;

    // Variance
    asm volatile("vsetvli zero, %0, e32, m8, ta, ma" ::"r"(vlmax));
    asm volatile("vmv.v.i v8, 0");
    p = x;
    for (size_t n = d; n > 0; n -= vl, p += vl) {
      asm volatile("vsetvli %0, %1, e32, m8, tu, ma" : "=r"(vl) : "r"(n));
      asm volatile("vle32.v v16, (%0)" ::"r"(p));
      asm volatile("vfsub.vf v16, v16, %0" ::"f"(mean));
      asm volatile("vfmacc.vv v8, v16, v16");
    }
    asm volatile("vsetvli zero, %0, e32, m8, ta, ma" ::"r"(rvl));
    asm volatile("vmv.s.x v24, zero");
    asm volatile("vfredusum.vs v24, v8, v24");
    asm volatile("vfmv.f.s %0, v24" : "=f"(sum));
    float a = 1.f / sqrtf(sum / d + eps);
    asm volatile("vsetvli zero, %0, e32, m8, ta, ma" ::"r"(vlmax));
    asm volatile("vfmv.v.f v0, %0" ::"f"(-mean * a));

    // Normalize, scale and shift
    const float *g = gamma, *bt = beta;
    for (size_t n = d; n > 0; n -= vl, x += vl, g += vl, bt += vl, y += vl) {
      asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(n));
      asm volatile("vle32.v v16, (%0)" ::"r"(x));
      asm volatile("vle32.v v24, (%0)" ::"r"(g));
      asm volatile("vle32.v v8, (%0)" ::"r"(bt));
      asm volatile("vfmadd.vf v16, %0, v0" ::"f"(a));
      asm volatile("vfmadd.vv v16, v24, v8");
      asm volatile("vse32.v v16, (%0)" ::"r"(y) : "memory");
    }
  }
}
