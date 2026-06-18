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

// Spike-vs-Ara differential probe for issue #446 (vcpop.m ignores VL).
//
// vmset.m sets the active (vl) mask bits; the tail beyond vl is mask-agnostic.
// vcpop.m must count only the first vl bits. The bug counts tail bits too, so
// Ara reports more than vl while Spike reports exactly vl. Each line prints the
// computed population count for a given vl; diff the Spike and Ara outputs.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#define PROBE(VLNUM)                                                     \
  do {                                                                   \
    uint64_t vl, cnt;                                                    \
    asm volatile("vsetivli %0, " #VLNUM ", e32, m1, ta, ma" : "=r"(vl)); \
    asm volatile("vmset.m v0");                                          \
    asm volatile("vcpop.m %0, v0" : "=r"(cnt));                          \
    printf("vl=%d vcpop=%d\n", (int)vl, (int)cnt);                       \
  } while (0)

int main() {
  PROBE(1);
  PROBE(2);
  PROBE(4);
  PROBE(8);
  PROBE(16);
  return 0;
}
