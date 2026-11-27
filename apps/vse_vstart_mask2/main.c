// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Store-side validation for the #462 fix: masked vse16.v with vstart=4, vl=5,
// mask bit 4 active. Only element 4 should be stored; the rest of the output
// buffer keeps its preset sentinel. Mirrors the load probe on the store path.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint16_t out[6] = {0x9990, 0x9991, 0x9992, 0x9993, 0x9994, 0x9995};
static volatile uint8_t mask_data[1] = {0x10}; // bit 4 active

int main() {
  asm volatile("fence" ::: "memory");
  asm volatile("vsetivli x0, 5, e16, m1, ta, ma");
  asm volatile("vmv.v.x v13, %0" ::"r"((uint64_t)0x2000)); // v13[i] = 0x2000
  asm volatile("vlm.v v0, (%0)" ::"r"(mask_data));
  asm volatile("csrw vstart, 4");
  asm volatile("vse16.v v13, (%0), v0.t" ::"r"(out) : "memory");
  asm volatile("fence" ::: "memory");

  // Expected: out[4] = 0x2000 = 8192 (stored); out[0..3] keep sentinels
  // (below vstart), out[5] = 0x9995 (beyond vl).
  for (int i = 0; i < 6; i++) printf("f%d=%d\n", i, (int)out[i]);
  return 0;
}
