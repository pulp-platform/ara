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

inline void enable_rvv() {
  asm volatile ("li t0, %0" :: "i"(MSTATUS_VS));
  asm volatile ("csrs mstatus, t0" );
}

#endif
