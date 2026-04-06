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
// Vectorized AES-128 ECB using the RISC-V Zvkned extension.
//
// Register layout:
//   v1..v11  : 11 AES-128 round keys (each LMUL=1, 128 bits = 4 × u32)
//   v16..v23 : data register group (LMUL=8) holding up to VL/4 blocks
//
// The .vs broadcast form of vaes*.vs replicates element group 0 of vs2
// (the single 128-bit round key) across every element group of vd.

#include "aes.h"

// Preload the 11 round keys from memory into v1..v11.
static inline void aes128_load_round_keys(const uint32_t *rk) {
  asm volatile("vsetivli zero, 4, e32, m1, ta, ma");
  asm volatile("vle32.v v1,  (%0)" ::"r"(rk + 0 * 4));
  asm volatile("vle32.v v2,  (%0)" ::"r"(rk + 1 * 4));
  asm volatile("vle32.v v3,  (%0)" ::"r"(rk + 2 * 4));
  asm volatile("vle32.v v4,  (%0)" ::"r"(rk + 3 * 4));
  asm volatile("vle32.v v5,  (%0)" ::"r"(rk + 4 * 4));
  asm volatile("vle32.v v6,  (%0)" ::"r"(rk + 5 * 4));
  asm volatile("vle32.v v7,  (%0)" ::"r"(rk + 6 * 4));
  asm volatile("vle32.v v8,  (%0)" ::"r"(rk + 7 * 4));
  asm volatile("vle32.v v9,  (%0)" ::"r"(rk + 8 * 4));
  asm volatile("vle32.v v10, (%0)" ::"r"(rk + 9 * 4));
  asm volatile("vle32.v v11, (%0)" ::"r"(rk + 10 * 4));
}

void aes128_ecb_encrypt_vec(const uint32_t *rk, const uint32_t *in,
                            uint32_t *out, size_t nblocks) {
  aes128_load_round_keys(rk);

  // VL measured in 32-bit words: each block is 4 words.
  size_t words_remaining = nblocks * AES_BLOCK_WORDS;

  while (words_remaining) {
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                 : "=r"(vl)
                 : "r"(words_remaining));
    asm volatile("vle32.v v16, (%0)" ::"r"(in));
    // Round 0: AddRoundKey only
    asm volatile("vaesz.vs  v16, v1");
    // Rounds 1..9: full AES round
    asm volatile("vaesem.vs v16, v2");
    asm volatile("vaesem.vs v16, v3");
    asm volatile("vaesem.vs v16, v4");
    asm volatile("vaesem.vs v16, v5");
    asm volatile("vaesem.vs v16, v6");
    asm volatile("vaesem.vs v16, v7");
    asm volatile("vaesem.vs v16, v8");
    asm volatile("vaesem.vs v16, v9");
    asm volatile("vaesem.vs v16, v10");
    // Round 10: final (no MixColumns)
    asm volatile("vaesef.vs v16, v11");
    asm volatile("vse32.v v16, (%0)" ::"r"(out));
    in += vl;
    out += vl;
    words_remaining -= vl;
  }
}

void aes128_ecb_decrypt_vec(const uint32_t *rk, const uint32_t *in,
                            uint32_t *out, size_t nblocks) {
  aes128_load_round_keys(rk);

  size_t words_remaining = nblocks * AES_BLOCK_WORDS;

  while (words_remaining) {
    size_t vl;
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                 : "=r"(vl)
                 : "r"(words_remaining));
    asm volatile("vle32.v v16, (%0)" ::"r"(in));
    // Decryption runs the round keys in reverse order.
    asm volatile("vaesz.vs  v16, v11");
    asm volatile("vaesdm.vs v16, v10");
    asm volatile("vaesdm.vs v16, v9");
    asm volatile("vaesdm.vs v16, v8");
    asm volatile("vaesdm.vs v16, v7");
    asm volatile("vaesdm.vs v16, v6");
    asm volatile("vaesdm.vs v16, v5");
    asm volatile("vaesdm.vs v16, v4");
    asm volatile("vaesdm.vs v16, v3");
    asm volatile("vaesdm.vs v16, v2");
    asm volatile("vaesdf.vs v16, v1");
    asm volatile("vse32.v v16, (%0)" ::"r"(out));
    in += vl;
    out += vl;
    words_remaining -= vl;
  }
}
