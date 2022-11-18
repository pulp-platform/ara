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

#include "kernel/fft.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

#define MAX_NFFT 256

#define DEBUG
#undef DEBUG

#include "support_data.h"

extern unsigned long int NFFT;

extern float twiddle[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
__attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float twiddle_vec_reim[]
    __attribute__((aligned(32 * NR_LANES), section(".l2")));
__attribute__((aligned(32 * NR_LANES), section(".l2")));
extern v2f samples[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern float samples_reim[]
    __attribute__((aligned(32 * NR_LANES), section(".l2")));
v2f samples_copy[MAX_NFFT]
    __attribute__((aligned(32 * NR_LANES), section(".l2")));
v2f samples_vec[MAX_NFFT]
    __attribute__((aligned(32 * NR_LANES), section(".l2")));
extern v2f gold_out[] __attribute__((aligned(32 * NR_LANES), section(".l2")));
signed short SwapTable[MAX_NFFT]
    __attribute__((aligned(32 * NR_LANES), section(".l2")));

// Threshold for FP numbers comparison during the final check
#define THRESHOLD 1

int main() {
  printf("\n");
  printf("=========\n");
  printf("=  FFT  =\n");
  printf("=========\n");
  printf("\n");
  printf("\n");

  printf("\n");
  printf("------------------------------------------------------------\n");
  printf("------------------------------------------------------------\n");
  printf("\n");

  printf("Radix 2 DIF FFT on %d points\n", NFFT);

  int error = 0;

  ////////////////////
  // INITIALIZATION //
  ////////////////////

  // Initialize Twiddle factors
  printf("Initializing Twiddle Factors\n");
  // SetupTwiddlesLUT(twiddle, NFFT, 0);
  //  Initialize Swap Table
  printf("Initializing Swap Table\n");
  SetupR2SwapTable(SwapTable, NFFT);
#ifdef DEBUG
  for (int i = 0; i < NFFT; i += 2)
    printf("%d, ", SwapTable[i]);
  printf("\n");
#endif
  // Initialize Inputs
  printf("Initializing Inputs for DIT\n");
  // SetupInput(In_DIT, NFFT, FFT2_SAMPLE_DYN);
  memcpy((void *)samples_copy, (void *)samples, 2 * NFFT * sizeof(float));
  memcpy((void *)samples_vec, (void *)samples, 2 * NFFT * sizeof(float));

  // Print the input
#ifdef DEBUG
  for (unsigned int i = 0; i < NFFT; ++i) {
    printf("In_DIT[%d] == %f + (%f)j\n", i, samples[i][0], samples[i][1]);
  }
  printf("\n");
#endif

  /////////////
  // DIF FFT //
  /////////////

  int64_t runtime;

#ifndef VCD_DUMP
#ifdef DEBUG
  printf("Intermediate butterfly outputs:\n");
  for (int k = 0; k < (31 - __builtin_clz(NFFT)) + 2; ++k) {
    // Run a partial bmark
    Radix2FFT_DIF_float((float *)samples_copy, twiddle, NFFT, k);
    // Print the partial res
    for (unsigned int i = 0; i < NFFT; ++i) {
      printf("Out_DIF_%d[%d] == %f + (%f)j\n", k, i, samples_copy[i][0],
             samples_copy[i][1]);
    }
    // Reset to initial situation
    memcpy((void *)samples_copy, (void *)samples, 2 * NFFT * sizeof(float));
  }
#else
  start_timer();
  Radix2FFT_DIF_float((float *)samples_copy, twiddle, NFFT, 10);
  stop_timer();
  SwapSamples(samples_copy, SwapTable, NFFT);
#endif

  printf("Initializing Inputs for DIF\n");

  // Performance metrics
  runtime = get_timer();
  printf("The DIF execution took %d cycles.\n", runtime);

  /////////////
  // DIT FFT //
  /////////////

  // Swap samples for DIT FFT
  SwapSamples(samples, SwapTable, NFFT);

#ifdef DEBUG
  printf("Swapping samples for DIT:\n\n");
  for (unsigned int i = 0; i < NFFT; ++i) {
    printf("In_DIT[%d] == %f + (%f)j\n", i, samples[i][0], samples[i][1]);
  }
#endif

  start_timer();
  Radix2FFT_DIT_float((float *)samples, twiddle, NFFT);
  stop_timer();

  // Performance metrics
  runtime = get_timer();
  printf("The DIT execution took %d cycles.\n", runtime);
#endif
  ////////////////////
  // Vector DIF FFT //
  ////////////////////

#ifdef DEBUG
  // Print the twiddles
  for (unsigned int i = 0;
       i < (unsigned int)((NFFT >> 1) * (31 - __builtin_clz(NFFT))); ++i) {
    printf("twiddle_vec[%d] == %f + j%f\n", i, (twiddle_vec[i])[0],
           (twiddle_vec[i])[1]);
  }
#endif

#ifdef DEBUG
  // Print the twiddles
  for (unsigned int i = 0;
       i < (unsigned int)((NFFT >> 1) * (31 - __builtin_clz(NFFT))); ++i) {
    printf("twiddle_re[%d] == %f\n", i, twiddle_reim[i]);
  }
  for (unsigned int i = 0;
       i < (unsigned int)((NFFT >> 1) * (31 - __builtin_clz(NFFT))); ++i) {
    printf("twiddle_im[%d] == %f\n", i,
           twiddle_reim[i + ((NFFT >> 1) * (31 - __builtin_clz(NFFT)))]);
  }
#endif

  // Execute FFT
  start_timer();
  fft_r2dif_vec(samples_reim, samples_reim + NFFT, twiddle_vec_reim,
                twiddle_vec_reim + ((NFFT >> 1) * (31 - __builtin_clz(NFFT))),
                mask_addr_vec, index_ptr, NFFT);
  stop_timer();
  runtime = get_timer();

  float perf = (float)10.0 * NFFT * (31 - __builtin_clz(NFFT)) / runtime;
  float max_perf = 6.0 / 5.0 * NR_LANES * 8.0 / sizeof(float);

  printf("Performance: %f. Max perf: %f. Actual performance is %f%% of max.\n",
         perf, max_perf, 100 * perf / max_perf);

  printf("\n");
  printf("Comparison of the first 5 output numbers:\n");
  printf("\n");

  for (unsigned int i = 0; i < 5; ++i) {
    printf("Out_DIF[%d] == %f + (%f)j\n", i, samples_copy[i][0],
           samples_copy[i][1]);
  }
  printf("\n");
  for (unsigned int i = 0; i < 5; ++i) {
    printf("Out_vec_DIF[%d] == %f + (%f)j\n", i, samples_reim[i],
           samples_reim[i + NFFT]);
  }

  /*
    // DIT results... should be the same as DIF
    for (unsigned int i = 0; i < NFFT; ++i) {
      printf("Out_DIT[%d] == %f + (%f)j\n", i, samples[i][0], samples[i][1]);
    }
  */

  /*
    // Golden output has a weird ordering. Anyway, it's easy to modify the final
    // ordering of our numbers since the idices are fetched from memory
    printf("\n");
    for (unsigned int i = 0; i < NFFT; ++i) {
      printf("gold_out[%d] == %f + (%f)j\n", i , gold_out[i][0],
    gold_out[i][1]);
    }
  */

  // Verify results
  for (unsigned int i = 0; i < NFFT; ++i) {
    if (!similarity_check(samples_reim[i], samples_copy[i][0], THRESHOLD)) {
      printf("Real part error at index %d\n", i);
      error = 1;
    }
    if (!similarity_check(samples_reim[i], samples_copy[i][0], THRESHOLD)) {
      printf("Img part error at index %d\n", i);
      error = 1;
    }
  }

  if (!error)
    printf("\n");
  if (!error)
    printf("Test result: PASS. The output is correct.\n");
  if (!error)
    printf("\n");

  return error;
}
