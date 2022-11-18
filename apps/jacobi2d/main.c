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

#include <stdio.h>
#include <string.h>

#include "kernel/jacobi2d.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#endif

// The padded matrices should be aligned in SW not on the padding,
// but on the actual data.
// R and C contain the padding as well.
extern uint64_t R;
extern uint64_t C;

extern uint64_t TSTEPS;

extern DATA_TYPE A_s[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern DATA_TYPE B_s[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern DATA_TYPE A_v[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern DATA_TYPE B_v[] __attribute__((aligned(4 * NR_LANES), section(".l2")));

int main() {
  printf("\n");
  printf("==============\n");
  printf("=  JACOBI2D  =\n");
  printf("==============\n");
  printf("\n");
  printf("\n");

  int error = 0;

  // Align the matrices so that the vector store will also be aligned
  size_t mtx_offset = ((4 * NR_LANES) / sizeof(DATA_TYPE)) - 1;
  DATA_TYPE *A_fixed_s = A_s + mtx_offset;
  DATA_TYPE *A_fixed_v = A_v + mtx_offset;
  DATA_TYPE *B_fixed_s = B_s + mtx_offset;
  DATA_TYPE *B_fixed_v = B_v + mtx_offset;

  // Check that the matrices are aligned on the actual output data
  // NR_LANES can be maximum 16 here
  if (((uint64_t)(B_fixed_v + 1) & (0x3f / (16 / NR_LANES))) != 0) {
    printf("Fatal warning: the matrices are not correctly aligned.\n");
    return -1;
  } else {
    printf("The store address 0x%lx is correctly aligned.\n",
           (uint64_t)(B_fixed_v + 1));
  }

#ifdef SOURCE_PRINT
  printf("Scalar A mtx:\n");
  output_printfile(R, C, A_fixed_s);
  printf("Vector A mtx:\n");
  output_printfile(R, C, A_fixed_v);
  printf("Scalar B mtx:\n");
  output_printfile(R, C, B_fixed_s);
  printf("Vector B mtx:\n");
  output_printfile(R, C, B_fixed_v);
#endif

#ifndef VCD_DUMP
  // Measure scalar kernel execution
  printf("Processing the scalar benchmark\n");
  start_timer();
  j2d_s(R, C, A_fixed_s, B_fixed_s, TSTEPS);
  stop_timer();
  printf("Scalar jacobi2d cycle count: %d\n", get_timer());
#endif

  // Measure vector kernel execution
  printf("Processing the vector benchmark\n");
  start_timer();
  j2d_v(R, C, A_fixed_v, B_fixed_v, TSTEPS);
  stop_timer();
  int64_t runtime = get_timer();
  // 2* since we have 2 jacobi kernels, one on A_fixed_v, one on B_fixed_v
  // TSTEPS*5*N*N is the number of DPFLOP to compute
  float performance = (2.0 * TSTEPS * 5.0 * (R - 1) * (C - 1) / runtime);
  float utilization = 100.0 * performance / NR_LANES;
  printf("Vector jacobi2d cycle count: %d\n", runtime);
  printf("The performance is %f DPFLOP/cycle (%f%% utilization).\n",
         performance, utilization);

#ifdef RESULT_PRINT
  printf("Scalar A mtx:\n");
  output_printfile(R, C, A_fixed_s);
  printf("Vector A mtx:\n");
  output_printfile(R, C, A_fixed_v);
  printf("Scalar B mtx:\n");
  output_printfile(R, C, B_fixed_s);
  printf("Vector B mtx:\n");
  output_printfile(R, C, B_fixed_v);
#endif

  printf("Checking the results:\n");
  for (uint32_t i = 0; i < R; i++)
    for (uint32_t j = 0; j < C; j++)
      if (!similarity_check(A_fixed_s[i * C + j], A_fixed_v[i * C + j],
                            THRESHOLD)) {
        printf("Error: [%d, %d], %f, %f\n", i, j, A_fixed_s[i * C + j],
               A_fixed_v[i * C + j]);
        error = 1;
      }
  if (!error)
    printf("Check successful: no errors.\n");

  return error;
}
