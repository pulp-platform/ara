// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti <mperotti@ethz.ch>
//
// fmatmul wrapper for Cheshire

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "params.h"
#include "util.h"

#include "cheshire_util.h"
#include "vector_util.h"

#include "fmatmul.c.h"

#ifndef _MM_SIZE_
#define _MM_SIZE_ 32
#endif

// Define Matrix dimensions:
// C = AB with A=[MxN], B=[NxP], C=[MxP]
uint64_t M = _MM_SIZE_;
uint64_t N = _MM_SIZE_;
uint64_t P = _MM_SIZE_;

// Max matrix size: 256x256
double a[_MM_SIZE_*_MM_SIZE_] __attribute__((aligned(32 * NR_LANES)));
double b[_MM_SIZE_*_MM_SIZE_] __attribute__((aligned(32 * NR_LANES)));
double c[_MM_SIZE_*_MM_SIZE_] __attribute__((aligned(32 * NR_LANES)));
// Gold results
double g[_MM_SIZE_*_MM_SIZE_] __attribute__((aligned(32 * NR_LANES)));

#define THRESHOLD 0.001

// Verify the matrix
int verify_matrix(double *result, double *gold, size_t R, size_t C,
                  double threshold) {
  for (uint64_t i = 0; i < R; ++i) {
    for (uint64_t j = 0; j < C; ++j) {
      int idx = i * C + j;
      if (!similarity_check(result[idx], gold[idx], threshold)) {
        return (i + j) == 0 ? -1 : idx;
      }
    }
  }
  return 0;
}

int main() {
  printf("fmatmul kernel:\r\n");

  cheshire_start();
  enable_rvv();

  unsigned int s = M;

  // Initialize matrices
  for (unsigned int i = 0; i < s; ++i) {
    for (unsigned int k = 0; k < s; ++k) {
      a[k + i*s] = (double) (i + k);
    }
  }
  for (unsigned int k = 0; k < s; ++k) {
    for (unsigned int j = 0; j < s; ++j) {
      b[j + k*s] = (double) (k - j);
    }
  }

  // Run scalar check
  printf("Calculating fmatmul on scalar core...\r\n");
  for (unsigned int i = 0; i < s; ++i) {
    for (unsigned int j = 0; j < s; ++j) {
      double sum = 0;
      for (unsigned int k = 0; k < s; ++k) {
        sum += a[k + i * s] * b[j + k * s];
      }
      g[j + i * s] = sum;
    }
  }

  // Run vector kernel
  printf("Calculating fmatmul on vector core...\r\n");
  start_timer();
  fmatmul(c, a, b, s, s, s);
  stop_timer();

  // Metrics
  int64_t runtime = get_timer();
  float performance = 2.0 * s * s * s / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES);

  printf("The execution took %d cycles.\r\n", runtime);
  printf("The performance is %f FLOP/cycle (%f%% utilization).\r\n",
         performance, utilization);

  // Verify the result only for s == M (to keep it simple)
  if (s == M) {
    printf("Verifying result...\r\n");
    int error = verify_matrix(c, g, s, s, THRESHOLD);
    if (error != 0) {
      printf("Error code %d\r\n", error);
      printf("c[%d]=%f != %f\r\n", error, c[error], g[error]);
      cheshire_end();
      return error;
    } else {
      printf("Passed.\r\n");
    }
  }


  cheshire_end();

  return 0;
}
