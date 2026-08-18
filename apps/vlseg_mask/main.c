// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential probe for issue #462 (masked vlseg2e16.v ignores an
// active mask bit and leaves that lane undisturbed). vl=6, e16, only mask bit 5
// active. v13/v14 preinit to 0x1111/0x2222. Lane 5 source = (0x1005, 0x2005).
// Only lane 5 should be loaded; all other lanes stay undisturbed.
// Static .data init + fence; read v13/v14 back with vse16.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// 6 segments x 2 fields, element-major: seg i -> {0x1000+i, 0x2000+i}.
static volatile uint16_t seg_data[12] = {0x1000, 0x2000, 0x1001, 0x2001,
                                         0x1002, 0x2002, 0x1003, 0x2003,
                                         0x1004, 0x2004, 0x1005, 0x2005};
// Mask: only bit 5 active (0x20).
static volatile uint8_t mask_data[1] = {0x20};
static volatile uint16_t out13[6], out14[6];

int main() {
  asm volatile("fence" ::: "memory");
  asm volatile("vsetivli x0, 6, e16, m1, ta, ma");
  asm volatile("vmv.v.x v13, %0" ::"r"((uint64_t)0x1111));
  asm volatile("vmv.v.x v14, %0" ::"r"((uint64_t)0x2222));
  asm volatile("vlm.v v0, (%0)" ::"r"(mask_data));
  asm volatile("vlseg2e16.v v13, (%0), v0.t" ::"r"(seg_data));
  asm volatile("vse16.v v13, (%0)" ::"r"(out13) : "memory");
  asm volatile("vse16.v v14, (%0)" ::"r"(out14) : "memory");
  asm volatile("fence" ::: "memory");

  // Expected (Spike): lane 5 loaded, all others undisturbed.
  //   out13 = {0x1111 x5, 0x1005}; out14 = {0x2222 x5, 0x2005}
  printf("c0=%d c5=%d d0=%d d5=%d\n", (int)out13[0], (int)out13[5],
         (int)out14[0], (int)out14[5]);
  return 0;
}
