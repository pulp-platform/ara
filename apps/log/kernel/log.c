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

#include "log.h"

void log_1xf64_bmark(double *args, double *results, size_t len) {

  size_t avl = len;
  vfloat64m1_t log_vec, res_vec;

  for (size_t vl = vsetvl_e64m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e64m1(avl);
    // Load vector
    log_vec = vle64_v_f64m1(args, vl);
    // Compute
    res_vec = __log_1xf64(log_vec, vl);
    // Store
    vse64_v_f64m1(results, res_vec, vl);
    // Bump pointers
    args += vl;
    results += vl;
  }
}

void log_2xf32_bmark(float *args, float *results, size_t len) {

  size_t avl = len;
  vfloat32m1_t log_vec, res_vec;

  for (size_t vl = vsetvl_e32m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e32m1(avl);
    // Load vector
    log_vec = vle32_v_f32m1(args, vl);
    // Compute
    res_vec = __log_2xf32(log_vec, vl);
    // Store
    vse32_v_f32m1(results, res_vec, vl);
    // Bump pointers
    args += vl;
    results += vl;
  }
}
