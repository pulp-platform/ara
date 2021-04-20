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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"

#define LEN    64
#define OFFSET 65
#define SCALAR -72

int64_t i[LEN];
int64_t scalar = SCALAR;
int64_t o;

int64_t vredsum(int64_t *i, int64_t *scalar, int64_t *o, uint64_t len);

// Initialize the vector to be reduced with len sequential numbers, starting from offset
void init_vector(int64_t *vec, uint64_t len, int64_t offset) {
  for (uint64_t i = 0; i < len; i++) {
    vec[i] = i + offset;
  }
}

// Return 0 if the reduced result is correct
int64_t golden_vredsum(int64_t scalar, int64_t offset, uint64_t len) {
  return scalar + ((((offset + len - 1) * (offset + len)) - ((offset - 1) * offset)) / 2);
}

int main() {
  printf("\n");
  printf("===============\n");
  printf("=   VREDSUM   =\n");
  printf("===============\n");
  printf("\n");
  printf("\n");

  // Initialize the vector
  printf("Initializing vector...\n");
  init_vector(i, LEN, OFFSET);

  // Vectors are initialized --> Start calculating and get the metrics
  printf("Calculating reduction...\n");
  int64_t runtime = vredsum(i, &scalar, &o, LEN);
  printf("The execution took %d cycles.\n", runtime);

  // Verify the result
  printf("Verifying result...\n");
  int64_t golden_result = golden_vredsum(scalar, OFFSET, LEN);
  if (golden_result != o) {
    printf("Error: you obtained %d, instead of %d\n", o, golden_result);
    return -1;
  } else {
    printf("Passed.\n");
  }

  return 0;
}

// Perform a vredsum
int64_t vredsum(int64_t *i, int64_t *scalar, int64_t *o, uint64_t len) {

  uint64_t leftover_len;
  uint64_t exp = 0;
  uint64_t temp_len = len;

  // Load the scalar
  asm volatile("vsetvli zero, %0, e64, m1" ::"r"(1));
  asm volatile("vle64.v v16, (%0);" ::"r"(scalar));
  // Load the vector
  asm volatile("vsetvli zero, %0, e64, m1" ::"r"(len));
  asm volatile("vle64.v v8, (%0);" ::"r"(i));

  // Check if len is a power of 2
  if (len % 2) {
    // len is not a power of 2
    // Find the closest power of 2 lower than len
    while (temp_len >>= 1) ++exp;
    // Find the leftover length
    leftover_len = len - (1 << (exp - 1));

    // Start the timer
    // TODO: check if the previous operations can be easily done in HW, otherwise we must count them
    start_timer();

    asm volatile("vslidedown.vx v0, v8,  %0" ::"r"(leftover_len));
    asm volatile("vsetvli zero, %0, e64, m1" ::"r"(len));
    asm volatile("vadd.vv v8, v8, v0");

    len -= leftover_len;

    while (len) {
      asm volatile("vslidedown.vx v0, v8,  %0" ::"r"(len));
      len >>= 1;
      asm volatile("vsetvli zero, %0, e64, m1" ::"r"(len));
      asm volatile("vadd.vv v8, v8, v0");
    }
  } else {
    // len is a power of 2
    // Start the timer
    start_timer();

    while (len > 1) {
      len >>= 1;
      asm volatile("vslidedown.vx v0, v8,  %0" ::"r"(len));
      asm volatile("vsetvli zero, %0, e64, m1" ::"r"(len));
      asm volatile("vadd.vv v8, v8, v0");
    }
  }
  asm volatile("vsetvli zero, %0, e64, m1" ::"r"(1));
  // Add the scalar element
  asm volatile("vadd.vv v0, v8, v16");

  // Stop the timer
  stop_timer();

  // Store the data back into memory (1 element only)
  asm volatile("vse64.v v0, (%0);" ::"r"(o));

  return get_timer();
}
