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

// Author: Matheus Cavalcante, ETH Zurich

#include "ex4.h"

// Matrix matrix multiplication kernel. Defined below.

void matmul(velement_t *c, velement_t *a, velement_t *b, uint64_t nrows,
            uint64_t ncols);

// Matrix multiplication

void ex4(velement_t *c, velement_t *a, velement_t *b) {
  // In this exercise, we will multiply matrices a and b (both of size
  // SIZE*SIZE), and store the result back in matrix c. We will implement the
  // kernel we analyzed during the lecture.

  /***************************
   *  Matrix initialization  *
   ***************************/

  const int64_t aa = 1;
  const int64_t ab = 1;
  const int64_t ac = -32;
  const int64_t ba = 2;
  const int64_t bb = 1;
  const int64_t bc = 16;
  const int64_t N = SIZE;

  // Initialize matrix a to a[i][j] = aa*i + ab*j + ac
  printf("Initializing matrix a...\n");
  for (int i = 0; i < N; ++i)
    for (int j = 0; j < N; ++j)
      *(a + i * N + j) = aa * i + ab * j + ac;
  // Initialize matrix b to b[i][j] = ba*i + bb*j + bc
  printf("Initializing matrix b...\n");
  for (int i = 0; i < N; ++i)
    for (int j = 0; j < N; ++j)
      *(b + i * N + j) = ba * i + bb * j + bc;

  /************
   *  Kernel  *
   ************/

  printf("Calling the matmul kernel...\n");
  // Check the matmul(c, a, b, N, N) function for the matmul kernel, and tasks 1
  // to 3.
  start_timer();
  matmul(c, a, b, SIZE, SIZE);
  stop_timer();

  /************
   *  Task 4  *
   ************/

  printf("The execution of the matmul kernel took %d cycles.\n", get_timer());

  // The matrix multiplication is a compute-bound kernel. This means that the
  // performance of this kernel is (theoretically) limited by the functional
  // units of the processor, and not by the memory bandwidth. Considering each
  // addition and multiplication of the vmacc instruction as two individual
  // operations, we need to 2N^3 operations to run the matmul kernel. Ara is
  // capable of running 8 operations per cycle.

  double performance = (double)get_timer() / 2 * N * N * N;
  printf(
      "Ara's performance is %lf OP/cycle, or %lf %% of the peak performance.",
      performance, performance / 8);

  // Q1: Did your kernel achieve a high performance?

  // Q2: Analyze your kernel and propose ways to improve the performance of this
  // kernel. Discuss with the TAs.

  /**********************
   *  Check the result  *
   **********************/

  // The result will be the following matrix
  // c[i][j] = (aa*bb*i*j + aa*bc*i + ac*bb*j + ac*bc) * N
  //         + (aa*ba*i + ab*bb*j + ab*bc + ba*ac) * (N*(N-1))/2
  //         + (ab*ba) * (N*(N-1)*(2*N-1))/6

  printf("Checking results...\n");

  for (int i = 0; i < N; ++i)
    for (int j = 0; j < N; ++j) {
      int64_t lin = (aa * bb * i * j + aa * bc * i + ac * bb * j + ac * bc) * N;
      int64_t qua =
          ((aa * ba * i + ab * bb * j + ab * bc + ba * ac) * (N * (N - 1))) / 2;
      int64_t cub = ((ab * ba) * (N * (N - 1) * (2 * N - 1))) / 6;

      if (*(c + i * N + j) != lin + qua + cub) {
        printf(
            "Error! Expected c[%d][%d] = %d, but found %d instead. Aborting.\n",
            i, j, lin + qua + cub, *(c + i * N + j));
        return;
      }
    }
}

void matmul(velement_t *c, velement_t *a, velement_t *b, uint64_t nrows,
            uint64_t ncols) {
  /************
   *  Task 1  *
   ************/

  // Since we do not have a vectorizing compiler, we will need to do vector
  // register allocation manually. For this matmul, you will need
  // two vector registers, `vA` and `vC`. Choose two vectors from the
  // v0-v31 available for the execution of this kernel.

  // vA = ??
  // vC = ??

  /************
   *  Task 2  *
   ************/

  // Implement the matrix multiplication, using the algorithm discussed during
  // the lecture. For the time being, consider that a row of the matrix fit
  // inside a vector. You will need to use other intrinsics defined in the
  // `intrinsics.h` file (Tip: look for the vmv and vmacc intrinsics).

  /************
   *  Task 3  *
   ************/

  // Optional: Implement the stripmining loop around your matrix multiplication.
  // You can test the result with a larger matrix (SIZE = 128, for example).
  // Beware of the runtime, this might take a long time to execute (a few
  // minutes to an hour).
}
