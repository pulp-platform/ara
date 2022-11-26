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

// Include <riscv_vector.h> to use vector intrinsics
// Documentation: https://github.com/riscv/rvv-intrinsic-doc
// Compiler support:
// https://github.com/riscv/riscv-gnu-toolchain/tree/rvv-intrinsic

#include "kernel/dropout.h"

extern const unsigned int N;
extern const float SCALE;
extern const float I[] __attribute__((aligned(4 * NR_LANES)));
extern const uint8_t SEL[] __attribute__((aligned(4 * NR_LANES)));
extern float o[] __attribute__((aligned(4 * NR_LANES)));
extern float o_gold[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("=============\n");
  printf("=  DROPOUT  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  printf("Running Dropout with %d elements.\n", N);

  // Call the main kernel, and measure cycles
  start_timer();
  dropout_vec(N, I, SCALE, SEL, o);
  stop_timer();
  // Performance metrics
  int64_t runtime = get_timer();

  // Only count effective SPFLOP/cycle
  float performance = (float)N / runtime;
  float arith_intensity = (float)1 / (8.0 + 1.0 / 8.0);
  float bw = (float)4 * NR_LANES;
  float max_perf = (float)bw * arith_intensity;
  float utilization = (float)100 * performance / NR_LANES;
  printf("The execution took %d cycles.\n", runtime);
  printf("Max performance.\n", runtime);
  printf("The performance is %f SPFLOP/cycle. Max achievable is %f "
         "SPFLOP/cycle. (%f%% on max). With %f%% FPU utilization.\n",
         performance, max_perf, 100 * performance / max_perf, utilization);

  // Verify correctness
  dropout_gold(N, I, SCALE, SEL, o_gold);

  for (unsigned int k = 0; k < N; ++k) {
    if (o[k] != o_gold[k]) {
      printf("Error: o[%d] = %f != %f\n", k, o[k], o_gold[k]);
      return k ? k : -1;
    }
  }
  printf("Passed.\n");

  return 0;
}
