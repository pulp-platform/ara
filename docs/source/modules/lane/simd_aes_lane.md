# `simd_aes_lane` - Per-Lane AES Cryptographic Unit

## Overview

The `simd_aes_lane` module is a combinational AES processing unit instantiated inside the `valu`. It implements the per-column cryptographic operations required by the RISC-V Zvkned vector crypto extension.

Each instance operates on a 64-bit lane word, which at SEW=32 contains **2 AES columns** (32 bits each). All operations are per-column with no cross-lane dependencies — cross-column permutations (ShiftRows) are handled by the SLDU.

---

## Role in the 3-Phase ALU-SLDU-ALU Pipeline

AES round and key schedule instructions execute in three phases. The `simd_aes_lane` unit is active during Phase 1 and Phase 3:

```
Phase 1 (simd_aes_lane, phase=0):
  Round ops:    SubBytes or InvSubBytes on each byte of the AES state
  Key schedule: SubWord(RotWord(w3)) ^ Rcon (column w3 only; others pass through)

    --> Result sent to SLDU for ShiftRows / prefix-XOR

Phase 3 (simd_aes_lane, phase=1):
  Round ops:    MixColumns + AddRoundKey (or just AddRoundKey for final rounds)
  Key schedule: nw3 = old_w3 ^ nw2 (finalization after SLDU prefix-XOR)
```

The exception is `vaesz.vs` (round zero), which performs a single-phase XOR (AddRoundKey) without SLDU involvement.

---

## Interface

| Signal | Type | Description |
|--------|------|-------------|
| `operand_a_i` | `elen_t` (64-bit) | AES state (Phase 0: from VRF; Phase 1: from SLDU) |
| `operand_b_i` | `elen_t` (64-bit) | Round key (`vs2`, or `vd` for `vaeskf2` Phase 1) |
| `phase_i` | `logic` | Phase select: 0 = SubBytes, 1 = MixColumns+AddRoundKey |
| `op_i` | `ara_op_e` | AES operation code |
| `lane_id_i` | Lane identifier | Identifies which AES column this lane holds (for key schedule w3 detection) |
| `rnum_i` | `logic [3:0]` | Round number immediate (for `vaeskf1`/`vaeskf2` Rcon lookup) |
| `result_o` | `elen_t` (64-bit) | Computed result |

---

## Supported Operations

### Round Operations

| Instruction | Phase 0 | Phase 1 |
|------------|---------|---------|
| `vaesem` (encrypt middle) | SubBytes | MixColumns + AddRoundKey |
| `vaesef` (encrypt final) | SubBytes | AddRoundKey (no MixColumns) |
| `vaesdm` (decrypt middle) | InvSubBytes | InvMixColumns + AddRoundKey |
| `vaesdf` (decrypt final) | InvSubBytes | AddRoundKey (no InvMixColumns) |
| `vaesz` (round zero) | — | AddRoundKey only (single phase) |

### Key Schedule Operations

| Instruction | Phase 0 | Phase 1 |
|------------|---------|---------|
| `vaeskf1` (AES-128) | Column w3: SubWord(RotWord(w3)) ^ Rcon; others: pass through | nw3 = old_w3 ^ nw2 |
| `vaeskf2` (AES-256) | Even rounds: RotWord + Rcon; odd rounds: SubWord only | nw3 = old_w3 ^ nw2 |

---

## Cryptographic Primitives

The module implements the following AES building blocks as combinational functions:

- **`sbox_fwd()` / `sbox_inv()`**: Full 256-entry AES S-box and inverse S-box lookup
- **`sub_word()` / `inv_sub_word()`**: Apply S-box to each byte of a 32-bit word
- **`rot_word()`**: Rotate right by 8 bits (byte-level rotation)
- **`mix_columns_col()` / `inv_mix_columns_col()`**: MixColumns on a single 32-bit column using GF(2^8) multiplication with coefficients {2,3,1,1} and {14,11,13,9}
- **`xtime()`**: Multiply by 2 in GF(2^8) with irreducible polynomial `0x11b`
- **`gf_mul()`**: General GF(2^8) multiplication
- **`aes_rcon()`**: Round constant lookup (indexed by round number 1..10)

---

## Configuration

The `simd_aes_lane` module is only instantiated when `Zvkned(CryptoSupport)` is enabled. When disabled, no AES hardware is synthesized.

---

## Design Notes

- All operations are **combinational** (no pipeline registers) — latency is absorbed by the VALU's state machine
- The module processes **2 AES columns per cycle** (64-bit lane at SEW=32)
- Cross-column operations (ShiftRows, key schedule prefix-XOR) are delegated to the SLDU, keeping `simd_aes_lane` simple and per-lane
- For `vaeskf2`, the round number is normalized (clamped to [2,14] by toggling bit 3) to select between RotWord+Rcon (even) and SubWord-only (odd) behavior
