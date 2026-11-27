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

// Spike-vs-Ara differential probe for issue #455 (indexed load/store hang when
// data SEW != index EEW).
//
// Index EEW (16) > data SEW (8): the index-operand fetch length is mis-scaled
// by the data SEW, so the address generator under-fetches and waits forever.
// On a buggy Ara this hangs (caught by the sim timeout); Spike completes.
// Each value line lets the harness diff the loaded elements.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

static volatile uint8_t  mem[128];
static volatile uint16_t idx[64];
static volatile uint8_t  out[64];

int main() {
  uint64_t vl;

  for (int i = 0; i < 128; i++) mem[i] = (uint8_t)(i & 0xff);
  for (int i = 0; i < 64; i++)  idx[i] = (uint16_t)(63 - i); // reverse order

  // Load 64 indices as e16 (index EEW = 16).
  asm volatile("vsetvli %0, %1, e16, m1, ta, ma" : "=r"(vl) : "r"((uint64_t)64));
  asm volatile("vle16.v v8, (%0)" ::"r"(idx));

  // Indexed load with data SEW = e8  (SEW < index EEW) -> the failing case.
  // 64 e16 indices span multiple NrLanes*64b words, so a mis-scaled (too small)
  // fetch length starves the address generator and hangs a buggy Ara.
  asm volatile("vsetvli %0, %1, e8, m1, ta, ma" : "=r"(vl) : "r"((uint64_t)64));
  asm volatile("vluxei16.v v16, (%0), v8" ::"r"(mem));
  asm volatile("vse8.v v16, (%0)" ::"r"(out) : "memory");

  // Expected: out[i] = mem[idx[i]] = mem[63-i] = (63 - i) & 0xff
  for (int i = 0; i < 64; i++)
    printf("o%d=%d\n", i, (int)out[i]);
  return 0;
}
