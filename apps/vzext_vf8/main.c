// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential probe for issue #452 (vzext.vf8 reads the wrong
// source width). v28[0] (e16) = 0xa04f; vzext.vf8 to e64 should zero-extend the
// 8-bit sub-elements: v14[0]=0x4f, v14[1]=0xa0. Register-only (no race).

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

int main() {
  uint64_t x20, x21;
  uint64_t v = 0xa04f;

  asm volatile("vsetivli x8, 1, e16, mf4, ta, ma");
  asm volatile("vmv.s.x v28, %0" ::"r"(v));
  asm volatile("vsetivli x8, 27, e64, m1, ta, ma");
  asm volatile("vzext.vf8 v14, v28");
  asm volatile("vmv.x.s %0, v14" : "=r"(x20));      // expect 0x4f = 79
  asm volatile("vslidedown.vi v15, v14, 1");
  asm volatile("vmv.x.s %0, v15" : "=r"(x21));      // expect 0xa0 = 160

  printf("x20=%d x21=%d\n", (int)x20, (int)x21);
  return 0;
}
