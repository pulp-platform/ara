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

// Differential reproducer for issue #451 (vredsum deadlock).
//
// A reduction (vredsum.vs) issued right after a widening op (vwaddu.wv) that
// leaves results in the VALU result queue deadlocks the lane: the reduction-init
// state and the result queue contend for the same sequential state. With the fix
// in valu.sv (gate reduction-init on result_queue_cnt_d == '0) the sequence
// completes; without it, the simulation hangs (caught by the testbench timeout).
//
// Reaching the final print => PASS (no deadlock).

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
  uint64_t vl;
  uint64_t res;

  // Initialize the wide destination group v8 (e64, m2 -> v8..v9).
  asm volatile("vsetvli %0, zero, e64, m2, ta, ma" : "=r"(vl));
  asm volatile("vmv.v.i v8, 1");

  // Narrow source v11 (e32, m1).
  asm volatile("vsetvli %0, zero, e32, m1, tu, ma" : "=r"(vl));
  asm volatile("vmv.v.i v11, 2");

  // Widening add: wide v8 += narrow v11. Leaves results queued in the VALU.
  asm volatile("vwaddu.wv v8, v8, v11");

  // Reduction immediately after, on the wide group.
  asm volatile("vsetvli %0, zero, e64, m2, ta, ma" : "=r"(vl));
  asm volatile("vmv.s.x v10, zero");
  asm volatile("vredsum.vs v8, v8, v10");

  // If we get here, no deadlock occurred.
  asm volatile("vmv.x.s %0, v8" : "=r"(res));
  printf("vredsum_deadlock: PASS (reduction result = %lu)\n", res);

  return 0;
}
