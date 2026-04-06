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
# AES-128 ECB test-vector generator for the Ara AES benchmark.
#
# Usage: gen_data.py [nblocks]
#   nblocks: number of 16-byte blocks to encrypt (default 64)

import numpy as np
import sys

################################################################################
# AES-128 reference implementation (FIPS 197)
################################################################################

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

RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]


def xtime(a):
    return ((a << 1) ^ (0x1b if a & 0x80 else 0)) & 0xff


def gmul(a, b):
    r = 0
    for _ in range(8):
        if b & 1:
            r ^= a
        a = xtime(a)
        b >>= 1
    return r


def key_expansion(key):
    assert len(key) == 16
    rk = list(key)
    for i in range(4, 44):
        t = rk[4 * (i - 1):4 * i]
        if i % 4 == 0:
            t = [SBOX[t[1]] ^ RCON[i // 4 - 1], SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]]
        for j in range(4):
            rk.append(rk[4 * (i - 4) + j] ^ t[j])
    return bytes(rk)  # 44 words = 176 bytes


def sub_bytes(s):
    return bytes(SBOX[b] for b in s)


def inv_sub_bytes(s):
    inv = bytearray(256)
    for i, v in enumerate(SBOX):
        inv[v] = i
    return bytes(inv[b] for b in s)


def shift_rows(s):
    # State is column-major: s[c*4 + r]
    r = bytearray(16)
    for c in range(4):
        for rr in range(4):
            r[c * 4 + rr] = s[((c + rr) % 4) * 4 + rr]
    return bytes(r)


def inv_shift_rows(s):
    r = bytearray(16)
    for c in range(4):
        for rr in range(4):
            r[c * 4 + rr] = s[((c - rr) % 4) * 4 + rr]
    return bytes(r)


def mix_columns(s):
    r = bytearray(16)
    for c in range(4):
        a = s[c * 4:c * 4 + 4]
        r[c * 4 + 0] = gmul(a[0], 2) ^ gmul(a[1], 3) ^ a[2] ^ a[3]
        r[c * 4 + 1] = a[0] ^ gmul(a[1], 2) ^ gmul(a[2], 3) ^ a[3]
        r[c * 4 + 2] = a[0] ^ a[1] ^ gmul(a[2], 2) ^ gmul(a[3], 3)
        r[c * 4 + 3] = gmul(a[0], 3) ^ a[1] ^ a[2] ^ gmul(a[3], 2)
    return bytes(r)


def add_round_key(s, rk):
    return bytes(a ^ b for a, b in zip(s, rk))


def aes128_encrypt_block(rk, pt):
    s = add_round_key(pt, rk[0:16])
    for r in range(1, 10):
        s = sub_bytes(s)
        s = shift_rows(s)
        s = mix_columns(s)
        s = add_round_key(s, rk[16 * r:16 * (r + 1)])
    s = sub_bytes(s)
    s = shift_rows(s)
    s = add_round_key(s, rk[160:176])
    return s


def aes128_encrypt(key, plaintext):
    rk = key_expansion(key)
    assert len(plaintext) % 16 == 0
    out = bytearray()
    for i in range(0, len(plaintext), 16):
        out += aes128_encrypt_block(rk, plaintext[i:i + 16])
    return bytes(rk), bytes(out)


################################################################################
# Emit helpers (match the format used by the other Ara benchmarks)
################################################################################

def emit(name, array, alignment='8'):
    print(".global %s" % name)
    print(".balign " + alignment)
    print("%s:" % name)
    bs = array.tobytes()
    for i in range(0, len(bs), 4):
        s = ""
        for n in range(4):
            s += "%02x" % bs[i + 3 - n]
        print("    .word 0x%s" % s)


def main():
    if len(sys.argv) > 1:
        N = int(sys.argv[1])
    else:
        N = 64

    np.random.seed(42)
    key = bytes(np.random.randint(0, 256, 16, dtype=np.uint8).tolist())
    pt_bytes = bytes(
        np.random.randint(0, 256, N * 16, dtype=np.uint8).tolist())
    rk_bytes, ct_bytes = aes128_encrypt(key, pt_bytes)

    plaintext = np.frombuffer(pt_bytes, dtype=np.uint32).copy()
    ciphertext_g = np.frombuffer(ct_bytes, dtype=np.uint32).copy()
    round_keys = np.frombuffer(rk_bytes, dtype=np.uint32).copy()
    zero_buf = np.zeros(N * 4, dtype=np.uint32)

    print(".section .data,\"aw\",@progbits")
    emit("N", np.array(N, dtype=np.uint64))
    emit("round_keys", round_keys, '16')
    emit("plaintext",    plaintext,    'NR_LANES*4')
    emit("ciphertext_g", ciphertext_g, 'NR_LANES*4')
    emit("ciphertext",   zero_buf,     'NR_LANES*4')
    emit("roundtrip",    zero_buf,     'NR_LANES*4')


if __name__ == "__main__":
    main()
