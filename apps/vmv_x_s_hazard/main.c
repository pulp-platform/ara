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

// Regression reproducer for issue #436.
//
// The VWXUNARY0 instructions (vmv.x.s, vcpop.m, vfirst.m) are decoded in the
// OPMVV path of ara_dispatcher.sv, where ara_req.use_vs1 defaults to 1'b1.
// Their rs1 field encodes the *sub-opcode*, not a vector register:
//
//   vmv.x.s  -> rs1 = 0b00000 (0)  -> a buggy dispatcher reads a false vs1 = v0
//   vcpop.m  -> rs1 = 0b10000 (16) -> false vs1 = v16
//   vfirst.m -> rs1 = 0b10001 (17) -> false vs1 = v17
//
// Leaving use_vs1 asserted makes the main sequencer raise a spurious RAW hazard
// against whatever register number occupies the rs1 field. The dominant failure
// mode is serialization or a deadlock (not data corruption), so:
//   * a hang is caught by the testbench cycle-timeout, and
//   * we additionally self-check the returned scalars to guard against any
//     regression that would corrupt the result while "fixing" the hazard.
//
// This test deliberately writes v0 immediately before each vmv.x.s that reads
// an unrelated source register, building a tight producer/consumer chain on the
// register the bug falsely depends on.

#include <stdint.h>

#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#define N_ITERS 8

int main() {
  uint64_t vl;
  int errors = 0;

  // SEW = 64, LMUL = 1
  asm volatile("vsetvli %0, zero, e64, m1, ta, ma" : "=r"(vl));

  // Tight chain: write v0 (the register vmv.x.s falsely depends on), write the
  // real source v8, then read back element 0 from v8 via vmv.x.s. A correct
  // dispatcher does not stall on v0 here.
  for (int i = 0; i < N_ITERS; i++) {
    uint64_t poison = 0xAAAA000000000000ULL | (uint64_t)i; // goes into v0
    uint64_t src    = 0x1122334455660000ULL | (uint64_t)i; // goes into v8
    uint64_t out;

    asm volatile("vmv.s.x v0, %0" ::"r"(poison)); // false-dependency target
    asm volatile("vmv.s.x v8, %0" ::"r"(src));    // actual source element 0
    asm volatile("vmv.x.s %0, v8" : "=r"(out));   // must read v8, not wait on v0

    if (out != src) {
      printf("vmv.x.s iter %d: got 0x%lx, expected 0x%lx\n", i, out, src);
      errors++;
    }
  }

  if (errors == 0)
    printf("vmv_x_s_hazard: PASS\n");
  else
    printf("vmv_x_s_hazard: FAIL (%d errors)\n", errors);

  return errors;
}
