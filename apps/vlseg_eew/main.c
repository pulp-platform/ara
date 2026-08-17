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

// Spike-vs-Ara differential probe for issue #453 (segment load corrupts
// vd+1..vd+nf on read-back when EEW != EW8).
//
// vlseg4e16.v writes v8..v11. The per-vreg EEW tracker only tagged the base vd,
// so reading v9/v10/v11 back triggered a spurious on-read reshuffle that
// byte-packs the data. We load 4 segments of 4 fields, store each field, and
// print them; diff Spike vs Ara.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint16_t in_buf[16]; // 4 elements x 4 fields, element-major
static volatile uint16_t f0[4], f1[4], f2[4], f3[4];

int main() {
  uint64_t vl;

  // in_buf[i*4 + j] = base[j] + i, with base = {1, 11, 21, 31}
  for (int i = 0; i < 4; i++)
    for (int j = 0; j < 4; j++)
      in_buf[i * 4 + j] = (uint16_t)((j * 10 + 1) + i);

  asm volatile("vsetivli %0, 4, e16, m1, ta, ma" : "=r"(vl));
  asm volatile("vlseg4e16.v v8, (%0)" ::"r"(in_buf));
  asm volatile("vse16.v v8,  (%0)" ::"r"(f0) : "memory");
  asm volatile("vse16.v v9,  (%0)" ::"r"(f1) : "memory");
  asm volatile("vse16.v v10, (%0)" ::"r"(f2) : "memory");
  asm volatile("vse16.v v11, (%0)" ::"r"(f3) : "memory");

  // Expected: f0={1,2,3,4} f1={11,12,13,14} f2={21,22,23,24} f3={31,32,33,34}
  for (int i = 0; i < 4; i++) printf("a%d=%d\n", i, (int)f0[i]);
  for (int i = 0; i < 4; i++) printf("b%d=%d\n", i, (int)f1[i]);
  for (int i = 0; i < 4; i++) printf("c%d=%d\n", i, (int)f2[i]);
  for (int i = 0; i < 4; i++) printf("d%d=%d\n", i, (int)f3[i]);
  return 0;
}
