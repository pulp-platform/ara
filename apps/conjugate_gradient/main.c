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

#include <stdint.h>
#include <string.h>

#include "runtime.h"
#include "shared_kernel/fdotproduct.h"
#include "shared_kernel/gemv.h"
#include "shared_kernel/spmv.h"
#include "util.h"

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#define USE_SPMV 1
#define MIN_LOSS 0.0005
#define abs(x) (x < 0 ? -x : x)

extern uint64_t size;
extern uint64_t step;
extern double sparsity;

extern double A[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double Ax[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double x[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double b[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double r[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double p[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double Ap[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int32_t A_PROW[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int32_t A_IDX[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double A_DATA[] __attribute__((aligned(4 * NR_LANES), section(".l2")));

void daxpy(double *x, double a, double *y, double *dest, uint64_t len) {
#define MAX_AVL 128
  while (len > MAX_AVL) {
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(MAX_AVL));
    asm volatile("vle64.v v0, (%0);" ::"r"(x));
    asm volatile("vle64.v v4, (%0);" ::"r"(y));
    asm volatile("vfmacc.vf v4, %0, v0" ::"f"(a));
    asm volatile("vse64.v v4, (%0);" ::"r"(dest));
    x = x + MAX_AVL;
    y = y + MAX_AVL;
    dest = dest + MAX_AVL;
    len = len - MAX_AVL;
  }
  if (len > 0) {
    asm volatile("vsetvli zero, %0, e64, m2, ta, ma" ::"r"(len));
    asm volatile("vle64.v v0, (%0);" ::"r"(x));
    asm volatile("vle64.v v4, (%0);" ::"r"(y));
    asm volatile("vfmacc.vf v4, %0, v0" ::"f"(a));
    asm volatile("vse64.v v4, (%0);" ::"r"(dest));
  }
}

double CG_iteration_gemv(double *A, double *x, double *b, double *r, double *p,
                         double *Ap, uint64_t size) {
  /*
  Calculate step length alpha
  */
  double rk_norm = fdotp_v64b(r, r, size);
  gemv_rowwise(size, size, A, p, Ap);
  double pAp = fdotp_v64b(p, Ap, size);
  double alpha = rk_norm / pAp;

  /*
  update x
  */
  daxpy(p, alpha, x, x, size);

  /*
  update loss r
  */
  daxpy(Ap, (-1.0) * alpha, r, r, size);

  /*
  calculate beta
  */
  double rk_norm_new = fdotp_v64b(r, r, size);
  double beta = rk_norm_new / rk_norm;
  /*
  update p
  */
  daxpy(p, beta, r, p, size);

  /*
  return loss
  */
  return rk_norm_new;
}

double CG_iteration_spmv(int32_t *A_PROW, int32_t *A_IDX, double *A_DATA,
                         double *x, double *b, double *r, double *p, double *Ap,
                         uint64_t size) {
  /*
  Calculate step length alpha
  */
  double rk_norm = fdotp_v64b(r, r, size);
  spmv_csr_idx32(size, A_PROW, A_IDX, A_DATA, p, Ap);
  double pAp = fdotp_v64b(p, Ap, size);
  // printf("pAp: %f\n", pAp);
  if (abs(pAp) < MIN_LOSS) {
    return rk_norm;
  }
  double alpha = rk_norm / pAp;

  /*
  update x
  */
  daxpy(p, alpha, x, x, size);

  /*
  update loss r
  */
  daxpy(Ap, (-1.0) * alpha, r, r, size);

  /*
  calculate beta
  */
  double rk_norm_new = fdotp_v64b(r, r, size);
  double beta = rk_norm_new / rk_norm;

  /*
  update p
  */
  daxpy(p, beta, r, p, size);

  /*
  return loss
  */
  return rk_norm_new;
}

int main() {
  printf("\n");
  printf("========================\n");
  printf("=  Conjugate Gradient  =\n");
  printf("========================\n");
  printf("\n");
  printf("\n");

  printf("\n");
  printf("------------------------------------------------------------\n");
  printf("Solving a Ax=b equation with (%d x %d) Matrix size...\n", size, size);
  if (USE_SPMV) {
    printf("Sparse Matrix in CSR format, with %f nonzeros per row\n",
           sparsity * size);
  }
  printf("------------------------------------------------------------\n");
  printf("\n");

  printf("Initializing CGM parameters...\n");
  if (USE_SPMV) {
    spmv_csr_idx32(size, A_PROW, A_IDX, A_DATA, x, Ax);
  } else {
    gemv_rowwise(size, size, A, x, Ax);
  }
  daxpy(Ax, -1.0, b, r, size);
  daxpy(Ax, -1.0, b, p, size);

  printf("Start CGM ...\n");
  uint64_t i = 0;
  while (1) {
    if (step > 0 && i >= step) {
      break;
    }

    double loss;
    if (USE_SPMV) {
      loss = CG_iteration_spmv(A_PROW, A_IDX, A_DATA, x, b, r, p, Ap, size);
    } else {
      loss = CG_iteration_gemv(A, x, b, r, p, Ap, size);
    }
    printf("iteration %d, loss: %f\n", i, loss);
    if (loss < MIN_LOSS) {
      break;
    }
    i++;
  }
  return 0;
}
