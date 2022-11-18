// Copyright 2020 ETH Zurich and University of Bologna.
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
// Author: Matteo Perotti

#include "dropout.h"

// Scalar dropout
void dropout_gold(const unsigned int n, const float *i, const float scale,
                  const uint8_t *sel_ptr, float *o) {
  uint8_t buf_sel, sel;
  for (unsigned int k = 0; k < n; ++k) {
    if (!(k % 8))
      buf_sel = sel_ptr[k >> 3];
    sel = buf_sel & 0x01;
    o[k] = sel ? (i[k] * scale) : 0;
    buf_sel >>= 1;
  }
}

#ifdef INTRINSICS
void dropout_vec(const unsigned int n, const float *i, const float scale,
                 const uint8_t *sel_ptr, float *o) {
  unsigned int vl;

  vfloat32m8_t vi, vo;
  vbool4_t vsel_m;

  for (unsigned int avl = n; (vl = vsetvl_e32m8(avl)) > 0; avl -= vl) {
    // Load selection vector
    vsel_m = vlm_v_b4(sel_ptr, vl);
    // Initialize output vector with zeroes
    vo = vfmv_v_f_f32m8((float)0, vl);
    // Load input vector
    vi = vle32_v_f32m8(i, vl);
    // Calculate output vector
    vo = vfmul_vf_f32m8_m(vsel_m, vo, vi, scale, vl);
    vse32_v_f32m8(o, vo, vl);
    // Bump pointers
    i += vl;
    sel_ptr += vl >> 3;
    o += vl;
  }
}
#else
void dropout_vec(const unsigned int n, const float *i, const float scale,
                 const uint8_t *sel_ptr, float *o) {
  unsigned int vl;

  asm volatile("vsetvli %[vl], %[n], e32, m8, ta, ma"
               : [vl] "=r"(vl)
               : [n] "r"(n));

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif

  for (unsigned int avl = n; avl > 0; avl -= vl) {
    // Find next vl
    asm volatile("vsetvli %[vl], %[avl], e32, m8, ta, ma"
                 : [vl] "=r"(vl)
                 : [avl] "r"(avl));
    // Load the mask vector (1 = keep, 0 = drop)
    asm volatile("vlm.v v0, (%[sel_ptr])" ::[sel_ptr] "r"(sel_ptr));
    // Initialize output vector with zeroes
    asm volatile("vmv.v.i v24, 0");
    // Load input vector
    asm volatile("vle32.v v8, (%[i])" ::[i] "r"(i));
    // Calculate output vector
    asm volatile("vfmul.vf v24, v8, %[scale], v0.t" ::[scale] "f"(scale));
    asm volatile("vse32.v v24, (%[o])" ::[o] "r"(o));
    // Bump pointers
    i += vl;
    sel_ptr += vl >> 3;
    o += vl;
  }

#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}
#endif
