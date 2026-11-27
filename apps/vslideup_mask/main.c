// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential probe for issue #459 (masked vslideup.vx with a
// large stride uses the wrong mask window). vl=300 (e8), slide by 256, mask
// active only for elements 256..299. Static .data init + fence.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// Mask bits 256..299 active: bytes 32..36 = 0xFF (bits 256..295), byte 37 = 0x0F
// (bits 296..299). All other bits inactive.
static volatile uint8_t mask_data[40] = {[32 ... 36] = 0xFF, [37] = 0x0F};
static volatile uint8_t out[320];

int main() {
  uint64_t vl;
  asm volatile("vsetvli %0, %1, e8, m1, ta, ma" : "=r"(vl) : "r"((uint64_t)300));
  asm volatile("vmv.v.x v1, %0" ::"r"(0xaaUL)); // background 0xaa
  asm volatile("vid.v   v2");                   // v2[i] = i (mod 256)
  asm volatile("vlm.v   v0, (%0)" ::"r"(mask_data));
  asm volatile("vslideup.vx v1, v2, %0, v0.t" ::"r"((uint64_t)256));
  asm volatile("vse8.v v1, (%0)" ::"r"(out) : "memory");
  asm volatile("fence" ::: "memory");

  // Expected: e255 stays 0xaa(170); e256=src0=0; e257=src1=1; e299=src43=43
  printf("o255=%d o256=%d o257=%d o299=%d\n",
         (int)out[255], (int)out[256], (int)out[257], (int)out[299]);
  return 0;
}
