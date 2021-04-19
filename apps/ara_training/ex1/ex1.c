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

#include "ex1.h"

// Vector length, vector type, and vsetvli

void ex1(void) {
  uint64_t vl = 0;

  // Trying to set the vl to 1...
  printf("Trying to set the vl to 1...\n");
  vl = __vsetvl(1, EW64);
  printf("The new vl is %d.\n", vl);

  // Trying to set the vl to 10...
  printf("Trying to set the vl to 10...\n");
  vl = __vsetvl(10, EW64);
  printf("The new vl is %d.\n", vl);

  /************
   *  Task 1  *
   ************/

  // Analyze the definition of the __vsetvl function, in the intrinsics.h
  // header. What does it do?

  /************
   *  Task 2  *
   ************/

  // How can you reliably determine the value of MAXVL, on any vector machine?
  printf("Determining the maximum vl...\n");
  vl = 0; // TODO
  printf("The maximum vl is %d.\n", vl);

  /************
   *  Task 3  *
   ************/

  // Does the value of MAXVL change depending on the standard element width?
  // Try it out. Do your results make sense?

  printf("For SEW = 8,  the maximum vl is %d.\n", vl);
  printf("For SEW = 16, the maximum vl is %d.\n", vl);
  printf("For SEW = 32, the maximum vl is %d.\n", vl);
  printf("For SEW = 64, the maximum vl is %d.\n", vl);
}
