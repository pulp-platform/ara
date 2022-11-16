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

#include "spmv.h"
#include "runtime.h"
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

#define SLICE_SIZE 128
#define DATA_BYTE 8 // double type has 8 bytes

void spmv_csr_idx32(int32_t N_ROW, int32_t *CSR_PROW, int32_t *CSR_INDEX,
                    double *CSR_DATA, double *IN_VEC, double *OUT_VEC) {
  for (int i = 0; i < N_ROW; ++i) {
    int32_t len = CSR_PROW[i + 1] - CSR_PROW[i];
    double *data = CSR_DATA + CSR_PROW[i];
    int32_t *index = CSR_INDEX + CSR_PROW[i];
    double *_dst_ = OUT_VEC + i - 1;

    if (i % 2 == 0) {
      // clear register file
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(1));
      asm volatile("vmv.v.i v16,  0");
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(SLICE_SIZE));
      asm volatile("vmv.v.i v12,  0");

      // SpVV
      while (len > SLICE_SIZE) {
        asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(SLICE_SIZE));
        asm volatile("vle64.v v4, (%0)" ::"r"(data));          // fetch entries
        asm volatile("vle32.v v8, (%0)" ::"r"(index));         // fetch indices
        asm volatile("vloxei32.v v0, (%0), v8" ::"r"(IN_VEC)); // load data
        asm volatile("vfmul.vv v12, v4, v0");      // vector multiply
        asm volatile("vfredsum.vs v16, v12, v16"); // reduction
        len = len - SLICE_SIZE;
        data = data + SLICE_SIZE;
        index = index + SLICE_SIZE;
      }
      if (len > 0) {
        asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(len));
        asm volatile("vle64.v v4, (%0)" ::"r"(data));          // fetch entries
        asm volatile("vle32.v v8, (%0)" ::"r"(index));         // fetch indices
        asm volatile("vloxei32.v v0, (%0), v8" ::"r"(IN_VEC)); // load data
        asm volatile("vfmul.vv v12, v4, v0");      // vector multiply
        asm volatile("vfredsum.vs v16, v12, v16"); // reduction
      }
      // store previous data
      if (i != 0) {
        double tmp;
        asm volatile("vfmv.f.s %0, v24" : "=f"(tmp));
        *_dst_ = tmp;
      }

    } else {
      // clear register file
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(1));
      asm volatile("vmv.v.i v24,  0");
      asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(SLICE_SIZE));
      asm volatile("vmv.v.i v12,  0");

      // SpVV
      while (len > SLICE_SIZE) {
        asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(SLICE_SIZE));
        asm volatile("vle64.v v4, (%0)" ::"r"(data));          // fetch entries
        asm volatile("vle32.v v8, (%0)" ::"r"(index));         // fetch indices
        asm volatile("vloxei32.v v0, (%0), v8" ::"r"(IN_VEC)); // load data
        asm volatile("vfmul.vv v12, v4, v0");      // vector multiply
        asm volatile("vfredsum.vs v24, v12, v24"); // reduction
        len = len - SLICE_SIZE;
        data = data + SLICE_SIZE;
        index = index + SLICE_SIZE;
      }
      if (len > 0) {
        asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(len));
        asm volatile("vle64.v v4, (%0)" ::"r"(data));          // fetch entries
        asm volatile("vle32.v v8, (%0)" ::"r"(index));         // fetch indices
        asm volatile("vloxei32.v v0, (%0), v8" ::"r"(IN_VEC)); // load data
        asm volatile("vfmul.vv v12, v4, v0");      // vector multiply
        asm volatile("vfredsum.vs v24, v12, v24"); // reduction
      }
      // store previous data
      double tmp;
      asm volatile("vfmv.f.s %0, v16" : "=f"(tmp));
      *_dst_ = tmp;
    }
  }

  // store the last value
  double *_dst_ = OUT_VEC + N_ROW - 1;
  if (N_ROW % 2 == 0) // even
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

int spmv_verify(int32_t N_ROW, int32_t *CSR_PROW, int32_t *CSR_INDEX,
                double *CSR_DATA, double *IN_VEC, double *OUT_VEC) {
  for (int32_t i = 0; i < N_ROW; ++i) {
    double res = OUT_VEC[i];

    int32_t len = CSR_PROW[i + 1] - CSR_PROW[i];
    double *data = CSR_DATA + CSR_PROW[i];
    int32_t *index = CSR_INDEX + CSR_PROW[i];

    double golden = 0;
    for (int32_t j = 0; j < len; ++j) {
      int32_t idx = index[j] / DATA_BYTE;
      golden = golden + data[j] * IN_VEC[idx];
      // printf("index:%d, data: %f, vec: %f\n", idx, data[j], IN_VEC[idx]);
    }
    if ((float)golden != (float)res) {
      printf("Sorry, wrong value! at index %d, result = %f, golden = %f \n", i,
             res, golden);
      return i;
    }
  }
  return 0;
}
