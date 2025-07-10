// Copyright 2025 ETH Zurich and University of Bologna.
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

#include <stdint.h>
#include <string.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#include "ex/ex.h"

int main() {
  printf("\n");
  printf("Welcome to the Arathon!\n");
  printf("\n");

#if defined (EX_VADD) || defined (SOL_VADD)

  //////////
  // VADD //
  //////////

  printf("\n");
  printf("Write a scalar function to add together (element-wise) two 64-bit vectors with N elements each.\n");
  printf("Then, compare the disassembly of your function against the same function written for RVV.\n");
  printf("\n");

  vadd_scalar();
  vadd_vector();

#elif defined (EX_VADD_STRIPMINE) || defined (SOL_VADD_STRIPMINE)

  ////////////////////
  // VADD STRIPMINE //
  ////////////////////

  printf("\n");
  printf("Write a scalar function to add together (element-wise) two 64-bit vectors with N (larger than your VRF's register capacity) elements each.\n");
  printf("Then, compare the disassembly of your function against the same function written for RVV.\n");
  printf("\n");

  vadd_stripmine_scalar();
  vadd_stripmine_vector();

#elif defined (EX_CHAINING) || defined (SOL_CHAINING)

  //////////////
  // CHAINING //
  //////////////

  printf("\n");
  printf("Write a vld - vadd.v.i - vst, and see how instructions chain.\n");
  printf("\n");

  chaining();

#elif defined (EX_MASK) || defined (SOL_MASK)

  //////////
  // MASK //
  //////////

  printf("\n");
  printf("Write a function that adds two vector together element-wise. For every index, add only when the element of the first vector is greater than the element of the second vector.\n");
  printf("\n");

  mask_scalar();
  mask_vector();

#elif defined (EX_VSETVLI) || defined (SOL_VSETVLI)

  /////////////
  // VSETVLI //
  /////////////

  printf("\n");
  printf("Play around with the vsetvli configuration instruction.\n");
  printf("\n");

  vsetvli();

#elif defined (EX_RESHUFFLE) || defined (SOL_RESHUFFLE)

  ///////////////
  // RESHUFFLE //
  ///////////////

  printf("\n");
  printf("Have a look at how data is reshuffled in Ara. Try to trigger a reshuffle!\n");
  printf("\n");

  reshuffle();

#elif defined (EX_VRF) || defined (SOL_VRF)

  /////////
  // VRF //
  /////////

  printf("\n");
  printf("Load some data, perform some additions, and observe how the data layout changes from the AXI bus of the load unit to the in-lane shuffled encoding!\n");
  printf("\n");

  vrf();

#elif defined (EX_SIMD) || defined (SOL_SIMD)

  //////////
  // SIMD //
  //////////

  printf("\n");
  printf("Try to perform an addition in SIMD on 64-bit and 8-bit!\n");
  printf("\n");

  simd();

#elif defined (EX_SCRATCH)

  /////////////
  // SCRATCH //
  /////////////

  printf("\n");
  printf("This is a space for yourself.\n");
  printf("\n");

  scratch();

#else
#error                                                                         \
    "You should define at least one of the exercises. Please run: 'make -C apps bin/arathon ENV_DEFINES=-DEX_${ex_name_in_capital_letters}'. For example: 'make -C apps bin/arathon ENV_DEFINES=-DEX_VADD'."
#endif

  return 0;
}
