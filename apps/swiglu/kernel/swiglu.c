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

// SwiGLU of the already-projected gate g and value u, per element:
//   o = u * SiLU(g) = u * g * sigmoid(g) = g * u / (1 + exp(-g))

#include <stdint.h>

#include "riscv_vector.h"

#include "../../exp/kernel/exp.h"
#include "swiglu.h"

// VCD window trigger
extern int64_t event_trigger;

void swiglu_vec(const float *g, const float *u, float *o, size_t len) {
#ifdef VCD_DUMP
  unsigned int strip = 0;
#endif
  size_t avl = len;
  while (avl > 0) {
#ifdef VCD_DUMP
    // VCD window: strips 5..8 of VLMAX(m1) (needs len >= 9 * VLMAX(m1))
    strip++;
    if (strip == 5)
      *(volatile int64_t *)&event_trigger = +1;
    if (strip == 9)
      *(volatile int64_t *)&event_trigger = -1;
#endif
    size_t vl = __riscv_vsetvl_e32m1(avl);
    vfloat32m1_t g_v = __riscv_vle32_v_f32m1(g, vl);
    vfloat32m1_t u_v = __riscv_vle32_v_f32m1(u, vl);
    // 1 + exp(-g)
    vfloat32m1_t den_v = __exp_2xf32(__riscv_vfneg_v_f32m1(g_v, vl), vl);
    den_v = __riscv_vfadd_vf_f32m1(den_v, 1.0f, vl);
    // g * u / (1 + exp(-g))
    vfloat32m1_t o_v = __riscv_vfmul_vv_f32m1(g_v, u_v, vl);
    o_v = __riscv_vfdiv_vv_f32m1(o_v, den_v, vl);
    __riscv_vse32_v_f32m1(o, o_v, vl);
    g += vl;
    u += vl;
    o += vl;
    avl -= vl;
  }
}
