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

#include "ex2.h"

// Vector-vector add kernel. Defined below.

void vvadd(velement_t *c, velement_t *a, velement_t *b, uint64_t len);

// Stripmining loop

void ex2(velement_t *c, velement_t *a, velement_t *b) {
  // In this exercise, we will add vectors a and b (both of size SIZE*SIZE, much
  // larger than the vector length) together, and store the result back in
  // vector c.

  /***************************
   *  Vector initialization  *
   ***************************/

  // Initialize vector a to a[i] = i + 2
  printf("Initializing vector a...\n");
  for (int i = 0; i < SIZE * SIZE; ++i)
    a[i] = i + 2;
  // Initialize vector b to b[i] = i - 3
  printf("Initializing vector b...\n");
  for (int i = 0; i < SIZE * SIZE; ++i)
    b[i] = i - 3;

  /************
   *  Kernel  *
   ************/

  printf("Calling the vvadd kernel...\n");
  // Check the vvadd(c, a, b, len) function for the vvadd kernel, and tasks 1
  // to 4.
  start_timer();
  vvadd(c, a, b, SIZE * SIZE);
  stop_timer();

  /************
   *  Task 5  *
   ************/

  // Consider SIZE = 64, i.e., vectors of length 64*64 = 4096.

  // Q1: How many bytes do you need to load to run the vvadd kernel?

  // Q2: How many bytes do you need to store?

  // Q3: Considering each individual `add` of the vector add as an operation,
  // how many additions do you need to execute? (Ignore bookkeeping
  // instructions).

  /************
   *  Task 6  *
   ************/

  printf("The execution of the vvadd kernel took %d cycles.\n", get_timer());

  // Ara can either load or store 16 bytes per cycle, and is capable of running
  // 4 additions per cycle.

  // Q1: How many cycles do you need to load/store all the data required to run
  // the vvadd kernel?

  // Q2: How many cycles do you need to execute all the vector additions
  // required to run the vvadd kernel?

  // Q3: Is the performance of vvadd is limited by the memory throughput
  // (memory-bound) or by the number of ALUs (compute-bound)? Justify.

  // Q4: Compare the runtime of the vvadd kernel with the ideal runtime (your
  // answer to either Q1 or Q2, depending on what you answered in Q3).

  /**********************
   *  Check the result  *
   **********************/

  printf("Checking results...\n");
  for (int i = 0; i < SIZE * SIZE; ++i)
    if (c[i] != 2 * i - 1) {
      printf("Error! Expected c[%d] = %d, but found %d instead. Aborting.\n", i,
             2 * i - 1, c[i]);
      return;
    }
}

void vvadd(velement_t *c, velement_t *a, velement_t *b, uint64_t len) {
  /************
   *  Task 1  *
   ************/

  // Since we do not have a vectorizing compiler, we will need to do vector
  // register allocation manually. For this vector-vector add, you will need
  // three vector registers, `vA`, `vB`, and `vC`. Choose three vectors from the
  // v0-v31 available for the execution of this kernel.

  // vA = ??
  // vB = ??
  // vC = ??

  /************
   *  Task 2  *
   ************/

  // In intrinsics.h, look for intrinsics that encode a vector load, a vector
  // store, and a vector add between two vectors. Using those intrinsics,
  // implement a vvadd between MAXVL elemets that follows the following
  // pseudocode.

  // set vl to MAXVL
  // load vl elements from a into vA
  // load vl elements from b into vB
  // add vA + vB into vC
  // store vl elements from vC into c

  /************
   *  Task 3  *
   ************/

  // Using the core kernel of task 2, write the stripmining loop that breaks the
  // addition into smaller pieces. There is no need to write
  // assembly---everything can be done with C constructs. Outside this kernel, a
  // function checks whether the result of the addition is correct.

  /************
   *  Task 4  *
   ************/

  // Would your vvadd kernel change if Ara had a MAXVL twice as long? Half as
  // long? What if MAXVL does not divide SIZE*SIZE? (Set SIZE=127, for example.)
}
