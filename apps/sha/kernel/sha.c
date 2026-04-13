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
//
// Vectorized SHA-256 using the RISC-V Zvknhb instructions. The kernel hashes
// multiple independent messages in parallel; each message is a sequence of
// pre-padded 512-bit blocks represented as 16 u32 schedule words.

#include "sha.h"

#ifndef VLEN
#define VLEN 4096
#endif

#define SHA256_MAX_BATCH_MESSAGES (VLEN / 16)
#define SHA256_MAX_BATCH_VWORDS (SHA256_MAX_BATCH_MESSAGES * 4)
#define SHA256_MAX_BATCH_STATE_WORDS (SHA256_MAX_BATCH_MESSAGES * SHA256_DIGEST_WORDS)
#define SHA256_MAX_BATCH_SCHEDULE_WORDS (SHA256_MAX_BATCH_MESSAGES * 64)

static const uint32_t k_sha256_init[SHA256_DIGEST_WORDS] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
};

static const uint32_t k_sha256_k[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu,
    0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u, 0xd807aa98u, 0x12835b01u,
    0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u,
    0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u,
    0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u,
    0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u,
    0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u, 0x1e376c08u,
    0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu,
    0x682e6ff3u, 0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

static uint32_t g_block_batch[SHA256_MAX_BATCH_MESSAGES * SHA256_BLOCK_WORDS]
    __attribute__((aligned(128)));
static uint32_t g_state_batch[SHA256_MAX_BATCH_STATE_WORDS]
    __attribute__((aligned(128)));
static uint32_t g_schedule_words[SHA256_MAX_BATCH_SCHEDULE_WORDS]
    __attribute__((aligned(128)));
static uint32_t g_cdgh[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_abef[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_tmp[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_kw[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_sched_vd[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_sched_vs2[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_sched_vs1[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));
static uint32_t g_sched_out[SHA256_MAX_BATCH_VWORDS] __attribute__((aligned(128)));

static inline size_t sha256_vset_words(size_t avl_words) {
  size_t vl;
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
               : "=r"(vl)
               : "r"(avl_words)
               : "memory");
  return vl;
}

static void sha256_compress_batch(uint32_t *state, const uint32_t *blocks,
                                  size_t nmessages) {
  const size_t vl_words = nmessages * 4;

  for (size_t msg = 0; msg < nmessages; ++msg) {
    const size_t s = msg * SHA256_DIGEST_WORDS;
    const size_t v = msg * 4;
    const size_t w = msg * 64;

    g_cdgh[v + 0] = state[s + 7];
    g_cdgh[v + 1] = state[s + 6];
    g_cdgh[v + 2] = state[s + 3];
    g_cdgh[v + 3] = state[s + 2];
    g_abef[v + 0] = state[s + 5];
    g_abef[v + 1] = state[s + 4];
    g_abef[v + 2] = state[s + 1];
    g_abef[v + 3] = state[s + 0];

    for (size_t i = 0; i < SHA256_BLOCK_WORDS; ++i)
      g_schedule_words[w + i] = blocks[msg * SHA256_BLOCK_WORDS + i];
  }

  sha256_vset_words(vl_words);

  for (size_t t = 16; t < 64; t += 4) {
    for (size_t msg = 0; msg < nmessages; ++msg) {
      const size_t v = msg * 4;
      const size_t w = msg * 64;

      g_sched_vd[v + 0] = g_schedule_words[w + t - 16];
      g_sched_vd[v + 1] = g_schedule_words[w + t - 15];
      g_sched_vd[v + 2] = g_schedule_words[w + t - 14];
      g_sched_vd[v + 3] = g_schedule_words[w + t - 13];

      g_sched_vs2[v + 0] = g_schedule_words[w + t - 12];
      g_sched_vs2[v + 1] = g_schedule_words[w + t - 7];
      g_sched_vs2[v + 2] = g_schedule_words[w + t - 6];
      g_sched_vs2[v + 3] = g_schedule_words[w + t - 5];

      g_sched_vs1[v + 0] = g_schedule_words[w + t - 4];
      g_sched_vs1[v + 1] = 0;
      g_sched_vs1[v + 2] = g_schedule_words[w + t - 2];
      g_sched_vs1[v + 3] = g_schedule_words[w + t - 1];
    }

    asm volatile("vle32.v v8, (%0)" ::"r"(g_sched_vd) : "memory");
    asm volatile("vle32.v v16, (%0)" ::"r"(g_sched_vs2) : "memory");
    asm volatile("vle32.v v24, (%0)" ::"r"(g_sched_vs1) : "memory");
    asm volatile("vsha2ms.vv v8, v16, v24");
    asm volatile("vse32.v v8, (%0)" ::"r"(g_sched_out) : "memory");

    for (size_t msg = 0; msg < nmessages; ++msg) {
      const size_t v = msg * 4;
      const size_t w = msg * 64 + t;
      for (size_t i = 0; i < 4; ++i)
        g_schedule_words[w + i] = g_sched_out[v + i];
    }
  }

  for (size_t t = 0; t < 64; t += 4) {
    for (size_t msg = 0; msg < nmessages; ++msg) {
      const size_t v = msg * 4;
      const size_t w = msg * 64 + t;
      g_kw[v + 0] = k_sha256_k[t + 0] + g_schedule_words[w + 0];
      g_kw[v + 1] = k_sha256_k[t + 1] + g_schedule_words[w + 1];
      g_kw[v + 2] = k_sha256_k[t + 2] + g_schedule_words[w + 2];
      g_kw[v + 3] = k_sha256_k[t + 3] + g_schedule_words[w + 3];
    }

    asm volatile("vle32.v v8, (%0)" ::"r"(g_cdgh) : "memory");
    asm volatile("vle32.v v16, (%0)" ::"r"(g_abef) : "memory");
    asm volatile("vle32.v v24, (%0)" ::"r"(g_kw) : "memory");
    asm volatile("vsha2cl.vv v8, v16, v24");
    asm volatile("vse32.v v8, (%0)" ::"r"(g_tmp) : "memory");

    asm volatile("vle32.v v8, (%0)" ::"r"(g_abef) : "memory");
    asm volatile("vle32.v v16, (%0)" ::"r"(g_tmp) : "memory");
    asm volatile("vle32.v v24, (%0)" ::"r"(g_kw) : "memory");
    asm volatile("vsha2ch.vv v8, v16, v24");
    asm volatile("vse32.v v8, (%0)" ::"r"(g_abef) : "memory");

    for (size_t i = 0; i < vl_words; ++i)
      g_cdgh[i] = g_tmp[i];
  }

  for (size_t msg = 0; msg < nmessages; ++msg) {
    const size_t s = msg * SHA256_DIGEST_WORDS;
    const size_t v = msg * 4;
    const uint32_t a = g_abef[v + 3];
    const uint32_t b = g_abef[v + 2];
    const uint32_t c = g_cdgh[v + 3];
    const uint32_t d = g_cdgh[v + 2];
    const uint32_t e = g_abef[v + 1];
    const uint32_t f = g_abef[v + 0];
    const uint32_t g = g_cdgh[v + 1];
    const uint32_t h = g_cdgh[v + 0];

    state[s + 0] += a;
    state[s + 1] += b;
    state[s + 2] += c;
    state[s + 3] += d;
    state[s + 4] += e;
    state[s + 5] += f;
    state[s + 6] += g;
    state[s + 7] += h;
  }
}

void sha256_hash_vec(const uint32_t *padded_blocks, uint32_t *digests,
                     size_t nmessages, size_t blocks_per_message) {
  size_t remaining = nmessages;
  size_t msg_offset = 0;

  while (remaining) {
    const size_t vl_words = sha256_vset_words(remaining * 4);
    const size_t batch_messages = vl_words / 4;

    for (size_t msg = 0; msg < batch_messages; ++msg)
      for (size_t i = 0; i < SHA256_DIGEST_WORDS; ++i)
        g_state_batch[msg * SHA256_DIGEST_WORDS + i] = k_sha256_init[i];

    for (size_t block = 0; block < blocks_per_message; ++block) {
      for (size_t msg = 0; msg < batch_messages; ++msg) {
        const size_t src_base =
            ((msg_offset + msg) * blocks_per_message + block) * SHA256_BLOCK_WORDS;
        const size_t dst_base = msg * SHA256_BLOCK_WORDS;
        for (size_t i = 0; i < SHA256_BLOCK_WORDS; ++i)
          g_block_batch[dst_base + i] = padded_blocks[src_base + i];
      }
      sha256_compress_batch(g_state_batch, g_block_batch, batch_messages);
    }

    for (size_t msg = 0; msg < batch_messages; ++msg) {
      const size_t src_base = msg * SHA256_DIGEST_WORDS;
      const size_t dst_base = (msg_offset + msg) * SHA256_DIGEST_WORDS;
      for (size_t i = 0; i < SHA256_DIGEST_WORDS; ++i)
        digests[dst_base + i] = g_state_batch[src_base + i];
    }

    msg_offset += batch_messages;
    remaining -= batch_messages;
  }
}
