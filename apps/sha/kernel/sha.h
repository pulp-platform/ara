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

#ifndef KERNEL_SHA_H
#define KERNEL_SHA_H

#include <stddef.h>
#include <stdint.h>

#define SHA256_BLOCK_BYTES 64
#define SHA256_BLOCK_WORDS 16
#define SHA256_DIGEST_WORDS 8

// Hash `nmessages` fixed-length messages. Each message is already padded and
// stored as `blocks_per_message` consecutive 512-bit blocks (16 u32 words per
// block). The output digest is eight u32 words per message in standard SHA-256
// order.
void sha256_hash_vec(const uint32_t *padded_blocks, uint32_t *digests,
                     size_t nmessages, size_t blocks_per_message);

#endif // KERNEL_SHA_H
