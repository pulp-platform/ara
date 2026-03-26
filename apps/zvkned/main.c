// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES-128 ECB correctness test using RISC-V Zvkned vector crypto extension.
// Test vectors from NIST FIPS 197, Appendix A.1 (key schedule) and
// Appendix B (encrypt/decrypt).

#include <stdint.h>
#include <string.h>

#ifndef SPIKE
#include "printf.h"
#include "runtime.h"
#endif

// ---------------------------------------------------------------------------
// NIST FIPS 197 test vectors – stored as little-endian uint32_t words.
//
// Conversion: each big-endian 32-bit column word 0xAABBCCDD becomes the
// uint32_t literal 0xDDCCBBAA on a little-endian machine, because byte 0xAA
// sits at the lowest address (bits [7:0]).
// ---------------------------------------------------------------------------

// Key: 2b7e1516 28aed2a6 abf71588 09cf4f3c
static const uint32_t aes128_key[4] __attribute__((aligned(16))) = {
    0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09
};

// Plaintext: 3243f6a8 885a308d 313198a2 e0370734
static const uint32_t plaintext[4] __attribute__((aligned(16))) = {
    0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0
};

// Expected ciphertext: 3925841d 02dc09fb dc118597 196a0b32
static const uint32_t expected_ct[4] = {
    0x1d842539, 0xfb09dc02, 0x978511dc, 0x320b6a19
};

// All 11 AES-128 round keys (from FIPS 197 Appendix A.1), LE uint32_t.
static const uint32_t expected_rk[11][4] = {
    {0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09}, // RK 0
    {0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a}, // RK 1
    {0xf295c2f2, 0x43b9967a, 0x7a803559, 0x7ff65973}, // RK 2
    {0x7d47803d, 0x3efe1647, 0x447e231e, 0x3b887a6d}, // RK 3
    {0x41a544ef, 0x7f5b52a8, 0x3b2571b6, 0x00ad0bdb}, // RK 4
    {0xf8c6d1d4, 0x879d837c, 0xbcb8f2ca, 0xbc15f911}, // RK 5
    {0x7aa3886d, 0xfd3e0b11, 0x4186f9db, 0xfd9300ca}, // RK 6
    {0x0ef7544e, 0xf3c95f5f, 0xb24fa684, 0x4fdca64e}, // RK 7
    {0x2173d2ea, 0xd2ba8db5, 0x60f52b31, 0x2f298d7f}, // RK 8
    {0xf36677ac, 0x21dcfa19, 0x4129d128, 0x6e005c57}, // RK 9
    {0xa8f914d0, 0x8925eec9, 0xc80c3fe1, 0xa60c63b6}, // RK10
};

// ---------------------------------------------------------------------------
// Working buffers
// ---------------------------------------------------------------------------
static uint32_t round_keys[11][4] __attribute__((aligned(16)));
static uint32_t result[4]        __attribute__((aligned(16)));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static int cmp128(const uint32_t *got, const uint32_t *exp, const char *tag) {
    int err = 0;
    for (int i = 0; i < 4; i++) {
        if (got[i] != exp[i]) {
            printf("  %s[%d]: got 0x%x, exp 0x%x\n", tag, i,
                   (unsigned)got[i], (unsigned)exp[i]);
            err = 1;
        }
    }
    return err;
}

// ---------------------------------------------------------------------------
// Test 1 – vaeskf1.vi  (AES-128 key schedule, rounds 1‥10)
// ---------------------------------------------------------------------------
static int test_key_schedule(void) {
    int fail = 0;
    printf("Test 1: vaeskf1 (key schedule)\n");

    // Copy RK0
    for (int i = 0; i < 4; i++) round_keys[0][i] = aes128_key[i];

    // Set VL=4, SEW=32, LMUL=1  (one 128-bit element group)
    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    // Load RK0 → v2
    asm volatile("vle32.v v2, (%0)" :: "r"(round_keys[0]));

    // Generate round keys 1‥10, alternating v2↔v4 to avoid WAR hazards.
    // Round number is an immediate, so we must unroll.
    asm volatile("vaeskf1.vi v4, v2, 1");
    asm volatile("vse32.v v4, (%0)" :: "r"(round_keys[1]) : "memory");

    asm volatile("vaeskf1.vi v2, v4, 2");
    asm volatile("vse32.v v2, (%0)" :: "r"(round_keys[2]) : "memory");

    asm volatile("vaeskf1.vi v4, v2, 3");
    asm volatile("vse32.v v4, (%0)" :: "r"(round_keys[3]) : "memory");

    asm volatile("vaeskf1.vi v2, v4, 4");
    asm volatile("vse32.v v2, (%0)" :: "r"(round_keys[4]) : "memory");

    asm volatile("vaeskf1.vi v4, v2, 5");
    asm volatile("vse32.v v4, (%0)" :: "r"(round_keys[5]) : "memory");

    asm volatile("vaeskf1.vi v2, v4, 6");
    asm volatile("vse32.v v2, (%0)" :: "r"(round_keys[6]) : "memory");

    asm volatile("vaeskf1.vi v4, v2, 7");
    asm volatile("vse32.v v4, (%0)" :: "r"(round_keys[7]) : "memory");

    asm volatile("vaeskf1.vi v2, v4, 8");
    asm volatile("vse32.v v2, (%0)" :: "r"(round_keys[8]) : "memory");

    asm volatile("vaeskf1.vi v4, v2, 9");
    asm volatile("vse32.v v4, (%0)" :: "r"(round_keys[9]) : "memory");

    asm volatile("vaeskf1.vi v2, v4, 10");
    asm volatile("vse32.v v2, (%0)" :: "r"(round_keys[10]) : "memory");

    for (int i = 0; i < 11; i++) {
        if (cmp128(round_keys[i], expected_rk[i], "RK")) {
            printf("  FAIL round key %d\n", i);
            fail++;
        }
    }
    if (!fail) printf("  PASSED (all 11 round keys)\n");
    return fail;
}

// ---------------------------------------------------------------------------
// Test 2 – AES-128 encryption  (vaesz.vs + vaesem.vv×9 + vaesef.vv)
// ---------------------------------------------------------------------------
static int test_encrypt_vv(void) {
    printf("Test 2: AES-128 encrypt (.vv)\n");

    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    // v4 = plaintext (state)
    asm volatile("vle32.v v4, (%0)" :: "r"(plaintext));

    // Round 0: AddRoundKey
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesz.vs v4, v8");

    // Rounds 1‥9: encrypt middle
    for (int i = 1; i <= 9; i++) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesem.vv v4, v8");
    }

    // Round 10: encrypt final
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesef.vv v4, v8");

    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");

    if (cmp128(result, expected_ct, "CT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Test 3 – AES-128 decryption  (vaesz.vs + vaesdm.vv×9 + vaesdf.vv)
// Uses the standard inverse cipher ordering with unmodified round keys.
// ---------------------------------------------------------------------------
static int test_decrypt_vv(void) {
    printf("Test 3: AES-128 decrypt (.vv)\n");

    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    // v4 = ciphertext (state)  — use the encrypted result from Test 2
    asm volatile("vle32.v v4, (%0)" :: "r"(expected_ct));

    // Round 0: AddRoundKey with last round key
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesz.vs v4, v8");

    // Rounds 9‥1: decrypt middle (reverse key order)
    for (int i = 9; i >= 1; i--) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesdm.vv v4, v8");
    }

    // Final round: decrypt final with RK0
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesdf.vv v4, v8");

    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");

    if (cmp128(result, plaintext, "PT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Test 4 – AES-128 encryption with .vs variants
// The .vs instructions broadcast the key from element-group 0 of vs2.
// With VL=4 (one element group) the result must match the .vv test.
// ---------------------------------------------------------------------------
static int test_encrypt_vs(void) {
    printf("Test 4: AES-128 encrypt (.vs)\n");

    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    // v4 = plaintext
    asm volatile("vle32.v v4, (%0)" :: "r"(plaintext));

    // Round 0
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesz.vs v4, v8");

    // Rounds 1‥9
    for (int i = 1; i <= 9; i++) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesem.vs v4, v8");
    }

    // Round 10
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesef.vs v4, v8");

    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");

    if (cmp128(result, expected_ct, "CT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Test 5 – AES-128 decryption with .vs variants
// ---------------------------------------------------------------------------
static int test_decrypt_vs(void) {
    printf("Test 5: AES-128 decrypt (.vs)\n");

    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    asm volatile("vle32.v v4, (%0)" :: "r"(expected_ct));

    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesz.vs v4, v8");

    for (int i = 9; i >= 1; i--) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesdm.vs v4, v8");
    }

    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesdf.vs v4, v8");

    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");

    if (cmp128(result, plaintext, "PT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Test 6 – Round-trip: encrypt then decrypt must recover plaintext
// ---------------------------------------------------------------------------
static int test_roundtrip(void) {
    printf("Test 6: encrypt-then-decrypt round-trip\n");

    asm volatile("vsetvli t0, %0, e32, m1, ta, ma" :: "r"(4));

    // Encrypt
    asm volatile("vle32.v v4, (%0)" :: "r"(plaintext));
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesz.vs v4, v8");
    for (int i = 1; i <= 9; i++) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesem.vv v4, v8");
    }
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesef.vv v4, v8");

    // Decrypt (v4 still holds the ciphertext)
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[10]));
    asm volatile("vaesz.vs v4, v8");
    for (int i = 9; i >= 1; i--) {
        asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[i]));
        asm volatile("vaesdm.vv v4, v8");
    }
    asm volatile("vle32.v v8, (%0)" :: "r"(round_keys[0]));
    asm volatile("vaesdf.vv v4, v8");

    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");

    if (cmp128(result, plaintext, "RT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
int main(void) {
    int num_failed = 0;

    printf("=== Zvkned AES-128 Test Suite ===\n\n");

    num_failed += test_key_schedule();
    num_failed += test_encrypt_vv();
    num_failed += test_decrypt_vv();
    num_failed += test_encrypt_vs();
    num_failed += test_decrypt_vs();
    num_failed += test_roundtrip();

    printf("\n=== Summary: %d test(s) failed ===\n", num_failed);
    return num_failed;
}
