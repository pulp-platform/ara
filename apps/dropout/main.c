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

// Include <riscv_vector.h> to use vector intrinsics
// Documentation: https://github.com/riscv/rvv-intrinsic-doc
// Compiler support:
// https://github.com/riscv/riscv-gnu-toolchain/tree/rvv-intrinsic
#include <stdio.h>
// Use intrinsics, by default
#include <riscv_vector.h>
#define INTRINSICS
#undef INTRINSICS

#include "dropout.h"
#include "runtime.h"

#ifndef SPIKE
#include "printf.h"
#endif

extern const unsigned int N;
extern const float I[];
extern const float SCALE;
extern const int32_t SEL[];
extern float o[];
extern float o_gold[];

// Scalar dropout
void dropout_gold(const unsigned int n, const float *i, const float scale,
                  const int32_t *sel, float *o) {
  for (unsigned int k = 0; k < n; ++k) {
    o[k] = (sel[k] == 1) ? (i[k] * scale) : 0;
  }
}

#ifdef INTRINSICS
void dropout_vec(const unsigned int n, const float *i, const float scale,
                 const int32_t *sel, float *o) {
  unsigned int vl;

  vfloat32m8_t vi, vo;
  vint32m8_t vsel;
  vbool4_t vsel_m;

  for (unsigned int avl = n; (vl = vsetvl_e32m8(avl)) > 0; avl -= vl) {
    // Load selection vector
    vsel = vle32_v_i32m8(sel, vl);
    // Produce the selection mask
    vsel_m = vmseq_vx_i32m8_b4(vsel, 1, vl);
    // Initialize output vector with zeroes
    vo = vfmv_v_f_f32m8((float)0, vl);
    // Load input vector
    vi = vle32_v_f32m8(i, vl);
    // Calculate output vector
    vo = vfmul_vf_f32m8_m(vsel_m, vo, vi, scale, vl);
    vse32_v_f32m8(o, vo, vl);
    // Bump pointers
    i += vl;
    sel += vl;
    o += vl;
  }
}
#else
void dropout_vec(const unsigned int n, const float *i, const float scale,
                 const int32_t *sel, float *o) {
  unsigned int vl;

  asm volatile("vsetvli %[vl], %[n], e32, m8, ta, ma"
               : [vl] "=r"(vl)
               : [n] "r"(n));

  for (unsigned int avl = n; avl > 0; avl -= vl) {
    // Find next vl
    asm volatile("vsetvli %[vl], %[avl], e32, m8, ta, ma"
                 : [vl] "=r"(vl)
                 : [avl] "r"(avl));
    asm volatile("vle32.v v16, (%[sel])" ::[sel] "r"(sel));
    // Produce the selection mask
    asm volatile("vmseq.vi v0, v16, 1");
    // Initialize output vector with zeroes
    asm volatile("vmv.v.i v24, 0");
    // Load input and selection vectors
    asm volatile("vle32.v v8, (%[i])" ::[i] "r"(i));
    // Calculate output vector
    asm volatile("vfmul.vf v24, v8, %[scale], v0.t" ::[scale] "f"(scale));
    asm volatile("vse32.v v24, (%[o])" ::[o] "r"(o));
    // Bump pointers
    i += vl;
    sel += vl;
    o += vl;
  }
}
#endif

int verify_array(float *arr, float *arr_gold, const unsigned int n) {
  for (unsigned int k = 0; k < n; ++k) {
    if (arr[k] != arr_gold[k]) {
      //      printf("(%x, %x)\n", *((uint32_t*) &arr[k]), *((uint32_t*)
      //      &arr_gold[k]));
      return k;
    }
  }
  return -1;
}

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  DROPOUT  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

#ifdef SPIKE
  // Enable V extension
  ENABLE_VEC;
#endif

#ifndef SPIKE
  // Call the main kernel, and measure cycles
  start_timer();
  dropout_vec(N, I, SCALE, SEL, o);
  stop_timer();
  // Performance metrics
  int64_t runtime = get_timer();

  // Only count effective SPFLOP/cycle
  float performance = (float)N / runtime;
  float utilization = (float)100 * performance / (2.0 * NR_LANES);
  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f SPFLOP/cycle (%f%% utilization).\n",
         performance, utilization);
#else
  // Call the main kernel
  dropout_vec(N, I, SCALE, SEL, o);
#endif

  // Verify correctness
  dropout_gold(N, I, SCALE, SEL, o_gold);
  int error = verify_array(o, o_gold, N);
  if (error != -1) {
    printf("Error code %d\n", error);
    printf("o[%d]=%d\n", error, o[error]);
    return -1;
  } else {
    printf("Passed.\n");
  }

  return 0;
}
