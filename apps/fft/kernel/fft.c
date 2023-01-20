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
//
// Original scalar code by: Giuseppe Tagliavini

#include <math.h>
#include <stdlib.h>

#include "fft.h"

#define DEBUG

extern int64_t event_trigger;

////////////////
// FIXED-POINT //
/////////////////

/*
   Radix-2 Decimated in Time FFT. Input have to be digitally-reversed, output is
   naturally ordered. First stage uses the fact that twiddles are all (1, 0)
*/
void Radix2FFT_DIT(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT2)

{
  // int iLog2N  = log2(N_FFT2);
  int iLog2N = 31 - __builtin_clz(N_FFT2);
  int iCnt1, iCnt2, iCnt3, iQ, iL, iM, iA, iB;
  v2s *CoeffV = (v2s *)Twiddles;
  v2s *DataV = (v2s *)Data;

  iL = N_FFT2 >> 1;
  iM = 1;
  iA = 0;
  /* First Layer: W = (1, 0) */
  for (iCnt3 = 0; iCnt3 < (N_FFT2 >> 1); iCnt3++) {
    v2s Tmp;
    iB = iA + iM;
    Tmp = DataV[iB];
    DataV[iB] =
        (DataV[iA] - Tmp); //  >> (v2s) {FFT2_SCALEDOWN, FFT2_SCALEDOWN};
    DataV[iA] =
        (DataV[iA] + Tmp); //  >> (v2s) {FFT2_SCALEDOWN, FFT2_SCALEDOWN};
    iA = iA + 2;
  }
  iL >>= 1;
  iM <<= 1;

  for (iCnt1 = 1; iCnt1 < iLog2N; ++iCnt1) {
    iQ = 0;
    for (iCnt2 = 0; iCnt2 < iM; ++iCnt2) {
      v2s W = CoeffV[iQ];
      iA = iCnt2;
      for (iCnt3 = 0; iCnt3 < iL; iCnt3++) {
        v2s Tmp, Tmp1;
        iB = iA + iM;
        Tmp = cplxmuls(DataV[iB], W);
        Tmp1 = DataV[iA];

        DataV[iB] = (Tmp1 - Tmp) >> (v2s){FFT2_SCALEDOWN, FFT2_SCALEDOWN};
        DataV[iA] = (Tmp1 + Tmp) >> (v2s){FFT2_SCALEDOWN, FFT2_SCALEDOWN};
        iA = iA + 2 * iM;
      }
      iQ += iL;
    }
    iL >>= 1;
    iM <<= 1;
  }
}

void Radix2FFT_DIF(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT2) {
  int iLog2N = 31 - __builtin_clz(N_FFT2);
  int iCnt1, iCnt2, iCnt3, iQ, iL, iM, iA, iB;
  v2s *CoeffV = (v2s *)Twiddles;
  v2s *DataV = (v2s *)Data;

  iL = 1;
  iM = N_FFT2 / 2;

  for (iCnt1 = 0; iCnt1 < (iLog2N - 1); iCnt1++) {
    iQ = 0;
    for (iCnt2 = 0; iCnt2 < iM; iCnt2++) {
      v2s W = CoeffV[iQ];
      iA = iCnt2;
      for (iCnt3 = 0; iCnt3 < iL; iCnt3++) {
        v2s Tmp;
        iB = iA + iM;
        Tmp = DataV[iA] - DataV[iB];
        DataV[iA] =
            (DataV[iA] + DataV[iB]) >> (v2s){FFT2_SCALEDOWN, FFT2_SCALEDOWN};
        DataV[iB] = cplxmulsdiv2(Tmp, W);
        iA = iA + 2 * iM;
      }
      iQ += iL;
    }
    iL <<= 1;
    iM >>= 1;
  }
  iA = 0;

  /* Last Layer: W = (1, 0) */
  for (iCnt3 = 0; iCnt3 < (N_FFT2 >> 1); iCnt3++) {
    v2s Tmp;
    iB = iA + 1;
    Tmp = (DataV[iA] - DataV[iB]);
    DataV[iA] = (DataV[iA] + DataV[iB]);
    DataV[iB] = Tmp;
    iA = iA + 2;
  }
}

static inline v2s cplxmuls(v2s x, v2s y) {
  return (v2s){(signed short)((((int)(x)[0] * (int)(y)[0]) -
                               ((int)(x)[1] * (int)(y)[1])) >>
                              15),
               (signed short)((((int)(x)[0] * (int)(y)[1]) +
                               ((int)(x)[1] * (int)(y)[0])) >>
                              15)};
}

static inline v2s cplxmulsdiv2(v2s x, v2s y) {
  return (v2s){((signed short)((((int)(x)[0] * (int)(y)[0]) -
                                ((int)(x)[1] * (int)(y)[1])) >>
                               15)) >>
                   1,
               ((signed short)((((int)(x)[0] * (int)(y)[1]) +
                                ((int)(x)[1] * (int)(y)[0])) >>
                               15)) >>
                   1};
}

/* Setup twiddles factors */
void SetupTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse) {
  int i;
  v2s *P_Twid = (v2s *)Twiddles;
  /* Radix 4: 3/4 of the twiddles
     Radix 2: 1/2 of the twiddles
  */
  if (Inverse) {
    float Theta = (2 * M_PI) / Nfft;
    for (i = 0; i < Nfft; i++) {
      float Phi = Theta * i;
      P_Twid[i] = (v2s){(short int)(cos(Phi) * ((1 << FFT_TWIDDLE_DYN) - 1)),
                        (short int)(sin(Phi) * ((1 << FFT_TWIDDLE_DYN) - 1))};
      // Twiddles[2*i  ] = (short int) (cos(Phi)*((1<<FFT_TWIDDLE_DYN)-1));
      // Twiddles[2*i+1] = (short int) (sin(Phi)*((1<<FFT_TWIDDLE_DYN)-1));
    }
  } else {
    float Theta = (2 * M_PI) / Nfft;
    for (i = 0; i < Nfft; i++) {
      float Phi = Theta * i;
      P_Twid[i] = (v2s){(short int)(cos(-Phi) * ((1 << FFT_TWIDDLE_DYN) - 1)),
                        (short int)(sin(-Phi) * ((1 << FFT_TWIDDLE_DYN) - 1))};
      // Twiddles[2*i  ] = (short int) (cos(-Phi)*((1<<FFT_TWIDDLE_DYN)-1));
      // Twiddles[2*i+1] = (short int) (sin(-Phi)*((1<<FFT_TWIDDLE_DYN)-1));
    }
  }
}

/* Reorder from natural indexes to digitally-reversed one. Uses a pre computed
 * LUT */

void SwapSamples(v2f *__restrict__ Data, short *__restrict__ SwapTable,
                 int Ni) {
  int i;

  for (i = 0; i < Ni; i++) {
    v2f S = Data[i];
    int SwapIndex = SwapTable[i];
    if (i < SwapIndex) {
      Data[i] = Data[SwapIndex];
      Data[SwapIndex] = S;
    }
  }
}

void SetupR2SwapTable(short int *SwapTable, int Ni) {
  int i, j, iL, iM;
  // int Log2N  = log2(Ni);
  int Log2N = 31 - __builtin_clz(Ni);
  iL = Ni / 2;
  iM = 1;
  SwapTable[0] = 0;
  for (i = 0; i < Log2N; ++i) {
    for (j = 0; j < iM; ++j)
      SwapTable[j + iM] = SwapTable[j] + iL;
    iL >>= 1;
    iM <<= 1;
  }
}

void __attribute__((__noinline__))
SetupInput(signed short *In, int N, int Dyn) {
  unsigned int i, j;
  /*
          float Freq_Step[] = {
                  2*M_PI/18.0,
                  2*M_PI/67.0,
                  2*M_PI/49.0,
                  2*M_PI/32.0
          };
  */
  float Freq_Step[] = {
      2 * M_PI / (N / 10.0),
  };
  for (i = 0; i < (unsigned)N; i++) {
    float sum = 0.0;
    for (j = 0; j < sizeof(Freq_Step) / sizeof(float); j++) {
      sum += sinf(i * Freq_Step[j]);
    }
    In[2 * i] =
        (short)((sum / (sizeof(Freq_Step) / sizeof(float))) * ((1 << Dyn) - 1));
    In[2 * i + 1] = In[2 * i];
  }
}

////////////////////
// Floating-Point //
////////////////////

static inline v2f cplxmuls_float(v2f x, v2f y) {
  return (v2f){(x)[0] * (y)[0] - (x)[1] * (y)[1],
               (x)[0] * (y)[1] + (x)[1] * (y)[0]};
}

/*
   Radix-2 Decimated in Time FFT. Input have to be digitally-reversed, output is
   naturally ordered. First stage uses the fact that twiddles are all (1, 0)
*/
void Radix2FFT_DIT_float(float *__restrict__ Data, float *__restrict__ Twiddles,
                         int N_FFT2) {
  // int iLog2N  = log2(N_FFT2);
  int iLog2N = 31 - __builtin_clz(N_FFT2);
  int iCnt1, iCnt2, iCnt3, iQ, iL, iM, iA, iB;
  v2f *CoeffV = (v2f *)Twiddles;
  v2f *DataV = (v2f *)Data;

  iL = N_FFT2 >> 1;
  iM = 1;
  iA = 0;
  /* First Layer: W = (1, 0) */
  for (iCnt3 = 0; iCnt3 < (N_FFT2 >> 1); iCnt3++) {
    v2f Tmp;
    iB = iA + iM;
    Tmp = DataV[iB];
    DataV[iB] = (DataV[iA] - Tmp);
    DataV[iA] = (DataV[iA] + Tmp);
    iA = iA + 2;
  }
  iL >>= 1;
  iM <<= 1;

  for (iCnt1 = 1; iCnt1 < iLog2N; ++iCnt1) {
    iQ = 0;
    for (iCnt2 = 0; iCnt2 < iM; ++iCnt2) {
      v2f W = CoeffV[iQ];
      iA = iCnt2;
      for (iCnt3 = 0; iCnt3 < iL; iCnt3++) {
        v2f Tmp, Tmp1;
        iB = iA + iM;
        Tmp = cplxmuls_float(DataV[iB], W);
        Tmp1 = DataV[iA];

        DataV[iB] = Tmp1 - Tmp;
        DataV[iA] = Tmp1 + Tmp;
        iA = iA + 2 * iM;
      }
      iQ += iL;
    }
    iL >>= 1;
    iM <<= 1;
  }
}

void Radix2FFT_DIF_float(float *__restrict__ Data, float *__restrict__ Twiddles,
                         int N_FFT2, int n_break) {
  int iLog2N = 31 - __builtin_clz(N_FFT2);
  int iCnt1, iCnt2, iCnt3, iQ, iL, iM, iA, iB;
  v2f *CoeffV = (v2f *)Twiddles;
  v2f *DataV = (v2f *)Data;

  iL = 1;
  iM = N_FFT2 / 2;

  for (iCnt1 = 0; iCnt1 < (iLog2N - 1); iCnt1++) {
    // n_break used for debug purposes only
    // remove all the n_break related lines if no debug
    if (iCnt1 >= n_break)
      break;
    iQ = 0;
    for (iCnt2 = 0; iCnt2 < iM; iCnt2++) {
      v2f W = CoeffV[iQ];
      iA = iCnt2;
      for (iCnt3 = 0; iCnt3 < iL; iCnt3++) {
        v2f Tmp;
        iB = iA + iM;
        Tmp = DataV[iA] - DataV[iB];
        DataV[iA] = DataV[iA] + DataV[iB];
        DataV[iB] = cplxmuls_float(Tmp, W);
        iA = iA + 2 * iM;
      }
      iQ += iL;
    }
    iL <<= 1;
    iM >>= 1;
  }
  iA = 0;

  if ((iCnt1) < n_break) {
    /* Last Layer: W = (1, 0) */
    for (iCnt3 = 0; iCnt3 < (N_FFT2 >> 1); iCnt3++) {
      v2f Tmp;
      iB = iA + 1;
      Tmp = (DataV[iA] - DataV[iB]);
      DataV[iA] = (DataV[iA] + DataV[iB]);
      DataV[iB] = Tmp;
      iA = iA + 2;
    }
  }
}

////////////////////
// Vectorial code //
////////////////////

/*

Q) WHY IS THIS FUNCTION COMMENTED?
A) The permutation steps depends on slides on a mask vector.
   This is a problem for the intrinsics (no slides on mask vector?)
   Some of the mask vectors should be prepared anyway only with
   splats of scalars from CVA6

// First implementation. LMUL == 1
// This implementation works if n_fft < VLMAX for a fixed vsew
// Current implementation does not make use of segment memory ops and keeps
// real and img parts in two different separated memory locations
// This will be changed as soon as Ara supports segmented mem ops
void fft_r2dif_vec(float* samples_re, float* samples_im,
                   const float* twiddles_re, const float* twiddles_im,
                   size_t n_fft) {

  // vl of the vectors (each vector contains half of the samples)
  size_t vl = n_fft/2;
  size_t vl_mask = vl;
  unsigned int log2_nfft= 31 - __builtin_clz(n_fft);
  vfloat32m1_t upper_wing_re, upper_wing_im;
  vfloat32m1_t lower_wing_re, lower_wing_im;
  vfloat32m1_t twiddle_re, twiddle_im;
  vfloat32m1_t vbuf_re, vbuf_im;
  vbool32_t mask_vec, mask_vec_buf;

  // Use undisturbed policy
  vsetvl_e32m1(vl);

  //////////////////////
  // Mask Preparation //
  //////////////////////

  // Prepare the first mask vector to be used in the permutations
  // VLSU and VALU can work separately
  mask_vec     = vmclr_m_b32(vl);
  mask_vec     = vmset_m_b32(vl/2);
  mask_vec_buf = vmclr_m_b32(vl);

  ///////////////////////////////
  // LOAD samples and twiddles /
  ///////////////////////////////

  // If real/img parts are consecutive in memory, it's possible to
  // load/store segment to divide in two registers.
  // Ara does not support these instructions now, so we will hypothesize
  // different mem locations
  upper_wing_re = vle32_v_f32m1(samples_re     , vl);
  lower_wing_re = vle32_v_f32m1(samples_re + vl, vl);
  upper_wing_im = vle32_v_f32m1(samples_im     , vl);
  lower_wing_im = vle32_v_f32m1(samples_im + vl, vl);

  // Load twiddle factors
  twiddle_re = vle32_v_f32m1(twiddles_re, vl);
  twiddle_im = vle32_v_f32m1(twiddles_im, vl);

  ///////////////////////////
  // First butterfly stage //
  ///////////////////////////

  // 1) Get the upper wing output
  vbuf_re = vfadd_vv_f32m1(upper_wing_re, lower_wing_re, vl);
  vbuf_im = vfadd_vv_f32m1(upper_wing_im, lower_wing_im, vl);
  // 2) Get the lower wing output
  lower_wing_re = vfsub_vv_f32m1(upper_wing_re, lower_wing_re, vl);
  lower_wing_im = vfsub_vv_f32m1(upper_wing_im, lower_wing_im, vl);
  // Copy labels
  upper_wing_re = vbuf_re;
  upper_wing_im = vbuf_im;
  // 3) Multiply lower wing for the twiddle factor
  vbuf_re       = cmplx_mul_re_vv(lower_wing_re, lower_wing_im, twiddle_re,
twiddle_im, vl); lower_wing_im = cmplx_mul_im_vv(lower_wing_re, lower_wing_im,
twiddle_re, twiddle_im, vl); lower_wing_re = vbuf_re; // Just for the label.
Verify that there is no actual copy of this vector!

  /////////////////////////////
  // First permutation stage //
  /////////////////////////////

  // Create the current mask level
//todo  vslideup_vx_f32m1(mask_vec_buf, mask_vec, vl/4, vl_mask);
  mask_vec = vmxor_mm_b32(mask_vec, mask_vec_buf, vl);
  mask_vec_buf = vmnot_m_b32(mask_vec, vl);

  // Permutate the numbers
  // The first permutation is easier (just halving, no masks needed)
  vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_re, upper_wing_re, vl/2, vl/2);
  vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_im, upper_wing_im, vl/2, vl/2);
  vslideup_vx_f32m1(upper_wing_re, lower_wing_re, vl/2, vl/2);
  vslideup_vx_f32m1(upper_wing_im, lower_wing_im, vl/2, vl/2);
  lower_wing_re = vmv_v_v_f32m1(vbuf_re, vl/2);
  lower_wing_im = vmv_v_v_f32m1(vbuf_im, vl/2);

  // Butterfly until the end
  for (unsigned int i = 1; i < log2_nfft; ++i) {
    // Bump the twiddle pointers.
    twiddles_re += vl;
    twiddles_im += vl;

    // Load twiddle factors
    twiddle_re = vle32_v_f32m1(twiddles_re, vl);
    twiddle_im = vle32_v_f32m1(twiddles_im, vl);

    // HALVE vl
    vl_mask >>= 1;

    // Create the current mask level
//todo    vslideup_vx_f32m1(mask_vec_buf, mask_vec, 0, vl_mask);
    mask_vec = vmxor_mm_b32(mask_vec, mask_vec_buf, vl);
    mask_vec_buf = vmnot_m_b32(mask_vec, vl);

    // 1) Get the upper wing output
    vbuf_re = vfadd_vv_f32m1(upper_wing_re, lower_wing_re, vl);
    vbuf_im = vfadd_vv_f32m1(upper_wing_im, lower_wing_im, vl);
    // 2) Get the lower wing output
    lower_wing_re = vfsub_vv_f32m1(upper_wing_re, lower_wing_re, vl);
    lower_wing_im = vfsub_vv_f32m1(upper_wing_im, lower_wing_im, vl);
    // Copy labels
    upper_wing_re = vbuf_re;
    upper_wing_im = vbuf_im;
    // 3) Multiply lower wing for the twiddle factor
    vbuf_re       = cmplx_mul_re_vv(lower_wing_re, lower_wing_im, twiddle_re,
twiddle_im, vl); lower_wing_im = cmplx_mul_im_vv(lower_wing_re, lower_wing_im,
twiddle_re, twiddle_im, vl); lower_wing_re = vbuf_re; // Just for the label.
Verify that there is no actual copy of this vector!

    // Different permutation for the last round
    if (i != log2_nfft - 1) {
      // Permutate the numbers
      vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_re, upper_wing_re, vl/2, vl/2);
      vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_im, upper_wing_im, vl/2, vl/2);
      vslideup_vx_f32m1(upper_wing_re, lower_wing_re, vl/2, vl/2);
      vslideup_vx_f32m1(upper_wing_im, lower_wing_im, vl/2, vl/2);
      lower_wing_re = vmerge_vvm_f32m1(mask_vec, vbuf_re, lower_wing_re, vl/2);
      lower_wing_im = vmerge_vvm_f32m1(mask_vec, vbuf_im, lower_wing_im, vl/2);
    }
  }

  // Store the result to memory
  // Reorder the results: rotate, mask, mix
  // Last round of permutation
  vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_re, upper_wing_re, 0, vl/2);
  vslideup_vx_f32m1_m(mask_vec, upper_wing_re, lower_wing_re, vl/2, vl/2);;
  lower_wing_re = vmerge_vvm_f32m1(mask_vec, vbuf_re, lower_wing_re, vl/2);

  // Store (segmented if RE and IM are separated!)
  vse32_v_f32m1(samples_re, lower_wing_re, vl);
  vse32_v_f32m1(samples_im, lower_wing_im, vl);
}

// Vector - Scalar
 vfloat32m1_t cmplx_mul_re_vf(vfloat32m1_t v0_re, vfloat32m1_t v0_im, float
f1_re, float f1_im, size_t vl) { vfloat32m1_t vbuf;

   vbuf = vfmul_vf_f32m1(v0_re, f1_re, vl);
   return vfnmsac_vf_f32m1(vbuf, v0_im, f1_im, vl);
 }

 vfloat32m1_t cmplx_mul_im_vf(vfloat32m1_t v0_re, vfloat32m1_t v0_im, float
f1_re, float f1_im, size_t vl) { vfloat32m1_t vbuf;

   vbuf = vfmul_vf_f32m1(v0_re, f1_im, vl);
   return vfmacc_vf_f32m1(vbuf, v0_im, f1_re, vl);
 }
*/

//  Vector - Vector
vfloat32m1_t cmplx_mul_re_vv(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             vfloat32m1_t f1_re, vfloat32m1_t f1_im,
                             size_t vl) {
  vfloat32m1_t vbuf;

  vbuf = vfmul_vv_f32m1(v0_re, f1_re, vl);
  return vfnmsac_vv_f32m1(vbuf, v0_im, f1_im, vl);
}

vfloat32m1_t cmplx_mul_im_vv(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             vfloat32m1_t f1_re, vfloat32m1_t f1_im,
                             size_t vl) {
  vfloat32m1_t vbuf;

  vbuf = vfmul_vv_f32m1(v0_re, f1_im, vl);
  return vfmacc_vv_f32m1(vbuf, v0_im, f1_re, vl);
}

// Ancillary function to divide real and imaginary parts
// sizeof(v2f) == 2*sizeof(float)
float *cmplx2reim(v2f *cmplx, float *buf, size_t len) {

  float *cmplx_flat_ptr = (float *)cmplx;

  // Divide the real and img parts
  for (unsigned int i = 0; i < len; ++i) {
    // Backup the img parts
    buf[i] = cmplx[i][1];
  }
  for (unsigned int i = 0; i < len; ++i) {
    // Save the real parts
    // No RAW hazards on mem in this way
    cmplx_flat_ptr[i] = cmplx[i][0];
  }

  for (unsigned int i = 0; i < len; ++i) {
    // Save the img parts
    cmplx_flat_ptr[i + len] = buf[i];
  }

  return cmplx_flat_ptr;
}

// First implementation. LMUL == 1
// This implementation works if n_fft < VLMAX for a fixed vsew
// Current implementation does not make use of segment memory ops and keeps
// real and img parts in two different separated memory locations
// This will be changed as soon as Ara supports segmented mem ops
void fft_r2dif_vec(float *samples_re, float *samples_im,
                   const float *twiddles_re, const float *twiddles_im,
                   const uint8_t **mask_addr_vec, const uint32_t *index_ptr,
                   size_t n_fft) {

  // vl of the vectors (each vector contains half of the samples)
  size_t vl = n_fft / 2;
  size_t vl_mask = vl;
  size_t vl_slamt = vl / 2;
  unsigned int log2_nfft = 31 - __builtin_clz(n_fft);
  vfloat32m1_t upper_wing_re, upper_wing_im;
  vfloat32m1_t lower_wing_re, lower_wing_im;
  vfloat32m1_t twiddle_re, twiddle_im;
  vfloat32m1_t vbuf_re, vbuf_im, vbuf1_re, vbuf1_im;
  vbool32_t mask_vec, mask_vec_buf;
  vuint32m1_t index, bindex;

  // Use undisturbed policy
  vsetvl_e32m1(vl);

  ///////////////////////////////
  // LOAD samples and twiddles /
  ///////////////////////////////

  // If real/img parts are consecutive in memory, it's possible to
  // load/store segment to divide in two registers.
  // Ara does not support these instructions now, so we will hypothesize
  // different mem locations
  upper_wing_re = vle32_v_f32m1(samples_re, vl);
  lower_wing_re = vle32_v_f32m1(samples_re + vl, vl);

  // 1) Get the upper wing output
  vbuf_re = vfadd_vv_f32m1(upper_wing_re, lower_wing_re, vl);

  upper_wing_im = vle32_v_f32m1(samples_im, vl);
  lower_wing_im = vle32_v_f32m1(samples_im + vl, vl);

  // Create the current mask level
  // vslideup_vx_f32m1(mask_vec_buf, mask_vec, vl/4, vl_mask);
  // mask_vec = vmxor_mm_b32(mask_vec, mask_vec_buf, vl);
  mask_vec = vlm_v_b32(mask_addr_vec[0], vl);

  // 1) Get the upper wing output
  vbuf_im = vfadd_vv_f32m1(upper_wing_im, lower_wing_im, vl);

  // Load twiddle factors
  twiddle_re = vle32_v_f32m1(twiddles_re, vl);

  mask_vec_buf = vmnot_m_b32(mask_vec, vl);

  // Load twiddle factors
  twiddle_im = vle32_v_f32m1(twiddles_im, vl);

  ///////////////////////////
  // First butterfly stage //
  ///////////////////////////

  // 2) Get the lower wing output
  lower_wing_re = vfsub_vv_f32m1(upper_wing_re, lower_wing_re, vl);
  vbuf1_re =
      vslidedown_vx_f32m1_m(mask_vec_buf, vbuf1_re, vbuf_re, vl_slamt, vl / 2);
  lower_wing_im = vfsub_vv_f32m1(upper_wing_im, lower_wing_im, vl);
  // Copy labels
  upper_wing_re = vbuf_re;
  upper_wing_im = vbuf_im;
  // 3) Multiply lower wing for the twiddle factor
  vbuf_re =
      cmplx_mul_re_vv(lower_wing_re, lower_wing_im, twiddle_re, twiddle_im, vl);

  vbuf1_im = vslidedown_vx_f32m1_m(mask_vec_buf, vbuf_im, upper_wing_im,
                                   vl_slamt, vl / 2);

  lower_wing_im =
      cmplx_mul_im_vv(lower_wing_re, lower_wing_im, twiddle_re, twiddle_im, vl);
  lower_wing_re = vbuf_re; // Just for the label. Verify that there is no actual
                           // copy of this vector!

  /////////////////////////////
  // First permutation stage //
  /////////////////////////////

  // Preload twiddle factors
  if (1 < log2_nfft) {
    twiddles_re += vl;
    twiddle_re = vle32_v_f32m1(twiddles_re, vl);
  }

  // Permutate the numbers
  // The first permutation is easier (just halving, no masks needed)
  upper_wing_re = vslideup_vx_f32m1(upper_wing_re, lower_wing_re, vl_slamt, vl);
  lower_wing_re = vmerge_vvm_f32m1(mask_vec, vbuf1_re, lower_wing_re, vl);

  // Preload twiddle factors
  if (1 < log2_nfft) {
    twiddles_im += vl;
    twiddle_im = vle32_v_f32m1(twiddles_im, vl);
  }

  upper_wing_im = vslideup_vx_f32m1(upper_wing_im, lower_wing_im, vl_slamt, vl);
  lower_wing_im = vmerge_vvm_f32m1(mask_vec, vbuf1_im, lower_wing_im, vl);

  // Butterfly until the end
  for (unsigned int i = 1; i < log2_nfft; ++i) {
#ifdef VCD_DUMP
    // Start dumping VCD
    if (i == 1)
      event_trigger = +1;
    // Stop dumping VCD
    if (i == 3)
      event_trigger = -1;
#endif

    // HALVE vl_mask and slamt (slide amount)
    vl_mask >>= 1;
    vl_slamt >>= 1;

    if (i != log2_nfft - 1)
      mask_vec = vlm_v_b32(mask_addr_vec[i], vl);

    // 1) Get the upper wing output
    vbuf_re = vfadd_vv_f32m1(upper_wing_re, lower_wing_re, vl);

    if (i != log2_nfft - 1) {
      // Create the current mask level
      // vslideup_vx_f32m1(mask_vec_buf, mask_vec, 0, vl_mask);
      // mask_vec = vmxor_mm_b32(mask_vec, mask_vec_buf, vl);
      mask_vec_buf = vmnot_m_b32(mask_vec, vl);
      vbuf1_re =
          vslidedown_vx_f32m1_m(mask_vec_buf, vbuf1_re, vbuf_re, vl_slamt, vl);
    }

    vbuf_im = vfadd_vv_f32m1(upper_wing_im, lower_wing_im, vl);
    // 2) Get the lower wing output
    lower_wing_re = vfsub_vv_f32m1(upper_wing_re, lower_wing_re, vl);
    lower_wing_im = vfsub_vv_f32m1(upper_wing_im, lower_wing_im, vl);

    if (i != log2_nfft - 1)
      vbuf1_im =
          vslidedown_vx_f32m1_m(mask_vec_buf, vbuf1_im, vbuf_im, vl_slamt, vl);

    // Copy labels
    upper_wing_re = vbuf_re;
    upper_wing_im = vbuf_im;
    // 3) Multiply lower wing for the twiddle factor
    vbuf_re = cmplx_mul_re_vv(lower_wing_re, lower_wing_im, twiddle_re,
                              twiddle_im, vl);

    if (i != log2_nfft - 1) {
      upper_wing_re =
          vslideup_vx_f32m1_m(mask_vec, upper_wing_re, vbuf_re, vl_slamt, vl);
    }

    lower_wing_im = cmplx_mul_im_vv(lower_wing_re, lower_wing_im, twiddle_re,
                                    twiddle_im, vl);

    if (i != log2_nfft - 1) {
      // Pre load twiddle factors
      twiddles_re += vl;
      twiddle_re = vle32_v_f32m1(twiddles_re, vl);
    }

    lower_wing_re = vbuf_re; // Just for the label. Verify that there is no
                             // actual copy of this vector!

    // Different permutation for the last round
    if (i != log2_nfft - 1) {

      // Bump the twiddle pointers.
      twiddles_im += vl;

      // Permutate the numbers
      upper_wing_im = vslideup_vx_f32m1_m(mask_vec, upper_wing_im,
                                          lower_wing_im, vl_slamt, vl);
      lower_wing_re = vmerge_vvm_f32m1(mask_vec, vbuf1_re, lower_wing_re, vl);
      // Pre load twiddle factors
      twiddle_im = vle32_v_f32m1(twiddles_im, vl);
      lower_wing_im = vmerge_vvm_f32m1(mask_vec, vbuf1_im, lower_wing_im, vl);
    }
  }

  // Get the indexes for the final store
  index = vle32_v_u32m1(index_ptr, vl);
  bindex = vmul_vx_u32m1(index, sizeof(float), vl);

  // Store indexed
  vsuxei32_v_f32m1(samples_re, bindex, upper_wing_re, vl);
  vsuxei32_v_f32m1(samples_im, bindex, upper_wing_im, vl);
  vsuxei32_v_f32m1(samples_re + vl, bindex, lower_wing_re, vl);
  vsuxei32_v_f32m1(samples_im + vl, bindex, lower_wing_im, vl);
}
