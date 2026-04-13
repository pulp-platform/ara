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
// AES-128 ECB vectorized implementation using the RISC-V Zvkned extension.
// Round keys are preloaded once (11 × 128-bit for AES-128) and reused across
// every block through the `.vs` broadcast form of vaes*.

#ifndef KERNEL_AES_H
#define KERNEL_AES_H

#include <stddef.h>
#include <stdint.h>

#define AES_BLOCK_BYTES 16
#define AES_BLOCK_WORDS 4
#define AES_128_NROUNDS 10
#define AES_128_NKEYS (AES_128_NROUNDS + 1) // 11 round keys
#define AES_256_KEY_WORDS 8
#define AES_256_KEY_BYTES (AES_256_KEY_WORDS * sizeof(uint32_t))
#define AES_256_NROUNDS 14
#define AES_256_NKEYS (AES_256_NROUNDS + 1) // 15 round keys

// Expand `nkeys` AES-128 user keys in parallel using `vaeskf1.vi`.
// `keys` holds `nkeys * 4` u32 words (one 128-bit key per 4-word group).
// `round_keys` is written in round-major order:
//   round_keys[(round * nkeys + key) * 4 + word]
void aes128_expand_keys_vec(const uint32_t *keys, uint32_t *round_keys,
                            size_t nkeys);

// Expand `nkeys` AES-256 user keys in parallel using `vaeskf2.vi`.
// `keys_lo` and `keys_hi` hold the first and second 128-bit halves of each
// user key as `nkeys * 4` u32 words each.
// `round_keys` is written in round-major order:
//   round_keys[(round * nkeys + key) * 4 + word]
void aes256_expand_keys_vec(const uint32_t *keys_lo, const uint32_t *keys_hi,
                            uint32_t *round_keys, size_t nkeys);

// Vectorized AES-128 ECB encryption of `nblocks` 16-byte blocks using the
// Zvkned instructions. The 44-word expanded key must already be stored at
// `rk` (little-endian u32 layout matching vle32.v). `in` and `out` may alias.
void aes128_ecb_encrypt_vec(const uint32_t *rk, const uint32_t *in,
                            uint32_t *out, size_t nblocks);

// Vectorized AES-128 ECB decryption counterpart.
void aes128_ecb_decrypt_vec(const uint32_t *rk, const uint32_t *in,
                            uint32_t *out, size_t nblocks);

#endif // KERNEL_AES_H
