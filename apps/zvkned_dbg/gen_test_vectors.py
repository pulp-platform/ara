#!/usr/bin/env python3
"""Generate expected test vectors for each RISC-V Zvkned instruction independently.

Uses NIST FIPS 197 Appendix B known-answer vectors as the base input.
All uint32 values use RISC-V little-endian convention:
  AES column [row0, row1, row2, row3] → uint32 with row0 at bits[7:0].
  i.e. big-endian AES word 0xAABBCCDD → LE uint32 0xDDCCBBAA.
"""

# ── AES Constants ─────────────────────────────────────────────────────────────

SBOX = [
    0x63,
    0x7C,
    0x77,
    0x7B,
    0xF2,
    0x6B,
    0x6F,
    0xC5,
    0x30,
    0x01,
    0x67,
    0x2B,
    0xFE,
    0xD7,
    0xAB,
    0x76,
    0xCA,
    0x82,
    0xC9,
    0x7D,
    0xFA,
    0x59,
    0x47,
    0xF0,
    0xAD,
    0xD4,
    0xA2,
    0xAF,
    0x9C,
    0xA4,
    0x72,
    0xC0,
    0xB7,
    0xFD,
    0x93,
    0x26,
    0x36,
    0x3F,
    0xF7,
    0xCC,
    0x34,
    0xA5,
    0xE5,
    0xF1,
    0x71,
    0xD8,
    0x31,
    0x15,
    0x04,
    0xC7,
    0x23,
    0xC3,
    0x18,
    0x96,
    0x05,
    0x9A,
    0x07,
    0x12,
    0x80,
    0xE2,
    0xEB,
    0x27,
    0xB2,
    0x75,
    0x09,
    0x83,
    0x2C,
    0x1A,
    0x1B,
    0x6E,
    0x5A,
    0xA0,
    0x52,
    0x3B,
    0xD6,
    0xB3,
    0x29,
    0xE3,
    0x2F,
    0x84,
    0x53,
    0xD1,
    0x00,
    0xED,
    0x20,
    0xFC,
    0xB1,
    0x5B,
    0x6A,
    0xCB,
    0xBE,
    0x39,
    0x4A,
    0x4C,
    0x58,
    0xCF,
    0xD0,
    0xEF,
    0xAA,
    0xFB,
    0x43,
    0x4D,
    0x33,
    0x85,
    0x45,
    0xF9,
    0x02,
    0x7F,
    0x50,
    0x3C,
    0x9F,
    0xA8,
    0x51,
    0xA3,
    0x40,
    0x8F,
    0x92,
    0x9D,
    0x38,
    0xF5,
    0xBC,
    0xB6,
    0xDA,
    0x21,
    0x10,
    0xFF,
    0xF3,
    0xD2,
    0xCD,
    0x0C,
    0x13,
    0xEC,
    0x5F,
    0x97,
    0x44,
    0x17,
    0xC4,
    0xA7,
    0x7E,
    0x3D,
    0x64,
    0x5D,
    0x19,
    0x73,
    0x60,
    0x81,
    0x4F,
    0xDC,
    0x22,
    0x2A,
    0x90,
    0x88,
    0x46,
    0xEE,
    0xB8,
    0x14,
    0xDE,
    0x5E,
    0x0B,
    0xDB,
    0xE0,
    0x32,
    0x3A,
    0x0A,
    0x49,
    0x06,
    0x24,
    0x5C,
    0xC2,
    0xD3,
    0xAC,
    0x62,
    0x91,
    0x95,
    0xE4,
    0x79,
    0xE7,
    0xC8,
    0x37,
    0x6D,
    0x8D,
    0xD5,
    0x4E,
    0xA9,
    0x6C,
    0x56,
    0xF4,
    0xEA,
    0x65,
    0x7A,
    0xAE,
    0x08,
    0xBA,
    0x78,
    0x25,
    0x2E,
    0x1C,
    0xA6,
    0xB4,
    0xC6,
    0xE8,
    0xDD,
    0x74,
    0x1F,
    0x4B,
    0xBD,
    0x8B,
    0x8A,
    0x70,
    0x3E,
    0xB5,
    0x66,
    0x48,
    0x03,
    0xF6,
    0x0E,
    0x61,
    0x35,
    0x57,
    0xB9,
    0x86,
    0xC1,
    0x1D,
    0x9E,
    0xE1,
    0xF8,
    0x98,
    0x11,
    0x69,
    0xD9,
    0x8E,
    0x94,
    0x9B,
    0x1E,
    0x87,
    0xE9,
    0xCE,
    0x55,
    0x28,
    0xDF,
    0x8C,
    0xA1,
    0x89,
    0x0D,
    0xBF,
    0xE6,
    0x42,
    0x68,
    0x41,
    0x99,
    0x2D,
    0x0F,
    0xB0,
    0x54,
    0xBB,
    0x16,
]

INV_SBOX = [
    0x52,
    0x09,
    0x6A,
    0xD5,
    0x30,
    0x36,
    0xA5,
    0x38,
    0xBF,
    0x40,
    0xA3,
    0x9E,
    0x81,
    0xF3,
    0xD7,
    0xFB,
    0x7C,
    0xE3,
    0x39,
    0x82,
    0x9B,
    0x2F,
    0xFF,
    0x87,
    0x34,
    0x8E,
    0x43,
    0x44,
    0xC4,
    0xDE,
    0xE9,
    0xCB,
    0x54,
    0x7B,
    0x94,
    0x32,
    0xA6,
    0xC2,
    0x23,
    0x3D,
    0xEE,
    0x4C,
    0x95,
    0x0B,
    0x42,
    0xFA,
    0xC3,
    0x4E,
    0x08,
    0x2E,
    0xA1,
    0x66,
    0x28,
    0xD9,
    0x24,
    0xB2,
    0x76,
    0x5B,
    0xA2,
    0x49,
    0x6D,
    0x8B,
    0xD1,
    0x25,
    0x72,
    0xF8,
    0xF6,
    0x64,
    0x86,
    0x68,
    0x98,
    0x16,
    0xD4,
    0xA4,
    0x5C,
    0xCC,
    0x5D,
    0x65,
    0xB6,
    0x92,
    0x6C,
    0x70,
    0x48,
    0x50,
    0xFD,
    0xED,
    0xB9,
    0xDA,
    0x5E,
    0x15,
    0x46,
    0x57,
    0xA7,
    0x8D,
    0x9D,
    0x84,
    0x90,
    0xD8,
    0xAB,
    0x00,
    0x8C,
    0xBC,
    0xD3,
    0x0A,
    0xF7,
    0xE4,
    0x58,
    0x05,
    0xB8,
    0xB3,
    0x45,
    0x06,
    0xD0,
    0x2C,
    0x1E,
    0x8F,
    0xCA,
    0x3F,
    0x0F,
    0x02,
    0xC1,
    0xAF,
    0xBD,
    0x03,
    0x01,
    0x13,
    0x8A,
    0x6B,
    0x3A,
    0x91,
    0x11,
    0x41,
    0x4F,
    0x67,
    0xDC,
    0xEA,
    0x97,
    0xF2,
    0xCF,
    0xCE,
    0xF0,
    0xB4,
    0xE6,
    0x73,
    0x96,
    0xAC,
    0x74,
    0x22,
    0xE7,
    0xAD,
    0x35,
    0x85,
    0xE2,
    0xF9,
    0x37,
    0xE8,
    0x1C,
    0x75,
    0xDF,
    0x6E,
    0x47,
    0xF1,
    0x1A,
    0x71,
    0x1D,
    0x29,
    0xC5,
    0x89,
    0x6F,
    0xB7,
    0x62,
    0x0E,
    0xAA,
    0x18,
    0xBE,
    0x1B,
    0xFC,
    0x56,
    0x3E,
    0x4B,
    0xC6,
    0xD2,
    0x79,
    0x20,
    0x9A,
    0xDB,
    0xC0,
    0xFE,
    0x78,
    0xCD,
    0x5A,
    0xF4,
    0x1F,
    0xDD,
    0xA8,
    0x33,
    0x88,
    0x07,
    0xC7,
    0x31,
    0xB1,
    0x12,
    0x10,
    0x59,
    0x27,
    0x80,
    0xEC,
    0x5F,
    0x60,
    0x51,
    0x7F,
    0xA9,
    0x19,
    0xB5,
    0x4A,
    0x0D,
    0x2D,
    0xE5,
    0x7A,
    0x9F,
    0x93,
    0xC9,
    0x9C,
    0xEF,
    0xA0,
    0xE0,
    0x3B,
    0x4D,
    0xAE,
    0x2A,
    0xF5,
    0xB0,
    0xC8,
    0xEB,
    0xBB,
    0x3C,
    0x83,
    0x53,
    0x99,
    0x61,
    0x17,
    0x2B,
    0x04,
    0x7E,
    0xBA,
    0x77,
    0xD6,
    0x26,
    0xE1,
    0x69,
    0x14,
    0x63,
    0x55,
    0x21,
    0x0C,
    0x7D,
]

RCON = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]


# ── GF(2^8) Helpers ───────────────────────────────────────────────────────────


def xtime(b):
    """Multiply by x in GF(2^8) with irreducible polynomial 0x11b."""
    return ((b << 1) ^ 0x1B) & 0xFF if b & 0x80 else (b << 1) & 0xFF


def gf_mul(a, b):
    """Multiply two bytes in GF(2^8)."""
    result = 0
    for _ in range(8):
        if b & 1:
            result ^= a
        a = xtime(a)
        b >>= 1
    return result


# ── State Representation ──────────────────────────────────────────────────────
# State is a 4x4 matrix: state[row][col], matching FIPS 197 convention.
# LE uint32 words map to columns: word[c] bits[7:0]=row0, [15:8]=row1, etc.


def words_to_state(words):
    """Convert 4 x LE uint32 → 4x4 state matrix [row][col]."""
    state = [[0] * 4 for _ in range(4)]
    for c in range(4):
        w = words[c]
        for r in range(4):
            state[r][c] = (w >> (8 * r)) & 0xFF
    return state


def state_to_words(state):
    """Convert 4x4 state matrix → 4 x LE uint32."""
    words = []
    for c in range(4):
        w = 0
        for r in range(4):
            w |= state[r][c] << (8 * r)
        words.append(w)
    return words


# ── AES Primitives ────────────────────────────────────────────────────────────


def sub_bytes(state):
    return [[SBOX[state[r][c]] for c in range(4)] for r in range(4)]


def inv_sub_bytes(state):
    return [[INV_SBOX[state[r][c]] for c in range(4)] for r in range(4)]


def shift_rows(state):
    out = [row[:] for row in state]
    for r in range(1, 4):
        out[r] = state[r][r:] + state[r][:r]  # rotate left by r
    return out


def inv_shift_rows(state):
    out = [row[:] for row in state]
    for r in range(1, 4):
        out[r] = state[r][4 - r :] + state[r][: 4 - r]  # rotate right by r
    return out


def mix_columns(state):
    out = [[0] * 4 for _ in range(4)]
    for c in range(4):
        col = [state[r][c] for r in range(4)]
        out[0][c] = gf_mul(2, col[0]) ^ gf_mul(3, col[1]) ^ col[2] ^ col[3]
        out[1][c] = col[0] ^ gf_mul(2, col[1]) ^ gf_mul(3, col[2]) ^ col[3]
        out[2][c] = col[0] ^ col[1] ^ gf_mul(2, col[2]) ^ gf_mul(3, col[3])
        out[3][c] = gf_mul(3, col[0]) ^ col[1] ^ col[2] ^ gf_mul(2, col[3])
    return out


def inv_mix_columns(state):
    out = [[0] * 4 for _ in range(4)]
    for c in range(4):
        col = [state[r][c] for r in range(4)]
        out[0][c] = (
            gf_mul(0x0E, col[0])
            ^ gf_mul(0x0B, col[1])
            ^ gf_mul(0x0D, col[2])
            ^ gf_mul(0x09, col[3])
        )
        out[1][c] = (
            gf_mul(0x09, col[0])
            ^ gf_mul(0x0E, col[1])
            ^ gf_mul(0x0B, col[2])
            ^ gf_mul(0x0D, col[3])
        )
        out[2][c] = (
            gf_mul(0x0D, col[0])
            ^ gf_mul(0x09, col[1])
            ^ gf_mul(0x0E, col[2])
            ^ gf_mul(0x0B, col[3])
        )
        out[3][c] = (
            gf_mul(0x0B, col[0])
            ^ gf_mul(0x0D, col[1])
            ^ gf_mul(0x09, col[2])
            ^ gf_mul(0x0E, col[3])
        )
    return out


def add_round_key(state, key_state):
    return [[state[r][c] ^ key_state[r][c] for c in range(4)] for r in range(4)]


# ── AES-128 Key Schedule ─────────────────────────────────────────────────────


def sub_word(w):
    """Apply S-box to each byte of a 32-bit word (packed as int)."""
    return (
        SBOX[(w >> 24) & 0xFF] << 24
        | SBOX[(w >> 16) & 0xFF] << 16
        | SBOX[(w >> 8) & 0xFF] << 8
        | SBOX[w & 0xFF]
    )


def rot_word(w):
    """Rotate 32-bit word left by one byte."""
    return ((w << 8) | (w >> 24)) & 0xFFFFFFFF


def key_expansion_128(key_words_le):
    """AES-128 key expansion.  Input: 4 LE uint32.  Output: 11 round keys, each 4 LE uint32."""

    # Convert LE uint32 to big-endian words for standard key schedule math
    def le_to_be(w):
        b = w.to_bytes(4, "little")
        return int.from_bytes(b, "big")

    def be_to_le(w):
        b = w.to_bytes(4, "big")
        return int.from_bytes(b, "little")

    W = [le_to_be(w) for w in key_words_le]  # W[0..3] in BE
    for i in range(4, 44):
        temp = W[i - 1]
        if i % 4 == 0:
            temp = sub_word(rot_word(temp)) ^ (RCON[i // 4] << 24)
        W.append(W[i - 4] ^ temp)

    # Group into round keys and convert back to LE
    rks = []
    for r in range(11):
        rks.append([be_to_le(W[4 * r + j]) for j in range(4)])
    return rks


# ── AES-256 Key Schedule (vaeskf2) ───────────────────────────────────────────


def key_expansion_256(key_words_le):
    """AES-256 key expansion.  Input: 8 LE uint32 (two 128-bit halves).
    Output: 15 round keys, each 4 LE uint32."""

    def le_to_be(w):
        b = w.to_bytes(4, "little")
        return int.from_bytes(b, "big")

    def be_to_le(w):
        b = w.to_bytes(4, "big")
        return int.from_bytes(b, "little")

    W = [le_to_be(w) for w in key_words_le]
    for i in range(8, 60):
        temp = W[i - 1]
        if i % 8 == 0:
            temp = sub_word(rot_word(temp)) ^ (RCON[i // 8] << 24)
        elif i % 8 == 4:
            temp = sub_word(temp)
        W.append(W[i - 8] ^ temp)

    rks = []
    for r in range(15):
        rks.append([be_to_le(W[4 * r + j]) for j in range(4)])
    return rks


# ── Zvkned Instruction Models ────────────────────────────────────────────────
# Each function takes LE uint32 words and returns LE uint32 words.


def vaesz_vs(vd, vs2):
    """AddRoundKey only: vd ^= vs2."""
    s = words_to_state(vd)
    k = words_to_state(vs2)
    s = add_round_key(s, k)
    return state_to_words(s)


def vaesem(vd, vs2):
    """Encrypt middle round: SubBytes → ShiftRows → MixColumns → AddRoundKey."""
    s = words_to_state(vd)
    k = words_to_state(vs2)
    s = sub_bytes(s)
    s = shift_rows(s)
    s = mix_columns(s)
    s = add_round_key(s, k)
    return state_to_words(s)


def vaesef(vd, vs2):
    """Encrypt final round: SubBytes → ShiftRows → AddRoundKey (no MixColumns)."""
    s = words_to_state(vd)
    k = words_to_state(vs2)
    s = sub_bytes(s)
    s = shift_rows(s)
    s = add_round_key(s, k)
    return state_to_words(s)


def vaesdm(vd, vs2):
    """Decrypt middle round: InvShiftRows → InvSubBytes → AddRoundKey → InvMixColumns.
    Note: AddRoundKey comes BEFORE InvMixColumns (RISC-V Zvkned / FIPS 197 direct inverse)."""
    s = words_to_state(vd)
    k = words_to_state(vs2)
    s = inv_shift_rows(s)
    s = inv_sub_bytes(s)
    s = add_round_key(s, k)
    s = inv_mix_columns(s)
    return state_to_words(s)


def vaesdf(vd, vs2):
    """Decrypt final round: InvShiftRows → InvSubBytes → AddRoundKey (no InvMixColumns)."""
    s = words_to_state(vd)
    k = words_to_state(vs2)
    s = inv_shift_rows(s)
    s = inv_sub_bytes(s)
    s = add_round_key(s, k)
    return state_to_words(s)


def vaeskf1(current_rk_le, rnum):
    """AES-128 key schedule round.  current_rk = RK[rnum-1], produces RK[rnum].
    rnum is the immediate operand (1..10)."""

    def le_to_be(w):
        return int.from_bytes(w.to_bytes(4, "little"), "big")

    def be_to_le(w):
        return int.from_bytes(w.to_bytes(4, "big"), "little")

    W = [le_to_be(w) for w in current_rk_le]
    temp = sub_word(rot_word(W[3])) ^ (RCON[rnum] << 24)
    nw = [0] * 4
    nw[0] = W[0] ^ temp
    nw[1] = W[1] ^ nw[0]
    nw[2] = W[2] ^ nw[1]
    nw[3] = W[3] ^ nw[2]
    return [be_to_le(w) for w in nw]


def vaeskf2(current_rk_le, prev_rk_le, rnum):
    """AES-256 key schedule round.
    current_rk = RK[rnum-1] (vs2), prev_rk = vd (previous round key).
    rnum is the immediate operand (2..14)."""

    def le_to_be(w):
        return int.from_bytes(w.to_bytes(4, "little"), "big")

    def be_to_le(w):
        return int.from_bytes(w.to_bytes(4, "big"), "little")

    cur = [le_to_be(w) for w in current_rk_le]
    prev = [le_to_be(w) for w in prev_rk_le]

    if rnum % 2 == 0:
        temp = sub_word(rot_word(cur[3])) ^ (RCON[rnum // 2] << 24)
    else:
        temp = sub_word(cur[3])
    nw = [0] * 4
    nw[0] = prev[0] ^ temp
    nw[1] = prev[1] ^ nw[0]
    nw[2] = prev[2] ^ nw[1]
    nw[3] = prev[3] ^ nw[2]
    return [be_to_le(w) for w in nw]


# ── Formatting Helpers ────────────────────────────────────────────────────────


def fmt(words):
    """Format 4 LE uint32 as hex for C."""
    return ", ".join(f"0x{w:08x}" for w in words)


def fmt_be(words):
    """Format as big-endian hex (matching FIPS 197 notation)."""

    def swap(w):
        return int.from_bytes(w.to_bytes(4, "little"), "big")

    return " ".join(f"{swap(w):08x}" for w in words)


# ── FIPS 197 Appendix B Test Vectors (AES-128) ───────────────────────────────
# Key:       2b7e1516 28aed2a6 abf71588 09cf4f3c
# Plaintext: 3243f6a8 885a308d 313198a2 e0370734

KEY_128_LE = [0x16157E2B, 0xA6D2AE28, 0x8815F7AB, 0x3C4FCF09]
PLAIN_LE = [0xA8F64332, 0x8D305A88, 0xA2983131, 0x340737E0]
# Expected ciphertext: 3925841d 02dc09fb dc118597 196a0b32
CIPHER_LE = [0x1D842539, 0xFB09DC02, 0x978511DC, 0x320B6A19]

# FIPS 197 Appendix A.3 AES-256 key
# Key: 603deb10 15ca71be 2b73aef0 857d7781 1f352c07 3b6108d7 2d9810a3 0914dff4
KEY_256_LE = [
    0x10EB3D60,
    0xBE71CA15,
    0xF0AE732B,
    0x81777D85,  # first 128 bits
    0x072C351F,
    0xD708613B,
    0xA310982D,
    0xF4DF1409,  # second 128 bits
]


# ── Main ──────────────────────────────────────────────────────────────────────


def main():
    print("=" * 72)
    print("Zvkned Test Vector Generator")
    print("Based on NIST FIPS 197 Appendix B (AES-128) known-answer vectors")
    print("All values are LE uint32 (RISC-V convention)")
    print("=" * 72)

    # ── Key schedule (vaeskf1) ────────────────────────────────────────────
    rks = [KEY_128_LE]
    print("\n── vaeskf1.vi (AES-128 key schedule) ──")
    print(f"  RK[ 0] (original key): {fmt(KEY_128_LE)}")
    print(f"         BE:             {fmt_be(KEY_128_LE)}")
    for rnd in range(1, 11):
        rk = vaeskf1(rks[-1], rnd)
        rks.append(rk)
        print(f"  vaeskf1.vi v_out, v_in, {rnd:2d}  →  {fmt(rk)}")
        print(f"         BE:                    {fmt_be(rk)}")

    # Cross-check against full key expansion
    rks_ref = key_expansion_128(KEY_128_LE)
    for i in range(11):
        assert rks[i] == rks_ref[i], f"Key schedule mismatch at round {i}"
    print("  ✓ Matches FIPS 197 Appendix A.1 key expansion")

    # ── vaesz.vs ──────────────────────────────────────────────────────────
    print("\n── vaesz.vs (AddRoundKey / round 0) ──")
    print(f"  Plaintext (vd):  {fmt(PLAIN_LE)}")
    print(f"  RK0       (vs2): {fmt(rks[0])}")
    state = vaesz_vs(PLAIN_LE, rks[0])
    print(f"  Result:          {fmt(state)}")
    print(f"         BE:       {fmt_be(state)}")

    # ── vaesem.vv (encrypt middle) ────────────────────────────────────────
    print("\n── vaesem.vv / vaesem.vs (encrypt middle round) ──")
    print("  Input: state after vaesz.vs (round 0)")
    state_after_rk0 = state  # from vaesz above
    state = state_after_rk0
    for rnd in range(1, 10):
        result = vaesem(state, rks[rnd])
        print(f"  Round {rnd:2d}: vaesem vd, RK{rnd:2d}  →  {fmt(result)}")
        print(f"           BE:                   {fmt_be(result)}")
        state = result

    # ── vaesef.vv (encrypt final) ─────────────────────────────────────────
    print("\n── vaesef.vv / vaesef.vs (encrypt final round) ──")
    print(f"  Input: state after round 9")
    encrypt_round9 = state
    result = vaesef(state, rks[10])
    print(f"  Round 10: vaesef vd, RK10  →  {fmt(result)}")
    print(f"            BE:                 {fmt_be(result)}")
    assert result == CIPHER_LE, (
        f"Encryption mismatch! Got {fmt(result)}, expected {fmt(CIPHER_LE)}"
    )
    print("  ✓ Matches FIPS 197 expected ciphertext")

    # ── vaesdm.vv (decrypt middle) ────────────────────────────────────────
    print("\n── vaesdm.vv / vaesdm.vs (decrypt middle round) ──")
    print("  Input: ciphertext after vaesz.vs with RK10")
    state = vaesz_vs(CIPHER_LE, rks[10])
    print(f"  After vaesz.vs RK10:  {fmt(state)}")
    for rnd in range(9, 0, -1):
        result = vaesdm(state, rks[rnd])
        print(f"  Round {rnd:2d}: vaesdm vd, RK{rnd:2d}  →  {fmt(result)}")
        print(f"           BE:                   {fmt_be(result)}")
        state = result

    # ── vaesdf.vv (decrypt final) ─────────────────────────────────────────
    print("\n── vaesdf.vv / vaesdf.vs (decrypt final round) ──")
    print(f"  Input: state after inverse round 1")
    result = vaesdf(state, rks[0])
    print(f"  Final:  vaesdf vd, RK0   →  {fmt(result)}")
    print(f"          BE:                  {fmt_be(result)}")
    assert result == PLAIN_LE, (
        f"Decryption mismatch! Got {fmt(result)}, expected {fmt(PLAIN_LE)}"
    )
    print("  ✓ Matches FIPS 197 expected plaintext")

    # ── vaeskf2 (AES-256 key schedule) ────────────────────────────────────
    print("\n── vaeskf2.vi (AES-256 key schedule) ──")
    rks256 = [KEY_256_LE[:4], KEY_256_LE[4:]]
    print(f"  RK[ 0] (key bits 0-127):   {fmt(rks256[0])}")
    print(f"  RK[ 1] (key bits 128-255): {fmt(rks256[1])}")
    for rnd in range(2, 15):
        rk = vaeskf2(rks256[-1], rks256[-2], rnd)
        rks256.append(rk)
        print(f"  vaeskf2.vi vd, vs2, {rnd:2d}     →  {fmt(rk)}")
        print(f"         BE:                     {fmt_be(rk)}")

    rks256_ref = key_expansion_256(KEY_256_LE)
    for i in range(15):
        assert rks256[i] == rks256_ref[i], f"AES-256 key schedule mismatch at round {i}"
    print("  ✓ Matches FIPS 197 Appendix A.3 key expansion")

    # ── Standalone single-instruction test vectors ────────────────────────
    print("\n" + "=" * 72)
    print("STANDALONE TEST VECTORS (one instruction each)")
    print("Copy these directly into C test code.")
    print("=" * 72)

    # Use state-after-RK0 as a realistic "mid-encryption" input
    mid_state = vaesz_vs(PLAIN_LE, rks[0])

    decrypt_start = vaesz_vs(CIPHER_LE, rks[10])
    decrypt_round9 = vaesdm(decrypt_start, rks[9])
    state_before_final = decrypt_start
    for rnd in range(9, 0, -1):
        state_before_final = vaesdm(state_before_final, rks[rnd])

    tests = [
        (
            "vaesz.vs",
            "vd = plaintext, vs2 = RK0",
            PLAIN_LE,
            rks[0],
            vaesz_vs(PLAIN_LE, rks[0]),
        ),
        (
            "vaesem.vv",
            "vd = state after RK0, vs2 = RK1",
            mid_state,
            rks[1],
            vaesem(mid_state, rks[1]),
        ),
        (
            "vaesef.vv",
            "vd = state after round 9, vs2 = RK10",
            encrypt_round9,
            rks[10],
            vaesef(encrypt_round9, rks[10]),
        ),
        (
            "vaesdm.vv",
            "vd = ciphertext xor RK10, vs2 = RK9",
            decrypt_start,
            rks[9],
            decrypt_round9,
        ),
        (
            "vaesdf.vv",
            "vd = state after inverse round 1, vs2 = RK0",
            state_before_final,
            rks[0],
            vaesdf(state_before_final, rks[0]),
        ),
        ("vaeskf1.vi", "vs2 = RK0, rnum = 1 → RK1", rks[0], None, rks[1]),
    ]

    for name, desc, vd, vs2, expected in tests:
        print(f"\n// {name}: {desc}")
        print(f"//   vd  = {{ {fmt(vd)} }};")
        if vs2 is not None:
            print(f"//   vs2 = {{ {fmt(vs2)} }};")
        print(f"//   expected = {{ {fmt(expected)} }};")

    # ── Full round-trip check ────────────────────────────────────────────
    print("\n" + "=" * 72)
    print("FULL ROUND-TRIP VERIFICATION")
    print("encrypt(plaintext) then decrypt(ciphertext) = plaintext")
    print("(already verified above via FIPS 197 known-answer vectors)")
    print("=" * 72)

    print("\n✓ All assertions passed.")


if __name__ == "__main__":
    main()
