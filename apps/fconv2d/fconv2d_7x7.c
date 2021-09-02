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

/*
  Optimized convolution for Ara
  The code is long only because of:
  1) Special cases related to the first/last 7 rows
  2) Unrolling of the loops to hide the latency of the moves, slides, mem ops

  At the end of the file, you can find the not-unrolled main loop in a comment, without the
  edge-code.

  Algorithm:
  a) Load the next input row
  b) Calculate its contributions to the F = 7 output rows using one column of the filter
  c) Slide down the input row by 1, injecting the next input scalar element in the tail
  d) Repeat from b), taking the next colum of the filter, until the last column is fetched
  e) Store the first output row, the one that is complete
  f) Move all the output rows up by one register, to restore the initial condition
  g) Repeat from a)

  Every time a new input row is loaded, a new output row is created.

  The first 6 rows and the last 6 rows do not follow this pattern, thus we wrote dedicated code.
  Because of the unrolling, we counted for this the first and last 7 rows, instead of 6

  This algorithm helps in minimizing the data dependencies, as every input rows is used
  To calculate 7 different output rows.
*/

#include "fconv2d.h"

void fconv2d_7x7_opt(double *o, double *i, double *f, int64_t R,
                         int64_t C, int64_t F) {

  // Helper variables
  int64_t ldo = C << 3;
  int64_t ldi = C << 3;
  int64_t ldi_pad = (C + F - 1) << 3;

  double f6, f13, f20, f27, f34, f41, f48;

  double *i_slide_ptr_0;
  double *i_slide_ptr_1;
  double *i_slide_ptr_2;
  double *i_slide_ptr_3;

  // Buffer some of the filter coefficients not to lose efficiency after a vector store
  // (CVA6 cannot issue memory operations if there is a pending store!)
  f6  = f[6 ];
  f13 = f[13];
  f20 = f[20];
  f27 = f[27];
  f34 = f[34];
  f41 = f[41];
  f48 = f[48];

  // Point to the scalar elements to insert during a slide
  i_slide_ptr_0 = i + C + 0*(C + F - 1);
  i_slide_ptr_1 = i + C + 1*(C + F - 1);
  i_slide_ptr_2 = i + C + 2*(C + F - 1);
  i_slide_ptr_3 = i + C + 3*(C + F - 1);

  // Compute on C elements
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(C));

  ////////////////
  // Row 0 -> 3 //
  ////////////////

  // Load one input row
  asm volatile("vle64.v v0, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vle64.v v4, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vle64.v v8, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vle64.v v12, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));

  // Main kernel, unrolled by 2
  for (int k = 0; k < F/2; ++k) {
    if (k == 0)
      asm volatile("vfmul.vf v16, v0, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[0 + (2*k)]));
    if (k == 0)
      asm volatile("vfmul.vf v18, v4, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v18, %0, v4" :: "f"(f[0 + (2*k)]));
    asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v16, %0, v4" :: "f"(f[7 + (2*k)]));
    if (k == 0)
      asm volatile("vfmul.vf v22, v12, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v22, %0, v12" :: "f"(f[0 + (2*k)]));
    asm volatile("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v18, %0, v8" :: "f"(f[7 + (2*k)]));
    asm volatile("vfmacc.vf v16, %0, v8" :: "f"(f[14 + (2*k)]));
    asm volatile("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++));
    if (k == 0)
      asm volatile("vfmul.vf v20, v8, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v20, %0, v8" :: "f"(f[0 + (2*k)]));
    asm volatile("vfmacc.vf v18, %0, v12" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v16, %0, v12" :: "f"(f[21 + (2*k)]));
    asm volatile("vfslide1down.vf v14, v12, %0" :: "f"(*i_slide_ptr_3++));
    asm volatile("vfmacc.vf v20, %0, v12" :: "f"(f[7 + (2*k)]));

    asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v6" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v16, %0, v6" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v10" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfmacc.vf v20, %0, v10" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v16, %0, v10" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v14" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++));
    asm volatile("vfmacc.vf v22, %0, v14" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfmacc.vf v16, %0, v14" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v12, v14, %0" :: "f"(*i_slide_ptr_3++));
    asm volatile("vfmacc.vf v20, %0, v14" :: "f"(f[7 + (2*k + 1)]));
  }

  // Start calculating the next pointers to the elements to be slided in
  i_slide_ptr_0 = i + C + 0*(C + F - 1);
  i_slide_ptr_1 = i + C + 1*(C + F - 1);
  i_slide_ptr_2 = i + C + 2*(C + F - 1);

  // Main kernel, last iteration with filter coefficients reuse
  // Start loading next rows, from 4 to 6
  asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f6));
  asm volatile("vle64.v v2, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v18, %0, v4" :: "f"(f6));
  asm volatile("vfmacc.vf v22, %0, v12" :: "f"(f6));
  asm volatile("vfmacc.vf v16, %0, v4" :: "f"(f13));
  asm volatile("vle64.v v6, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v18, %0, v8" :: "f"(f13));
  asm volatile("vfmacc.vf v20, %0, v8" :: "f"(f6));
  asm volatile("vfmacc.vf v16, %0, v8" :: "f"(f20));
  asm volatile("vle64.v v10, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v18, %0, v12" :: "f"(f20));
  asm volatile("vfmacc.vf v20, %0, v12" :: "f"(f13));
  asm volatile("vfmacc.vf v16, %0, v12" :: "f"(f27));

  ////////////////
  // Row 4 -> 6 //
  ////////////////

  // Main kernel, unrolled by 2
  for (int k = 0; k < F/2; ++k) {
    asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v16, %0, v6" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v18, %0, v6" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v16, %0, v10" :: "f"(f[42 + (2*k)]));
    asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++));

    asm volatile("vfmacc.vf v18, %0, v10" :: "f"(f[35 + (2*k)]));
    asm volatile("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++));

    asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v20, %0, v6" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v20, %0, v10" :: "f"(f[28 + (2*k)]));
    asm volatile("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++));

    asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f[7 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v6" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v10" :: "f"(f[21 + (2*k)]));

    if (k == 0)
      asm volatile("vfmul.vf v24, v2, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[0 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v6" :: "f"(f[7 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v10" :: "f"(f[14 + (2*k)]));

    if (k == 0)
      asm volatile("vfmul.vf v26, v6, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v26, %0, v6" :: "f"(f[0 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v10" :: "f"(f[7 + (2*k)]));

    if (k == 0)
      asm volatile("vfmul.vf v28, v10, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v28, %0, v10" :: "f"(f[0 + (2*k)]));

    asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v16, %0, v4" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v16, %0, v8" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++));

    asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v4" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v8" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++));

    asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfmacc.vf v20, %0, v4" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfmacc.vf v20, %0, v8" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++));

    asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfmacc.vf v22, %0, v4" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfmacc.vf v22, %0, v8" :: "f"(f[21 + (2*k + 1)]));

    asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v4" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v8" :: "f"(f[14 + (2*k + 1)]));

    asm volatile("vfmacc.vf v26, %0, v4" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v8" :: "f"(f[7 + (2*k + 1)]));

    asm volatile("vfmacc.vf v28, %0, v8" :: "f"(f[0 + (2*k + 1)]));
  }

  // Main kernel, last iteration with filter coefficients reuse
  asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f34));
  asm volatile("vfmacc.vf v16, %0, v6" :: "f"(f41));
  asm volatile("vfmacc.vf v16, %0, v10" :: "f"(f48));
  asm volatile("vse64.v v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));

  asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f27));
  asm volatile("vfmacc.vf v18, %0, v6" :: "f"(f34));
  asm volatile("vfmacc.vf v18, %0, v10" :: "f"(f41));
  asm volatile("vmv.v.v v16, v18");

  asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f20));
  asm volatile("vfmacc.vf v20, %0, v6" :: "f"(f27));
  asm volatile("vfmacc.vf v20, %0, v10" :: "f"(f34));
  asm volatile("vmv.v.v v18, v20");

  asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f13));
  asm volatile("vfmacc.vf v22, %0, v6" :: "f"(f20));
  asm volatile("vfmacc.vf v22, %0, v10" :: "f"(f27));
  asm volatile("vmv.v.v v20, v22");

  asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f6));
  asm volatile("vfmacc.vf v24, %0, v6" :: "f"(f13));
  asm volatile("vfmacc.vf v24, %0, v10" :: "f"(f20));
  asm volatile("vmv.v.v v22, v24");

  asm volatile("vfmacc.vf v26, %0, v6" :: "f"(f6));
  asm volatile("vfmacc.vf v26, %0, v10" :: "f"(f13));
  asm volatile("vmv.v.v v24, v26");

  asm volatile("vfmacc.vf v28, %0, v10" :: "f"(f6));
  asm volatile("vmv.v.v v26, v28");

  ////////////
  // REGIME //
  ////////////

  // Start calculating the next pointers to the elements to be slided in
  i_slide_ptr_0 = i + C;

  asm volatile("vle64.v v0, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));

  // The following loop is unrolled by 2
  // The input matrix has R + F - 1 rows
  // We have computed F input rows already
  // Compute now until only F input rows are left
  // (The last F-1 rows do not contribute to F output rows each, so keep them outside of this loop)
  // (We keep F rows outside because of the unrolling by 2, just for easeness)
  for (int j = 0; j < ((R + F - 1) - 2*F)/2; ++j) {
    // Work on F output rows

    //////////////
    // UNROLL 0 //
    //////////////

    // Main loop
    for (int k = 0; k < F/2; ++k) {
      // Calculate F contributions of the input rows, on F different output rows
      asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[42  + (2*k)]));
      asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f[35  + (2*k)]));
      asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f[28 + (2*k)]));
      asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f[21 + (2*k)]));
      asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[14 + (2*k)]));
      asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f[7 + (2*k)]));
      if (k == 0)
        asm volatile("vfmul.vf v28, v0, %0" :: "f"(f[0 + (2*k)]));
      else
        asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f[0 + (2*k)]));

      // Calculate F contributions of the input rows, on F different output rows
      asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[42  + (2*k + 1)]));
      asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f[35  + (2*k + 1)]));
      asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f[28 + (2*k + 1)]));
      asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f[21 + (2*k + 1)]));
      asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[14 + (2*k + 1)]));
      asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f[7 + (2*k + 1)]));
      asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f[0 + (2*k + 1)]));
    }

    // Start calculating the next pointers to the elements to be slided in
    i_slide_ptr_1 = i + C;

    // The last iteration is used to mask the latency of the store and the moves
    // Use buffered coefficients not to stall CVA6 for coherency
    asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f48));
    asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f41));
    asm volatile("vmv.v.v v16, v18");
    asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f34));
    asm volatile("vle64.v v2, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
    asm volatile("vmv.v.v v18, v20");
    asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f27));
    asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f20));
    asm volatile("vmv.v.v v20, v22");
    asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f13));
    asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f6));
    asm volatile("vmv.v.v v22, v24");

    //////////////
    // UNROLL 1 //
    //////////////

    asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[42]));
    asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f[35]));
    asm volatile("vmv.v.v v24, v26");
    asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f[28]));
    asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f[21]));
    asm volatile("vmv.v.v v26, v28");
    asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[14]));
    asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f[7]));
    asm volatile("vfmul.vf v28, v2, %0" :: "f"(f[0]));

    for (int k = 1; k < F; k += 2) {
      asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[42  + k]));
      asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f[35  + k]));
      asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f[28 + k]));
      asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f[21 + k]));
      asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[14 + k]));
      asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f[7 + k]));
      asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f[0 + k]));

      if (k == F - 2)
        break;

      asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[42  + (k + 1)]));
      asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f[35  + (k + 1)]));
      asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f[28 + (k + 1)]));
      asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f[21 + (k + 1)]));
      asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[14 + (k + 1)]));
      asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f[7 + (k + 1)]));
      asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f[0 + (k + 1)]));
    }

    // Start calculating the next pointers to the elements to be slided in
    i_slide_ptr_0 = i + C;

    asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f48));
    asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f41));
    asm volatile("vmv.v.v v16, v18");
    asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f34));
    asm volatile("vle64.v v0, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
    asm volatile("vmv.v.v v18, v20");
    asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f27));
    asm volatile("vmv.v.v v20, v22");
    asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f20));
    asm volatile("vmv.v.v v22, v24");
    asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f13));
    asm volatile("vmv.v.v v24, v26");
    asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f6));
    asm volatile("vmv.v.v v26, v28");
  }

  ////////////////////////
  // Row I-F -> (I-1)-3 //
  ////////////////////////

  // Point to the scalar elements to insert during a slide
  // i_slide_ptr_0 has already been computed
  i_slide_ptr_1 = i + C + 0*(C + F - 1);
  i_slide_ptr_2 = i + C + 1*(C + F - 1);
  i_slide_ptr_3 = i + C + 2*(C + F - 1);

  // Load other three input rows (one was already loaded)
  asm volatile("vle64.v v4, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vle64.v v8, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vle64.v v12, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));

  // Main kernel, unrolled by 2
  // Process 4 input rows
  for (int k = 0; k < F/2; ++k) {
    asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[42 + (2*k)]));
    asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f[7 + (2*k)]));
    if (k == 0)
      asm volatile("vfmul.vf v28, v0, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f[0 + (2*k)]));
    asm volatile("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v18, %0, v4" :: "f"(f[42 + (2*k)]));
    asm volatile("vfmacc.vf v20, %0, v4" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v4" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v4" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v4" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v28, %0, v4" :: "f"(f[7 + (2*k)]));
    asm volatile("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++));
    asm volatile("vfmacc.vf v20, %0, v8" :: "f"(f[42 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v8" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v8" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v8" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v28, %0, v8" :: "f"(f[14 + (2*k)]));
    asm volatile("vfslide1down.vf v14, v12, %0" :: "f"(*i_slide_ptr_3++));
    asm volatile("vfmacc.vf v22, %0, v12" :: "f"(f[42 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v12" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v12" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v28, %0, v12" :: "f"(f[21 + (2*k)]));

    asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v16, %0, v2" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfmacc.vf v18, %0, v2" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v20, %0, v2" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v22, %0, v2" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f[0 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v18, %0, v6" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfmacc.vf v20, %0, v6" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v22, %0, v6" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v6" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v6" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfmacc.vf v28, %0, v6" :: "f"(f[7 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++));
    asm volatile("vfmacc.vf v20, %0, v10" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfmacc.vf v22, %0, v10" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v10" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v10" :: "f"(f[21 + (2*k + 1)]));
    asm volatile("vfmacc.vf v28, %0, v10" :: "f"(f[14 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v12, v14, %0" :: "f"(*i_slide_ptr_3++));
    asm volatile("vfmacc.vf v22, %0, v14" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfmacc.vf v24, %0, v14" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v14" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v28, %0, v14" :: "f"(f[21 + (2*k + 1)]));
  }

  // Start calculating the next pointers to the elements to be slided in
  i_slide_ptr_0 = i + C + 0*(C + F - 1);
  i_slide_ptr_1 = i + C + 1*(C + F - 1);
  i_slide_ptr_2 = i + C + 2*(C + F - 1);

  asm volatile("vle64.v v2, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f48));
  asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f41));
  asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f34));
  asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f27));
  asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f20));
  asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f13));
  asm volatile("vle64.v v6, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f6));
  asm volatile("vfmacc.vf v18, %0, v4" :: "f"(f48));
  asm volatile("vfmacc.vf v20, %0, v4" :: "f"(f41));
  asm volatile("vse64.v  v18, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v22, %0, v4" :: "f"(f34));
  asm volatile("vfmacc.vf v24, %0, v4" :: "f"(f27));
  asm volatile("vfmacc.vf v26, %0, v4" :: "f"(f20));
  asm volatile("vle64.v v10, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));
  asm volatile("vfmacc.vf v28, %0, v4" :: "f"(f13));
  asm volatile("vfmacc.vf v20, %0, v8" :: "f"(f48));
  asm volatile("vfmacc.vf v22, %0, v8" :: "f"(f41));
  asm volatile("vse64.v  v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v24, %0, v8" :: "f"(f34));
  asm volatile("vfmacc.vf v26, %0, v8" :: "f"(f27));
  asm volatile("vfmacc.vf v28, %0, v8" :: "f"(f20));
  asm volatile("vfmacc.vf v22, %0, v12" :: "f"(f48));
  asm volatile("vse64.v  v22, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v24, %0, v12" :: "f"(f41));
  asm volatile("vfmacc.vf v26, %0, v12" :: "f"(f34));
  asm volatile("vfmacc.vf v28, %0, v12" :: "f"(f27));

  //////////////////////////
  // Row (I-1)-3 -> (I-1) //
  //////////////////////////

  // Main kernel, unrolled by 2
  for (int k = 0; k < F/2; ++k) {
    asm volatile("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f[42 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f[35 + (2*k)]));
    asm volatile("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v6" :: "f"(f[42 + (2*k)]));
    asm volatile("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++));
    asm volatile("vfmacc.vf v28, %0, v6" :: "f"(f[35 + (2*k)]));
    asm volatile("vfmacc.vf v28, %0, v10" :: "f"(f[42 + (2*k)]));

    asm volatile("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++));
    asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++));
    asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f[28 + (2*k + 1)]));
    asm volatile("vfmacc.vf v26, %0, v4" :: "f"(f[42 + (2*k + 1)]));
    asm volatile("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++));
    asm volatile("vfmacc.vf v28, %0, v4" :: "f"(f[35 + (2*k + 1)]));
    asm volatile("vfmacc.vf v28, %0, v8" :: "f"(f[42 + (2*k + 1)]));
  }

  asm volatile("vfmacc.vf v24, %0, v2" :: "f"(f48));
  asm volatile("vse64.v  v24, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v26, %0, v2" :: "f"(f41));
  asm volatile("vfmacc.vf v28, %0, v2" :: "f"(f34));
  asm volatile("vfmacc.vf v26, %0, v6" :: "f"(f48));
  asm volatile("vse64.v  v26, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v28, %0, v6" :: "f"(f41));
  asm volatile("vfmacc.vf v28, %0, v10" :: "f"(f48));
  asm volatile("vse64.v  v28, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
}

/*
  ////////////////////
  // MAIN ALGORITHM //
  ////////////////////

  // Start calculating the pointer to the next element to be slided in
  i_slide_ptr_0 = i + C;

  // Load one input row
  asm volatile("vle64.v v0, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));

  // Kernel
  for (int k = 0; k < F; ++k) {
    // Calculate F*F contributions of the input rows, on F different output rows
    // v28 should be initialized during the first iteration
    asm volatile("vfmacc.vf v16, %0, v0" :: "f"(f[42  + (2*k)]));
    asm volatile("vfmacc.vf v18, %0, v0" :: "f"(f[35  + (2*k)]));
    asm volatile("vfmacc.vf v20, %0, v0" :: "f"(f[28 + (2*k)]));
    asm volatile("vfmacc.vf v22, %0, v0" :: "f"(f[21 + (2*k)]));
    asm volatile("vfmacc.vf v24, %0, v0" :: "f"(f[14 + (2*k)]));
    asm volatile("vfmacc.vf v26, %0, v0" :: "f"(f[7 + (2*k)]));
    if (k == 0)
      asm volatile("vfmul.vf v28, v0, %0" :: "f"(f[0 + (2*k)]));
    else
      asm volatile("vfmacc.vf v28, %0, v0" :: "f"(f[0 + (2*k)]));

    // Slide the input row by one, and inject the next scalar element of the row
    asm volatile("vfslide1down.vf v0, v0, %0" :: "f"(*i_slide_ptr_0++));
  }

  // Store one output row
  asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));

  // Move all the input rows to return to the initial situation
  // To avoid these operations, unroll the loop via software, renaming the registers manually
  asm volatile("vmv.v.v v16, v18");
  asm volatile("vmv.v.v v18, v20");
  asm volatile("vmv.v.v v20, v22");
  asm volatile("vmv.v.v v22, v24");
  asm volatile("vmv.v.v v24, v26");
  asm volatile("vmv.v.v v26, v28");
*/
