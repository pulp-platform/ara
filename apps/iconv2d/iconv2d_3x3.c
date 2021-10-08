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

void iconv2d_3x3(int64_t *o, int64_t *i, int64_t *f, int64_t R, int64_t C,
                 int64_t F) {
  // We work on 4 rows of the output matrix at once
  int64_t block_size_o = 4;
  // We work on block_size_o + F - 1 rows of the input matrix at once

  // First iteration round, r = 0
  int64_t *i_ = i;
  int64_t *o_ = o;

  // Preload the first two input rows -> This is not needed in the other rounds
  iconv2d_vec_4xC_slice_preload_3x3(i_, C, F);
  // The first F-1 rows have already been loaded by
  // iconv2d_vec_4xC_slice_preload_3x3()
  int64_t *i__ = i_ + (F - 1) * (C + F - 1);
  iconv2d_vec_4xC_3x3(o_, i__, f, C, F);
  // Re-use some of the already-loaded input rows
  iconv2d_vec_4xC_slice_move_3x3(C, F);

  i_ = i + block_size_o * (C + F - 1);
  i__ = i_ + (F - 1) * (C + F - 1);

  int64_t ldi = (C + F - 1) << 3;
  int64_t ldf = F << 3;

  // Temporary variables
  int64_t t0, t1, t2;
  // Helper variables
  int64_t *f_;
  f_ = f;
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t2));

  // Iterate over the output rows
  for (int64_t r = block_size_o; r < R; r += block_size_o) {

    // The first F-1 rows have already been loaded by
    // iconv2d_vec_4xC_slice_init()

    int64_t t3, t4, t5;

    // Fetch C + F - 1 elements (padding included)
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
    f_ = f;

    // Fetch the first column of the filter, and start calculating its
    // contribution on the four output rows (v0, v2, v4, v6)

    // Fetch 4 + F - 1 - 2 rows of the input matrix
    // Compute on C + F - 1 elements, instead of C elements, to cover the
    // latency of the load instructions
    asm volatile("vmv.v.v v8, v16");
    asm volatile("vle64.v v12, (%0); add %0, %0, %1" : "+&r"(i__) : "r"(ldi));
    asm volatile("vmul.vx v0, v8, %0" ::"r"(t0));

    asm volatile("vmv.v.v v10, v18");
    asm volatile("vmul.vx v2, v10, %0" ::"r"(t0));
    asm volatile("vle64.v v14, (%0); add %0, %0, %1" : "+&r"(i__) : "r"(ldi));
    asm volatile("vmacc.vx v0, %0, v10" ::"r"(t1));

    asm volatile("vmacc.vx v2, %0, v12" ::"r"(t1));
    asm volatile("vle64.v v16, (%0); add %0, %0, %1" : "+&r"(i__) : "r"(ldi));
    asm volatile("vmacc.vx v0, %0, v12" ::"r"(t2));
    asm volatile("vslidedown.vi v20, v8,  1");
    asm volatile("vmul.vx v4, v12, %0" ::"r"(t0));

    asm volatile("vle64.v v18, (%0); add %0, %0, %1" : "+&r"(i__) : "r"(ldi));

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C));

    asm volatile("vmul.vx v6, v14, %0" ::"r"(t0));
    asm volatile("vslidedown.vi v22, v10, 1");
    asm volatile("vmacc.vx v4, %0, v14" ::"r"(t1));
    asm volatile("vmacc.vx v2, %0, v14" ::"r"(t2));
    asm volatile("vslidedown.vi v24, v12, 1");

    asm volatile("vmacc.vx v6, %0, v16" ::"r"(t1));
    asm volatile("vmacc.vx v4, %0, v16" ::"r"(t2));

    asm volatile("vslidedown.vi v26, v14, 1");

    asm volatile("vmacc.vx v6, %0, v18" ::"r"(t2));

    f_ = f + 1;
    // Fetch the middle column of the filter, and start calculating its
    // contributions on the output rows To do so, slide down the input rows by
    // one
    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t3)
                 : "r"(ldf));
    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t4)
                 : "r"(ldf));
    asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t5));

    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t3));

    asm volatile("vmacc.vx v0, %0, v22" ::"r"(t4));
    asm volatile("vslidedown.vi v28, v16, 1");
    asm volatile("vmacc.vx v2, %0, v22" ::"r"(t3));

    i_ = i + (r + block_size_o) * (C + F - 1);
    asm volatile("vmacc.vx v0, %0, v24" ::"r"(t5));
    asm volatile("vslidedown.vi v30, v18, 1");
    asm volatile("vmacc.vx v2, %0, v24" ::"r"(t4));
    asm volatile("vmacc.vx v4, %0, v24" ::"r"(t3));
    asm volatile("vslidedown.vi v20, v8,  2");

    asm volatile("vmacc.vx v2, %0, v26" ::"r"(t5));
    asm volatile("vmacc.vx v4, %0, v26" ::"r"(t4));
    asm volatile("vslidedown.vi v22, v10, 2");
    asm volatile("vmacc.vx v6, %0, v26" ::"r"(t3));
    i__ = i_ + (F - 1) * (C + F - 1);

    asm volatile("vmacc.vx v4, %0, v28" ::"r"(t5));
    f_ = f + 2;
    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t3)
                 : "r"(ldf));
    asm volatile("vmacc.vx v6, %0, v28" ::"r"(t4));
    asm volatile("vslidedown.vi v24, v12, 2");

    asm volatile("vmacc.vx v6, %0, v30" ::"r"(t5));
    asm volatile("vmacc.vx v0, %0, v20" ::"r"(t3));
    asm volatile("vslidedown.vi v26, v14, 2");

    // Repeat for the last filter column, and then store the output rows
    asm volatile("ld %1, (%0); add %0, %0, %2"
                 : "+&r"(f_), "=&r"(t4)
                 : "r"(ldf));
    asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t5));

    asm volatile("vmacc.vx v0, %0, v22" ::"r"(t4));
    o_ = o + r * C;

    // Compute on C elements
    int64_t ldo = C << 3;
    asm volatile("vmacc.vx v2, %0, v22" ::"r"(t3));
    asm volatile("vslidedown.vi v28, v16, 2");

    asm volatile("vmacc.vx v0, %0, v24" ::"r"(t5));
    asm volatile("vmacc.vx v2, %0, v24" ::"r"(t4));
    asm volatile("vslidedown.vi v30, v18, 2");
    asm volatile("vse64.v  v0, (%0); add %0, %0, %1" : "+&r"(o_) : "r"(ldo));
    asm volatile("vmacc.vx v4, %0, v24" ::"r"(t3));

    asm volatile("vmacc.vx v2, %0, v26" ::"r"(t5));
    asm volatile("vse64.v  v2, (%0); add %0, %0, %1" : "+&r"(o_) : "r"(ldo));
    asm volatile("vmacc.vx v4, %0, v26" ::"r"(t4));
    asm volatile("vmacc.vx v6, %0, v26" ::"r"(t3));

    asm volatile("vmacc.vx v4, %0, v28" ::"r"(t5));
    asm volatile("vse64.v  v4, (%0); add %0, %0, %1" : "+&r"(o_) : "r"(ldo));
    asm volatile("vmacc.vx v6, %0, v28" ::"r"(t4));

    asm volatile("vmacc.vx v6, %0, v30" ::"r"(t5));
    asm volatile("vse64.v  v6, (%0);" : "+r"(o_));
  }
}

// Load 4 rows of the output matrix
void iconv2d_vec_4xC_slice_preload_3x3(int64_t *i, int64_t C, int64_t F) {
  // Helper variables
  int64_t ldi = (C + F - 1) << 3;

  // Set the vector configuration
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  // Fetch the first floor(F/2) + 1 input rows
  asm volatile("vle64.v v8,  (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vle64.v v10, (%0); add %0, %0, %1" : "+r"(i));
}

// Calculate 4 output matrix rows
void iconv2d_vec_4xC_3x3(int64_t *o, int64_t *i, int64_t *f, int64_t C,
                         int64_t F) {

  // Temporary variables
  int64_t t0, t1, t2;

  // Helper variables
  int64_t ldo = C << 3;
  int64_t ldi = (C + F - 1) << 3;
  int64_t ldf = F << 3;
  int64_t *f_;

  // Fetch C + F - 1 elements (padding included)
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  f_ = f;
  // Fetch the first column of the filter, and start calculating its
  // contribution on the four output rows (v0, v2, v4, v6)
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t2));

  // Fetch 4 + F - 1 - 2 rows of the input matrix
  // Compute on C + F - 1 elements, instead of C elements, to cover the latency
  // of the load instructions
  asm volatile("vle64.v v12, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vmul.vx v0, v8, %0" ::"r"(t0));

  asm volatile("vmul.vx v2, v10, %0" ::"r"(t0));
  asm volatile("vle64.v v14, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vmacc.vx v0, %0, v10" ::"r"(t1));

  asm volatile("vmacc.vx v2, %0, v12" ::"r"(t1));
  asm volatile("vle64.v v16, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));
  asm volatile("vmacc.vx v0, %0, v12" ::"r"(t2));
  asm volatile("vslidedown.vi v20, v8,  1");
  asm volatile("vmul.vx v4, v12, %0" ::"r"(t0));

  asm volatile("vle64.v v18, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi));

  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C));

  asm volatile("vmul.vx v6, v14, %0" ::"r"(t0));
  asm volatile("vmacc.vx v4, %0, v14" ::"r"(t1));
  asm volatile("vslidedown.vi v22, v10, 1");
  asm volatile("vmacc.vx v2, %0, v14" ::"r"(t2));

  asm volatile("vmacc.vx v6, %0, v16" ::"r"(t1));
  asm volatile("vmacc.vx v4, %0, v16" ::"r"(t2));

  asm volatile("vslidedown.vi v24, v12, 1");
  asm volatile("vmacc.vx v6, %0, v18" ::"r"(t2));

  f_ = f + 1;
  // Fetch the middle column of the filter, and start calculating its
  // contributions on the output rows To do so, slide down the input rows by one
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t2));

  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));

  asm volatile("vmacc.vx v0, %0, v22" ::"r"(t1));
  asm volatile("vslidedown.vi v26, v14, 1");
  asm volatile("vmacc.vx v2, %0, v22" ::"r"(t0));

  asm volatile("vmacc.vx v0, %0, v24" ::"r"(t2));
  asm volatile("vmacc.vx v2, %0, v24" ::"r"(t1));
  asm volatile("vslidedown.vi v28, v16, 1");
  asm volatile("vmacc.vx v4, %0, v24" ::"r"(t0));

  asm volatile("vmacc.vx v2, %0, v26" ::"r"(t2));
  asm volatile("vmacc.vx v4, %0, v26" ::"r"(t1));
  asm volatile("vslidedown.vi v30, v18, 1");
  asm volatile("vmacc.vx v6, %0, v26" ::"r"(t0));

  asm volatile("vmacc.vx v4, %0, v28" ::"r"(t2));
  asm volatile("vslidedown.vi v20, v8,  2");
  asm volatile("vmacc.vx v6, %0, v28" ::"r"(t1));

  asm volatile("vmacc.vx v6, %0, v30" ::"r"(t2));
  asm volatile("vslidedown.vi v22, v10, 2");

  f_ = f + 2;
  // Repeat for the last filter column, and then store the output rows
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t0) : "r"(ldf));
  asm volatile("ld %1, (%0); add %0, %0, %2" : "+&r"(f_), "=&r"(t1) : "r"(ldf));
  asm volatile("ld %1, (%0);" : "+&r"(f_), "=&r"(t2));

  asm volatile("vmacc.vx v0, %0, v20" ::"r"(t0));

  asm volatile("vmacc.vx v0, %0, v22" ::"r"(t1));
  asm volatile("vslidedown.vi v24, v12, 2");
  asm volatile("vmacc.vx v2, %0, v22" ::"r"(t0));

  // Compute on C elements

  asm volatile("vmacc.vx v0, %0, v24" ::"r"(t2));
  asm volatile("vse64.v  v0, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vslidedown.vi v26, v14, 2");
  asm volatile("vmacc.vx v2, %0, v24" ::"r"(t1));
  asm volatile("vmacc.vx v4, %0, v24" ::"r"(t0));

  asm volatile("vmacc.vx v2, %0, v26" ::"r"(t2));
  asm volatile("vse64.v  v2, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vslidedown.vi v28, v16, 2");
  asm volatile("vmacc.vx v4, %0, v26" ::"r"(t1));
  asm volatile("vmacc.vx v6, %0, v26" ::"r"(t0));

  asm volatile("vmacc.vx v4, %0, v28" ::"r"(t2));
  asm volatile("vslidedown.vi v30, v18, 2");
  asm volatile("vse64.v  v4, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vmacc.vx v6, %0, v28" ::"r"(t1));

  asm volatile("vmacc.vx v6, %0, v30" ::"r"(t2));
  asm volatile("vse64.v  v6, (%0);" : "+r"(o));
}

void iconv2d_vec_4xC_slice_move_3x3(int64_t C, int64_t F) {
  // Move C+F-1 elements
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C + F - 1));
  // Move the last floor(F/2) + 1 input rows
  asm volatile("vmv.v.v v8, v16");
  asm volatile("vmv.v.v v10, v18");
}
