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
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "cos.h"
#include "cos_hoist.h"

// VCD window trigger
extern int64_t event_trigger;

void cos_1xf64_intr_bmark(double *angles, double *results, size_t len) {

  size_t avl = len;
  vfloat64m1_t cos_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
  for (size_t vl = __riscv_vsetvl_e64m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = __riscv_vsetvl_e64m1(avl);
    // Load vector
    cos_vec = __riscv_vle64_v_f64m1(angles, vl);
    // Compute
    res_vec = __cos_1xf64(cos_vec, vl);
    // Store
    __riscv_vse64_v_f64m1(results, res_vec, vl);
    // Bump pointers
    angles += vl;
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}

void cos_2xf32_intr_bmark(float *angles, float *results, size_t len) {

  size_t avl = len;
  vfloat32m1_t cos_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
  for (size_t vl = __riscv_vsetvl_e32m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = __riscv_vsetvl_e32m1(avl);
    // Load vector
    cos_vec = __riscv_vle32_v_f32m1(angles, vl);
    // Compute
    res_vec = __cos_2xf32(cos_vec, vl);
    // Store
    __riscv_vse32_v_f32m1(results, res_vec, vl);
    // Bump pointers
    angles += vl;
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}

// Constants hoisted out of the loop (cos_hoist.h)
void cos_1xf64_bmark(double *angles, double *results, size_t len) {
  size_t avl = len, vlmax;
  asm volatile("vsetvli %0, zero, e64, m1, ta, ma" : "=r"(vlmax));
  VCOS_CONST_INIT_F64();
#ifdef VCD_DUMP
  size_t strip = 0;
#endif
  while (avl > 0) {
#ifdef VCD_DUMP
    // VCD window: strips 25..32 (needs len > 32 * VLMAX)
    strip++;
    if (strip == 25)
      *(volatile int64_t *)&event_trigger = +1;
    if (strip == 33)
      *(volatile int64_t *)&event_trigger = -1;
#endif

    size_t vl;
    asm volatile("vsetvli %0, %1, e64, m1, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle64.v v1, (%0)" ::"r"(angles));
    VCOS_F64M1(v2, v1);
    asm volatile("vse64.v v2, (%0)" ::"r"(results) : "memory");
    angles += vl;
    results += vl;
    avl -= vl;
  }
}

void cos_2xf32_bmark(float *angles, float *results, size_t len) {
  size_t avl = len, vlmax;
  asm volatile("vsetvli %0, zero, e32, m1, ta, ma" : "=r"(vlmax));
  VCOS_CONST_INIT_F32();
#ifdef VCD_DUMP
  size_t strip = 0;
#endif
  while (avl > 0) {
#ifdef VCD_DUMP
    // VCD window: strips 13..16 (needs len > 16 * VLMAX)
    strip++;
    if (strip == 13)
      *(volatile int64_t *)&event_trigger = +1;
    if (strip == 17)
      *(volatile int64_t *)&event_trigger = -1;
#endif

    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v1, (%0)" ::"r"(angles));
    VCOS_F32M1(v2, v1);
    asm volatile("vse32.v v2, (%0)" ::"r"(results) : "memory");
    angles += vl;
    results += vl;
    avl -= vl;
  }
}
