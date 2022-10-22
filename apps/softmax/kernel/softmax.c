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
  for (vl = vsetvl_e32m1(avl); avl > 0; avl -= vl) {

    vl = vsetvl_e32m1(avl);

    /*
      Calculate the maximum along the channel dimension
    */

    // Initialize the max vector
    max_chunk_v = vle32_v_f32m1(__i, vl);
    // Bump the pointer
    __i += innerSize;
    for (uint64_t ch = 1; ch < channels; ++ch) {
      // Load a chunk of the input vector
      buf_chunk_v = vle32_v_f32m1(__i, vl);
      // Bump the channel pointer
      __i += innerSize;
      // Calculate the elm-wise maximum between the two chunks
      max_chunk_v = vfmax_vv_f32m1(max_chunk_v, buf_chunk_v, vl);
    }
    // Restore the channel pointer
    __i = _i;

    /*
      Fetch, subtract, exponentiate along the channel dimension
    */

    // Initialize accumulator
    den_chunk_v = vfmv_v_f_f32m1(0, vl);
    for (uint64_t ch = 0; ch < channels; ++ch) {
      // Fetch one chunk from channel ch
      buf_chunk_v = vle32_v_f32m1(__i, vl);
      // Subtract the maximum
      buf_chunk_v = vfsub_vv_f32m1(buf_chunk_v, max_chunk_v, vl);
      // Exponentiate
      buf_chunk_v = __exp_2xf32(buf_chunk_v, vl);
      // Store the numerator to memory
      vse32_v_f32m1(__o, buf_chunk_v, vl);
      // Accumulate
      den_chunk_v = vfadd_vv_f32m1(den_chunk_v, buf_chunk_v, vl);
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
      num_chunk_v = vle32_v_f32m1(__o, vl);
      // Divide
      res_chunk_v = vfdiv_vv_f32m1(num_chunk_v, den_chunk_v, vl);
      // Store the result to memory
      vse32_v_f32m1(__o, res_chunk_v, vl);
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
