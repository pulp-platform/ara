#!/usr/bin/env python3
# Copyright 2024 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# AES-256 key schedule test-vector generator for the Ara AES keygen benchmark.
#
# Usage: gen_data.py [nkeys]

import random
import sys

SBOX = bytes.fromhex(
    "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0"
    "b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275"
    "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf"
    "d0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2"
    "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb"
    "e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08"
    "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e"
    "e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16"
)

RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]


def sub_word(word):
    return bytes(SBOX[b] for b in word)


def xor_word(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def key_expansion_256(key):
    words = [key[i * 4:(i + 1) * 4] for i in range(8)]
    for i in range(8, 60):
        temp = words[i - 1]
        if i % 8 == 0:
            temp = temp[1:] + temp[:1]
            temp = sub_word(temp)
            temp = bytes([temp[0] ^ RCON[i // 8 - 1], temp[1], temp[2], temp[3]])
        elif i % 8 == 4:
            temp = sub_word(temp)
        words.append(xor_word(words[i - 8], temp))
    return b"".join(words)


def emit_bytes(name, payload, alignment='8'):
    print(f".global {name}")
    print(f".balign {alignment}")
    print(f"{name}:")
    for i in range(0, len(payload), 4):
        word = int.from_bytes(payload[i:i + 4], byteorder='little')
        print(f"    .word 0x{word:08x}")


def main():
    nkeys = int(sys.argv[1]) if len(sys.argv) > 1 else 64

    rng = random.Random(42)
    keys_lo = []
    keys_hi = []
    schedules = []
    for _ in range(nkeys):
        key = bytes(rng.randrange(256) for _ in range(32))
        keys_lo.append(key[:16])
        keys_hi.append(key[16:])
        schedules.append(key_expansion_256(key))

    round_keys = []
    for rnd in range(15):
        for schedule in schedules:
            round_keys.append(schedule[rnd * 16:(rnd + 1) * 16])

    print(".section .data,\"aw\",@progbits")
    emit_bytes("N", nkeys.to_bytes(8, byteorder='little'))
    emit_bytes("keys_lo", b"".join(keys_lo), 'NR_LANES*4')
    emit_bytes("keys_hi", b"".join(keys_hi), 'NR_LANES*4')
    emit_bytes("round_keys_g", b"".join(round_keys), 'NR_LANES*4')
    emit_bytes("round_keys", bytes(15 * nkeys * 16), 'NR_LANES*4')


if __name__ == "__main__":
    main()
