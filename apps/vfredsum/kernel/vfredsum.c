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

#include "vfredsum.h"

#define vfredsum_def_gen(DATA_TYPE, sew)                                       \
  DATA_TYPE vfredsum_##sew(DATA_TYPE *i, size_t avl, uint8_t is_ordered,       \
                           uint8_t is_chained) {                               \
                                                                               \
    size_t vl = vsetvl_e##sew##m8(avl);                                        \
                                                                               \
    vfloat##sew##m8_t vector;                                                  \
    vfloat##sew##m1_t red, scalar;                                             \
                                                                               \
    vector = vfmv_s_f_f##sew##m8(vector, 0, vl);                               \
    scalar = vfmv_s_f_f##sew##m1(scalar, 0, vl);                               \
    red = vfmv_s_f_f##sew##m1(red, 0, vl);                                     \
    vfmv_f_s_f##sew##m1_f##sew(red);                                           \
                                                                               \
    if (is_chained) {                                                          \
      vector = vle##sew##_v_f##sew##m8(i, vl);                                 \
    }                                                                          \
                                                                               \
    if (is_ordered)                                                            \
      red = vfredosum_vs_f##sew##m8_f##sew##m1(red, vector, scalar, vl);       \
    else                                                                       \
      red = vfredusum_vs_f##sew##m8_f##sew##m1(red, vector, scalar, vl);       \
                                                                               \
    return vfmv_f_s_f##sew##m1_f##sew(red);                                    \
  }

vfredsum_def_gen(_Float16, 16);
vfredsum_def_gen(float, 32);
vfredsum_def_gen(double, 64);
