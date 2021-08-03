/*
OHIO STATE UNIVERSITY SOFTWARE DISTRIBUTION LICENSE

PolyBench/C, a collection of benchmarks containing static control
parts (the "Software")
Copyright (c) 2010-2016, Ohio State University. All rights reserved.

The Software is available for download and use subject to the terms
and conditions of this License.  Access or use of the Software
constitutes acceptance and agreement to the terms and conditions of
this License.  Redistribution and use of the Software in source and
binary forms, with or without modification, are permitted provided
that the following conditions are met:

1. Redistributions of source code must retain the above copyright
notice, this list of conditions and the capitalized paragraph below.

2. Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the capitalized paragraph below in
the documentation and/or other materials provided with the
distribution.

3. The name of Ohio State University, or its faculty, staff or
students may not be used to endorse or promote products derived from
the Software without specific prior written permission.

This software was produced with support from the U.S. Defense Advanced
Research Projects Agency (DARPA), the U.S. Department of Energy (DoE)
and the U.S. National Science Foundation. Nothing in this work should
be construed as reflecting the official policy or position of the
Defense Department, the United States government or Ohio State
University.

THIS SOFTWARE HAS BEEN APPROVED FOR PUBLIC RELEASE, UNLIMITED
DISTRIBUTION.  THE SOFTWARE IS PROVIDED ?AS IS? AND WITHOUT ANY
EXPRESS, IMPLIED OR STATUTORY WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, WARRANTIES OF ACCURACY, COMPLETENESS, NONINFRINGEMENT,
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
ACCESS OR USE OF THE SOFTWARE IS ENTIRELY AT THE USER?S RISK.  IN NO
EVENT SHALL OHIO STATE UNIVERSITY OR ITS FACULTY, STAFF OR STUDENTS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  THE SOFTWARE USER SHALL
INDEMNIFY, DEFEND AND HOLD HARMLESS OHIO STATE UNIVERSITY AND ITS
FACULTY, STAFF AND STUDENTS FROM ANY AND ALL CLAIMS, ACTIONS, DAMAGES,
LOSSES, LIABILITIES, COSTS AND EXPENSES, INCLUDING ATTORNEYS? FEES AND
COURT COSTS, DIRECTLY OR INDIRECTLY ARISING OUT OF OR IN CONNECTION
WITH ACCESS OR USE OF THE SOFTWARE.
*/

/**
 * This version is stamped on May 10, 2016
 *
 * Contact:
 *   Louis-Noel Pouchet <pouchet.ohio-state.edu>
 *   Tomofumi Yuki <tomofumi.yuki.fr>
 *
 * Web address: http://polybench.sourceforge.net
 */
/* jacobi-2d.c: this file is part of PolyBench/C */

/*************************************************************************
* RISC-V Vectorized Version
* Author: Cristóbal Ramírez Lazo
* email: cristobal.ramirez@bsc.es
* Barcelona Supercomputing Center (2020)
*************************************************************************/

// Porting to Ara SW environment
// Author: Matteo Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"
#include "riscv_vector.h"

// Define vector size
#if defined(SIMTINY)
#define N 256
#define TSTEPS 1
#elif defined(SIMSMALL)
#define N 128
#define TSTEPS 10
#elif defined(SIMMEDIUM)
#define N 256
#define TSTEPS 100
#elif defined(SIMLARGE)
#define N 256
#define TSTEPS 2000
#else
#define N 32
#define TSTEPS 1
//#define N 64
//#define TSTEPS 4
#endif

#define FABS(x) ((x < 0) ? -x : x)

// The vector algorithm seems not to be parametrized on the data type
// So, don't change this parameter if also the vector implementation is used
#define DATA_TYPE double
// Threshold for FP numbers comparison during the final check
#define THRESHOLD 0.000000000001
//#define SOURCE_PRINT
//#define RESULT_PRINT

static void init_array(uint32_t n, DATA_TYPE A[N][N], DATA_TYPE B[N][N]);
void kernel_jacobi_2d_vector(uint32_t n, DATA_TYPE A[N][N], DATA_TYPE B[N][N]);
static void jacobi_2d_scalar(uint32_t tsteps, uint32_t n, DATA_TYPE A[N][N],
                             DATA_TYPE B[N][N]);
static void jacobi_2d_vector(uint32_t tsteps, uint32_t n, DATA_TYPE A[N][N],
                             DATA_TYPE B[N][N]);
int check_result(DATA_TYPE A_s[N][N], DATA_TYPE B_s[N][N], DATA_TYPE A_v[N][N],
                 DATA_TYPE B_v[N][N], uint32_t n);
void output_printfile(uint32_t n, DATA_TYPE A[N][N]);
DATA_TYPE similarity_check(DATA_TYPE a, DATA_TYPE b, double threshold);

DATA_TYPE A_s[N][N] __attribute__((aligned(32 * NR_LANES), section(".l2")));
DATA_TYPE B_s[N][N] __attribute__((aligned(32 * NR_LANES), section(".l2")));
DATA_TYPE A_v[N][N] __attribute__((aligned(32 * NR_LANES), section(".l2")));
DATA_TYPE B_v[N][N] __attribute__((aligned(32 * NR_LANES), section(".l2")));

/* Array initialization. */
static void init_array(uint32_t n, DATA_TYPE A[N][N], DATA_TYPE B[N][N]) {
  for (uint32_t i = 0; i < n; i++)
    for (uint32_t j = 0; j < n; j++) {
      A[i][j] = ((DATA_TYPE)i * (j + 2) + 2) / n;
      B[i][j] = ((DATA_TYPE)i * (j + 3) + 3) / n;
    }
}

void kernel_jacobi_2d_vector(uint32_t n, DATA_TYPE A[N][N], DATA_TYPE B[N][N]) {
  vfloat64m1_t xU;
  vfloat64m1_t xUtmp;
  vfloat64m1_t xUleft;
  vfloat64m1_t xUright;
  vfloat64m1_t xUtop;
  vfloat64m1_t xUbottom;
  vfloat64m1_t xConstant;

  DATA_TYPE izq, der;
  uint32_t size_y = n - 2;
  uint32_t size_x = n - 2;

  // unsigned long int gvl = __builtin_epi_vsetvl(size_y, __epi_e64, __epi_m1);
  size_t gvl = vsetvl_e64m1(size_y); // PLCT

  xConstant = vfmv_v_f_f64m1(0.20, gvl);

  for (uint32_t j = 1; j <= size_x; j = j + gvl) {
    gvl = vsetvl_e64m1(size_x - j + 1);
    xU = vle64_v_f64m1(&A[1][j], gvl);
    xUtop = vle64_v_f64m1(&A[0][j], gvl);
    xUbottom = vle64_v_f64m1(&A[2][j], gvl);

    for (uint32_t i = 1; i <= size_y; i++) {
      if (i != 1) {
        xUtop = xU;
        xU = xUbottom;
        xUbottom = vle64_v_f64m1(&A[i + 1][j], gvl);
      }
      izq = A[i][j - 1];
      der = A[i][j + gvl];
      xUleft = vfslide1up_vf_f64m1(xU, izq, gvl);
      xUright = vfslide1down_vf_f64m1(xU, der, gvl);
      xUtmp = vfadd_vv_f64m1(xUleft, xUright, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xUtop, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xUbottom, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xU, gvl);
      xUtmp = vfmul_vv_f64m1(xUtmp, xConstant, gvl);
      vse64_v_f64m1(&B[i][j], xUtmp, gvl);
      //      if (i == 1 && j == 1) printf("0.2 * (%llx + %llx + %llx + %llx +
      // %llx) = %llx\n", A[i][j], A[i][j - 1], A[i][1 + j], A[1 + i][j], A[i -
      // 1][j], B[i][j]);
    }
  }
  asm volatile("fence" ::);
}

/* Main computational kernel. The whole function will be timed,
   including the call and return. */
static void jacobi_2d_scalar(uint32_t tsteps, uint32_t n, DATA_TYPE A[N][N],
                             DATA_TYPE B[N][N]) {
  for (uint32_t t = 0; t < tsteps; t++) {
    for (uint32_t i = 1; i < n - 1; i++)
      for (uint32_t j = 1; j < n - 1; j++) {
        B[i][j] = (0.2) * (A[i][j] + A[i][j - 1] + A[i][1 + j] + A[1 + i][j] +
                           A[i - 1][j]);
        //        if (i == 1 && j == 1) printf("0.2 * (%llx + %llx + %llx + %llx
        // + %llx) = %llx\n", A[i][j], A[i][j - 1], A[i][1 + j], A[1 + i][j],
        // A[i - 1][j], B[i][j]);
      }
    for (uint32_t i = 1; i < n - 1; i++)
      for (uint32_t j = 1; j < n - 1; j++)
        A[i][j] = (0.2) * (B[i][j] + B[i][j - 1] + B[i][1 + j] + B[1 + i][j] +
                           B[i - 1][j]);
  }
}

/* Main computational kernel. The whole function will be timed,
   including the call and return. */
static void jacobi_2d_vector(uint32_t tsteps, uint32_t n, DATA_TYPE A[N][N],
                             DATA_TYPE B[N][N]) {
  for (uint32_t t = 0; t < tsteps; t++) {
    kernel_jacobi_2d_vector(n, A, B);
    kernel_jacobi_2d_vector(n, B, A);
  }
}

int check_result(DATA_TYPE A_s[N][N], DATA_TYPE B_s[N][N], DATA_TYPE A_v[N][N],
                 DATA_TYPE B_v[N][N], uint32_t n) {
  for (uint32_t i = 0; i < n; i++) {
    for (uint32_t j = 0; j < n; j++) {
      if (!similarity_check(A_s[i][j], A_v[i][j], THRESHOLD) ||
          !similarity_check(B_s[i][j], B_v[i][j], THRESHOLD)) {
        printf("Error: A_s[%d][%d] = %llx != A_v[%d][%d] = %llx || B_s[%d][%d] "
               "= %llx != B_v[%d][%d] = %llx",
               i, j, A_s[i][j], i, j, A_v[i][j], i, j, B_s[i][j], i, j,
               B_v[i][j]);
        return -1;
      }
    }
  }
  printf("Passed.\n");
  return 0;
}

void output_printfile(uint32_t n, DATA_TYPE A[N][N]) {
  for (uint32_t i = 0; i < n; i++)
    for (uint32_t j = 0; j < n; j++) {
      printf("A[%d][%d] = %llx, ", i, j, A[i][j]);
      if (j == n - 1)
        printf("A[%d][%d] = %llx\n", i, j, A[i][j]);
    }
}

// Return 0 if the two FP numbers differ by more than a threshold
DATA_TYPE similarity_check(DATA_TYPE a, DATA_TYPE b, double threshold) {
  DATA_TYPE diff = a - b;
  if (FABS(diff) > threshold) {
    printf("fabs(diff): %llx, threshold: %llx\n", diff, threshold);
    return 0;
  }
  else
    return 1;
}

int main() {

  int error;

  printf("\n");
  printf("==============\n");
  printf("=  JACOBI2D  =\n");
  printf("==============\n");
  printf("\n");
  printf("\n");

  /* Initialize array(s). */
  printf("Initializing the arrays...\n");
  init_array(N, A_s, B_s);
  init_array(N, A_v, B_v);

#ifdef SOURCE_PRINT
  printf("Scalar A mtx:\n");
  output_printfile(N, A_s);
  printf("Vector A mtx:\n");
  output_printfile(N, A_v);
  printf("Scalar B mtx:\n");
  output_printfile(N, B_s);
  printf("Vector B mtx:\n");
  output_printfile(N, B_v);
#endif // RESULT_PRINT

  // Measure scalar kernel execution
  printf("Processing the scalar benchmark\n");
  start_timer();
  jacobi_2d_scalar(TSTEPS, N, A_s, B_s);
  stop_timer();
  printf("Scalar jacobi2d cycle count: %d\n", get_timer());

  // Measure vector kernel execution
  printf("Processing the vector benchmark\n");
  start_timer();
  jacobi_2d_vector(TSTEPS, N, A_v, B_v);
  stop_timer();
  int64_t runtime = get_timer();
  // 2* since we have 2 jacobi kernels, one on A_v, one on B_v
  // TSTEPS*5*N*N is the number of DPFLOP to compute
  float performance = 2.0 * (TSTEPS * 5.0 * N * N / runtime);
  float utilization = 100.0 * performance / NR_LANES;
  printf("Vector jacobi2d cycle count: %d\n", runtime);
  printf("The performance is %f DPFLOP/cycle (%f%% utilization).\n", performance,
         utilization);

#ifdef RESULT_PRINT
  printf("Scalar A mtx:\n");
  output_printfile(N, A_s);
  printf("Vector A mtx:\n");
  output_printfile(N, A_v);
  printf("Scalar B mtx:\n");
  output_printfile(N, B_s);
  printf("Vector B mtx:\n");
  output_printfile(N, B_v);
#endif // RESULT_PRINT

  printf("Checking the results:\n");
  error = check_result(A_s, B_s, A_v, B_v, N);

  return error;
}
