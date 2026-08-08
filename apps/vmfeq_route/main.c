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

// Differential reproducer for issue #447 (FP-compare mask-routing desync).
//
// FP comparisons are non-computational FPU ops, but without the vmfpu.sv fix
// they use the arithmetic (sew-based) latency. Under pipeline pressure (a
// preceding FP op still in flight) the mask-routing tag is sampled at the wrong
// cycle, so the comparison result is written to the VRF instead of being routed
// to the mask unit. A subsequent masked FP op then uses a wrong mask.
//
// Sequence (mirrors the report): filler vfadd -> vmfge producing v0 ->
// masked vfadd using v0.t. Self-checks the masked output.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile float src[4]  = {2.0f, 4.0f, 6.0f, 8.0f};
static volatile uint32_t out[4];

int main() {
  uint64_t vl;
  float thresh = 5.0f;

  // mask-undisturbed so inactive elements keep their old (defined) value.
  asm volatile("vsetivli %0, 4, e32, m1, ta, mu" : "=r"(vl));

  asm volatile("vle32.v v6, (%0)" ::"r"(src));
  asm volatile("vfmv.v.f v4,  %0" ::"f"(100.0f)); // base for masked op
  asm volatile("vfmv.v.f v24, %0" ::"f"(7.0f));   // filler operands
  asm volatile("vfmv.v.f v26, %0" ::"f"(3.0f));

  // Heavy, long-latency pressure: keep the FPU pipe busy across the compare.
  asm volatile("vfdiv.vv v24, v24, v26");          // long latency in flight
  asm volatile("vfmacc.vv v24, v24, v26");
  asm volatile("vfmacc.vv v24, v24, v26");
  asm volatile("vmfge.vf v0, v6, %0" ::"f"(thresh)); // mask = src >= 5 -> {0,0,1,1}
  asm volatile("vfadd.vv v4, v6, v6, v0.t");        // v4[i] = mask? 2*src : 100.0
  asm volatile("vse32.v v4, (%0)" ::"r"(out) : "memory");

  // Expected: {100.0, 100.0, 12.0, 16.0}
  uint32_t e0 = 0x42C80000u; // 100.0f
  uint32_t e2 = 0x41400000u; // 12.0f
  uint32_t e3 = 0x41800000u; // 16.0f
  if (out[0] == e0 && out[1] == e0 && out[2] == e2 && out[3] == e3) {
    printf("vmfeq_route: PASS (out[2]=0x%x out[3]=0x%x)\n", out[2], out[3]);
    return 0;
  }
  printf("vmfeq_route: FAIL (out={0x%x,0x%x,0x%x,0x%x})\n",
         out[0], out[1], out[2], out[3]);
  return 1;
}
