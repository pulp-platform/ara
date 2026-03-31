// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES-128 ECB correctness test using RISC-V Zvkned vector crypto extension.
// Test vectors from NIST FIPS 197, Appendix A.1 (key schedule) and
// Appendix B (encrypt/decrypt).

#include <stdint.h>
#include <string.h>

#ifdef SPIKE
#include <stdio.h>
#else
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

// Realistic standalone instruction operands/results derived from the FIPS 197
// AES-128 known-answer test. These let the suite validate each instruction in
// isolation before checking the full encrypt/decrypt flow.
static const uint32_t state_after_rk0[4] = {
    0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9
};

static const uint32_t state_after_round1[4] = {
    0xf27f9ca4, 0x2b359f68, 0x43ea5b6b, 0x49506a02
};

static const uint32_t state_after_round9[4] = {
    0x1ef240eb, 0x84382e59, 0xe713a18b, 0xd242c31b
};

static const uint32_t state_after_ct_rk10[4] = {
    0xb57d31e9, 0x722c32cb, 0x5f892e3d, 0x940709af
};

static const uint32_t state_after_inv_round9[4] = {
    0xa6466e87, 0x8ce74cf2, 0xd84a904d, 0x95c3ec97
};

static const uint32_t state_before_final_decrypt[4] = {
    0x305dbfd4, 0xae52b4e0, 0xf11141b8, 0xe598271e
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
static uint32_t result[4]        __attribute__((aligned(16)));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static int cmp128(const uint32_t *got, const uint32_t *exp, const char *tag) {
    uint32_t got_snapshot[4];
    uint32_t exp_snapshot[4];
    int err = 0;
    for (int i = 0; i < 4; i++) {
        got_snapshot[i] = got[i];
        exp_snapshot[i] = exp[i];
    }
    for (int i = 0; i < 4; i++) {
        if (got_snapshot[i] != exp_snapshot[i]) {
            printf("  %s[%d]: got 0x%x, exp 0x%x\n", tag, i,
                   (unsigned)got_snapshot[i], (unsigned)exp_snapshot[i]);
            err = 1;
        }
    }
    return err;
}

static void set_vl_128(void) {
    unsigned long vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
}

static void store_result(void) {
    asm volatile("vse32.v v4, (%0)" :: "r"(result) : "memory");
}

static void prepare_operands(const uint32_t *vd_in, const uint32_t *vs2_in,
                             uint32_t *vd_words, uint32_t *vs2_words) {
    for (int i = 0; i < 4; i++) {
        vd_words[i] = vd_in[i];
        vs2_words[i] = vs2_in[i];
    }
}

static void load_vd_vs2(const uint32_t *vd_words, const uint32_t *vs2_words) {
    asm volatile("vle32.v v4, (%0)" :: "r"(vd_words) : "memory");
    asm volatile("vle32.v v2, (%0)" :: "r"(vs2_words) : "memory");
}

// ---------------------------------------------------------------------------
// Test 1 – vaeskf1.vi  (AES-128 key schedule, rounds 1‥10)
// ---------------------------------------------------------------------------
static int test_key_schedule(void) {
    uint32_t round_keys[11][4] __attribute__((aligned(16)));
    int fail = 0;
    printf("Test 1: vaeskf1 (key schedule)\n");

    // Copy RK0
    for (int i = 0; i < 4; i++) round_keys[0][i] = aes128_key[i];

    // Set VL=4, SEW=32, LMUL=1  (one 128-bit element group)
    set_vl_128();

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
// Tests 2-9 – Single-instruction checks with realistic AES round-state inputs
// ---------------------------------------------------------------------------
static int test_vaesz_vs(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 2: vaesz.vs\n");
    set_vl_128();
    prepare_operands(plaintext, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");
    store_result();
    if (cmp128(result, state_after_rk0, "RK0")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesem_vv(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 3: vaesem.vv\n");
    set_vl_128();
    prepare_operands(state_after_rk0, expected_rk[1], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesem.vv v4, v2");
    store_result();
    if (cmp128(result, state_after_round1, "R1")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesem_vs(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 4: vaesem.vs\n");
    set_vl_128();
    prepare_operands(state_after_rk0, expected_rk[1], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesem.vs v4, v2");
    store_result();
    if (cmp128(result, state_after_round1, "R1")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesef_vv(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 5: vaesef.vv\n");
    set_vl_128();
    prepare_operands(state_after_round9, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesef.vv v4, v2");
    store_result();
    if (cmp128(result, expected_ct, "CT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesef_vs(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 6: vaesef.vs\n");
    set_vl_128();
    prepare_operands(state_after_round9, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesef.vs v4, v2");
    store_result();
    if (cmp128(result, expected_ct, "CT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesdm_vv(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 7: vaesdm.vv\n");
    set_vl_128();
    prepare_operands(state_after_ct_rk10, expected_rk[9], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdm.vv v4, v2");
    store_result();
    if (cmp128(result, state_after_inv_round9, "R9")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesdm_vs(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 8: vaesdm.vs\n");
    set_vl_128();
    prepare_operands(state_after_ct_rk10, expected_rk[9], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdm.vs v4, v2");
    store_result();
    if (cmp128(result, state_after_inv_round9, "R9")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesdf_vv(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 9: vaesdf.vv\n");
    set_vl_128();
    prepare_operands(state_before_final_decrypt, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdf.vv v4, v2");
    store_result();
    if (cmp128(result, plaintext, "PT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

static int test_vaesdf_vs(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 10: vaesdf.vs\n");
    set_vl_128();
    prepare_operands(state_before_final_decrypt, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdf.vs v4, v2");
    store_result();
    if (cmp128(result, plaintext, "PT")) {
        printf("  FAIL\n");
        return 1;
    }
    printf("  PASSED\n");
    return 0;
}

// ---------------------------------------------------------------------------
// Test 11 – AES-128 encryption  (vaesz.vs + vaesem.vv×9 + vaesef.vv)
// ---------------------------------------------------------------------------
static int test_encrypt_vv(void) {
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 11: AES-128 encrypt (.vv)\n");

    set_vl_128();
    prepare_operands(plaintext, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");
    for (int i = 1; i <= 9; i++) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesem.vv v4, v2");
    }
    store_result();
    prepare_operands(result, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesef.vv v4, v2");
    store_result();

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
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 12: AES-128 decrypt (.vv)\n");

    set_vl_128();
    prepare_operands(expected_ct, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");

    // Rounds 9‥1: decrypt middle (reverse key order)
    for (int i = 9; i >= 1; i--) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesdm.vv v4, v2");
    }

    // Final round: decrypt final with RK0
    store_result();
    prepare_operands(result, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdf.vv v4, v2");
    store_result();

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
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 13: AES-128 encrypt (.vs)\n");

    set_vl_128();
    prepare_operands(plaintext, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");

    // Rounds 1‥9
    for (int i = 1; i <= 9; i++) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesem.vs v4, v2");
    }

    // Round 10
    store_result();
    prepare_operands(result, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesef.vs v4, v2");
    store_result();

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
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 14: AES-128 decrypt (.vs)\n");

    set_vl_128();
    prepare_operands(expected_ct, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");

    for (int i = 9; i >= 1; i--) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesdm.vs v4, v2");
    }

    store_result();
    prepare_operands(result, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdf.vs v4, v2");
    store_result();

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
    uint32_t vd_words[4] __attribute__((aligned(16)));
    uint32_t vs2_words[4] __attribute__((aligned(16)));

    printf("Test 15: encrypt-then-decrypt round-trip\n");

    set_vl_128();

    // Encrypt
    prepare_operands(plaintext, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");
    for (int i = 1; i <= 9; i++) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesem.vv v4, v2");
    }
    store_result();
    prepare_operands(result, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesef.vv v4, v2");

    // Decrypt (v4 still holds the ciphertext)
    store_result();
    prepare_operands(result, expected_rk[10], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesz.vs v4, v2");
    for (int i = 9; i >= 1; i--) {
        store_result();
        prepare_operands(result, expected_rk[i], vd_words, vs2_words);
        load_vd_vs2(vd_words, vs2_words);
        asm volatile("vaesdm.vv v4, v2");
    }
    store_result();
    prepare_operands(result, expected_rk[0], vd_words, vs2_words);
    load_vd_vs2(vd_words, vs2_words);
    asm volatile("vaesdf.vv v4, v2");
    store_result();

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
    num_failed += test_vaesz_vs();
    num_failed += test_vaesem_vv();
    num_failed += test_vaesem_vs();
    num_failed += test_vaesef_vv();
    num_failed += test_vaesef_vs();
    num_failed += test_vaesdm_vv();
    num_failed += test_vaesdm_vs();
    num_failed += test_vaesdf_vv();
    num_failed += test_vaesdf_vs();
    num_failed += test_encrypt_vv();
    num_failed += test_decrypt_vv();
    num_failed += test_encrypt_vs();
    num_failed += test_decrypt_vs();
    num_failed += test_roundtrip();

    printf("\n=== Summary: %d test(s) failed ===\n", num_failed);
    return num_failed;
}
