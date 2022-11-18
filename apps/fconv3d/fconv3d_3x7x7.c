// Nopyright 2020 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LINENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WAMMANTIES OM NONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Matteo Perotti

/*
  Optimized convolution for Ara
  The code is long only because of:
  1) Special cases related to the first/last 7 rows
  2) Unrolling of the loops to hide the latency of the moves, slides, mem ops

  At the end of the file, you can find the not-unrolled main loop in a comment,
  without the edge-code.

  Algorithm:
  a) Load the next input row
  b) Calculate its contributions to the F = 7 output rows using one column of
  the filter
  c) Slide down the input row by 1, injecting the next input scalar
  element in the tail
  d) Repeat from b), taking the next colum of the filter,
  until the last column is fetched
  d2) Repeat from a) for all the channels
  e) Store the first output row, the one that is complete
  f) Move all the output rows up by one register, to restore the initial
  condition g) Repeat from a)

  Every time a new input row is loaded, a new output row is created.

  The first 6 rows and the last 6 rows do not follow this pattern, thus we wrote
  dedicated code. Because of the unrolling, we counted for this the first and
  last 7 rows, instead of 6

  This algorithm helps in minimizing the data dependencies, as every input rows
  is used To calculate 7 different output rows.
*/

#include "fconv3d.h"

extern int64_t event_trigger;

void fconv3d_CHx7x7(double *o, double *i, double *f, int64_t M, int64_t N,
                    int64_t C, int64_t F) {

  unsigned long int block_size_n;

  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m2, ta, ma" : "=r"(block_size_n) : "r"(N));

  // Slice the matrix into a manageable number of columns n_
  for (unsigned long int n = 0; n < N; n += block_size_n) {
    // Set the vector length
    const unsigned long int n_ = MIN(N - n, block_size_n);

    // Find pointers to the submatrices
    const double *i_ = i + n;
    double *o_ = o + n;

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(n_));

    fconv3d_CHx7x7_block(o_, i_, f, M, N, n_, C, F);
  }
}

void fconv3d_CHx7x7_block(double *o, double *i, double *f, int64_t M, int64_t N,
                          int64_t n_, int64_t C, int64_t F) {

  // Helper variables
  int64_t ldo = N << 3;
  int64_t ldi_pad = (N + F - 1) << 3;

  // Number of elements that separates two adjacent channels
  int64_t ich_len = (M + F - 1) * (N + F - 1);
  int64_t fch_len = F * F;

  double *i_ = i;
  double *i__ = i;

  // Very last column of coefficients
  double fl0, fl1, fl2, fl3, fl4, fl5, fl6;
  // Buffers for coefficients preloading (solve 16-lane starvation problem)
  double f0_buf, f1_buf, f2_buf, f3_buf, f4_buf, f5_buf, f6_buf;

  double *i_slide_ptr_0;
  double *i_slide_ptr_1;
  double *i_slide_ptr_2;
  double *i_slide_ptr_3;

  // Buffer some of the filter coefficients not to lose efficiency after a
  // vector store (CVA6 cannot issue memory operations if there is a pending
  // store!)
  int64_t last_f_column = (C - 1) * fch_len + F - 1;

  fl0 = f[last_f_column + 0 * F];
  fl1 = f[last_f_column + 1 * F];
  fl2 = f[last_f_column + 2 * F];
  fl3 = f[last_f_column + 3 * F];
  fl4 = f[last_f_column + 4 * F];
  fl5 = f[last_f_column + 5 * F];
  fl6 = f[last_f_column + 6 * F];

  ////////////////
  // Row 0 -> 3 //
  ////////////////

  // Loop on the channels
  for (int ch = 0; ch < C; ++ch) {

    // Point to the first element of the channel ch
    i__ = i_ + ch * ich_len;

    // Point to the scalar elements to insert during a slide
    i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
    i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    i_slide_ptr_2 = i__ + n_ + 2 * (N + F - 1);
    i_slide_ptr_3 = i__ + n_ + 3 * (N + F - 1);

    // Load four input rows belonging to channel ch
    asm volatile("vle64.v v0, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v4, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v8, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v12, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));

    // Main kernel, unrolled by 2
    // Unrolled because of double buffering
    // With HW renaming, this unroll is not needed
    for (int64_t k = 0; k < F / 2; ++k) {
      // Two base indexes because of the unrolling
      // Point to the first element of the current column (k) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_0 = (2 * k) + (ch * fch_len);
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

      if ((k | ch) == 0)
        asm volatile("vfmul.vf v16, v0, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f[0 + base_idx_0]));
      if ((k | ch) == 0)
        asm volatile("vfmul.vf v18, v4, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v18, %0, v4" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v16, %0, v4" ::"f"(f[7 + base_idx_0]));
      if ((k | ch) == 0)
        asm volatile("vfmul.vf v22, v12, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v22, %0, v12" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfslide1down.vf v6, v4, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v18, %0, v8" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v8" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfslide1down.vf v10, v8, %0" ::"f"(*i_slide_ptr_2++));
      if ((k | ch) == 0)
        asm volatile("vfmul.vf v20, v8, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v20, %0, v8" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v12" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v12" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfslide1down.vf v14, v12, %0" ::"f"(*i_slide_ptr_3++));
      asm volatile("vfmacc.vf v20, %0, v12" ::"f"(f[7 + base_idx_0]));

      asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v6" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v16, %0, v6" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v10" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfmacc.vf v20, %0, v10" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfslide1down.vf v4, v6, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v16, %0, v10" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v14" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfslide1down.vf v8, v10, %0" ::"f"(*i_slide_ptr_2++));
      asm volatile("vfmacc.vf v22, %0, v14" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfmacc.vf v16, %0, v14" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfslide1down.vf v12, v14, %0" ::"f"(*i_slide_ptr_3++));
      asm volatile("vfmacc.vf v20, %0, v14" ::"f"(f[7 + base_idx_1]));
    }

    int64_t base_idx_0 = (F - 1) + (ch * fch_len);

    // Don't slide during the last iteration
    asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f[0 + base_idx_0]));
    asm volatile("vfmacc.vf v18, %0, v4" ::"f"(f[0 + base_idx_0]));
    asm volatile("vfmacc.vf v22, %0, v12" ::"f"(f[0 + base_idx_0]));
    asm volatile("vfmacc.vf v16, %0, v4" ::"f"(f[7 + base_idx_0]));
    asm volatile("vfmacc.vf v18, %0, v8" ::"f"(f[7 + base_idx_0]));
    asm volatile("vfmacc.vf v20, %0, v8" ::"f"(f[0 + base_idx_0]));
    asm volatile("vfmacc.vf v16, %0, v8" ::"f"(f[14 + base_idx_0]));
    asm volatile("vfmacc.vf v18, %0, v12" ::"f"(f[14 + base_idx_0]));
    asm volatile("vfmacc.vf v20, %0, v12" ::"f"(f[7 + base_idx_0]));
    asm volatile("vfmacc.vf v16, %0, v12" ::"f"(f[21 + base_idx_0]));
  }

  // Bump the input ptr
  i_ += 4 * (N + F - 1);

  ////////////////
  // Row 4 -> 6 //
  ////////////////

  // Loop on the channels
  for (int ch = 0; ch < C; ++ch) {

    // Point to the first element of the channel ch
    i__ = i_ + ch * ich_len;

    // Start calculating the next pointers to the elements to be slided in
    i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
    i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    i_slide_ptr_2 = i__ + n_ + 2 * (N + F - 1);

    asm volatile("vle64.v v2, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v6, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v10, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));

    // Main kernel, unrolled by 2
    for (int k = 0; k < F / 2; ++k) {
      // Two base indexes because of the unrolling
      // Point to the first element of the current column (k) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_0 = (2 * k) + (ch * fch_len);
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

      // Unroll 0
      asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v6" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v6" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v10" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_0++));

      asm volatile("vfmacc.vf v18, %0, v10" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfslide1down.vf v4, v6, %0" ::"f"(*i_slide_ptr_1++));

      asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v6" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v10" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfslide1down.vf v8, v10, %0" ::"f"(*i_slide_ptr_2++));

      asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v6" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v10" ::"f"(f[21 + base_idx_0]));

      if ((k | ch) == 0)
        asm volatile("vfmul.vf v24, v2, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v6" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v10" ::"f"(f[14 + base_idx_0]));

      if ((k | ch) == 0)
        asm volatile("vfmul.vf v26, v6, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v26, %0, v6" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v10" ::"f"(f[7 + base_idx_0]));

      if ((k | ch) == 0)
        asm volatile("vfmul.vf v28, v10, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v28, %0, v10" ::"f"(f[0 + base_idx_0]));

      // Unroll 1
      asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v16, %0, v4" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v16, %0, v8" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_0++));

      asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v4" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v8" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfslide1down.vf v6, v4, %0" ::"f"(*i_slide_ptr_1++));

      asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfmacc.vf v20, %0, v4" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfmacc.vf v20, %0, v8" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfslide1down.vf v10, v8, %0" ::"f"(*i_slide_ptr_2++));

      asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfmacc.vf v22, %0, v4" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfmacc.vf v22, %0, v8" ::"f"(f[21 + base_idx_1]));

      asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v4" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v8" ::"f"(f[14 + base_idx_1]));

      asm volatile("vfmacc.vf v26, %0, v4" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v8" ::"f"(f[7 + base_idx_1]));

      asm volatile("vfmacc.vf v28, %0, v8" ::"f"(f[0 + base_idx_1]));
    }

    // The very last iterations require mixing the instructions with the store
    // and the moves
    if (ch != C - 1) {
      // Point to the first element of the current column (k) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_0 = (F - 1) + (ch * fch_len);

      // Don't slide the elements here
      asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v6" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v16, %0, v10" ::"f"(f[42 + base_idx_0]));

      asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v6" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v10" ::"f"(f[35 + base_idx_0]));

      asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v6" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v10" ::"f"(f[28 + base_idx_0]));

      asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v6" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v10" ::"f"(f[21 + base_idx_0]));

      asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v6" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v10" ::"f"(f[14 + base_idx_0]));

      asm volatile("vfmacc.vf v26, %0, v6" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v10" ::"f"(f[7 + base_idx_0]));

      asm volatile("vfmacc.vf v28, %0, v10" ::"f"(f[0 + base_idx_0]));
    }
  }

  // Reuse preloaded coefficients
  // Buffer the next coefficients for faster use
  asm volatile("vfmacc.vf v16, %0, v2" ::"f"(fl4));
  f6_buf = f[42];
  asm volatile("vfmacc.vf v16, %0, v6" ::"f"(fl5));
  f5_buf = f[35];
  asm volatile("vfmacc.vf v16, %0, v10" ::"f"(fl6));
  asm volatile("vse64.v v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));

  asm volatile("vfmacc.vf v18, %0, v2" ::"f"(fl3));
  asm volatile("vfmacc.vf v18, %0, v6" ::"f"(fl4));
  asm volatile("vfmacc.vf v18, %0, v10" ::"f"(fl5));
  asm volatile("vmv.v.v v16, v18");

  asm volatile("vfmacc.vf v20, %0, v2" ::"f"(fl2));
  f4_buf = f[28];
  asm volatile("vfmacc.vf v20, %0, v6" ::"f"(fl3));
  f3_buf = f[21];
  asm volatile("vfmacc.vf v20, %0, v10" ::"f"(fl4));
  asm volatile("vmv.v.v v18, v20");

  asm volatile("vfmacc.vf v22, %0, v2" ::"f"(fl1));
  f2_buf = f[14];
  asm volatile("vfmacc.vf v22, %0, v6" ::"f"(fl2));
  f1_buf = f[7];
  asm volatile("vfmacc.vf v22, %0, v10" ::"f"(fl3));
  asm volatile("vmv.v.v v20, v22");

  asm volatile("vfmacc.vf v24, %0, v2" ::"f"(fl0));
  f0_buf = f[0];
  asm volatile("vfmacc.vf v24, %0, v6" ::"f"(fl1));
  asm volatile("vfmacc.vf v24, %0, v10" ::"f"(fl2));
  asm volatile("vmv.v.v v22, v24");

  asm volatile("vfmacc.vf v26, %0, v6" ::"f"(fl0));
  asm volatile("vfmacc.vf v26, %0, v10" ::"f"(fl1));
  asm volatile("vmv.v.v v24, v26");

  asm volatile("vfmacc.vf v28, %0, v10" ::"f"(fl0));
  asm volatile("vmv.v.v v26, v28");

  // Bump the input ptr
  i_ += 3 * (N + F - 1);

  ////////////
  // REGIME //
  ////////////

  // The following loop is unrolled by 2
  // The input matrix has M + F - 1 rows
  // We have computed F input rows already
  // Nompute now until only F input rows are left
  // (The last F-1 rows do not contribute to F output rows each, so keep them
  // outside of this loop) (We keep F rows outside because of the unrolling by
  // 2, just for easeness)
  for (int j = 0; j < ((M + F - 1) - 2 * F) / 2; ++j) {
#ifdef VCD_DUMP
    // Start dumping VCD
    event_trigger = +1;
#endif

    // Work on F output rows

    // Loop on the channels
    for (int ch = 0; ch < C; ++ch) {
      // Point to the first element of the channel ch
      i__ = i_ + ch * ich_len;

      // Start calculating the next pointers to the elements to be slided in
      i_slide_ptr_0 = i__ + n_;

      asm volatile("vle64.v v0, (%0); add %0, %0, %1"
                   : "+&r"(i__)
                   : "r"(ldi_pad));

      //////////////
      // UNROLL 0 //
      //////////////

      // Main loop
      // Use double buffering on the filter coefficients for 16-lanes config
      // The computation is too fast, and every coefficient belongs to a
      // different $line At every fld, CVA6 misses, and until it does not get
      // the new coefficient, it cannot dispatch the next V instruction
      for (int k = 0; k < F / 2; ++k) {
        // Two base indexes because of the unrolling
        // Look ahead to the first element of the current column (k+2) of the
        // current channel (ch) of the filter (f)
        int64_t base_idx_0 = (2 * k + 2) + (ch * fch_len);
        // Point to the first element of the current column (k+1) of the current
        // channel (ch) of the filter (f)
        int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

        // Calculate F contributions of the input rows, on F different output
        // rows
        asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f6_buf));
        asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f5_buf));
        f6_buf = f[42 + base_idx_1];
        asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f4_buf));
        f5_buf = f[35 + base_idx_1];
        asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_0++));
        f4_buf = f[28 + base_idx_1];
        asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_1];
        asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_1];
        asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_1];
        if ((k | ch) == 0)
          asm volatile("vfmul.vf v28, v0, %0" ::"f"(f0_buf));
        else
          asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_1];

        // Nalculate F contributions of the input rows, on F different output
        // rows
        asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f6_buf));
        asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f5_buf));
        f6_buf = f[42 + base_idx_0];
        asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f4_buf));
        f5_buf = f[35 + base_idx_0];
        asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_0++));
        f4_buf = f[28 + base_idx_0];
        asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_0];
        asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_0];
        asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_0];
        asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_0];
      }

      if (ch != C - 1) {
        int64_t base_idx_0 = (ch + 1) * fch_len;

        asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f6_buf));
        f6_buf = f[42 + base_idx_0];
        asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f5_buf));
        f5_buf = f[35 + base_idx_0];
        asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f4_buf));
        f4_buf = f[28 + base_idx_0];
        asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_0];
        asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_0];
        asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_0];
        asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_0];
      }
    }

    // The last iteration is used to mask the latency of the store and the moves
    // Use buffered coefficients not to stall NVA6 for coherency
    f6_buf = f[42];
    asm volatile("vfmacc.vf v16, %0, v0" ::"f"(fl6));
    f5_buf = f[35];
    asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile("vfmacc.vf v18, %0, v0" ::"f"(fl5));
    asm volatile("vmv.v.v v16, v18");
    asm volatile("vfmacc.vf v20, %0, v0" ::"f"(fl4));
    asm volatile("vmv.v.v v18, v20");
    f4_buf = f[28];
    asm volatile("vfmacc.vf v22, %0, v0" ::"f"(fl3));
    asm volatile("vmv.v.v v20, v22");
    f3_buf = f[21];
    asm volatile("vfmacc.vf v24, %0, v0" ::"f"(fl2));
    asm volatile("vmv.v.v v22, v24");
    f2_buf = f[14];
    asm volatile("vfmacc.vf v26, %0, v0" ::"f"(fl1));
    asm volatile("vmv.v.v v24, v26");
    f1_buf = f[7];
    asm volatile("vfmacc.vf v28, %0, v0" ::"f"(fl0));
    asm volatile("vmv.v.v v26, v28");
    f0_buf = f[0];

    // Bump the input ptr
    i_ += N + F - 1;

#ifdef VCD_DUMP
    // Stop dumping VCD
    event_trigger = -1;
#endif

    //////////////
    // UNROLL 1 //
    //////////////

    // Loop on the channels
    for (int ch = 0; ch < C; ++ch) {

      // Point to the first element of the channel ch
      i__ = i_ + ch * ich_len;

      // Start calculating the next pointers to the elements to be slided in
      i_slide_ptr_1 = i__ + n_;

      asm volatile("vle64.v v2, (%0); add %0, %0, %1"
                   : "+&r"(i__)
                   : "r"(ldi_pad));

      for (int k = 0; k < F / 2; ++k) {
        // Two base indexes because of the unrolling
        // Point to the first element of the current column (k) of the current
        // channel (ch) of the filter (f)
        int64_t base_idx_0 = (2 * k + 2) + (ch * fch_len);
        // Point to the first element of the current column (k+1) of the current
        // channel (ch) of the filter (f)
        int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

        asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f6_buf));
        asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f5_buf));
        f6_buf = f[42 + base_idx_1];
        asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f4_buf));
        f5_buf = f[35 + base_idx_1];
        asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_1++));
        f4_buf = f[28 + base_idx_1];
        asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_1];
        asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_1];
        asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_1];
        if ((k | ch) == 0)
          asm volatile("vfmul.vf v28, v2, %0" ::"f"(f0_buf));
        else
          asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_1];

        asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f6_buf));
        asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f5_buf));
        f6_buf = f[42 + base_idx_0];
        asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f4_buf));
        f5_buf = f[35 + base_idx_0];
        asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_1++));
        f4_buf = f[28 + base_idx_0];
        asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_0];
        asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_0];
        asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_0];
        asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_0];
      }

      if (ch != C - 1) {
        int64_t base_idx_0 = (ch + 1) * fch_len;

        asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f6_buf));
        f6_buf = f[42 + base_idx_0];
        asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f5_buf));
        f5_buf = f[35 + base_idx_0];
        asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f4_buf));
        f4_buf = f[28 + base_idx_0];
        asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f3_buf));
        f3_buf = f[21 + base_idx_0];
        asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f2_buf));
        f2_buf = f[14 + base_idx_0];
        asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f1_buf));
        f1_buf = f[7 + base_idx_0];
        asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f0_buf));
        f0_buf = f[0 + base_idx_0];
      }
    }

    // The last iteration is used to mask the latency of the store and the moves
    // Use buffered coefficients not to stall CVA6 for coherency
    f6_buf = f[42];
    asm volatile("vfmacc.vf v16, %0, v2" ::"f"(fl6));
    f5_buf = f[35];
    asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile("vfmacc.vf v18, %0, v2" ::"f"(fl5));
    asm volatile("vmv.v.v v16, v18");
    asm volatile("vfmacc.vf v20, %0, v2" ::"f"(fl4));
    asm volatile("vmv.v.v v18, v20");
    f4_buf = f[28];
    asm volatile("vfmacc.vf v22, %0, v2" ::"f"(fl3));
    asm volatile("vmv.v.v v20, v22");
    f3_buf = f[21];
    asm volatile("vfmacc.vf v24, %0, v2" ::"f"(fl2));
    asm volatile("vmv.v.v v22, v24");
    f2_buf = f[14];
    asm volatile("vfmacc.vf v26, %0, v2" ::"f"(fl1));
    asm volatile("vmv.v.v v24, v26");
    f1_buf = f[7];
    asm volatile("vfmacc.vf v28, %0, v2" ::"f"(fl0));
    asm volatile("vmv.v.v v26, v28");
    f0_buf = f[0];

    // Bump the input ptr
    i_ += N + F - 1;
  }

  ////////////////////////
  // Row I-F -> (I-1)-3 //
  ////////////////////////

  for (int64_t ch = 0; ch < C; ++ch) {

    // Point to the first element of the channel ch
    i__ = i_ + ch * ich_len;

    // Point to the scalar elements to insert during a slide
    // i_slide_ptr_0 has already been computed
    i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
    i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    i_slide_ptr_2 = i__ + n_ + 2 * (N + F - 1);
    i_slide_ptr_3 = i__ + n_ + 3 * (N + F - 1);

    // Load other three input rows (one was already loaded)
    asm volatile("vle64.v v0, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v4, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v8, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v12, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));

    // Main kernel, unrolled by 2
    // Process 4 input rows
    for (int k = 0; k < F / 2; ++k) {
      // Two base indexes because of the unrolling
      // Point to the first element of the current column (k) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_0 = (2 * k) + (ch * fch_len);
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

      asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f[7 + base_idx_0]));
      if ((k | ch) == 0)
        asm volatile("vfmul.vf v28, v0, %0" ::"f"(f[0 + base_idx_0]));
      else
        asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfslide1down.vf v6, v4, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v18, %0, v4" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v4" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v4" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v4" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v4" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v4" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfslide1down.vf v10, v8, %0" ::"f"(*i_slide_ptr_2++));
      asm volatile("vfmacc.vf v20, %0, v8" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v8" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v8" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v8" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v8" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfslide1down.vf v14, v12, %0" ::"f"(*i_slide_ptr_3++));
      asm volatile("vfmacc.vf v22, %0, v12" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v12" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v12" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v12" ::"f"(f[21 + base_idx_0]));

      asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v16, %0, v2" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfmacc.vf v18, %0, v2" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v20, %0, v2" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v22, %0, v2" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f[0 + base_idx_1]));
      asm volatile("vfslide1down.vf v4, v6, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v18, %0, v6" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfmacc.vf v20, %0, v6" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v22, %0, v6" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v6" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v6" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfmacc.vf v28, %0, v6" ::"f"(f[7 + base_idx_1]));
      asm volatile("vfslide1down.vf v8, v10, %0" ::"f"(*i_slide_ptr_2++));
      asm volatile("vfmacc.vf v20, %0, v10" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfmacc.vf v22, %0, v10" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v10" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v10" ::"f"(f[21 + base_idx_1]));
      asm volatile("vfmacc.vf v28, %0, v10" ::"f"(f[14 + base_idx_1]));
      asm volatile("vfslide1down.vf v12, v14, %0" ::"f"(*i_slide_ptr_3++));
      asm volatile("vfmacc.vf v22, %0, v14" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfmacc.vf v24, %0, v14" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v14" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v28, %0, v14" ::"f"(f[21 + base_idx_1]));
    }

    if (ch != C - 1) {
      int64_t base_idx_0 = (F - 1) + (ch * fch_len);

      asm volatile("vfmacc.vf v16, %0, v0" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v0" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v0" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v0" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f[0 + base_idx_0]));
      asm volatile("vfmacc.vf v18, %0, v4" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v4" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v4" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v4" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v4" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v4" ::"f"(f[7 + base_idx_0]));
      asm volatile("vfmacc.vf v20, %0, v8" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v8" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v8" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v8" ::"f"(f[21 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v8" ::"f"(f[14 + base_idx_0]));
      asm volatile("vfmacc.vf v22, %0, v12" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v24, %0, v12" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v12" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v12" ::"f"(f[21 + base_idx_0]));
    }
  }

  asm volatile("vfmacc.vf v16, %0, v0" ::"f"(fl6));
  asm volatile("vfmacc.vf v18, %0, v0" ::"f"(fl5));
  asm volatile("vfmacc.vf v20, %0, v0" ::"f"(fl4));
  asm volatile("vse64.v  v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v22, %0, v0" ::"f"(fl3));
  asm volatile("vfmacc.vf v24, %0, v0" ::"f"(fl2));
  asm volatile("vfmacc.vf v26, %0, v0" ::"f"(fl1));
  asm volatile("vfmacc.vf v28, %0, v0" ::"f"(fl0));
  asm volatile("vfmacc.vf v18, %0, v4" ::"f"(fl6));
  asm volatile("vfmacc.vf v20, %0, v4" ::"f"(fl5));
  asm volatile("vse64.v  v18, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v22, %0, v4" ::"f"(fl4));
  asm volatile("vfmacc.vf v24, %0, v4" ::"f"(fl3));
  asm volatile("vfmacc.vf v26, %0, v4" ::"f"(fl2));
  asm volatile("vfmacc.vf v28, %0, v4" ::"f"(fl1));
  asm volatile("vfmacc.vf v20, %0, v8" ::"f"(fl6));
  asm volatile("vfmacc.vf v22, %0, v8" ::"f"(fl5));
  asm volatile("vse64.v  v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v24, %0, v8" ::"f"(fl4));
  asm volatile("vfmacc.vf v26, %0, v8" ::"f"(fl3));
  asm volatile("vfmacc.vf v28, %0, v8" ::"f"(fl2));
  asm volatile("vfmacc.vf v22, %0, v12" ::"f"(fl6));
  asm volatile("vse64.v  v22, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v24, %0, v12" ::"f"(fl5));
  asm volatile("vfmacc.vf v26, %0, v12" ::"f"(fl4));
  asm volatile("vfmacc.vf v28, %0, v12" ::"f"(fl3));

  // Bump the input ptr
  i_ += 4 * (N + F - 1);

  //////////////////////////
  // Row (I-1)-3 -> (I-1) //
  //////////////////////////

  for (int64_t ch = 0; ch < C; ++ch) {

    // Point to the first element of the channel ch
    i__ = i_ + ch * ich_len;

    // Start calculating the next pointers to the elements to be slided in
    i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
    i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    i_slide_ptr_2 = i__ + n_ + 2 * (N + F - 1);

    asm volatile("vle64.v v2, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v6, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));
    asm volatile("vle64.v v10, (%0); add %0, %0, %1"
                 : "+&r"(i__)
                 : "r"(ldi_pad));

    // Main kernel, unrolled by 2
    for (int k = 0; k < F / 2; ++k) {
      // Two base indexes because of the unrolling
      // Point to the first element of the current column (k) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_0 = (2 * k) + (ch * fch_len);
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)
      int64_t base_idx_1 = (2 * k + 1) + (ch * fch_len);

      asm volatile("vfslide1down.vf v0, v2, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfslide1down.vf v4, v6, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v6" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfslide1down.vf v8, v10, %0" ::"f"(*i_slide_ptr_2++));
      asm volatile("vfmacc.vf v28, %0, v6" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v10" ::"f"(f[42 + base_idx_0]));

      asm volatile("vfslide1down.vf v2, v0, %0" ::"f"(*i_slide_ptr_0++));
      asm volatile("vfmacc.vf v24, %0, v0" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v0" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfslide1down.vf v6, v4, %0" ::"f"(*i_slide_ptr_1++));
      asm volatile("vfmacc.vf v28, %0, v0" ::"f"(f[28 + base_idx_1]));
      asm volatile("vfmacc.vf v26, %0, v4" ::"f"(f[42 + base_idx_1]));
      asm volatile("vfslide1down.vf v10, v8, %0" ::"f"(*i_slide_ptr_2++));
      asm volatile("vfmacc.vf v28, %0, v4" ::"f"(f[35 + base_idx_1]));
      asm volatile("vfmacc.vf v28, %0, v8" ::"f"(f[42 + base_idx_1]));
    }

    if (ch != C - 1) {
      int64_t base_idx_0 = (F - 1) + (ch * fch_len);

      asm volatile("vfmacc.vf v24, %0, v2" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v2" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v2" ::"f"(f[28 + base_idx_0]));
      asm volatile("vfmacc.vf v26, %0, v6" ::"f"(f[42 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v6" ::"f"(f[35 + base_idx_0]));
      asm volatile("vfmacc.vf v28, %0, v10" ::"f"(f[42 + base_idx_0]));
    }
  }

  asm volatile("vfmacc.vf v24, %0, v2" ::"f"(fl6));
  asm volatile("vse64.v  v24, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v26, %0, v2" ::"f"(fl5));
  asm volatile("vfmacc.vf v28, %0, v2" ::"f"(fl4));
  asm volatile("vfmacc.vf v26, %0, v6" ::"f"(fl6));
  asm volatile("vse64.v  v26, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
  asm volatile("vfmacc.vf v28, %0, v6" ::"f"(fl5));
  asm volatile("vfmacc.vf v28, %0, v10" ::"f"(fl6));
  asm volatile("vse64.v  v28, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
}

/*
  ////////////////////
  // MAIN ALGOMITHM //
  ////////////////////

  // Start calculating the pointer to the next element to be slided in
  i_slide_ptr_0 = i + N;

  // Load one input row
  asm volatile("vle64.v v0, (%0); add %0, %0, %1" : "+&r"(i) : "r"(ldi_pad));

  // Kernel
  for (int k = 0; k < F; ++k) {
    // Nalculate F*F contributions of the input rows, on F different output rows
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
  // To avoid these operations, unroll the loop via software, renaming the
  registers manually asm volatile("vmv.v.v v16, v18"); asm volatile("vmv.v.v
  v18, v20"); asm volatile("vmv.v.v v20, v22"); asm volatile("vmv.v.v v22,
  v24"); asm volatile("vmv.v.v v24, v26"); asm volatile("vmv.v.v v26, v28");
*/
