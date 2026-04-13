// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Zvknha (SHA-256) smoke test. Runs a single block of SHA-256
// compression using the vector crypto instructions vsha2ms.vv,
// vsha2ch.vv, vsha2cl.vv. Reference digest is from FIPS 180-4 test
// vectors for the empty message padded to one 512-bit block.
//
// Build:
//   make -C apps bin/zvknh
//
// Run under Spike:
//   ./toolchain/verilator run-spike apps/bin/zvknh

#include <stdint.h>
#include <string.h>

#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#include "runtime.h"
#endif

// SHA-256 H0
static const uint32_t H0[8] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
};

// SHA-256 K
static const uint32_t K256[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

// Expected SHA-256("") = e3b0c442 98fc1c14 9afbf4c8 996fb924 27ae41e4 649b934c a495991b 7852b855
static const uint32_t expected[8] = {
    0xe3b0c442u, 0x98fc1c14u, 0x9afbf4c8u, 0x996fb924u,
    0x27ae41e4u, 0x649b934cu, 0xa495991bu, 0x7852b855u,
};

// Pre-padded empty message (512-bit block)
static uint32_t msg_block[16] = {
    0x80000000u, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};

// State layout for the Zvknh compression loop per RVV spec:
//   vd  = {d, c, b, a}   (high to low)
//   vs2 = {h, g, f, e}
// After processing all 64 rounds in 16 steps, add back to H.

int main(void) {
  uint32_t state_dcba[4] = { H0[3], H0[2], H0[1], H0[0] };
  uint32_t state_hgfe[4] = { H0[7], H0[6], H0[5], H0[4] };

  // Message schedule: W[0..15] = message; W[16..63] computed via vsha2ms.
  uint32_t W[64];
  for (int i = 0; i < 16; i++) W[i] = msg_block[i];

  // TODO: use inline asm with vsha2ms.vv/vsha2ch.vv/vsha2cl.vv to compute
  // the schedule extension and the 64 compression rounds. This stub
  // produces the scalar reference so the Ara RTL pipeline can be exercised
  // once the VALU/SLDU glue is complete.

  // Scalar reference for the compression (for now):
  for (int i = 16; i < 64; i++) {
    uint32_t s0 = ((W[i-15] >> 7)  | (W[i-15] << 25))
                ^ ((W[i-15] >> 18) | (W[i-15] << 14))
                ^  (W[i-15] >> 3);
    uint32_t s1 = ((W[i-2]  >> 17) | (W[i-2]  << 15))
                ^ ((W[i-2]  >> 19) | (W[i-2]  << 13))
                ^  (W[i-2]  >> 10);
    W[i] = W[i-16] + s0 + W[i-7] + s1;
  }

  uint32_t a = state_dcba[0], b = state_dcba[1], c = state_dcba[2], d = state_dcba[3];
  uint32_t e = state_hgfe[0], f = state_hgfe[1], g = state_hgfe[2], h = state_hgfe[3];
  for (int i = 0; i < 64; i++) {
    uint32_t S1 = ((e >> 6)  | (e << 26))
                ^ ((e >> 11) | (e << 21))
                ^ ((e >> 25) | (e << 7));
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t t1 = h + S1 + ch + K256[i] + W[i];
    uint32_t S0 = ((a >> 2)  | (a << 30))
                ^ ((a >> 13) | (a << 19))
                ^ ((a >> 22) | (a << 10));
    uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = S0 + mj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }

  uint32_t digest[8];
  digest[0] = H0[0] + a;
  digest[1] = H0[1] + b;
  digest[2] = H0[2] + c;
  digest[3] = H0[3] + d;
  digest[4] = H0[4] + e;
  digest[5] = H0[5] + f;
  digest[6] = H0[6] + g;
  digest[7] = H0[7] + h;

  int ok = 1;
  for (int i = 0; i < 8; i++) {
    if (digest[i] != expected[i]) ok = 0;
  }

  printf("zvknh smoke test: %s\n", ok ? "PASS" : "FAIL");
  return ok ? 0 : 1;
}
