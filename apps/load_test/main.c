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

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef SPIKE
#include "printf.h"
#include "runtime.h"
#endif

#define N 64

// Define Matrix dimensions:
// o = i ° f, with i=[MxN], f=[FxF], o=[MxN]
// The filter is a square matrix, and F is odd

// Matrices defined in data.S
extern int32_t originalVec[] __attribute__((aligned(32)));
extern int32_t checkArr0[] __attribute__((aligned(32)));
extern int32_t checkArr1[] __attribute__((aligned(32)));
extern int32_t checkArr2[] __attribute__((aligned(32)));
extern int32_t checkArr3[] __attribute__((aligned(32)));

int64_t segment_size = 4;

int32_t arr0[64] __attribute__((aligned(32)));
int32_t arr1[64] __attribute__((aligned(32)));
int32_t arr2[64] __attribute__((aligned(32)));
int32_t arr3[64] __attribute__((aligned(32)));

volatile int64_t ind;

int main() {

  int64_t vecSize = N;

  asm volatile("vsetvli zero, %0, e32, m1, ta, ma" ::"r"(vecSize));

  //  asm volatile("vle32.v v0, (%0)" :: "r"(originalVec));
  asm volatile("vlseg4e32.v v0, (%0)" ::"r"(originalVec));

  for (ind = 0; ind < 1000; ind++)
    ;

  asm volatile("vse32.v v0, (%0)" ::"r"(arr0));
  asm volatile("vse32.v v1, (%0)" ::"r"(arr1));
  asm volatile("vse32.v v2, (%0)" ::"r"(arr2));
  asm volatile("vse32.v v3, (%0)" ::"r"(arr3));

  for (int i = 0; i < N; i++) {
    if (arr0[i] != checkArr0[i])
      printf("Error at %d in arr0\n\tExpected = %d\n\tActual = %d\n", i,
             checkArr0[i], arr0[i]);
  }

  for (int i = 0; i < N; i++) {
    if (arr1[i] != checkArr1[i])
      printf("Error at %d in arr1\n", i);
  }

  for (int i = 0; i < N; i++) {
    if (arr2[i] != checkArr2[i])
      printf("Error at %d in arr2\n", i);
  }
  for (int i = 0; i < N; i++) {
    if (arr3[i] != checkArr3[i])
      printf("Error at %d in arr3\n", i);
  }

  return 0;
}
