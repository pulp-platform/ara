// dgemm_rvv.c - hand-written RVV 1.0 intrinsic DGEMM engine (v3/v4/v5)
//
// Carried over from linpack-ara2/src/dgemm_rvv.c (26 macro-generated kernel
// instances). The intrinsics used (vsetvl/vle64/vfmacc.vf/vse64/vmv) are the
// standardized RVV 1.0 API and compile under both GCC and Clang/LLVM; both
// compilers reject arrays of sizeless vector types, hence the compile-time
// macro unrolling.
//
// Design mapped to the Ara2 microarchitecture (Perotti et al., IEEE TC 2024):
//  * Register blocking MR x VL: the C tile lives in vector registers across a
//    KC-deep k-panel, so each B vector element is reused MR times - matching
//    the VLSU bandwidth (4L B/cyc) to the FP64 FMA rate (2L FLOP/cyc).
//  * A-panel packing: At[kk][i] contiguous -> scalar unit-stride loads issued
//    by CVA6, keeping the vector load/store unit free for B streams.
//  * B streams unit-stride along j -> full VLSU burst bandwidth.
//  * Optional software pipelining (PIPE=1): prefetch B(k+1) before the MR-long
//    FMA chain of step k, hiding the memory latency behind FMA work.
//  * LMUL lengthens vectors: fewer instructions per element, relieving the
//    CVA6 issue-rate bound.
// Constraint: MR*LMUL accumulator groups must fit the 32-entry VRF
// (MR*LMUL + LMUL <= ~30), otherwise the compiler spills to memory.
//
// Ideal-Dispatcher note: this kernel is fire-and-forget vector code (no scalar
// reads of vector results), so `bin/linpack.ideal` timing is valid; results
// are meaningless in that mode because scalar packing never executes.
#include <riscv_vector.h>
#include "lp_compat.h"
#include "dgemm.h"

#define KC_MAX 256
#define MR_MAX 16
static double at_panel[KC_MAX * MR_MAX] __attribute__((aligned(64)));

static int g_mr = 4, g_lmul = 1, g_kc = 128, g_pipe = 0;

void dgemm_rvv_config(int mr, int lmul, int kc, int pipeline) {
    if (mr > 0 && mr <= MR_MAX) g_mr = mr;
    if (lmul == 1 || lmul == 2 || lmul == 4 || lmul == 8) g_lmul = lmul;
    if (kc > 0 && kc <= KC_MAX) g_kc = kc;
    g_pipe = pipeline ? 1 : 0;
}
int dgemm_rvv_current_mr(void)   { return g_mr; }
int dgemm_rvv_current_lmul(void) { return g_lmul; }
int dgemm_rvv_current_kc(void)   { return g_kc; }

#define CAT2_(a, b) a##b
#define CAT2(a, b) CAT2_(a, b)
#define CAT3_(a, b, c) a##b##c
#define CAT3(a, b, c) CAT3_(a, b, c)
#define CAT4_(a, b, c, d) a##b##c##d
#define CAT4(a, b, c, d) CAT4_(a, b, c, d)

// parameterized type/intrinsic selectors: LM is substituted at expansion site
#define VTT(LM)       CAT3(vfloat64m, LM, _t)
#define VSETVL(LM)    CAT2(__riscv_vsetvl_e64m, LM)
#define VSETVLMAX(LM) CAT2(__riscv_vsetvlmax_e64m, LM)
#define VLE64(LM)     CAT2(__riscv_vle64_v_f64m, LM)
#define VSE64(LM)     CAT2(__riscv_vse64_v_f64m, LM)
#define VFMACC(LM)    CAT2(__riscv_vfmacc_vf_f64m, LM)

// compile-time unroll helpers: statement macros receive (LM, MR, i)
#define STMTS_2(S, L, R)  S(L, R, 0) S(L, R, 1)
#define STMTS_4(S, L, R)  STMTS_2(S, L, R) S(L, R, 2) S(L, R, 3)
#define STMTS_8(S, L, R)  STMTS_4(S, L, R) S(L, R, 4) S(L, R, 5) S(L, R, 6) S(L, R, 7)
#define STMTS_16(S, L, R) STMTS_8(S, L, R) S(L, R, 8) S(L, R, 9) S(L, R, 10) S(L, R, 11) \
    S(L, R, 12) S(L, R, 13) S(L, R, 14) S(L, R, 15)
#define UNROLL(N, S, L, R) CAT2(STMTS_, N)(S, L, R)

// accumulator statement generators (runtime vars resolved at expansion site)
#define DECL_ACC(L, R, i)   VTT(L) CAT2(creg, i);
#define LOAD_ACC(L, R, i)   CAT2(creg, i) = VLE64(L)(&c[(i0 + i) * ldc + j0], vl);
#define FMACC_ACC(L, R, i)  CAT2(creg, i) = VFMACC(L)(CAT2(creg, i), at[kk * R + i], vb, vl);
#define FMACC_LAST(L, R, i) CAT2(creg, i) = VFMACC(L)(CAT2(creg, i), at[(kcq - 1) * R + i], vb, vl);
#define STORE_ACC(L, R, i)  VSE64(L)(&c[(i0 + i) * ldc + j0], CAT2(creg, i), vl);

// Generate one full DGEMM driver for a fixed (MR, LM, PIPE) point.
#define MAKE_DGEMM(MR, LM, PIPE)                                                            \
    __attribute__((noinline)) static void CAT3(CAT4(dgemm_mr, MR, _m, LM), _p, PIPE)(       \
        size_t n, size_t m, size_t k, const double *a, size_t lda, const double *b,         \
        size_t ldb, double *c, size_t ldc) {                                                \
        const size_t vlmax = VSETVLMAX(LM)();                                               \
        const size_t kc = (size_t)g_kc;                                                     \
        for (size_t j0 = 0; j0 < m; j0 += vlmax) {                                          \
            const size_t vl = VSETVL(LM)(m - j0);                                           \
            for (size_t k0 = 0; k0 < k; k0 += kc) {                                         \
                const size_t kcq = k - k0 < kc ? k - k0 : kc;                               \
                for (size_t i0 = 0; i0 + MR <= n; i0 += MR) {                               \
                    double *at = at_panel; /* at[kk][i] = A[i0+i][k0+kk] */                 \
                    for (size_t kk = 0; kk < kcq; kk++)                                     \
                        for (size_t i = 0; i < MR; i++)                                     \
                            at[kk * MR + i] = a[(i0 + i) * lda + k0 + kk];                  \
                    UNROLL(MR, DECL_ACC, LM, MR)                                            \
                    UNROLL(MR, LOAD_ACC, LM, MR)                                            \
                    const double *bp = &b[k0 * ldb + j0];                                   \
                    if (PIPE) {                                                             \
                        VTT(LM) vb = VLE64(LM)(bp, vl);                                     \
                        for (size_t kk = 0; kk + 1 < kcq; kk++) {                           \
                            VTT(LM) vbn = VLE64(LM)(bp + (kk + 1) * ldb, vl);               \
                            UNROLL(MR, FMACC_ACC, LM, MR)                                   \
                            vb = vbn;                                                       \
                        }                                                                   \
                        if (kcq > 0) UNROLL(MR, FMACC_LAST, LM, MR)                         \
                    } else {                                                                \
                        for (size_t kk = 0; kk < kcq; kk++) {                               \
                            VTT(LM) vb = VLE64(LM)(bp + kk * ldb, vl);                      \
                            UNROLL(MR, FMACC_ACC, LM, MR)                                   \
                        }                                                                   \
                    }                                                                       \
                    UNROLL(MR, STORE_ACC, LM, MR)                                           \
                }                                                                           \
                for (size_t i0 = n - (n % MR); i0 < n; i0++) { /* i-tail rows */            \
                    double *at = at_panel;                                                  \
                    for (size_t kk = 0; kk < kcq; kk++) at[kk] = a[i0 * lda + k0 + kk];     \
                    VTT(LM) c0 = VLE64(LM)(&c[i0 * ldc + j0], vl);                          \
                    const double *bp = &b[k0 * ldb + j0];                                   \
                    for (size_t kk = 0; kk < kcq; kk++)                                     \
                        c0 = VFMACC(LM)(c0, at[kk], VLE64(LM)(bp + kk * ldb, vl), vl);      \
                    VSE64(LM)(&c[i0 * ldc + j0], c0, vl);                                   \
                }                                                                           \
            }                                                                               \
        }                                                                                   \
    }

/* clang-format off */
MAKE_DGEMM(2, 1, 0) MAKE_DGEMM(2, 2, 0) MAKE_DGEMM(2, 4, 0) MAKE_DGEMM(2, 8, 0)
MAKE_DGEMM(4, 1, 0) MAKE_DGEMM(4, 2, 0) MAKE_DGEMM(4, 4, 0) MAKE_DGEMM(4, 8, 0)
MAKE_DGEMM(8, 1, 0) MAKE_DGEMM(8, 2, 0) MAKE_DGEMM(8, 4, 0)
MAKE_DGEMM(16, 1, 0) MAKE_DGEMM(16, 2, 0)
MAKE_DGEMM(2, 1, 1) MAKE_DGEMM(2, 2, 1) MAKE_DGEMM(2, 4, 1) MAKE_DGEMM(2, 8, 1)
MAKE_DGEMM(4, 1, 1) MAKE_DGEMM(4, 2, 1) MAKE_DGEMM(4, 4, 1) MAKE_DGEMM(4, 8, 1)
MAKE_DGEMM(8, 1, 1) MAKE_DGEMM(8, 2, 1) MAKE_DGEMM(8, 4, 1)
MAKE_DGEMM(16, 1, 1) MAKE_DGEMM(16, 2, 1)
/* clang-format on */

#define DGEMM_KEY(MR, LM, PIPE) (((PIPE) << 12) | ((MR) << 4) | (LM))
#define DGEMM_DISPATCH(MR, LM, PIPE)                                                      \
    case DGEMM_KEY(MR, LM, PIPE):                                                         \
        CAT3(CAT4(dgemm_mr, MR, _m, LM), _p, PIPE)(n, m, k, a, lda, b, ldb, c, ldc);      \
        return;

void dgemm_rvv(size_t n, size_t m, size_t k, const double *a, size_t lda,
               const double *b, size_t ldb, double *c, size_t ldc) {
    switch (DGEMM_KEY(g_mr, g_lmul, g_pipe)) {
        DGEMM_DISPATCH(2, 1, 0) DGEMM_DISPATCH(2, 2, 0) DGEMM_DISPATCH(2, 4, 0)
        DGEMM_DISPATCH(2, 8, 0) DGEMM_DISPATCH(4, 1, 0) DGEMM_DISPATCH(4, 2, 0)
        DGEMM_DISPATCH(4, 4, 0) DGEMM_DISPATCH(4, 8, 0) DGEMM_DISPATCH(8, 1, 0)
        DGEMM_DISPATCH(8, 2, 0) DGEMM_DISPATCH(8, 4, 0) DGEMM_DISPATCH(16, 1, 0)
        DGEMM_DISPATCH(16, 2, 0) DGEMM_DISPATCH(2, 1, 1) DGEMM_DISPATCH(2, 2, 1)
        DGEMM_DISPATCH(2, 4, 1) DGEMM_DISPATCH(2, 8, 1) DGEMM_DISPATCH(4, 1, 1)
        DGEMM_DISPATCH(4, 2, 1) DGEMM_DISPATCH(4, 4, 1) DGEMM_DISPATCH(4, 8, 1)
        DGEMM_DISPATCH(8, 1, 1) DGEMM_DISPATCH(8, 2, 1) DGEMM_DISPATCH(8, 4, 1)
        DGEMM_DISPATCH(16, 1, 1) DGEMM_DISPATCH(16, 2, 1)
    default:
        dgemm_naive(n, m, k, a, lda, b, ldb, c, ldc); // unreachable for valid configs
        return;
    }
}
