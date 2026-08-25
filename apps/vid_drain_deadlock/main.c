// Copyright 2026 ETH Zurich and University of Bologna.
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

// Differential reproducer for issue #448 (mask unit ALU-operand drain on vid.v).
//
// vid.v does not consume an ALU operand, but lanes can still drive ALU data into
// the mask-unit operand path. If it is never acknowledged, the stale operand
// state corrupts the following mask flow. With the fix in masku_operands.sv
// (drain ALU operands during VID) the masked merge is correct; without it the
// merge under v0 is dropped (observed here as a wrong element-2 result; the same
// drain bug can also deadlock under different timing).
//
// Mirrors the reported sequence (vid.v -> mask compare -> masked merge) and
// self-checks: vfmerge must write 9.0f (0x41100000) into masked element 2.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint32_t mask_out[1];
static volatile uint32_t out[4];

int main() {
  uint64_t vl;
  float f = 9.0f;

  asm volatile("vsetivli %0, 4, e32, m1, ta, ma" : "=r"(vl));
  asm volatile("vmv.v.i v8, 7");                 // stand-in for a vle32.v load
  asm volatile("vid.v   v9");                    // v9 = {0,1,2,3}
  asm volatile("vmseq.vi v0, v9, 2");            // mask: element 2 set
  asm volatile("vsm.v   v0, (%0)" ::"r"(mask_out) : "memory");
  asm volatile("vfmerge.vfm v8, v8, %0, v0" ::"f"(f)); // merge under mask
  asm volatile("vse32.v v8, (%0)" ::"r"(out) : "memory");

  // Masked merge must write 9.0f (0x41100000) into element 2; others stay 7.
  uint32_t expected = 0x41100000u; // 9.0f
  if (out[2] == expected && out[0] == 7 && out[1] == 7 && out[3] == 7) {
    printf("vid_drain_deadlock: PASS (out[2]=0x%x)\n", out[2]);
    return 0;
  }
  printf("vid_drain_deadlock: FAIL (out={%u,%u,0x%x,%u}, expected out[2]=0x%x)\n",
         out[0], out[1], out[2], out[3], expected);
  return 1;
}
