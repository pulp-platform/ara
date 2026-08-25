// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential reproducer for issue #434: a Read-After-Read that
// turns into a correctness bug under Ara's out-of-order retirement.
//
// The main sequencer's read table only remembered the *last* instruction
// reading each vector register, so a later writer built a WAR hazard against
// only that last reader. A slow earlier reader could then be overtaken:
//
//   vdivu v6, v4, v2   ; SLOW, reads v2 (the value we care about)
//   vadd  v8, v2, v2   ; fast, reads v2 -> overwrites the read table entry
//   vadd  v2, v12, v12 ; writes v2 -> WAR only vs the fast vadd (bug!)
//
// Once the fast vadd retires, the writer to v2 was allowed to proceed while the
// slow vdivu had not finished reading v2, so vdivu's tail elements divided by
// the *new* v2. Correct hardware (and Spike) must keep v6 == num/old_a for all
// elements.
//
//   old_a = 1000, num = 8000 -> v6 = 8 everywhere (correct)
//   new_a = 4000             -> 8000/4000 = 2 on corrupted tail elements (buggy)
//
// Expected (Spike, and Ara after the #434 fix): sum=2048 bad=0   (256 * 8).

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

#define N 256

static volatile uint32_t arr_a[N];   // old value of "a"   = 1000
static volatile uint32_t arr_num[N]; // numerator          = 8000
static volatile uint32_t arr_new[N]; // half of new "a"    = 2000  (new a = 4000)
static volatile uint32_t result[N];

int main() {
  for (int i = 0; i < N; i++) {
    arr_a[i]   = 1000;
    arr_num[i] = 8000;
    arr_new[i] = 2000;
  }
  asm volatile("fence" ::: "memory");

  uint64_t vl;
  asm volatile("vsetvli %0, %1, e32, m2, ta, ma" : "=r"(vl) : "r"((uint64_t)N));

  asm volatile("vle32.v v2,  (%0)" ::"r"(arr_a));   // v2  = 1000 (old a)
  asm volatile("vle32.v v4,  (%0)" ::"r"(arr_num)); // v4  = 8000 (num)
  asm volatile("vle32.v v12, (%0)" ::"r"(arr_new)); // v12 = 2000

  // Slow reader of v2.
  asm volatile("vdivu.vv v6, v4, v2");
  // Fast reader of v2 (used to clobber the single-entry read table).
  asm volatile("vadd.vv v8, v2, v2");
  // Writer of v2: must wait for *both* readers above to retire.
  asm volatile("vadd.vv v2, v12, v12"); // v2 <- 4000

  asm volatile("vse32.v v6, (%0)" ::"r"(result));
  asm volatile("fence" ::: "memory");

  uint32_t sum = 0;
  int bad = 0;
  for (int i = 0; i < N; i++) {
    sum += result[i];
    if (result[i] != 8) bad++;
  }
  printf("R: sum=%d bad=%d\n", (int)sum, bad);
  return 0;
}
