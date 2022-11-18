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

// Porting to Ara SW environment and Optimization
// Author: Matteo Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>

#include "jacobi2d.h"

void j2d_s(uint64_t r, uint64_t c, DATA_TYPE *A, DATA_TYPE *B,
           uint64_t tsteps) {
  for (uint32_t t = 0; t < tsteps; t++) {
    for (uint32_t i = 1; i < r - 1; i++)
      for (uint32_t j = 1; j < c - 1; j++)
        B[i * c + j] =
            (0.2) * (A[i * c + j] + A[i * c + j - 1] + A[i * c + j + 1] +
                     A[(i + 1) * c + j] + A[(i - 1) * c + j]);
    for (uint32_t i = 1; i < r - 1; i++)
      for (uint32_t j = 1; j < c - 1; j++)
        A[i * c + j] =
            (0.2) * (B[i * c + j] + B[i * c + j - 1] + B[i * c + j + 1] +
                     B[(i + 1) * c + j] + B[(i - 1) * c + j]);
  }
}

void j2d_v(uint64_t r, uint64_t c, DATA_TYPE *A, DATA_TYPE *B,
           uint64_t tsteps) {
  for (uint32_t t = 0; t < tsteps; t++) {
    j2d_kernel_asm_v(r, c, A, B);
    j2d_kernel_asm_v(r, c, B, A);
  }
}

void j2d_kernel_v(uint64_t r, uint64_t c, DATA_TYPE *A, DATA_TYPE *B) {
  vfloat64m1_t xU;
  vfloat64m1_t xUtmp;
  vfloat64m1_t xUleft;
  vfloat64m1_t xUright;
  vfloat64m1_t xUtop;
  vfloat64m1_t xUbottom;

  DATA_TYPE izq, der;
  uint32_t size_x = c - 2;
  uint32_t size_y = r - 2;

  size_t gvl = vsetvl_e64m1(size_x);

  for (uint32_t j = 1; j <= size_x; j = j + gvl) {
    gvl = vsetvl_e64m1(size_x - j + 1);
    xU = vle64_v_f64m1(&A[1 * c + j], gvl);
    xUtop = vle64_v_f64m1(&A[0 * c + j], gvl);
    xUbottom = vle64_v_f64m1(&A[2 * c + j], gvl);

    for (uint32_t i = 1; i <= size_y; i++) {
      if (i != 1) {
        xUtop = xU;
        xU = xUbottom;
        xUbottom = vle64_v_f64m1(&A[(i + 1) * c + j], gvl);
      }
      izq = A[i * c + j - 1];
      der = A[i * c + j + gvl];
      xUleft = vfslide1up_vf_f64m1(xU, izq, gvl);
      xUright = vfslide1down_vf_f64m1(xU, der, gvl);
      xUtmp = vfadd_vv_f64m1(xUleft, xUright, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xUtop, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xUbottom, gvl);
      xUtmp = vfadd_vv_f64m1(xUtmp, xU, gvl);
      xUtmp = vfmul_vf_f64m1(xUtmp, (float)0.2, gvl);
      vse64_v_f64m1(&B[i * c + j], xUtmp, gvl);
    }
  }
}

// Optimized version of the jacobi2d kernel
// 1) Preload the coefficients, before each vstore
// 2) Eliminate WAW and WAR hazards
// 3) Unroll the loop and use multiple buffers
void j2d_kernel_asm_v(uint64_t r, uint64_t c, DATA_TYPE *A, DATA_TYPE *B) {
  DATA_TYPE izq_0, izq_1, izq_2;
  DATA_TYPE der_0, der_1, der_2;
  uint32_t size_x = c - 2;
  uint32_t size_y = r - 2;

  // Avoid division. 1/5 == 0.2
  double five_ = 0.2;

  size_t gvl;

  asm volatile("vsetvli %0, %1, e64, m4, ta, ma" : "=r"(gvl) : "r"(size_x));

  for (uint32_t j = 1; j <= size_x; j = j + gvl) {
    asm volatile("vsetvli %0, %1, e64, m4, ta, ma"
                 : "=r"(gvl)
                 : "r"(size_x - j + 1));
    asm volatile("vle64.v v0, (%0)" ::"r"(&A[0 * c + j])); // v0 top
    asm volatile("vle64.v v4, (%0)" ::"r"(&A[1 * c + j])); // v4 middle
    asm volatile("vle64.v v8, (%0)" ::"r"(&A[2 * c + j])); // v8 bottom

    // Look ahead and load the next coefficients
    // Do it before vector stores
    izq_0 = A[1 * c + j - 1];
    der_0 = A[1 * c + j + gvl];

    for (uint32_t i = 1; i <= size_y; i += 3) {
#ifdef VCD_DUMP
      // Start dumping VCD
      if (i == 7)
        event_trigger = +1;
      // Stop dumping VCD
      if (i == 13)
        event_trigger = -1;
#endif
      asm volatile("vfslide1up.vf v24, v4, %0" ::"f"(izq_0));
      asm volatile("vfslide1down.vf v28, v4, %0" ::"f"(der_0));
      asm volatile("vfadd.vv v12, v4, v0");   // middle - top
      asm volatile("vfadd.vv v12, v12, v8");  // bottom
      asm volatile("vfadd.vv v12, v12, v24"); // left
      if ((i + 1) <= size_y) {
        asm volatile(
            "vle64.v v0, (%0)" ::"r"(&A[((i + 1) + 1) * c + j])); // v0 top
      }
      asm volatile("vfadd.vv v12, v12, v28"); // right
      asm volatile("vfmul.vf v12, v12, %0" ::"f"(five_));
      if ((i + 1) <= size_y) {
        izq_1 = A[(i + 1) * c + j - 1];
        der_1 = A[(i + 1) * c + j + gvl];
      }
      asm volatile("vse64.v v12, (%0)" ::"r"(&B[i * c + j]));

      if ((i + 1) <= size_y) {
        asm volatile("vfslide1up.vf v24, v8, %0" ::"f"(izq_1));
        asm volatile("vfslide1down.vf v28, v8, %0" ::"f"(der_1));
        asm volatile("vfadd.vv v16, v4, v8");   // middle - top
        asm volatile("vfadd.vv v16, v16, v0");  // bottom
        asm volatile("vfadd.vv v16, v16, v24"); // left
        if ((i + 2) <= size_y) {
          asm volatile(
              "vle64.v v4, (%0)" ::"r"(&A[((i + 2) + 1) * c + j])); // v4 middle
        }
        asm volatile("vfadd.vv v16, v16, v28"); // right
        asm volatile("vfmul.vf v16, v16, %0" ::"f"(five_));
        if ((i + 2) <= size_y) {
          izq_2 = A[(i + 2) * c + j - 1];
          der_2 = A[(i + 2) * c + j + gvl];
        }
        asm volatile("vse64.v v16, (%0)" ::"r"(&B[(i + 1) * c + j]));

        if ((i + 2) <= size_y) {
          asm volatile("vfslide1up.vf v24, v0, %0" ::"f"(izq_2));
          asm volatile("vfslide1down.vf v28, v0, %0" ::"f"(der_2));
          asm volatile("vfadd.vv v20, v0, v8");   // middle - top
          asm volatile("vfadd.vv v20, v20, v4");  // bottom
          asm volatile("vfadd.vv v20, v20, v24"); // left
          if ((i + 3) <= size_y) {
            asm volatile("vle64.v v8, (%0)" ::"r"(
                &A[((i + 3) + 1) * c + j])); // v8 bottom
          }
          asm volatile("vfadd.vv v20, v20, v28"); // right
          asm volatile("vfmul.vf v20, v20, %0" ::"f"(five_));
          if ((i + 3) <= size_y) {
            izq_0 = A[(i + 3) * c + j - 1];
            der_0 = A[(i + 3) * c + j + gvl];
          }
          asm volatile("vse64.v v20, (%0)" ::"r"(&B[(i + 2) * c + j]));
        }
      }
    }
  }
}

// Debug
inline void output_printfile(uint64_t r, uint64_t c, DATA_TYPE *A) {
  for (uint32_t i = 0; i < r; i++)
    for (uint32_t j = 0; j < c; j++) {
      printf("A[%d][%d] = %f, ", i, j, A[i * c + j]);
      if (j == c - 1)
        printf("A[%d][%d] = %f\n", i, j, A[i * c + j]);
    }
}

/*
Intermediate optimization kernel, to better understand the algorithm

void j2d_kernel_asm_v(uint64_t r, uint64_t c, DATA_TYPE *A, DATA_TYPE *B) {
  DATA_TYPE izq, der;
  uint32_t size_y = r - 2;
  uint32_t size_x = c - 2;

  // Avoid division. 1/5 == 0.2
  double five_ = 0.2;

  size_t gvl;

  asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r" (gvl) : "r" (size_x));

  for (uint32_t j = 1; j <= size_x; j = j + gvl) {
    asm volatile ("vsetvli %0, %1, e64, m1, ta, ma" : "=r" (gvl) : "r" (size_x -
j + 1)); asm volatile ("vle64.v v0, (%0)" :: "r" (&A[0*c + j])); // v0 top asm
volatile ("vle64.v v1, (%0)" :: "r" (&A[1*c + j])); // v1 middle asm volatile
("vle64.v v2, (%0)" :: "r" (&A[2*c + j])); // v2 bottom

    for (uint32_t i = 1; i <= size_y; i += 3) {
      if (i != 1) {
        asm volatile ("vle64.v v2, (%0)" :: "r" (&A[(i+1)*c + j])); // v2 bottom
      }
      izq = A[i*c + j - 1];
      der = A[i*c + j + gvl];
      asm volatile ("vfslide1up.vf v6, v1, %0" :: "f" (izq));
      asm volatile ("vfslide1down.vf v7, v1, %0" :: "f" (der));
      asm volatile ("vfadd.vv v5, v6, v7"); // left, right
      asm volatile ("vfadd.vv v5, v5, v0"); // top
      asm volatile ("vfadd.vv v5, v5, v2"); // bottom
      asm volatile ("vfadd.vv v5, v5, v1"); // middle
      asm volatile ("vfmul.vf v5, v5, %0" :: "f" (five_));
      asm volatile ("vse64.v v5, (%0)" :: "r" (&B[i*c + j]));

      asm volatile ("vle64.v v0, (%0)" :: "r" (&A[((i+1)+1)*c + j])); // v0 top

      izq = A[(i+1)*c + j - 1];
      der = A[(i+1)*c + j + gvl];
      asm volatile ("vfslide1up.vf v6, v2, %0" :: "f" (izq));
      asm volatile ("vfslide1down.vf v7, v2, %0" :: "f" (der));
      asm volatile ("vfadd.vv v5, v6, v7"); // left, right
      asm volatile ("vfadd.vv v5, v5, v1"); // top
      asm volatile ("vfadd.vv v5, v5, v0"); // bottom
      asm volatile ("vfadd.vv v5, v5, v2"); // middle
      asm volatile ("vfmul.vf v5, v5, %0" :: "f" (five_));
      asm volatile ("vse64.v v5, (%0)" :: "r" (&B[(i+1)*c + j]));

      asm volatile ("vle64.v v1, (%0)" :: "r" (&A[((i+2)+1)*c + j])); // v1
middle

      izq = A[(i+2)*c + j - 1];
      der = A[(i+2)*c + j + gvl];
      asm volatile ("vfslide1up.vf v6, v0, %0" :: "f" (izq));
      asm volatile ("vfslide1down.vf v7, v0, %0" :: "f" (der));
      asm volatile ("vfadd.vv v5, v6, v7"); // left, right
      asm volatile ("vfadd.vv v5, v5, v2"); // top
      asm volatile ("vfadd.vv v5, v5, v1"); // bottom
      asm volatile ("vfadd.vv v5, v5, v0"); // middle
      asm volatile ("vfmul.vf v5, v5, %0" :: "f" (five_));
      asm volatile ("vse64.v v5, (%0)" :: "r" (&B[(i+2)*c + j]));
    }
  }
}
*/
