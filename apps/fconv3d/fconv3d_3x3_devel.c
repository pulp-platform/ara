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
//         Gianmarco Ottavi

/*
  Algorithm:
  a) Load the next input row
  b) Calculate its contributions of 2 output channels the F = 3 output rows using one column of
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

#ifndef SPIKE
#include "printf.h"
#include "runtime.h"
#endif


void fconv3d_CHx3x3(double *o, double *i, double *f, int64_t M, int64_t N,
                    int64_t C, int64_t OC, int64_t F) {

  long int block_size_n;
  
  // Set the vector configuration
  asm volatile("vsetvli %0, %1, e64, m2, ta, ma" : "=r"(block_size_n) : "r"(N));
  
  // Slice the matrix into a manageable number of columns n_
  for (long int n = 0; n < N; n += block_size_n) {
    // Set the vector length
    const long int n_ = MIN(N - n, block_size_n);

    // Find pointers to the submatrices
    double *i_ = i + n;
    double *o_ = o + n;

    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(n_));

    fconv3d_CHx3x3_block(o_, i_, f, M, N, n_, C, OC, F);
  }
}

void fconv3d_CHx3x3_block(double *o, double *i, double *f, int64_t M, int64_t N,
                          int64_t n_, int64_t C, int64_t OC, int64_t F) {

  // Helper variables
  int64_t ldo = N << 3;
  int64_t *o_p1 = o;
  int64_t ldi_pad = (N + F - 1) << 3;

  // Number of elements that separates two adjacent channels
  int64_t ich_len = (M + F - 1) * (N + F - 1);
  int64_t fch_len = F * F;
  int64_t fch_full_len = fch_len * C;

  double *i_  = i;
  double *i__ = i;

  // Very last column of coefficients
  double fl0, fl1, fl2, fl0_1, fl1_1, fl2_1;
  // Buffers for coefficients preloading (solve 16-lane starvation problem)
  double f0_buf, f1_buf, f2_buf, f3_buf, f4_buf, f5_buf, f6_buf;

  double *i_slide_ptr_0;
  double *i_slide_ptr_1;
  double *i_slide_ptr_2;
  double *i_slide_ptr_3;

  // Buffer some of the filter coefficients not to lose efficiency after a
  // vector store (CVA6 cannot issue memory operations if there is a pending
  // store!)
  int64_t last_f_column, last_f_column_1;

  ////////////////
  // Row 0 -> 3 //
  ////////////////
  
  for (int och = 0; och<OC/2; ++och){
    last_f_column   = 2*och*fch_len*C + (C - 1)   * fch_len + F - 1;
    last_f_column_1 = 2*och*fch_len*C + (2*C - 1) * fch_len + F - 1;

    fl0 = f[last_f_column + 0 * F];
    fl1 = f[last_f_column + 1 * F];
    fl2 = f[last_f_column + 2 * F];
    
    fl0_1 = f[last_f_column_1 + 0 * F];
    fl1_1 = f[last_f_column_1 + 1 * F];
    fl2_1 = f[last_f_column_1 + 2 * F];

    // Loop on the channels
    i_ = i;
    o_p1 = o + (M*N);

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
      // Unrolled the whole filter (only size 3)

      // base_idx point at the current ch of the filter
      int64_t base_idx_0 = 2*och*fch_full_len + ch * fch_len;
      int64_t base_idx_1 = 2*och*fch_full_len + fch_full_len + ch * fch_len;
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)

      // V0/2 VEC
      if (!ch) {
        asm volatile ("vfmul.vf  v16, v0, %0" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmul.vf  v24, v0, %0" :: "f"(f[0 + base_idx_1]) );
      } else {
        asm volatile ("vfmacc.vf  v16, %0, v0" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmacc.vf  v24, %0, v0" :: "f"(f[0 + base_idx_1]) );
      }
      asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      // V4/6 VEC
      if (!ch) {
        asm volatile ("vfmul.vf  v18, v4, %0" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmul.vf  v26, v4, %0" :: "f"(f[0 + base_idx_1]) );
      } else {
        asm volatile ("vfmacc.vf  v18, %0, v4" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmacc.vf  v26, %0, v4" :: "f"(f[0 + base_idx_1]) );
      }
      asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(f[3 + base_idx_0]) );
      asm volatile ("vfmacc.vf v24, %0, v4" :: "f"(f[3 + base_idx_1]) );
      asm volatile ("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      // V8/10
      if (!ch) {
        asm volatile ("vfmul.vf  v20, v8, %0" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmul.vf  v28, v8, %0" :: "f"(f[0 + base_idx_1]) );
      } else {
        asm volatile ("vfmacc.vf  v20, %0, v8" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmacc.vf  v28, %0, v8" :: "f"(f[0 + base_idx_1]) );
      }
      asm volatile ("vfmacc.vf v16, %0, v8"    :: "f"(f[6 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v18, %0, v8"    :: "f"(f[3 + base_idx_0]) );
      asm volatile ("vfmacc.vf v24, %0, v8"    :: "f"(f[6 + base_idx_1]) ); 
      asm volatile ("vfmacc.vf v26, %0, v8"    :: "f"(f[3 + base_idx_1]) ); 
      
      asm volatile ("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++)); //SLIDE
    
      // V12/14
      if (!ch) {
        asm volatile ("vfmul.vf  v22, v12, %0" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmul.vf  v30, v12, %0" :: "f"(f[0 + base_idx_1]) );
      } else {
        asm volatile ("vfmacc.vf  v22, %0, v12" :: "f"(f[0 + base_idx_0]) );
        asm volatile ("vfmacc.vf  v30, %0, v12" :: "f"(f[0 + base_idx_1]) );
      }
      asm volatile ("vfmacc.vf v18, %0, v12"    :: "f"(f[6 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v20, %0, v12"    :: "f"(f[3 + base_idx_0]) );
      asm volatile ("vfmacc.vf v26, %0, v12"    :: "f"(f[6 + base_idx_1]) ); 
      asm volatile ("vfmacc.vf v28, %0, v12"    :: "f"(f[3 + base_idx_1]) ); 
      
      asm volatile ("vfslide1down.vf v14, v12, %0" :: "f"(*i_slide_ptr_3++)); //SLIDE

    
      // V2/0 VEC
      asm volatile ("vfmacc.vf     v16, %0, v2" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf     v24, %0, v2" :: "f"(f[1 + base_idx_1]) );    
      asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      // V6/4 VEC
      asm volatile ("vfmacc.vf v18, %0, v6" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v16, %0, v6" :: "f"(f[4 + base_idx_0]) );
      asm volatile ("vfmacc.vf v26, %0, v6" :: "f"(f[1 + base_idx_1]) );
      asm volatile ("vfmacc.vf v24, %0, v6" :: "f"(f[4 + base_idx_1]) );
      asm volatile ("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      // V10/8
      asm volatile ("vfmacc.vf v20, %0, v10"  :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v18, %0, v10"  :: "f"(f[4 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v16, %0, v10"  :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfmacc.vf v28, %0, v10"  :: "f"(f[1 + base_idx_1]) );
      asm volatile ("vfmacc.vf v26, %0, v10"  :: "f"(f[4 + base_idx_1]) ); 
      asm volatile ("vfmacc.vf v24, %0, v10"  :: "f"(f[7 + base_idx_1]) ); 
      asm volatile ("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++)); //SLIDE

      // V12/14
      asm volatile ("vfmacc.vf v22, %0, v14" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v20, %0, v14" :: "f"(f[4 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v18, %0, v14" :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfmacc.vf v30, %0, v14" :: "f"(f[1 + base_idx_1]) );
      asm volatile ("vfmacc.vf v28, %0, v14" :: "f"(f[4 + base_idx_1]) ); 
      asm volatile ("vfmacc.vf v26, %0, v14" :: "f"(f[7 + base_idx_1]) ); 
      asm volatile ("vfslide1down.vf v12, v14, %0" :: "f"(*i_slide_ptr_3++)); //SLIDE
    

      if (ch != C-1) {
        // V0/2 VEC
        asm volatile ("vfmacc.vf v16, %0, v0" :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v24, %0, v0" :: "f"(f[2 + base_idx_1]) );
      
        // V4/6 VEC
        asm volatile ("vfmacc.vf v18, %0, v4" :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(f[5 + base_idx_0]) );

        asm volatile ("vfmacc.vf v26, %0, v4" :: "f"(f[2 + base_idx_1]) );
        asm volatile ("vfmacc.vf v24, %0, v4" :: "f"(f[5 + base_idx_1]) );

        // V8/10
        asm volatile ("vfmacc.vf v20, %0, v8"  :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v18, %0, v8"  :: "f"(f[5 + base_idx_0]) ); 
        asm volatile ("vfmacc.vf v16, %0, v8"  :: "f"(f[8 + base_idx_0]) ); 

        asm volatile ("vfmacc.vf v28, %0, v8"  :: "f"(f[2 + base_idx_1]) );
        asm volatile ("vfmacc.vf v26, %0, v8"  :: "f"(f[5 + base_idx_1]) ); 
        asm volatile ("vfmacc.vf v24, %0, v8"  :: "f"(f[8 + base_idx_1]) ); 
       
        asm volatile ("vfmacc.vf v22, %0, v12" :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v12" :: "f"(f[5 + base_idx_0]) ); 
        asm volatile ("vfmacc.vf v18, %0, v12" :: "f"(f[8 + base_idx_0]) ); 

        asm volatile ("vfmacc.vf v30, %0, v12" :: "f"(f[2 + base_idx_1]) );
        asm volatile ("vfmacc.vf v28, %0, v12" :: "f"(f[5 + base_idx_1]) ); 
        asm volatile ("vfmacc.vf v26, %0, v12" :: "f"(f[8 + base_idx_1]) ); 
      }
    }

    // V0/2 VEC
    asm volatile ("vfmacc.vf v16, %0, v0" :: "f"(fl0)   );    
    asm volatile ("vfmacc.vf v24, %0, v0" :: "f"(fl0_1) );
    // V4/6 VEC
    asm volatile ("vfmacc.vf v18, %0, v4" :: "f"(fl0) );
    asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(fl1) );
    asm volatile ("vfmacc.vf v26, %0, v4" :: "f"(fl0_1) );
    asm volatile ("vfmacc.vf v24, %0, v4" :: "f"(fl1_1) );
  
    // V8/10
    asm volatile ("vfmacc.vf v20, %0, v8"  :: "f"(fl0) );
    asm volatile ("vfmacc.vf v18, %0, v8"  :: "f"(fl1) ); 
    asm volatile ("vfmacc.vf v16, %0, v8"  :: "f"(fl2) ); 
    asm volatile ("vse64.v v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile ("vfmacc.vf v28, %0, v8"  :: "f"(fl0_1) );
    asm volatile ("vfmacc.vf v26, %0, v8"  :: "f"(fl1_1) ); 
    asm volatile ("vfmacc.vf v24, %0, v8"  :: "f"(fl2_1) );
    asm volatile ("vse64.v v24, (%0); add %0, %0, %1" : "+&r"(o_p1) : "r"(ldo));

    asm volatile ("vfmacc.vf v22, %0, v12" :: "f"(fl0) );
    asm volatile ("vfmacc.vf v20, %0, v12" :: "f"(fl1) );     
    asm volatile ("vfmacc.vf v18, %0, v12" :: "f"(fl2) ); 
    asm volatile ("vse64.v v18, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
    asm volatile ("vfmacc.vf v30, %0, v12" :: "f"(fl0_1));
    asm volatile ("vfmacc.vf v28, %0, v12" :: "f"(fl1_1)); 
    asm volatile ("vfmacc.vf v26, %0, v12" :: "f"(fl2_1));
    asm volatile ("vse64.v v26, (%0); add %0, %0, %1" : "+&r"(o_p1) : "r"(ldo));

    for (int row = F-1; row < M - (F-1); row++){

      i_ = i + (row + (F-1))*(ldi_pad>>3);
      for (int ch=0; ch<C; ch++){
        i__ = i_ + ch * ich_len;

        i_slide_ptr_0 = i__ + n_;
        asm volatile("vle64.v v0, (%0)" :: "r"(i__));

        int64_t base_idx_0 = 2*och*fch_full_len + ch * fch_len;
        int64_t base_idx_1 = 2*och*fch_full_len + fch_full_len + ch * fch_len;

        if(!ch) {
          asm volatile ("vfmul.vf  v18, v0, %0" :: "f"(f[0 + base_idx_0]) );
          asm volatile ("vfmul.vf  v26, v0, %0" :: "f"(f[0 + base_idx_1]) );
        } else {
          asm volatile ("vfmacc.vf v18, %0, v0" :: "f"(f[0 + base_idx_0]) );
          asm volatile ("vfmacc.vf v26, %0, v0" :: "f"(f[0 + base_idx_1]) );
        }
        asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(f[3 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(f[6 + base_idx_0]) );
        asm volatile ("vfmacc.vf v30, %0, v0"   :: "f"(f[3 + base_idx_1]) );
        asm volatile ("vfmacc.vf v28, %0, v0"   :: "f"(f[6 + base_idx_1]) );
        
        asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

        asm volatile ("vfmacc.vf v18, %0, v2"   :: "f"(f[1 + base_idx_0]) );
        asm volatile ("vfmacc.vf v22, %0, v2"   :: "f"(f[4 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v2"   :: "f"(f[7 + base_idx_0]) );
        asm volatile ("vfmacc.vf v26, %0, v2"   :: "f"(f[1 + base_idx_1]) );
        asm volatile ("vfmacc.vf v30, %0, v2"   :: "f"(f[4 + base_idx_1]) );
        asm volatile ("vfmacc.vf v28, %0, v2"   :: "f"(f[7 + base_idx_1]) );
      
        asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

        if (ch != C-1) {
          asm volatile ("vfmacc.vf v18, %0, v0"   :: "f"(f[2 + base_idx_0]) );
          asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(f[5 + base_idx_0]) );
          asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(f[8 + base_idx_0]) );
          asm volatile ("vfmacc.vf v26, %0, v0"   :: "f"(f[2 + base_idx_1]) );
          asm volatile ("vfmacc.vf v30, %0, v0"   :: "f"(f[5 + base_idx_1]) );
          asm volatile ("vfmacc.vf v28, %0, v0"   :: "f"(f[8 + base_idx_1]) );      
        }      
      }

      //maybe change order
      asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(fl2) );
      asm volatile ("vse64.v v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
      asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(fl1) );
      asm volatile ("vmv.v.v v20, v22");
      asm volatile ("vfmacc.vf v18, %0, v0"   :: "f"(fl0) );
      asm volatile ("vmv.v.v v22, v18");

      asm volatile ("vfmacc.vf v28, %0, v0"   :: "f"(fl2_1) );
      asm volatile ("vse64.v v28, (%0); add %0, %0, %1" : "+&r"(o_p1) : "r"(ldo));
      asm volatile ("vfmacc.vf v30, %0, v0"   :: "f"(fl1_1) );
      asm volatile ("vmv.v.v v28, v30");
      asm volatile ("vfmacc.vf v26, %0, v0"   :: "f"(fl0_1) );
      asm volatile ("vmv.v.v v30, v26");
      
    }

    i_ += (ldi_pad >> 3);
  
    // Loop on the channels
    for (int ch = 0; ch < C; ++ch) {

      // Point to the first element of the channel ch
      i__ = i_ + ch * ich_len;

      // Point to the scalar elements to insert during a slide
      i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
      i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    
      // Load four input rows belonging to channel ch
      asm volatile("vle64.v v0, (%0); add %0, %0, %1"
                   : "+&r"(i__)
                   : "r"(ldi_pad));    
      asm volatile("vle64.v v4, (%0)" :: "r" (i__));
    
      // Main kernel, unrolled by 2
      // Unrolled the whole filter (only size 3)

      // base_idx_0 point at the current ch of the filter
      int64_t base_idx_0 = 2*och*fch_full_len + ch * fch_len;
      int64_t base_idx_1 = 2*och*fch_full_len + fch_full_len + ch * fch_len;
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)

      // V0/2 VEC
      asm volatile ("vfmacc.vf  v20, %0, v0"     :: "f"(f[6 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v0"     :: "f"(f[3 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v28, %0, v0"     :: "f"(f[6 + base_idx_1]) );
      asm volatile ("vfmacc.vf  v30, %0, v0"     :: "f"(f[3 + base_idx_1]) );
      
      asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      asm volatile ("vfmacc.vf  v22, %0, v4"     :: "f"(f[6 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v30, %0, v4"     :: "f"(f[6 + base_idx_1]) );
      asm volatile ("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      asm volatile ("vfmacc.vf  v20, %0, v2"     :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v2"     :: "f"(f[4 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v28, %0, v2"     :: "f"(f[7 + base_idx_1]) );
      asm volatile ("vfmacc.vf  v30, %0, v2"     :: "f"(f[4 + base_idx_1]) );
      asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      asm volatile ("vfmacc.vf  v22, %0, v6"     :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v30, %0, v6"     :: "f"(f[7 + base_idx_1]) );
      asm volatile ("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      asm volatile ("vfmacc.vf  v20, %0, v0" :: "f"(f[8 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v0" :: "f"(f[5 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v4" :: "f"(f[8 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v28, %0, v0" :: "f"(f[8 + base_idx_1]) );
      asm volatile ("vfmacc.vf  v30, %0, v0" :: "f"(f[5 + base_idx_1]) );
      asm volatile ("vfmacc.vf  v30, %0, v4" :: "f"(f[8 + base_idx_1]) );
    }
  
    asm volatile ("vse64.v v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));  
    asm volatile ("vse64.v v22, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo + ((M*N)<<3)));
    asm volatile ("vse64.v v28, (%0); add %0, %0, %1" : "+&r"(o_p1) : "r"(ldo));  
    asm volatile ("vse64.v v30, (%0); add %0, %0, %1" : "+&r"(o_p1) : "r"(ldo));

  }

  if (OC & 0x1) {
    last_f_column   = (OC-1)*fch_len*C + (C - 1)   * fch_len + F - 1;

    fl0 = f[last_f_column + 0 * F];
    fl1 = f[last_f_column + 1 * F];
    fl2 = f[last_f_column + 2 * F];

    // Loop on the channels
    i_ = i;
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
      // Unrolled the whole filter (only size 3)

      // base_idx point at the current ch of the filter
      int64_t base_idx_0 = (OC-1)*fch_full_len + ch * fch_len;
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)

      // V0/2 VEC
      if (!ch) {
        asm volatile ("vfmul.vf  v16, v0, %0" :: "f"(f[0 + base_idx_0]) );
      } else {
        asm volatile ("vfmacc.vf  v16, %0, v0" :: "f"(f[0 + base_idx_0]) );
      }
      asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      // V4/6 VEC
      if (!ch) {
        asm volatile ("vfmul.vf  v18, v4, %0" :: "f"(f[0 + base_idx_0]) );
      } else {
        asm volatile ("vfmacc.vf  v18, %0, v4" :: "f"(f[0 + base_idx_0]) );
      }
      asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(f[3 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      // V8/10
      if (!ch) {
        asm volatile ("vfmul.vf  v20, v8, %0" :: "f"(f[0 + base_idx_0]) );
      } else {
        asm volatile ("vfmacc.vf  v20, %0, v8" :: "f"(f[0 + base_idx_0]) );
      }
      asm volatile ("vfmacc.vf v16, %0, v8"    :: "f"(f[6 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v18, %0, v8"    :: "f"(f[3 + base_idx_0]) );
      
      asm volatile ("vfslide1down.vf v10, v8, %0" :: "f"(*i_slide_ptr_2++)); //SLIDE
    
      // V12/14
      if (!ch) {
        asm volatile ("vfmul.vf  v22, v12, %0" :: "f"(f[0 + base_idx_0]) );
      } else {
        asm volatile ("vfmacc.vf  v22, %0, v12" :: "f"(f[0 + base_idx_0]) );
      }
      asm volatile ("vfmacc.vf v18, %0, v12"    :: "f"(f[6 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v20, %0, v12"    :: "f"(f[3 + base_idx_0]) );
      
      asm volatile ("vfslide1down.vf v14, v12, %0" :: "f"(*i_slide_ptr_3++)); //SLIDE

    
      // V2/0 VEC
      asm volatile ("vfmacc.vf     v16, %0, v2" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      // V6/4 VEC
      asm volatile ("vfmacc.vf v18, %0, v6" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v16, %0, v6" :: "f"(f[4 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      // V10/8
      asm volatile ("vfmacc.vf v20, %0, v10"  :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v18, %0, v10"  :: "f"(f[4 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v16, %0, v10"  :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v8, v10, %0" :: "f"(*i_slide_ptr_2++)); //SLIDE

      // V12/14
      asm volatile ("vfmacc.vf v22, %0, v14" :: "f"(f[1 + base_idx_0]) );
      asm volatile ("vfmacc.vf v20, %0, v14" :: "f"(f[4 + base_idx_0]) ); 
      asm volatile ("vfmacc.vf v18, %0, v14" :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v12, v14, %0" :: "f"(*i_slide_ptr_3++)); //SLIDE
    

      if (ch != C-1) {
        // V0/2 VEC
        asm volatile ("vfmacc.vf v16, %0, v0" :: "f"(f[2 + base_idx_0]) );
      
        // V4/6 VEC
        asm volatile ("vfmacc.vf v18, %0, v4" :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(f[5 + base_idx_0]) );

        // V8/10
        asm volatile ("vfmacc.vf v20, %0, v8"  :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v18, %0, v8"  :: "f"(f[5 + base_idx_0]) ); 
        asm volatile ("vfmacc.vf v16, %0, v8"  :: "f"(f[8 + base_idx_0]) ); 

        asm volatile ("vfmacc.vf v22, %0, v12" :: "f"(f[2 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v12" :: "f"(f[5 + base_idx_0]) ); 
        asm volatile ("vfmacc.vf v18, %0, v12" :: "f"(f[8 + base_idx_0]) ); 
      }
    }

    // V0/2 VEC
    asm volatile ("vfmacc.vf v16, %0, v0" :: "f"(fl0)   );    
    // V4/6 VEC
    asm volatile ("vfmacc.vf v18, %0, v4" :: "f"(fl0) );
    asm volatile ("vfmacc.vf v16, %0, v4" :: "f"(fl1) );
  
    // V8/10
    asm volatile ("vfmacc.vf v20, %0, v8"  :: "f"(fl0) );
    asm volatile ("vfmacc.vf v18, %0, v8"  :: "f"(fl1) ); 
    asm volatile ("vfmacc.vf v16, %0, v8"  :: "f"(fl2) ); 
    asm volatile ("vse64.v v16, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));

    asm volatile ("vfmacc.vf v22, %0, v12" :: "f"(fl0) );
    asm volatile ("vfmacc.vf v20, %0, v12" :: "f"(fl1) );     
    asm volatile ("vfmacc.vf v18, %0, v12" :: "f"(fl2) ); 
    asm volatile ("vse64.v v18, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));

    for (int row = F-1; row < M - (F-1); row++){

      i_ = i + (row + (F-1))*(ldi_pad>>3);
      for (int ch=0; ch<C; ch++){
        i__ = i_ + ch * ich_len;

        i_slide_ptr_0 = i__ + n_;
        asm volatile("vle64.v v0, (%0)" :: "r"(i__));

        int64_t base_idx_0 = (OC-1)*fch_full_len + ch * fch_len;

        if(!ch) {
          asm volatile ("vfmul.vf  v18, v0, %0" :: "f"(f[0 + base_idx_0]) );
        } else {
          asm volatile ("vfmacc.vf v18, %0, v0" :: "f"(f[0 + base_idx_0]) );
        }
        asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(f[3 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(f[6 + base_idx_0]) );
        
        asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

        asm volatile ("vfmacc.vf v18, %0, v2"   :: "f"(f[1 + base_idx_0]) );
        asm volatile ("vfmacc.vf v22, %0, v2"   :: "f"(f[4 + base_idx_0]) );
        asm volatile ("vfmacc.vf v20, %0, v2"   :: "f"(f[7 + base_idx_0]) );
      
        asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

        if (ch != C-1) {
          asm volatile ("vfmacc.vf v18, %0, v0"   :: "f"(f[2 + base_idx_0]) );
          asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(f[5 + base_idx_0]) );
          asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(f[8 + base_idx_0]) );
        }      
      }

      //maybe change order
      asm volatile ("vfmacc.vf v20, %0, v0"   :: "f"(fl2) );
      asm volatile ("vse64.v v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));
      asm volatile ("vfmacc.vf v22, %0, v0"   :: "f"(fl1) );
      asm volatile ("vmv.v.v v20, v22");
      asm volatile ("vfmacc.vf v18, %0, v0"   :: "f"(fl0) );
      asm volatile ("vmv.v.v v22, v18");
    }

    i_ += (ldi_pad >> 3);
  
    // Loop on the channels
    for (int ch = 0; ch < C; ++ch) {

      // Point to the first element of the channel ch
      i__ = i_ + ch * ich_len;

      // Point to the scalar elements to insert during a slide
      i_slide_ptr_0 = i__ + n_ + 0 * (N + F - 1);
      i_slide_ptr_1 = i__ + n_ + 1 * (N + F - 1);
    
      // Load four input rows belonging to channel ch
      asm volatile("vle64.v v0, (%0); add %0, %0, %1"
                   : "+&r"(i__)
                   : "r"(ldi_pad));    
      asm volatile("vle64.v v4, (%0)" :: "r" (i__));
    
      // Main kernel, unrolled by 2
      // Unrolled the whole filter (only size 3)

      // base_idx_0 point at the current ch of the filter
      int64_t base_idx_0 = (OC-1)*fch_full_len + ch * fch_len;
      // Point to the first element of the current column (k+1) of the current
      // channel (ch) of the filter (f)

      // V0/2 VEC
      asm volatile ("vfmacc.vf  v20, %0, v0"     :: "f"(f[6 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v0"     :: "f"(f[3 + base_idx_0]) );
      
      asm volatile ("vfslide1down.vf v2, v0, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      asm volatile ("vfmacc.vf  v22, %0, v4"     :: "f"(f[6 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v6, v4, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      asm volatile ("vfmacc.vf  v20, %0, v2"     :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v2"     :: "f"(f[4 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v0, v2, %0" :: "f"(*i_slide_ptr_0++)); //SLIDE

      asm volatile ("vfmacc.vf  v22, %0, v6"     :: "f"(f[7 + base_idx_0]) );
      asm volatile ("vfslide1down.vf v4, v6, %0" :: "f"(*i_slide_ptr_1++)); //SLIDE

      asm volatile ("vfmacc.vf  v20, %0, v0" :: "f"(f[8 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v0" :: "f"(f[5 + base_idx_0]) );
      asm volatile ("vfmacc.vf  v22, %0, v4" :: "f"(f[8 + base_idx_0]) );
    }
  
    asm volatile ("vse64.v v20, (%0); add %0, %0, %1" : "+&r"(o) : "r"(ldo));  
    asm volatile ("vse64.v v22, (%0)" :: "r"(o));
  }
}
