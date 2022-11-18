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

void cos_1xf64_bmark(double *angles, double *results, size_t len) {

  size_t avl = len;
  vfloat64m1_t cos_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
  for (size_t vl = vsetvl_e64m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e64m1(avl);
    // Load vector
    cos_vec = vle64_v_f64m1(angles, vl);
    // Compute
    res_vec = __cos_1xf64(cos_vec, vl);
    // Store
    vse64_v_f64m1(results, res_vec, vl);
    // Bump pointers
    angles += vl;
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}

void cos_2xf32_bmark(float *angles, float *results, size_t len) {

  size_t avl = len;
  vfloat32m1_t cos_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
  for (size_t vl = vsetvl_e32m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e32m1(avl);
    // Load vector
    cos_vec = vle32_v_f32m1(angles, vl);
    // Compute
    res_vec = __cos_2xf32(cos_vec, vl);
    // Store
    vse32_v_f32m1(results, res_vec, vl);
    // Bump pointers
    angles += vl;
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}
