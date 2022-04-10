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

// Author: Matteo Perotti, ETH Zurich

#include "ex3.h"

// Dropout kernel, defined below.
// Look at the end of the file for the definition of the scalar function.
void dropout_scalar(uint64_t n, velement_t *i, velement_t scale,
                 velement_t *sel, velement_t *o);
void dropout_vector(uint64_t n, velement_t *i, velement_t scale,
                 velement_t *sel, velement_t *o);

// Dropout

void ex3(velement_t *i, velement_t *sel, velement_t *o, velement_t *o_gold) {
  // In this exercise, you will implement Dropout, a way to fight against
  // network overfitting during training. Some of the nodes are
  // dropped out from the network, introducing random noise.
  // We will assume to already have in memory our keep/drop vector.

  /***************************
   *  Vectors initialization  *
   ***************************/

  const int64_t N = SIZE;
  velement_t scale;
  uint64_t error;

  printf("Initializing input vector...\n");
  for (int k = 0; k < N; ++k) {
    i[k] = k;
  }
  printf("Initializing output vector...\n");
  for (int k = 0; k < N; ++k) {
    // Fill the output memory bits with 1s to increase the
    // verification process reliability
    o[k] = ~0;
  }
  printf("Initializing keep/drop vector...\n");
  for (int k = 0; k < N; ++k) {
    // A real dropout would randomize this process with a given probability.
    sel[k] = (k % 3) ? 1 : 0;
  }
  // In a real dropout kernel, this value depends on the drop probability.
  printf("Initializing the scale factor...\n");
  scale = 17;

  /************
   *  Kernel  *
   ************/

  printf("Calling the dropout kernel...\n");
  start_timer();
  dropout_vector(N, i, scale, sel, o);
  stop_timer();

  /************
   *  Task 4  *
   ************/

  printf("The execution of the dropout kernel took %d cycles.\n", get_timer());

  // Let's analyze the performances of the dropout kernel

  double performance = (double)N / get_timer();
  printf(
      "Ara's performance is %lf OP/cycle, or %lf %% of the peak performance.\n",
      performance, performance / 8);

  // Q1: Did your kernel achieve a high performance?

  // Q2: Analyze the dropout performance finding its arithmetic intensity.
  // How can you improve the perfromance of the kernel?

  /**********************
   *  Check the result  *
   **********************/

  // The result vector is checked against the golden value produced
  // by the scalar implementation.
  dropout_scalar(N, i, scale, sel, o_gold);
  printf("Checking results...\n");

  error = 0;
  for (uint64_t k = 0; k < N; ++k) {
    if (o[k] != o_gold[k]) {
      printf("Error at index %d. (o[%d] = %ld) != (o_gold[%d] = %ld)\n", k, k, o[k], k, o_gold[k]);
      error++;
      break;
    }
  }

  if (error) {
    printf("FAIL.\n");
  } else {
    printf("SUCCESS. Your vector dropout works like a charm!\n");
  }
}

// Dropout, scalar version.
// n: the number of elements of the input vector
// i: addr of the input vector
// scale: scaling factor
// sel: addr of the keep/drop vector
// o: addr of the output vector
void dropout_scalar(uint64_t n, velement_t *i, velement_t scale,
                 velement_t *sel, velement_t *o) {
  /************
   *  Task 1  *
   ************/

  // What does this function do?

  for (uint64_t k = 0; k < n; ++k) {
    o[k] = sel[k] ? (i[k] * scale) : 0;
  }
}

void dropout_vector(uint64_t n, velement_t *i, velement_t scale,
                 velement_t *sel, velement_t *o) {
  /************
   *  Task 2  *
   ************/

  // We want to vectorize the dropout_scalar function.
  // The ternary operator in the loop forks the flow at each iteration.
  // This seems to prevent a vector implementation... how can you circumvent the issue?
  // Provide a vector implementation

  /************
   *  Task 2  *
   ************/

  // Test your implementation. Is it correct? If not, why?
  // Suggestion: pay attention to the RISC-V V VRF byte layouts.

  /************
   *  Task 3  *
   ************/

  // Implement the stripmining loop around your Dropout kernel to support vectors longer
  // then your current maximum vl.

  /*
    IMPLEMENT THE VECTOR DROPOUT CODE HERE
  */
}
