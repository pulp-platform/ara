// Zvkned single-instruction debug test
// Select which instruction to test by defining exactly one of:
//   TEST_VAESZ, TEST_VAESEM, TEST_VAESEF, TEST_VAESDM, TEST_VAESDF, TEST_VAESKF1
// Default: TEST_VAESEM
//
// All vectors from NIST FIPS 197 Appendix B (AES-128), verified by gen_test_vectors.py

#include <stdint.h>
#ifndef SPIKE
#include "printf.h"
#include "runtime.h"
#endif

// Default to TEST_VAESEM if nothing is defined
#if !defined(TEST_VAESZ)   && !defined(TEST_VAESEM)  && !defined(TEST_VAESEF) && \
    !defined(TEST_VAESDM)  && !defined(TEST_VAESDF)  && !defined(TEST_VAESKF1)
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

// State after vaesz.vs (plaintext XOR rk0)
static uint32_t state_after_rk0[4] __attribute__((aligned(16))) = {
    0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9
};

static uint32_t buf[4] __attribute__((aligned(16)));

// ── Per-instruction test data ────────────────────────────────────────────────

#ifdef TEST_VAESZ
// vaesz.vs: vd = plaintext, vs2 = RK0 → state_after_rk0
static uint32_t *vd_data   = plaintext;
static uint32_t *vs2_data  = rk0;
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xbee33d19, 0x2be2f4a0, 0x2a8dc69a, 0x0848f8e9
};
static const char *test_name = "vaesz.vs";
#endif

#ifdef TEST_VAESEM
// vaesem.vv: vd = state_after_rk0, vs2 = RK1 → round 1 state
static uint32_t *vd_data   = state_after_rk0;
static uint32_t *vs2_data  = rk1;
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xf27f9ca4, 0x2b359f68, 0x43ea5b6b, 0x49506a02
};
static const char *test_name = "vaesem.vv";
#endif

#ifdef TEST_VAESEF
// vaesef.vv: vd = state_after_rk0, vs2 = RK1 (standalone final-round test)
static uint32_t *vd_data   = state_after_rk0;
static uint32_t *vs2_data  = rk1;
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x27a34574, 0x1f7ee068, 0xc828e29b, 0xe0ee4b34
};
static const char *test_name = "vaesef.vv";
#endif

#ifdef TEST_VAESDM
// vaesdm.vv: vd = round1 encrypt result, vs2 = RK1
static uint32_t vaesdm_input[4] __attribute__((aligned(16))) = {
    0xf27f9ca4, 0x2b359f68, 0x43ea5b6b, 0x49506a02
};
static uint32_t *vd_data   = vaesdm_input;
static uint32_t *vs2_data  = rk1;
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xcb7af90e, 0x1d48df28, 0xb403ac3f, 0x4c5ec700
};
static const char *test_name = "vaesdm.vv";
#endif

#ifdef TEST_VAESDF
// vaesdf.vv: vd = vaesef result, vs2 = RK1
static uint32_t vaesdf_input[4] __attribute__((aligned(16))) = {
    0x27a34574, 0x1f7ee068, 0xc828e29b, 0xe0ee4b34
};
static uint32_t *vd_data   = vaesdf_input;
static uint32_t *vs2_data  = rk1;
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0xdc10366a, 0x00b53c7f, 0x994803cb, 0x38fc5702
};
static const char *test_name = "vaesdf.vv";
#endif

#ifdef TEST_VAESKF1
// vaeskf1.vi: vs2 = RK0, rnum = 1 → RK1
static uint32_t *vd_data   = rk0;
static uint32_t *vs2_data  = rk0; // unused for vaeskf1, but load for register setup
static uint32_t expected[4] __attribute__((aligned(16))) = {
    0x17fefaa0, 0xb12c5488, 0x3939a323, 0x05766c2a
};
static const char *test_name = "vaeskf1.vi";
#endif

// ── Main ─────────────────────────────────────────────────────────────────────

int main(void) {
    printf("Zvkned debug: %s\n", test_name);

    unsigned long vl;
    asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(4));
    printf("VL = %ld\n", (long)vl);

    // Load operands: v4 = vd, v2 = vs2
    asm volatile("vle32.v v4, (%0)" :: "r"(vd_data));
    asm volatile("vle32.v v2, (%0)" :: "r"(vs2_data));

    // Verify loads
    asm volatile("vse32.v v4, (%0)" :: "r"(buf) : "memory");
    printf("v4 (vd):  %08x %08x %08x %08x\n",
           (unsigned)buf[0], (unsigned)buf[1],
           (unsigned)buf[2], (unsigned)buf[3]);
    asm volatile("vse32.v v2, (%0)" :: "r"(buf) : "memory");
    printf("v2 (vs2): %08x %08x %08x %08x\n",
           (unsigned)buf[0], (unsigned)buf[1],
           (unsigned)buf[2], (unsigned)buf[3]);

    // Execute the instruction under test
    printf("executing %s...\n", test_name);
#ifdef TEST_VAESZ
    asm volatile("vaesz.vs v4, v2");
#elif defined(TEST_VAESEM)
    asm volatile("vaesem.vv v4, v2");
#elif defined(TEST_VAESEF)
    asm volatile("vaesef.vv v4, v2");
#elif defined(TEST_VAESDM)
    asm volatile("vaesdm.vv v4, v2");
#elif defined(TEST_VAESDF)
    asm volatile("vaesdf.vv v4, v2");
#elif defined(TEST_VAESKF1)
    asm volatile("vaeskf1.vi v4, v2, 1");
#endif

    // Store result
    asm volatile("vse32.v v4, (%0)" :: "r"(buf) : "memory");

    printf("result:   %08x %08x %08x %08x\n",
           (unsigned)buf[0], (unsigned)buf[1],
           (unsigned)buf[2], (unsigned)buf[3]);
    printf("expected: %08x %08x %08x %08x\n",
           (unsigned)expected[0], (unsigned)expected[1],
           (unsigned)expected[2], (unsigned)expected[3]);

    int ok = (buf[0] == expected[0] && buf[1] == expected[1] &&
              buf[2] == expected[2] && buf[3] == expected[3]);

    printf("%s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
