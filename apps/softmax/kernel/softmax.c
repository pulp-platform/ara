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

#include <math.h>
#include <string.h>

#include "riscv_vector.h"

#include "../softmax/lib/exp.h"

// Our fdiv cannot receive any X in input
// The following macro is just a trick and should NOT be used
#define RESET_VREGS

// Scalar implmentation inspired by OpenCV softmax:
// https://github.com/opencv/opencv/blob/master/modules/dnn/src/layers/softmax_layer.cpp
void softmax(const float *i, const float *o, const float *buf,
             uint64_t channels, uint64_t innerSize) {

  // OpenCV names
  float *srcPtr = (float *)i;
  float *bufPtr = (float *)buf;
  float *dstPtr = (float *)o;

  // Batch size == 1
  size_t outerSize = 1;

  // Steps
  size_t outerStep = channels * innerSize;
  size_t cnStep = innerSize;

  // Compute max along axis
  for (size_t outerDim = 0; outerDim < outerSize; outerDim++) {

    size_t srcOffset = outerDim * outerStep;
    size_t bufOffset = outerDim * cnStep;

    memcpy(bufPtr + bufOffset, srcPtr + srcOffset, innerSize * sizeof(float));

    for (size_t cnDim = 1; cnDim < channels; cnDim++) {
      for (size_t i = 0; i < innerSize; i++) {
        bufPtr[bufOffset + i] =
            fmax(bufPtr[bufOffset + i], srcPtr[srcOffset + cnDim * cnStep + i]);
      }
    }

    // Subtract max
    for (size_t outerDim = 0; outerDim < outerSize; outerDim++) {
      size_t srcOffset = outerDim * outerStep;
      size_t bufOffset = outerDim * cnStep;

      for (size_t cnDim = 0; cnDim < channels; cnDim++) {
        const int offset = srcOffset + cnDim * cnStep;
        for (size_t i = 0; i < innerSize; i++)
          dstPtr[offset + i] = srcPtr[offset + i] - bufPtr[bufOffset + i];
      }
    }

    // Exponentiate
    for (size_t outerDim = 0; outerDim < outerSize; outerDim++) {
      size_t srcOffset = outerDim * outerStep;

      for (size_t cnDim = 0; cnDim < channels; cnDim++) {
        const int offset = srcOffset + cnDim * cnStep;
        for (size_t i = 0; i < innerSize; i++)
          dstPtr[offset + i] = exp(dstPtr[offset + i]);
      }
    }

    // Sum exps and divide
    for (size_t outerDim = 0; outerDim < outerSize; outerDim++) {
      size_t srcOffset = outerDim * outerStep;
      size_t bufOffset = outerDim * cnStep;

      // Sum exp along axis
      for (size_t i = 0; i < innerSize; i++)
        bufPtr[bufOffset + i] = 0.f;

      for (size_t cnDim = 0; cnDim < channels; cnDim++) {
        const int offset = srcOffset + cnDim * cnStep;
        for (size_t i = 0; i < innerSize; i++)
          bufPtr[bufOffset + i] += dstPtr[offset + i];
      }

      // Divide by computed sum
      for (size_t cnDim = 0; cnDim < channels; cnDim++) {
        const int offset = srcOffset + cnDim * cnStep;
        for (size_t i = 0; i < innerSize; i++)
          dstPtr[offset + i] /= bufPtr[bufOffset + i];
      }
    }
  }
}

void softmax_vec(const float *i, const float *o, uint64_t channels,
                 uint64_t innerSize) {

  /* ONLY FOR DEBUGGING PURPOSE. DELETE THE FOLLOWING ASM LINES
   */
  // Clean the regs from Xes
#ifdef RESET_VREGS
  volatile int temp;
  asm volatile("vsetvli %0, zero, e32, m8, ta, ma" : "=r"(temp));

  asm volatile("vmv.v.i  v0, 0");
  asm volatile("vmv.v.i  v8, 0");
  asm volatile("vmv.v.i v16, 0");
  asm volatile("vmv.v.i v24, 0");
#endif

  size_t avl = innerSize;
  size_t vl;

  // Stripmining pointers
  float *_i = (float *)i;
  float *_o = (float *)o;
  // Channel pointers
  float *__i = (float *)i;
  float *__o = (float *)o;

  // Vector registers
  vfloat32m1_t max_chunk_v;
  vfloat32m1_t buf_chunk_v;
  vfloat32m1_t num_chunk_v;
  vfloat32m1_t den_chunk_v;
  vfloat32m1_t res_chunk_v;

  // Stripmine on innerSize
  for (vl = __riscv_vsetvl_e32m1(avl); avl > 0; avl -= vl) {

    vl = __riscv_vsetvl_e32m1(avl);

    /*
      Calculate the maximum along the channel dimension
    */

    // Initialize the max vector
    max_chunk_v = __riscv_vle32_v_f32m1(__i, vl);
    // Bump the pointer
    __i += innerSize;
    for (uint64_t ch = 1; ch < channels; ++ch) {
      // Load a chunk of the input vector
      buf_chunk_v = __riscv_vle32_v_f32m1(__i, vl);
      // Bump the channel pointer
      __i += innerSize;
      // Calculate the elm-wise maximum between the two chunks
      max_chunk_v = __riscv_vfmax_vv_f32m1(max_chunk_v, buf_chunk_v, vl);
    }
    // Restore the channel pointer
    __i = _i;

    /*
      Fetch, subtract, exponentiate along the channel dimension
    */

    // Initialize accumulator
    den_chunk_v = __riscv_vfmv_v_f_f32m1(0, vl);
    for (uint64_t ch = 0; ch < channels; ++ch) {
      // Fetch one chunk from channel ch
      buf_chunk_v = __riscv_vle32_v_f32m1(__i, vl);
      // Subtract the maximum
      buf_chunk_v = __riscv_vfsub_vv_f32m1(buf_chunk_v, max_chunk_v, vl);
      // Exponentiate
      buf_chunk_v = __exp_2xf32(buf_chunk_v, vl);
      // Store the numerator to memory
      __riscv_vse32_v_f32m1(__o, buf_chunk_v, vl);
      // Accumulate
      den_chunk_v = __riscv_vfadd_vv_f32m1(den_chunk_v, buf_chunk_v, vl);
      // Bump channel pointers
      __i += innerSize;
      __o += innerSize;
    }
    // Restore the pointers
    __i = _i;
    __o = _o;

    /*
      Divide by the computed sum
    */

    for (uint64_t ch = 0; ch < channels; ++ch) {
      // Load numerator from memory
      num_chunk_v = __riscv_vle32_v_f32m1(__o, vl);
      // Divide
      res_chunk_v = __riscv_vfdiv_vv_f32m1(num_chunk_v, den_chunk_v, vl);
      // Store the result to memory
      __riscv_vse32_v_f32m1(__o, res_chunk_v, vl);
      // Bump channel pointers
      __o += innerSize;
    }
    // Bump stripmining pointers
    _i += vl;
    _o += vl;
    // Reset channel pointers
    __i = _i;
    __o = _o;
  }
}

void softmax_vec_reduction(const double *i, const double *o, uint64_t channels,
  uint64_t innerSize) {

size_t avl = innerSize;
size_t vl;

double *i_ = (double *) i;
double *o_ = (double *) o;

vl = vsetvl_e64m1(avl); // For now assuming avl fits VRF, so vl = avl

vfloat64m1_t vec_zero = vfmv_v_f_f64m1(0, vl);

vfloat64m1_t vec_res;
vfloat64m1_t vec_a = vle64_v_f64m1(i_, vl);
i_ += vl;

for (uint64_t c=0; c<channels; c+=1) {
// Find max
vfloat64m1_t vec_red_max;
vec_red_max = vfredmax_vs_f64m1_f64m1(vec_red_max, vec_a, vec_zero, vl);

if (c > 0) {
vse64_v_f64m1(o_, vec_res, vl);
o_ += vl;
}

double max = vfmv_f_s_f64m1_f64(vec_red_max);
vfloat64m1_t vec_b = vfsub_vf_f64m1(vec_a, max, vl);

// Find exp
vfloat64m1_t vec_c = __exp_1xf64(vec_b, vl);

// Sum and divide
vfloat64m1_t vec_red_sum;
vec_red_sum = vfredusum_vs_f64m1_f64m1(vec_red_sum, vec_c, vec_zero, vl);

// Load next row
if (c+1 < channels) {
vec_a = vle64_v_f64m1(i_, vl);
}

double sum = vfmv_f_s_f64m1_f64(vec_red_sum);
double sum_inv = 1.0/sum;

vec_res = vfmul_vf_f64m1(vec_c, sum_inv, vl);
i_ += vl;

}

vse64_v_f64m1(o_, vec_res, vl);

}

void softmax_vec_reduction_2(const double *i, const double *o, uint64_t channels,
  uint64_t innerSize) {

size_t avl = innerSize;
size_t vl;

double *i_ = (double *) i;
double *o_ = (double *) o;
double *is = (double *) i;
double *os = (double *) o;

vfloat64m1_t vec_zero = vfmv_v_f_f64m1(0, vl);
vfloat64m1_t vec_a, vec_b, vec_c, vec_max;

for (uint64_t c=0; c<channels; c+=1) {
  vl = vsetvl_e64m1(avl);
  // Find max
  vec_max = vfmv_v_f_f64m1(0.0, vl);
  while (avl > 0) {
    vec_a = vle64_v_f64m1(i_, vl);
    vec_max = vfmax_vv_f64m1(vec_max, vec_a, vl);
    i_ += vl;
    avl -= vl;
  }
  vfloat64m1_t vec_red_max = vfredmax_vs_f64m1_f64m1(vec_red_max, vec_max, vec_zero, vl);
  i_ = is;
  avl = innerSize;

  double max = vfmv_f_s_f64m1_f64(vec_red_max);
  vfloat64m1_t vec_sum = vfmv_v_f_f64m1(0, vl);

  while (avl > 0) {
    vec_a = vle64_v_f64m1(i_, vl);
    vec_b = vfsub_vf_f64m1(vec_a, max, vl);

    // Find exp
    vec_c = __exp_1xf64(vec_b, vl);
    
    // Sum and divide
    vec_sum = vfadd_vv_f64m1(vec_sum, vec_c, vl);

    // Store
    vse64_v_f64m1(o_, vec_c, vl);
    i_ += vl;
    o_ += vl;
    avl -= vl;
  }

  is += innerSize;
  os += innerSize;
  i_ = is;
  o_ = os;
  avl=innerSize;

}
}

void softmax_vec_reduction_3(const double *i, const double *o, uint64_t innerSize) {

double *i_ = (double *)i;
double *o_ = (double *)o;

size_t vl, avl = innerSize;

// Load the first portion of the long vector
vl = vsetvl_e64m1(avl);
vfloat64m1_t buf_a = vfmv_v_f_f64m1(0, vl);;

// buf_a = vle64_v_f64m1(i_, vl);
// i_ += vl;

// Stripmining
// avl -= vl;
for (; avl > 0; avl-=vl) {
    // Load the next remaining vector
    vl = vsetvl_e64m1(avl);
    vfloat64m1_t buf_b = vle64_v_f64m1(i_, vl);

    // Do a vector-vector max operation
    buf_a = vfmax_vv_f64m1(buf_a, buf_b, vl);

    // Update vector length
    i_ += vl;
}

// Reduce the max present in buf_a
vfloat64m1_t vec_zero = vfmv_v_f_f64m1(0, vl);

vfloat64m1_t vec_red_max;
vec_red_max = vfredmax_vs_f64m1_f64m1(vec_red_max, buf_a, vec_zero, vl);

double max = vfmv_f_s_f64m1_f64(vec_red_max);

// Reset avl, i_
avl = innerSize;
double *i1_ = (double *)i;
vfloat64m1_t buf_d = vfmv_v_f_f64m1(0, vl);

// Stripmine and find exponentials
double gvl = vl;
vfloat64m1_t exp_hi = vfmv_v_f_f64m1(88.3762626647949, gvl);
vfloat64m1_t exp_lo = vfmv_v_f_f64m1(-88.3762626647949, gvl);

vfloat64m1_t cephes_LOG2EF = vfmv_v_f_f64m1(1.44269504088896341, gvl);
vfloat64m1_t cephes_exp_C1 = vfmv_v_f_f64m1(0.693359375, gvl);
vfloat64m1_t cephes_exp_C2 = vfmv_v_f_f64m1(-2.12194440e-4, gvl);

vfloat64m1_t cephes_exp_p0 = vfmv_v_f_f64m1(1.9875691500E-4, gvl);
vfloat64m1_t cephes_exp_p1 = vfmv_v_f_f64m1(1.3981999507E-3, gvl);
vfloat64m1_t cephes_exp_p2 = vfmv_v_f_f64m1(8.3334519073E-3, gvl);
vfloat64m1_t cephes_exp_p3 = vfmv_v_f_f64m1(4.1665795894E-2, gvl);
vfloat64m1_t cephes_exp_p4 = vfmv_v_f_f64m1(1.6666665459E-1, gvl);
vfloat64m1_t cephes_exp_p5 = vfmv_v_f_f64m1(5.0000001201E-1, gvl);

for (; avl > 0; avl-= vl) {
    vl = vsetvl_e64m1(avl);
    vfloat64m1_t x = vle64_v_f64m1(i1_, vl);
    // vfloat64m1_t buf_b = vfsub_vf_f64m1(buf_a, max, vl);
    
    // Find exp
    // vfloat64m1_t buf_c = __exp_1xf64(buf_a, vl);
    double gvl = vl;

    /////////////// START EXP ////////////////////

    vfloat64m1_t tmp;
    vfloat64m1_t tmp2;
    vfloat64m1_t tmp4;
    vfloat64m1_t fx;
  
    vfloat64m1_t one = vfmv_v_f_f64m1(1.0, gvl);
    vfloat64m1_t zero = vec_zero; //vfmv_v_f_f64m1(0.0, gvl);
    vfloat64m1_t z;
    vfloat64m1_t y;
  
    vbool64_t mask;
    vint64m1_t imm0;
    vint64m1_t tmp3;
  
    x = vfmin_vv_f64m1(x, exp_hi, gvl);
    x = vfmax_vv_f64m1(x, exp_lo, gvl);
  
    fx = vfmv_v_f_f64m1(0.5, gvl);
    fx = vfmacc_vv_f64m1(fx, x, cephes_LOG2EF, gvl);
  
    tmp3 = vfcvt_x_f_v_i64m1(fx, gvl);
    tmp = vfcvt_f_x_v_f64m1(tmp3, gvl);
  
    mask = vmflt_vv_f64m1_b64(fx, tmp, gvl);
    tmp2 = vmerge_vvm_f64m1(mask, zero, one, gvl);
    fx = vfsub_vv_f64m1(tmp, tmp2, gvl);
    tmp = vfmul_vv_f64m1(fx, cephes_exp_C1, gvl);
    z = vfmul_vv_f64m1(fx, cephes_exp_C2, gvl);
    x = vfsub_vv_f64m1(x, tmp, gvl);
    x = vfsub_vv_f64m1(x, z, gvl);
  
    z = vfmul_vv_f64m1(x, x, gvl);
  
    y = cephes_exp_p0;
    y = vfmadd_vv_f64m1(y, x, cephes_exp_p1, gvl);
    y = vfmadd_vv_f64m1(y, x, cephes_exp_p2, gvl);
    y = vfmadd_vv_f64m1(y, x, cephes_exp_p3, gvl);
    y = vfmadd_vv_f64m1(y, x, cephes_exp_p4, gvl);
    y = vfmadd_vv_f64m1(y, x, cephes_exp_p5, gvl);
    y = vfmadd_vv_f64m1(y, z, x, gvl);
    y = vfadd_vv_f64m1(y, one, gvl);
  
    imm0 = vfcvt_x_f_v_i64m1(fx, gvl);
    imm0 = vadd_vv_i64m1(imm0, vmv_v_x_i64m1(1023, gvl), gvl);
    imm0 = vsll_vv_i64m1(imm0, vmv_v_x_u64m1(52, gvl), gvl);
  
    tmp4 = vreinterpret_v_i64m1_f64m1(imm0);
    y = vfmul_vv_f64m1(y, tmp4, gvl);

    ////////////////// END EXP ////////////////////////

    // buf_d = vfadd_vv_f64m1(buf_c, buf_d, vl);
    vse64_v_f64m1(o_, y, vl);
    i1_ += vl;
    o_ += vl;
}

// // Reset avl, i_
// avl = innerSize;
// double *i2_ = (double *)i;
// o_ = (double *)o;
// vl = vsetvl_e64m1(avl);

// // Reduction to find sum of exponentials
// vfloat64m1_t vec_red_sum;
// vec_red_sum = vfredusum_vs_f64m1_f64m1(vec_red_sum, buf_d, vec_zero, vl);

// double sum = vfmv_f_s_f64m1_f64(vec_red_sum);
// double sum_inv = 1.0/sum;

// // Stripmining to the last multiplications
// for (; avl > 0; avl-= vl) {
//     vl = vsetvl_e64m1(avl);
//     vfloat64m1_t buf_a = vle64_v_f64m1(i2_, vl);
//     i2_ += vl;
//     vfloat64m1_t buf_b = vfmul_vf_f64m1(buf_a, sum_inv, vl);
//     vse64_v_f64m1(o_, buf_b, vl);
//     o_ += vl;
// }

}
