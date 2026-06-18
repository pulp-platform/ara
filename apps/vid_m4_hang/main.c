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

// Probe for issue #437 (vid.v hang). Mirrors the reported sequence: a widening
// multiply followed by vid.v at LMUL=4 hangs a buggy Ara. Reaching the print
// means no deadlock. This shares the mask-unit VID path with #448.

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
  uint64_t vl, res;

  asm volatile("vsetvli %0, zero, e16, m4, ta, ma" : "=r"(vl));
  asm volatile("vmv.v.i v0, 2");
  asm volatile("vwmul.vx v8, v0, %0" ::"r"(0L)); // widening -> v8 group (e32, m8)
  asm volatile("vid.v   v0");                    // <- reported hang point
  asm volatile("vadd.vi v0, v0, 1");
  asm volatile("vmv.x.s %0, v0" : "=r"(res));    // v0 = {0,1,2,...}+1 -> res = 1

  printf("vid_m4=%d\n", (int)res);
  return 0;
}
