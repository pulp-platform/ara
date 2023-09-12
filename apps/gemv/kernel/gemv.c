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

// Author: Chi Zhang, ETH Zurich <chizhang@iis.ee.ethz.ch>

#include "gemv.h"
#include "util.h"
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

void init_gemv_data(const unsigned long int m_row,
                    const unsigned long int v_len, double *matrix,
                    double *vector, double a, double b, double c) {
  // initialize matrix
  for (uint64_t i = 0; i < m_row; ++i) {
    for (uint64_t j = 0; j < v_len; ++j) {
      matrix[i * v_len + j] = a * (double)i + b * (double)j + c;
    }
  }

  // initialize vector
  for (uint64_t i = 0; i < v_len; ++i) {
    vector[i] = a * (double)i + b;
  }
}

//=====================================//
//========= GEMV ROW WISE KERNEL ======//
//=====================================//

#define SLICE_SIZE 128

void clear_reduction_register() {
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(SLICE_SIZE));
  asm volatile("vmv.v.i v16,  0");
  asm volatile("vmv.v.i v24,  0");
}

void store_slice_results(double *dest, const unsigned long int slice_height) {
  double tmp;
  // round slide
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_height));
  asm volatile("vfmv.f.s %0, v24" : "=f"(tmp));
  asm volatile("vfslide1down.vf  v16, v24, %0" ::"f"(tmp));
  // store
  asm volatile("vse64.v v16, (%0);" ::"r"(dest));
}

void gemv_rowwise_small_than_slice(const unsigned long int m_row,
                                   const unsigned long int v_len,
                                   double *matrix, double *vector,
                                   double *dest) {
  // setup
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(1));
  asm volatile("vmv.v.i v24,  0");
  asm volatile("vmv.v.i v16,  0");
  // load vector
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(v_len));
  asm volatile("vle64.v v0, (%0);" ::"r"(vector));
  for (uint64_t i = 0; i < m_row; ++i) {
    double *_mat_ = matrix + i * v_len;
    double *_dst_ = dest + i - 1; // delayed store
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(v_len));

    if (i % 2 == 0) {
      // load matrix slice row
      asm volatile("vle64.v v4, (%0);" ::"r"(_mat_));
      // multiply with vector
      asm volatile("vfmul.vv v8, v4, v0");
      // reduction
      asm volatile("vfredsum.vs v16, v8, v16");
      // store previous data
      if (i != 0) {
        // asm volatile("vse64.v v24, (%0);" ::"r"(_dst_));
        double tmp;
        asm volatile("vfmv.f.s %0, v24" : "=f"(tmp));
        *_dst_ = tmp;
        // clear reduction register
        asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(1));
        asm volatile("vmv.v.i v24,  0");
      }

    } else {
      // load matrix slice row
      asm volatile("vle64.v v2, (%0);" ::"r"(_mat_));
      // multiply with vector
      asm volatile("vfmul.vv v6, v2, v0");
      // reduction
      asm volatile("vfredsum.vs v24, v6, v24");
      // store previous data
      // asm volatile("vse64.v v16, (%0);" ::"r"(_dst_));
      double tmp;
      asm volatile("vfmv.f.s %0, v16" : "=f"(tmp));
      *_dst_ = tmp;
      // clear reduction register
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(1));
      asm volatile("vmv.v.i v16,  0");
    }
  }

  // store the last value
  double *_dst_ = dest + m_row - 1;
  if (m_row % 2 == 0) // even
  {
    double tmp;
    asm volatile("vfmv.f.s %0, v24" : "=f"(tmp));
    *_dst_ = tmp;
  } else { // odd
    double tmp;
    asm volatile("vfmv.f.s %0, v16" : "=f"(tmp));
    *_dst_ = tmp;
  }
}

void gemv_rowwise_kernel_slice(const unsigned long int v_len,
                               const unsigned long int slice_width,
                               const unsigned long int slice_height,
                               double *matrix, double *vector) {
  asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_width));
  // load vector
  asm volatile("vle64.v v0, (%0);" ::"r"(vector));

  // for each row in slice
  for (uint64_t i = 0; i < slice_height; ++i) {
    double *_mat_ = matrix + i * v_len;
    double tmp; // for round slice later
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_width));
    // load matrix slice row
    asm volatile("vle64.v v4, (%0);" ::"r"(_mat_));
    // multiply with vector
    asm volatile("vfmul.vv v8, v4, v0");
    if (i % 2 == 0) {
      // round slide
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_height));
      asm volatile("vfmv.f.s %0, v24" : "=f"(tmp));
      asm volatile("vfslide1down.vf  v16, v24, %0" ::"f"(tmp));
      // reduction
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_width));
      asm volatile("vfredsum.vs v16, v8, v16");
    } else {
      // round slide
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_height));
      asm volatile("vfmv.f.s %0, v16" : "=f"(tmp));
      asm volatile("vfslide1down.vf  v24, v16, %0" ::"f"(tmp));
      // reduction
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_width));
      asm volatile("vfredsum.vs v24, v8, v24");
    }
  }

  if (slice_height % 2) {
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(slice_height));
    asm volatile("vmv.v.v v24, v16");
  }
}

void gemv_rowwise(const unsigned long int m_row, const unsigned long int v_len,
                  double *matrix, double *vector, double *dest) {
  // when matrix is samller than a slice
  if (v_len <= SLICE_SIZE) {
    gemv_rowwise_small_than_slice(m_row, v_len, matrix, vector, dest);
    return;
  }

  uint64_t num_slice_row = m_row / SLICE_SIZE;
  uint64_t rest_row = m_row % SLICE_SIZE;
  uint64_t num_slice_col = v_len / SLICE_SIZE;
  uint64_t rest_col = v_len % SLICE_SIZE;

  // each slice row
  for (uint64_t i = 0; i < num_slice_row; ++i) {
    // clear reduction sum register file
    clear_reduction_register();
    // each full slice
    for (uint64_t j = 0; j < num_slice_col; ++j) {
      double *_mat_ = matrix + i * SLICE_SIZE * v_len + j * SLICE_SIZE;
      double *_vec_ = vector + j * SLICE_SIZE;
      gemv_rowwise_kernel_slice(v_len, SLICE_SIZE, SLICE_SIZE, _mat_, _vec_);
    }
    // margin slice
    if (rest_col > 0) {
      double *_mat_ =
          matrix + i * SLICE_SIZE * v_len + num_slice_col * SLICE_SIZE;
      double *_vec_ = vector + num_slice_col * SLICE_SIZE;
      gemv_rowwise_kernel_slice(v_len, rest_col, SLICE_SIZE, _mat_, _vec_);
    }
    // store dest vector value
    double *_dst_ = dest + i * SLICE_SIZE;
    store_slice_results(_dst_, SLICE_SIZE);
  }

  // margin slice row
  if (rest_row > 0) {
    // clear reduction sum register file
    clear_reduction_register();
    // each bottom slice
    for (uint64_t j = 0; j < num_slice_col; ++j) {
      double *_mat_ =
          matrix + num_slice_row * SLICE_SIZE * v_len + j * SLICE_SIZE;
      double *_vec_ = vector + j * SLICE_SIZE;
      gemv_rowwise_kernel_slice(v_len, SLICE_SIZE, rest_row, _mat_, _vec_);
    }
    // margin slice
    if (rest_col > 0) {
      double *_mat_ = matrix + num_slice_row * SLICE_SIZE * v_len +
                      num_slice_col * SLICE_SIZE;
      double *_vec_ = vector + num_slice_col * SLICE_SIZE;
      gemv_rowwise_kernel_slice(v_len, rest_col, rest_row, _mat_, _vec_);
    }
    // store dest vector value
    double *_dst_ = dest + num_slice_row * SLICE_SIZE;
    store_slice_results(_dst_, rest_row);
  }
}

int gemv_verify(const unsigned long int m_row, const unsigned long int v_len,
                double *matrix, double *vector, double *dest) {
  for (uint64_t i = 0; i < m_row; ++i) {
    double res = dest[i];
    double golden = 0;
    for (uint64_t j = 0; j < v_len; ++j) {
      golden = golden + matrix[i * v_len + j] * vector[j];
    }
    if (golden != res) {
      printf("Sorry, wrong value! at index %d, result = %f, golden = %f \n", i,
             res, golden);
      return i;
    }
  }
  return 0;
}
