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

#include "kernel/sha.h"
#include "runtime.h"

#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#endif

extern const uint64_t N;
extern const uint64_t MSG_BYTES;
extern const uint64_t BLOCKS_PER_MESSAGE;
extern const uint32_t padded_blocks[] __attribute__((aligned(16)));
extern const uint32_t digests_g[] __attribute__((aligned(4 * NR_LANES)));
extern uint32_t digests[] __attribute__((aligned(4 * NR_LANES)));

int main() {
  printf("\n");
  printf("============\n");
  printf("=  SHA256  =\n");
  printf("============\n");
  printf("\n");
  printf("Hashing %lu messages of %lu bytes each (%lu total bytes).\n",
         (unsigned long)N, (unsigned long)MSG_BYTES,
         (unsigned long)(N * MSG_BYTES));

  start_timer();
  sha256_hash_vec(padded_blocks, digests, N, BLOCKS_PER_MESSAGE);
  stop_timer();

  const int64_t runtime = get_timer();
  const size_t bytes = N * MSG_BYTES;
  if (runtime > 0) {
    const uint64_t bpc_milli = ((uint64_t)bytes * 1000ull) / (uint64_t)runtime;
    printf("Hash: %ld cycles (%lu bytes, %lu.%03lu B/cycle)\n", runtime,
           (unsigned long)bytes, (unsigned long)(bpc_milli / 1000ull),
           (unsigned long)(bpc_milli % 1000ull));
  } else {
    printf("Hash: %ld cycles (%lu bytes)\n", runtime, (unsigned long)bytes);
  }

  for (uint64_t i = 0; i < N * SHA256_DIGEST_WORDS; ++i) {
    if (digests[i] != digests_g[i]) {
      printf("Digest error at word %lu: 0x%08x != 0x%08x\n", (unsigned long)i,
             digests[i], digests_g[i]);
      return 1;
    }
  }

  printf("Passed.\n");
  return 0;
}
