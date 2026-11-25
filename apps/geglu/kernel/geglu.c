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

// GeGLU of the already-projected gate g and value u, per element, with the
// tanh approximation of GELU:
//   o = 0.5 * g * u * (1 + tanh(t)),  t = sqrt(2/pi) * (g + 0.044715 * g^3)
// Since 0.5 * (1 + tanh(t)) = 1 / (1 + exp(-2t)), this is computed exactly as
//   o = g * u / (1 + exp(-2t)),
//   -2t = -2 * sqrt(2/pi) * g * (1 + 0.044715 * g^2)

#include <stdint.h>

#include "riscv_vector.h"

#include "../../exp/kernel/exp.h"
#include "geglu.h"

// VCD window trigger
extern int64_t event_trigger;

void geglu_vec(const float *g, const float *u, float *o, size_t len) {
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
    vfloat32m1_t one_v = __riscv_vfmv_v_f_f32m1(1.0f, vl);
    // y_v holds: -2t = -2 * sqrt(2/pi) * g * (1 + 0.044715 * g^2)
    vfloat32m1_t y_v = __riscv_vfmul_vv_f32m1(g_v, g_v, vl);
    y_v = __riscv_vfmadd_vf_f32m1(y_v, 0.044715f, one_v, vl);
    y_v = __riscv_vfmul_vv_f32m1(y_v, g_v, vl);
    y_v = __riscv_vfmul_vf_f32m1(y_v, -1.5957691216057308f, vl);
    // 1 + exp(-2t)
    vfloat32m1_t den_v = __exp_2xf32(y_v, vl);
    den_v = __riscv_vfadd_vv_f32m1(den_v, one_v, vl);
    // g * u / (1 + exp(-2t))
    vfloat32m1_t o_v = __riscv_vfmul_vv_f32m1(g_v, u_v, vl);
    o_v = __riscv_vfdiv_vv_f32m1(o_v, den_v, vl);
    __riscv_vse32_v_f32m1(o, o_v, vl);
    g += vl;
    u += vl;
    o += vl;
    avl -= vl;
  }
}
