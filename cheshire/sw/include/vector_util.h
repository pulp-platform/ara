// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti <mperotti@ethz.ch>
//
// Custom vector util

#ifndef __VECTOR_UTIL_H__
#define __VECTOR_UTIL_H__

// Compile with version(GCC) >= 13
#include <riscv_vector.h>
#include "encoding.h"

#define FABS(x) ((x < 0) ? -x : x)

unsigned int timer;

// Return the current value of the cycle counter
int64_t get_cycle_count() {
  int64_t cycle_count;
  // The fence is needed to be sure that Ara is idle, and it is not performing
  // the last vector stores when we read mcycle with stop_timer()
  asm volatile("fence; csrr %[cycle_count], cycle" : [cycle_count] "=r"(cycle_count));
  return cycle_count;
};

// Start and stop the counter
void start_timer() { timer = -get_cycle_count(); }
void stop_timer() { timer += get_cycle_count(); }

// Get the value of the timer
int64_t get_timer() { return timer; }

#ifndef _ENABLE_RVV_
#define _ENABLE_RVV_
inline void enable_rvv() {
  asm volatile ("li t0, %0" :: "i"(MSTATUS_VS));
  asm volatile ("csrs mstatus, t0" );
}
#endif

inline int similarity_check(double a, double b, double threshold) {
  double diff = a - b;
  if (FABS(diff) > threshold)
    return 0;
  else
    return 1;
}

inline int similarity_check_32b(float a, float b, float threshold) {
  float diff = a - b;
  if (FABS(diff) > threshold)
    return 0;
  else
    return 1;
}

#endif
