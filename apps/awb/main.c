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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"

#include "kernel/awb.h"

extern const uint64_t W, H;
extern const uint8_t i_s[] __attribute__((aligned(4 * NR_LANES)));
extern const uint8_t i_v[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("=========\n");
  printf("=  AWB  =\n");
  printf("=========\n");
  printf("\n");
  printf("\n");

  printf("AWB with Gray-World HP on a 3-channels image. W = %lu, H = %lu.\n", W, H);
  printf("Total number of pixels in each channel = %lu\n", W * H);

  // Call the main kernel, and measure cycles
  printf("Executing the scalar program.\n");
  start_timer();
  gw_awb_s(i_s, W*H);
  stop_timer();
  // Performance metrics
  int64_t runtime_s = get_timer();
  printf("The scalar execution took %d cycles.\n", runtime_s);

  // Call the main kernel, and measure cycles
  printf("Executing the vector program.\n");
  start_timer();
  gw_awb_v(i_v, W*H);
  stop_timer();
  // Performance metrics
  int64_t runtime_v = get_timer();
  printf("The vector execution took %d cycles.\n", runtime_v);

  // Verify correctness
  printf("Verifying result...\n");
  for (uint64_t k = 0; k < 3*W*H; ++k) {
    if (i_v[k] != i_s[k]) {
      printf("Error at index %lu: i_v[%lu] == %u != %u == i_s[%lu]\n", k, k, i_v[k], i_s[k], k);
      printf("FAIL!\n");
      return k;
    }
  }

  printf("SUCCESS!");

  return 0;
}
