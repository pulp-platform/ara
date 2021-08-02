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

// Author: Matteo Perotti

#include "iconv2d.h"
#include <stdio.h>

#define MIN(a, b) ((a) < (b) ? (a) : (b))

void iconv2d_5x5(int64_t *o, int64_t *i, int64_t *f, int64_t R, int64_t C,
                 int64_t F) {
  // We work on 2 rows of the output matrix at once
  int64_t block_size_o = 2;
  // We work on block_size_o + F - 1 rows of the input matrix at once

  // First iteration round, r = 0
  int64_t *i_ = i;
  int64_t *o_ = o;

  // For simplicity, compute over the padding rows as well
  iconv2d_vec_4xC_slice_init_5x5(o_, C);
  // Preload the first two input rows -> This is not needed in the other rounds
  iconv2d_vec_4xC_slice_preload_5x5(i_, C, F);
  // The first (floor(F/2) + 1 = 2) rows have already been loaded by
  // iconv2d_vec_4xC_slice_init()
  int64_t *i__ = i_ + (F - 1) * (C + F - 1);
  iconv2d_vec_4xC_5x5(o_, i__, f, C, F);
  // Re-use some of the already-loaded input rows
  iconv2d_vec_4xC_slice_move_5x5(C, F);

  // Iterate over the output rows
  for (int64_t r = block_size_o; r < R; r += block_size_o) {
    i_ = i + r * (C + F - 1);
    o_ = o + r * C;

    // For simplicity, compute over the padding rows as well
    iconv2d_vec_4xC_slice_init_5x5(o_, C);
    // The first F-1 rows have already been loaded by
    // iconv2d_vec_4xC_slice_init()
    i__ = i_ + (F - 1) * (C + F - 1);
    iconv2d_vec_4xC_5x5(o_, i__, f, C, F);
    // Re-use some of the already-loaded input rows
    iconv2d_vec_4xC_slice_move_5x5(C, F);
  }
}

// Load 4 rows of the output matrix
void iconv2d_vec_4xC_slice_init_5x5(int64_t *o, int64_t C) {
  // Helper variables
  int64_t ldo = C << 3;

  // Set the vector configuration
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C));
  // Fetch 2 output rows
  asm volatile("vmv.v.i v0,  0; add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vmv.v.i v2,  0;" : "+r"(o));
}

// Load 4 rows of the output matrix
void iconv2d_vec_4xC_slice_preload_5x5(int64_t *i, int64_t C, int64_t F) {
  // Helper variables
  int64_t ldi = (C + F - 1) << 3;

  // Set the vector configuration
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  // Fetch the first F-1 = 4 input rows
  asm volatile("vle64.v v4, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vle64.v v6, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vle64.v v8, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vle64.v v10, (%0); add %0, %0, %1" : "+r"(i));
}

// Calculate 4 output matrix rows
void iconv2d_vec_4xC_5x5(int64_t *o, int64_t *i, int64_t *f, int64_t C,
                         int64_t F) {

  // Temporary variables (one filter column)
  int64_t t0, t1, t2, t3, t4;
  int64_t slamt;

  // Helper variables
  int64_t ldo = C << 3;
  int64_t ldi = (C + F - 1) << 3;
  int64_t ldf = F << 3;
  int64_t *f_;

  // Compute on C elements
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  // Fetch other 2 rows of the input matrix
  asm volatile("vle64.v v12, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vle64.v v14, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));

  // Compute on C elements
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C));
  f_ = f;
  // Fetch the first column of the filter, and start calculating its
  // contribution on the two output rows (v0, v2)
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("vmacc.vx v0, %0, v4" ::"r"(t0));
  asm volatile("vmacc.vx v2, %0, v6" ::"r"(t0));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("vmacc.vx v0, %0, v6" ::"r"(t1));
  asm volatile("vmacc.vx v2, %0, v8" ::"r"(t1));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t2) : "r"(ldf));
  asm volatile("vmacc.vx v0, %0, v8" ::"r"(t2));
  asm volatile("vmacc.vx v2, %0, v10" ::"r"(t2));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t3) : "r"(ldf));
  asm volatile("vmacc.vx v0, %0, v10" ::"r"(t3));
  asm volatile("vmacc.vx v2, %0, v12" ::"r"(t3));

  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t4));
  asm volatile("vmacc.vx v0, %0, v12" ::"r"(t4));
  asm volatile("vmacc.vx v2, %0, v14" ::"r"(t4));

  for (int64_t idx = 1; idx < F - 1; ++idx) {
    // Adjust filter mtx pointer and slide-amount
    f_ = f + idx;
    slamt = idx;
    // Fetch the other columns of the filter (except for the last one), and
    // start calculating their contributions on the two output rows (v0, v2) To
    // do so, at each iteration slide down the input rows by one
    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t0)
                 : "r"(ldf));
    asm volatile("vslidedown.vx v16, v4,  %0" ::"r"(slamt));
    asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));

    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t1)
                 : "r"(ldf));
    asm volatile("vslidedown.vx v18, v6,  %0" ::"r"(slamt));
    asm volatile("vmacc.vx v0, %0, v18" ::"r"(t1));
    asm volatile("vmacc.vx v2, %0, v18" ::"r"(t0));

    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t2)
                 : "r"(ldf));
    asm volatile("vslidedown.vx v20, v8,  %0" ::"r"(slamt));
    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t2));
    asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));

    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t3)
                 : "r"(ldf));
    asm volatile("vslidedown.vx v22, v10, %0" ::"r"(slamt));
    asm volatile("vmacc.vx v0, %0, v22" ::"r"(t3));
    asm volatile("vmacc.vx v2, %0, v22" ::"r"(t2));

    asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t4));
    asm volatile("vslidedown.vx v24, v12, %0" ::"r"(slamt));
    asm volatile("vmacc.vx v0, %0, v24" ::"r"(t4));
    asm volatile("vmacc.vx v2, %0, v24" ::"r"(t3));

    asm volatile("vslidedown.vx v26, v14, %0" ::"r"(slamt));
    asm volatile("vmacc.vx v2, %0, v26" ::"r"(t4));
  }

  f_ = f + (F - 1);
  slamt = (F - 1);
  // Repeat for the last filter column, and then store the output rows
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("vslidedown.vx v16, v4,  %0" ::"r"(slamt));
  asm volatile("vmacc.vx v0, %0, v16" ::"r"(t0));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("vslidedown.vx v18, v6,  %0" ::"r"(slamt));
  asm volatile("vmacc.vx v0, %0, v18" ::"r"(t1));
  asm volatile("vmacc.vx v2, %0, v18" ::"r"(t0));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t2) : "r"(ldf));
  asm volatile("vslidedown.vx v20, v8,  %0" ::"r"(slamt));
  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t2));
  asm volatile("vmacc.vx v2, %0, v20" ::"r"(t1));

  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t3) : "r"(ldf));
  asm volatile("vslidedown.vx v22, v10, %0" ::"r"(slamt));
  asm volatile("vmacc.vx v0, %0, v22" ::"r"(t3));
  asm volatile("vmacc.vx v2, %0, v22" ::"r"(t2));

  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t4));
  asm volatile("vslidedown.vx v24, v12, %0" ::"r"(slamt));
  asm volatile("vmacc.vx v0, %0, v24" ::"r"(t4));
  asm volatile("vse64.v  v0, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vmacc.vx v2, %0, v24" ::"r"(t3));

  asm volatile("vslidedown.vx v26, v14, %0" ::"r"(slamt));
  asm volatile("vmacc.vx v2, %0, v26" ::"r"(t4));
  asm volatile("vse64.v  v2, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
}

void iconv2d_vec_4xC_slice_move_5x5(int64_t C, int64_t F) {
  // Move C+F-1 elements
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  // Move the last floor(F/2) + 1 input rows
  asm volatile("vmv.v.v v4, v8");
  asm volatile("vmv.v.v v6, v10");
  asm volatile("vmv.v.v v8, v12");
  asm volatile("vmv.v.v v10, v14");
}
