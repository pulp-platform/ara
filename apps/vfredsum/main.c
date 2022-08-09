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
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "kernel/vfredsum.h"
#include "printf.h"
#include "runtime.h"

// Size of the largest possible vector register in Bytes (LMUL == 8)
#define MAX_BYTE_LMUL8 VLEN

uint8_t buf[MAX_BYTE_LMUL8] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("==============\n");
  printf("=  VFREDSUM  =\n");
  printf("==============\n");
  printf("\n");
  printf("\n");

  printf("---------------------------------------------------------------------"
         "-----\n");
  printf("FP reduction benchmark, meant for manual measurements and checks.\n");
  printf("For precise measurements, look at the waves directly.\n");
  printf("This benchmark sets the conditions for stalled and unstalled "
         "execution.\n");
  printf("---------------------------------------------------------------------"
         "-----\n\n");

  size_t avl;

  // Divider for #bytes <-> #elements conversion
  uint8_t div;

  printf("Unstalled FP reduction:\n");

  div = 2;
  avl = MAX_BYTE_LMUL8 / div;
  printf("16b vfred on %lu elements\n", avl);
  vfredsum_16((_Float16 *)buf, avl, 0, 0);
  vfredsum_16((_Float16 *)buf, avl, 1, 0);

  div = 4;
  avl = MAX_BYTE_LMUL8 / div;
  printf("32b vfred on %lu elements\n", avl);
  vfredsum_32((float *)buf, avl, 0, 0);
  vfredsum_32((float *)buf, avl, 1, 0);

  div = 8;
  avl = MAX_BYTE_LMUL8 / div;
  printf("64b vfred on %lu elements\n", avl);
  vfredsum_64((double *)buf, avl, 0, 0);
  vfredsum_64((double *)buf, avl, 1, 0);

  printf("FP reduction chained with load:\n");

  div = 2;
  avl = MAX_BYTE_LMUL8 / div;
  printf("16b vfred on %lu elements\n", avl);
  vfredsum_16((_Float16 *)buf, avl, 0, 1);
  vfredsum_16((_Float16 *)buf, avl, 1, 1);

  div = 4;
  avl = MAX_BYTE_LMUL8 / div;
  printf("32b vfred on %lu elements\n", avl);
  vfredsum_32((float *)buf, avl, 0, 1);
  vfredsum_32((float *)buf, avl, 1, 1);

  div = 8;
  avl = MAX_BYTE_LMUL8 / div;
  printf("64b vfred on %lu elements\n", avl);
  vfredsum_64((double *)buf, avl, 0, 1);
  vfredsum_64((double *)buf, avl, 1, 1);

  return 0;
}
