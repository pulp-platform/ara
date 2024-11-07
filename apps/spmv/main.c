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

// Author: Chi Zhang, ETH Zurich <chizhang@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "kernel/spmv.h"
#include "runtime.h"
#include "util.h"

#ifdef SPIKE
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

extern uint64_t R;
extern uint64_t C;
extern uint64_t NZ;

extern int32_t CSR_PROW[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int32_t CSR_INDEX[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double CSR_DATA[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double CSR_IN_VECTOR[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern double CSR_OUT_VECTOR[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  SpMV  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  double density = ((double)NZ) / (R * C);
  double nz_per_row = ((double)NZ) / R;

  printf("\n");
  printf(
      "-------------------------------------------------------------------\n");
  printf(
      "Calculating a (%d x %d) x %d sparse matrix vector multiplication...\n",
      R, C, C);
  printf("CSR format with %d nozeros: %f density, %f nonzeros per row \n", NZ,
         density, nz_per_row);
  printf(
      "-------------------------------------------------------------------\n");
  printf("\n");

  printf("calculating ... \n");
  start_timer();
  spmv_csr_idx32(R, CSR_PROW, CSR_INDEX, CSR_DATA, CSR_IN_VECTOR,
                 CSR_OUT_VECTOR);
  stop_timer();

  // Metrics
  int64_t runtime = get_timer();
  float performance = 2.0 * NZ / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES);

  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f FLOP/cycle (%f%% utilization) at %d lanes.\n",
         performance, utilization, NR_LANES);

  printf("Verifying ...\n");
  if (spmv_verify(R, CSR_PROW, CSR_INDEX, CSR_DATA, CSR_IN_VECTOR,
                  CSR_OUT_VECTOR)) {
    return 1;
  } else {
    printf("Passed.\n");
  }
  return 0;
}
