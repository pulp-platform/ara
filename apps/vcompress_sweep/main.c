// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Self-checking regression test for issue #450 (vcompress hang). Covers the
// reported trailing-unselected case plus last-selected, all-selected, a
// multi-word vl, and the all-unselected (compress-to-0) edge. Built from vector
// ops only. Expected values verified against Spike. Returns nonzero on mismatch;
// a hang is caught by the testbench timeout.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint32_t out[24];

static int check4(const char *tag, int e0, int e1, int e2, int e3) {
  if (out[0] == (uint32_t)e0 && out[1] == (uint32_t)e1 &&
      out[2] == (uint32_t)e2 && out[3] == (uint32_t)e3)
    return 0;
  printf("%s FAIL: {%d,%d,%d,%d}\n", tag, (int)out[0], (int)out[1], (int)out[2], (int)out[3]);
  return 1;
}

int main() {
  uint64_t vl;
  int err = 0;

  // Case A: even selected -> last element unselected (the reported bug). {0,2,4,6}
  asm volatile("vsetivli %0, 8, e32, m1, ta, ma" : "=r"(vl));
  asm volatile("vid.v v2");
  asm volatile("vand.vi  v3, v2, 1");
  asm volatile("vmseq.vi v6, v3, 0");
  asm volatile("vcompress.vm v4, v2, v6");
  asm volatile("vse32.v v4, (%0)" ::"r"(out) : "memory");
  err += check4("A", 0, 2, 4, 6);

  // Case B: odd selected -> last element selected (regression guard). {1,3,5,7}
  asm volatile("vid.v v2");
  asm volatile("vand.vi  v3, v2, 1");
  asm volatile("vmsne.vi v6, v3, 0");
  asm volatile("vcompress.vm v4, v2, v6");
  asm volatile("vse32.v v4, (%0)" ::"r"(out) : "memory");
  err += check4("B", 1, 3, 5, 7);

  // Case C: all selected -> identity {0,1,2,3}
  asm volatile("vid.v v2");
  asm volatile("vmset.m v6");
  asm volatile("vcompress.vm v4, v2, v6");
  asm volatile("vse32.v v4, (%0)" ::"r"(out) : "memory");
  err += check4("C", 0, 1, 2, 3);

  // Case E: multi-word vl=20, even selected -> {0,2,...,18}; check out[0,1,9]
  asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"((uint64_t)20));
  asm volatile("vid.v v2");
  asm volatile("vand.vi  v3, v2, 1");
  asm volatile("vmseq.vi v6, v3, 0");
  asm volatile("vcompress.vm v4, v2, v6");
  asm volatile("vse32.v v4, (%0)" ::"r"(out) : "memory");
  if (!(out[0] == 0 && out[1] == 2 && out[9] == 18)) {
    printf("E FAIL: out[0]=%d out[1]=%d out[9]=%d\n", (int)out[0], (int)out[1], (int)out[9]);
    err++;
  }

  // Case D: none selected (vl=8) -> compress to length 0; must complete.
  asm volatile("vsetivli %0, 8, e32, m1, ta, ma" : "=r"(vl));
  asm volatile("vid.v v2");
  asm volatile("vmclr.m v6");
  asm volatile("vcompress.vm v4, v2, v6");

  if (err == 0)
    printf("vcompress_sweep: PASS\n");
  else
    printf("vcompress_sweep: FAIL (%d)\n", err);
  return err;
}
