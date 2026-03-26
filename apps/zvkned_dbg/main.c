// Zvkned single-instruction debug test
// Select which instruction to test by defining exactly one of:
//   TEST_VAESZ, TEST_VAESEM, TEST_VAESEM_VS, TEST_VAESEF, TEST_VAESEF_VS,
//   TEST_VAESDM, TEST_VAESDM_VS, TEST_VAESDF, TEST_VAESDF_VS,
//   TEST_VAESKF1, TEST_VAESKF2_EVEN, TEST_VAESKF2_ODD
// Default: TEST_VAESZ
//
// AES-128 vectors from NIST FIPS 197 Appendix B, verified by gen_test_vectors.py
// AES-256 vectors from NIST FIPS 197 Appendix A.3 (vaeskf2 tests)

#include <stdint.h>

#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#include "runtime.h"
#endif

// Default to TEST_VAESZ if nothing is defined
#if !defined(TEST_VAESZ)      && !defined(TEST_VAESEM)     && \
    !defined(TEST_VAESEM_VS)  && !defined(TEST_VAESEF)     && \
    !defined(TEST_VAESEF_VS)  && !defined(TEST_VAESDM)     && \
    !defined(TEST_VAESDM_VS)  && !defined(TEST_VAESDF)     && \
    !defined(TEST_VAESDF_VS)  && !defined(TEST_VAESKF1)    && \
    !defined(TEST_VAESKF2_EVEN) && !defined(TEST_VAESKF2_ODD)
#define TEST_VAESZ
#endif

// FIPS 197 Appendix B, AES-128 key (LE uint32)
// BE: 2b7e1516 28aed2a6 abf71588 09cf4f3c
static uint32_t rk0[4] __attribute__((aligned(16))) = {
    0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09
};

// FIPS 197 Appendix B, AES-128 plaintext (LE uint32)
// BE: 3243f6a8 885a308d 313198a2 e0370734
static uint32_t plaintext[4] __attribute__((aligned(16))) = {
    0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0
};

// Round key 1 (from vaeskf1 round 1)
static uint32_t rk1[4] __attribute__((aligned(16))) = {
    0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a
};

// Round key 9
static uint32_t rk9[4] __attribute__((aligned(16))) = {
    0xf36677ac, 0x21dcfa19, 0x4129d128, 0x6e005c57
};

// Round key 10
static uint32_t rk10[4] __attribute__((aligned(16))) = {
    0xa8f914d0, 0x8925eec9, 0xc80c3fe1, 0xa60c63b6
};

// State after vaesz.vs (plaintext XOR rk0)
static uint32_t state_after_rk0[4] __attribute__((aligned(16))) = {
    0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9
};

// ── Per-instruction test data ────────────────────────────────────────────────

#ifdef TEST_VAESZ
// vaesz.vs: vd = plaintext, vs2 = RK0 → state_after_rk0
#define VD_DATA plaintext
#define VS2_DATA rk0
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9
};
static const char *test_name = "vaesz.vs";
#endif

#if defined(TEST_VAESEM) || defined(TEST_VAESEM_VS)
// vaesem: vd = state_after_rk0, vs2 = RK1 → round 1 state
#define VD_DATA state_after_rk0
#define VS2_DATA rk1
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xf27f9ca4, 0x2b359f68, 0x43ea5b6b, 0x49506a02
};
#ifdef TEST_VAESEM
static const char *test_name = "vaesem.vv";
#else
static const char *test_name = "vaesem.vs";
#endif
#endif

#if defined(TEST_VAESEF) || defined(TEST_VAESEF_VS)
// State after encrypt round 9.
static uint32_t state_after_round9[4] __attribute__((aligned(16))) = {
    0x1ef240eb, 0x84382e59, 0xe713a18b, 0xd242c31b
};

// vaesef: vd = state after round 9, vs2 = RK10
#define VD_DATA state_after_round9
#define VS2_DATA rk10
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x1d842539, 0xfb09dc02, 0x978511dc, 0x320b6a19
};
#ifdef TEST_VAESEF
static const char *test_name = "vaesef.vv";
#else
static const char *test_name = "vaesef.vs";
#endif
#endif

#if defined(TEST_VAESDM) || defined(TEST_VAESDM_VS)
// State after ciphertext xor RK10, matching the first decrypt middle round.
static uint32_t state_after_ct_rk10[4] __attribute__((aligned(16))) = {
    0xb57d31e9, 0x722c32cb, 0x5f892e3d, 0x940709af
};

// vaesdm: vd = ciphertext xor RK10, vs2 = RK9
#define VD_DATA state_after_ct_rk10
#define VS2_DATA rk9
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xa6466e87, 0x8ce74cf2, 0xd84a904d, 0x95c3ec97
};
#ifdef TEST_VAESDM
static const char *test_name = "vaesdm.vv";
#else
static const char *test_name = "vaesdm.vs";
#endif
#endif

#if defined(TEST_VAESDF) || defined(TEST_VAESDF_VS)
// State after inverse round 1, matching the final decrypt round.
static uint32_t state_before_final_decrypt[4] __attribute__((aligned(16))) = {
    0x305dbfd4, 0xae52b4e0, 0xf11141b8, 0xe598271e
};

// vaesdf: vd = state after inverse round 1, vs2 = RK0
#define VD_DATA state_before_final_decrypt
#define VS2_DATA rk0
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xa8f64332, 0x8d305a88, 0xa2983131, 0x340737e0
};
#ifdef TEST_VAESDF
static const char *test_name = "vaesdf.vv";
#else
static const char *test_name = "vaesdf.vs";
#endif
#endif

#ifdef TEST_VAESKF1
// vaeskf1.vi: vs2 = RK0, rnum = 1 → RK1
#define VD_DATA rk0
#define VS2_DATA rk0 // unused for vaeskf1, but load for register setup
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a
};
static const char *test_name = "vaeskf1.vi";
#endif

#if defined(TEST_VAESKF2_EVEN) || defined(TEST_VAESKF2_ODD)
// ── AES-256 key schedule test data (FIPS 197 Appendix A.3) ───────────────────
// Key: 603deb10 15ca71be 2b73aef0 857d7781 1f352c07 3b6108d7 2d9810a3 0914dff4

// AES-256 RK0 (key bits 0-127)
static uint32_t rk256_0[4] __attribute__((aligned(16))) = {
    0x10eb3d60, 0xbe71ca15, 0xf0ae732b, 0x81777d85
};
// AES-256 RK1 (key bits 128-255)
static uint32_t rk256_1[4] __attribute__((aligned(16))) = {
    0x072c351f, 0xd708613b, 0xa310982d, 0xf4df1409
};
// AES-256 RK2 (vaeskf2 rnum=2, even round)
static uint32_t rk256_2[4] __attribute__((aligned(16))) = {
    0x1154a39b, 0xaf25698e, 0x5f8b1aa5, 0xdefc6720
};
// AES-256 RK3 (vaeskf2 rnum=3, odd round)
static uint32_t rk256_3[4] __attribute__((aligned(16))) = {
    0x1a9cb0a8, 0xcd94d193, 0x6e8449be, 0x9a5b5db7
};
#endif

#ifdef TEST_VAESKF2_EVEN
// vaeskf2.vi rnum=2 (even): vd = RK0, vs2 = RK1 → RK2
#define VD_DATA rk256_0
#define VS2_DATA rk256_1
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x1154a39b, 0xaf25698e, 0x5f8b1aa5, 0xdefc6720
};
static const char *test_name = "vaeskf2.vi rnum=2 (even)";
#endif

#ifdef TEST_VAESKF2_ODD
// vaeskf2.vi rnum=3 (odd): vd = RK1, vs2 = RK2 → RK3
#define VD_DATA rk256_1
#define VS2_DATA rk256_2
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x1a9cb0a8, 0xcd94d193, 0x6e8449be, 0x9a5b5db7
};
static const char *test_name = "vaeskf2.vi rnum=3 (odd)";
#endif

// ── Main ─────────────────────────────────────────────────────────────────────

int main(void) {
    uint32_t vd_words[4];
    uint32_t vs2_words[4];
    uint32_t expected_words[4];
    uint32_t result_words[4];

    for (int i = 0; i < 4; i++) {
        vd_words[i] = VD_DATA[i];
        vs2_words[i] = VS2_DATA[i];
        expected_words[i] = expected[i];
    }

    printf("Zvkned debug: %s\n", test_name);

    unsigned long vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    printf("VL = %ld\n", (long)vl);
    printf("scalar vd:  %08x %08x %08x %08x\n",
           (unsigned)vd_words[0], (unsigned)vd_words[1],
           (unsigned)vd_words[2], (unsigned)vd_words[3]);
    printf("scalar vs2: %08x %08x %08x %08x\n",
           (unsigned)vs2_words[0], (unsigned)vs2_words[1],
           (unsigned)vs2_words[2], (unsigned)vs2_words[3]);

    // Load operands: v4 = vd, v2 = vs2
    asm volatile("vle32.v v4, (%0)" :: "r"(vd_words));
    asm volatile("vle32.v v2, (%0)" :: "r"(vs2_words));

    // Verify loads
    asm volatile("vse32.v v4, (%0)" :: "r"(result_words) : "memory");
    printf("v4 (vd):  %08x %08x %08x %08x\n",
           (unsigned)result_words[0], (unsigned)result_words[1],
           (unsigned)result_words[2], (unsigned)result_words[3]);
    asm volatile("vse32.v v2, (%0)" :: "r"(result_words) : "memory");
    printf("v2 (vs2): %08x %08x %08x %08x\n",
           (unsigned)result_words[0], (unsigned)result_words[1],
           (unsigned)result_words[2], (unsigned)result_words[3]);

    // Execute the instruction under test
    printf("executing %s...\n", test_name);
#ifdef TEST_VAESZ
    asm volatile("vaesz.vs v4, v2");
#elif defined(TEST_VAESEM)
    asm volatile("vaesem.vv v4, v2");
#elif defined(TEST_VAESEM_VS)
    asm volatile("vaesem.vs v4, v2");
#elif defined(TEST_VAESEF)
    asm volatile("vaesef.vv v4, v2");
#elif defined(TEST_VAESEF_VS)
    asm volatile("vaesef.vs v4, v2");
#elif defined(TEST_VAESDM)
    asm volatile("vaesdm.vv v4, v2");
#elif defined(TEST_VAESDM_VS)
    asm volatile("vaesdm.vs v4, v2");
#elif defined(TEST_VAESDF)
    asm volatile("vaesdf.vv v4, v2");
#elif defined(TEST_VAESDF_VS)
    asm volatile("vaesdf.vs v4, v2");
#elif defined(TEST_VAESKF1)
    asm volatile("vaeskf1.vi v4, v2, 1");
#elif defined(TEST_VAESKF2_EVEN)
    asm volatile("vaeskf2.vi v4, v2, 2");
#elif defined(TEST_VAESKF2_ODD)
    asm volatile("vaeskf2.vi v4, v2, 3");
#endif

    // Store result
    asm volatile("vse32.v v4, (%0)" :: "r"(result_words) : "memory");

    printf("result:   %08x %08x %08x %08x\n",
           (unsigned)result_words[0], (unsigned)result_words[1],
           (unsigned)result_words[2], (unsigned)result_words[3]);
    printf("expected: %08x %08x %08x %08x\n",
           (unsigned)expected_words[0], (unsigned)expected_words[1],
           (unsigned)expected_words[2], (unsigned)expected_words[3]);

    int ok = (result_words[0] == expected_words[0] &&
              result_words[1] == expected_words[1] &&
              result_words[2] == expected_words[2] &&
              result_words[3] == expected_words[3]);

    printf("%s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
