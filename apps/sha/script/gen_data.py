#!/usr/bin/env python3
# Copyright 2024 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# SHA-256 benchmark dataset generator.
#
# Usage: gen_data.py [nmessages] [message_bytes]

import hashlib
import random
import sys


def emit_u64(name, value):
    print(f".global {name}")
    print(".balign 8")
    print(f"{name}:")
    print(f"    .word 0x{value & 0xFFFFFFFF:08x}")
    print(f"    .word 0x{(value >> 32) & 0xFFFFFFFF:08x}")


def emit_u32_array(name, values, alignment):
    print(f".global {name}")
    print(f".balign {alignment}")
    print(f"{name}:")
    for value in values:
        print(f"    .word 0x{value & 0xFFFFFFFF:08x}")


def pad_sha256(msg):
    bit_len = len(msg) * 8
    padded = bytearray(msg)
    padded.append(0x80)
    while (len(padded) + 8) % 64 != 0:
      padded.append(0)
    padded.extend(bit_len.to_bytes(8, "big"))
    return bytes(padded)


def bytes_to_words(block_bytes):
    words = []
    for idx in range(0, len(block_bytes), 4):
        words.append(int.from_bytes(block_bytes[idx:idx + 4], "big"))
    return words


def digest_to_words(digest_bytes):
    return bytes_to_words(digest_bytes)


def main():
    nmessages = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    msg_bytes = int(sys.argv[2]) if len(sys.argv) > 2 else 1024

    rng = random.Random(42)
    all_block_words = []
    all_digest_words = []
    blocks_per_message = None

    for _ in range(nmessages):
        msg = bytes(rng.getrandbits(8) for _ in range(msg_bytes))
        padded = pad_sha256(msg)
        digest = hashlib.sha256(msg).digest()

        block_words = bytes_to_words(padded)
        digest_words = digest_to_words(digest)

        if blocks_per_message is None:
            blocks_per_message = len(padded) // 64

        all_block_words.extend(block_words)
        all_digest_words.extend(digest_words)

    zero_digest_words = [0] * (nmessages * 8)

    print('.section .data,"aw",@progbits')
    emit_u64("N", nmessages)
    emit_u64("MSG_BYTES", msg_bytes)
    emit_u64("BLOCKS_PER_MESSAGE", blocks_per_message)
    emit_u32_array("padded_blocks", all_block_words, "16")
    emit_u32_array("digests_g", all_digest_words, "NR_LANES*4")
    emit_u32_array("digests", zero_digest_words, "NR_LANES*4")


if __name__ == "__main__":
    main()
