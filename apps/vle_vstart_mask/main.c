// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Isolation probe for issue #462: a masked vle16.v with an explicit
// vstart=4 (>= NrLanes), vl=5, mask bit 4 active. This mimics the segment
// micro-op (vstart=s, vl=s+1, masked). Element 4 should be loaded; elements
// 0..3 stay undisturbed (below vstart). If Ara drops element 4, the bug is in
// the masked-load + vstart path, independent of segments.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint16_t in_data[6] = {0x1000, 0x1001, 0x1002,
                                       0x1003, 0x1004, 0x1005};
static volatile uint8_t mask_data[1] = {0x10}; // bit 4 active
static volatile uint16_t out[6];

int main() {
  asm volatile("fence" ::: "memory");
  asm volatile("vsetivli x0, 5, e16, m1, ta, ma");
  asm volatile("vmv.v.x v13, %0" ::"r"((uint64_t)0x1111));
  asm volatile("vlm.v v0, (%0)" ::"r"(mask_data));
  asm volatile("csrw vstart, 4");
  asm volatile("vle16.v v13, (%0), v0.t" ::"r"(in_data));
  asm volatile("vse16.v v13, (%0)" ::"r"(out) : "memory");
  asm volatile("fence" ::: "memory");

  // Expected: out[4] = 0x1004 = 4100; out[0..3] = 0x1111 = 4369 (below vstart)
  for (int i = 0; i < 6; i++) printf("e%d=%d\n", i, (int)out[i]);
  return 0;
}
