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
// Author: Matteo Perotti

#include <stdint.h>
#include <string.h>

#include "kernel/exp.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

extern size_t N_f64;
extern double exponents_f64[] __attribute__((aligned(4 * NR_LANES)));
extern double results_f64[] __attribute__((aligned(4 * NR_LANES)));
extern double gold_results_f64[] __attribute__((aligned(4 * NR_LANES)));

extern size_t N_f32;
extern float exponents_f32[] __attribute__((aligned(4 * NR_LANES)));
extern float results_f32[] __attribute__((aligned(4 * NR_LANES)));
extern float gold_results_f32[] __attribute__((aligned(4 * NR_LANES)));

#define THRESHOLD 1

#define CHECK

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  FEXP  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  int error = 0;
  int64_t runtime;

  printf("Executing exponential on %d 64-bit data...\n", N_f64);

  start_timer();
  exp_1xf64_bmark(exponents_f64, results_f64, N_f64);
  stop_timer();

  runtime = get_timer();
  printf("The execution took %d cycles.\n", runtime);

  printf("Executing exponential on %d 32-bit data...\n", N_f32);
  start_timer();
  exp_2xf32_bmark(exponents_f32, results_f32, N_f32);
  stop_timer();

  runtime = get_timer();
  printf("The execution took %d cycles.\n", runtime);

#ifdef CHECK
  printf("Checking results:\n");

  for (uint64_t i = 0; i < N_f64; ++i) {
    if (!similarity_check(results_f64[i], gold_results_f64[i], THRESHOLD)) {
      error = 1;
      printf("64-bit error at index %d. %f != %f\n", i, results_f64[i],
             gold_results_f64[i]);
    }
  }
  for (uint64_t i = 0; i < N_f32; ++i) {
    if (!similarity_check(results_f32[i], gold_results_f32[i], THRESHOLD)) {
      error = 1;
      printf("32-bit error at index %d. %f != %f\n", i, results_f32[i],
             gold_results_f32[i]);
    }
  }
  if (!error)
    printf("Test result: PASS. No errors found.\n");
#endif

  return error;
}
