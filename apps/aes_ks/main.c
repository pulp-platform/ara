// Copyright 2024 ETH Zurich and University of Bologna.
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

#include <stdint.h>

#include "kernel/aes.h"
#include "runtime.h"

#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#endif

extern const uint64_t N;
extern const uint32_t keys[] __attribute__((aligned(4 * NR_LANES)));
extern const uint32_t round_keys_g[] __attribute__((aligned(4 * NR_LANES)));
extern uint32_t round_keys[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("============\n");
  printf("= AES-128  =\n");
  printf("= KEYGEN   =\n");
  printf("============\n");
  printf("\n");
  printf("Expanding %lu AES-128 keys (%lu input bytes).\n", (unsigned long)N,
         (unsigned long)(N * AES_BLOCK_BYTES));

  start_timer();
  aes128_expand_keys_vec(keys, round_keys, N);
  stop_timer();

  const int64_t runtime = get_timer();
  const size_t bytes = N * AES_BLOCK_BYTES;
  if (runtime > 0) {
    const uint64_t bpc_milli = ((uint64_t)bytes * 1000ull) / (uint64_t)runtime;
    printf("Expand: %ld cycles (%lu bytes, %lu.%03lu B/cycle)\n", runtime,
           (unsigned long)bytes, (unsigned long)(bpc_milli / 1000ull),
           (unsigned long)(bpc_milli % 1000ull));
  } else {
    printf("Expand: %ld cycles (%lu bytes)\n", runtime, (unsigned long)bytes);
  }

  for (uint64_t i = 0; i < N * AES_128_NKEYS * AES_BLOCK_WORDS; ++i) {
    if (round_keys[i] != round_keys_g[i]) {
      printf("Round key error at word %lu: 0x%08x != 0x%08x\n",
             (unsigned long)i, round_keys[i], round_keys_g[i]);
      return 1;
    }
  }

  printf("Passed.\n");
  return 0;
}
