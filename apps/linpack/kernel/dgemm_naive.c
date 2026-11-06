// dgemm_naive.c - baseline (v0) and compiler-auto-vectorized blocked (v2).
//
// Ported from linpack-ara2/src/dgemm_naive.c. Two compilers must both work:
//  - GCC  (host regression build, and Ara Linux mode): per-function
//    __attribute__((optimize(...))) keeps v0 scalar and lets v2 use fast-math.
//  - Clang/LLVM (Ara bare-metal default, apps/common/runtime.mk): the GCC
//    optimize attribute does not exist there; v0 uses per-loop
//    `#pragma clang loop vectorize(disable)` instead, and v2 relies on
//    `#pragma clang fp reassociate(on)` + explicit vectorize(enable) to
//    legalize the FP reduction. Under LLVM, verify v2 actually vectorized by
//    checking the disassembly for vfmacc (this compiler difference is exactly
//    experiment E7 of the study plan).
#include "lp_compat.h"
#include "dgemm.h"

// v0: plain ijk triple loop, forced scalar
#if defined(__clang__)
void dgemm_naive(size_t n, size_t m, size_t k, const double *a, size_t lda,
                 const double *b, size_t ldb, double *c, size_t ldc) {
    for (size_t i = 0; i < n; i++)
        for (size_t l = 0; l < k; l++) {
            double aa = a[i * lda + l];
#pragma clang loop vectorize(disable)
            for (size_t j = 0; j < m; j++)
                c[i * ldc + j] += aa * b[l * ldb + j];
        }
}
#else
__attribute__((optimize("O2", "no-tree-vectorize")))
void dgemm_naive(size_t n, size_t m, size_t k, const double *a, size_t lda,
                 const double *b, size_t ldb, double *c, size_t ldc) {
    for (size_t i = 0; i < n; i++)
        for (size_t l = 0; l < k; l++) {
            double aa = a[i * lda + l];
            for (size_t j = 0; j < m; j++)
                c[i * ldc + j] += aa * b[l * ldb + j];
        }
}
#endif

// v2: cache-blocked triple loop; inner j-loop auto-vectorizes to unit-stride RVV
#define BM 64
#define BN 64
#define BK 64

#if defined(__clang__)
// Fast-math semantics for this TU region only (needed to vectorize the FP
// reduction). Keep it scoped right before the function.
#pragma clang fp reassociate(on)
void dgemm_blocked(size_t n, size_t m, size_t k, const double *a, size_t lda,
                   const double *b, size_t ldb, double *c, size_t ldc) {
    for (size_t ii = 0; ii < n; ii += BM) {
        size_t iie = ii + BM < n ? ii + BM : n;
        for (size_t jj = 0; jj < m; jj += BN) {
            size_t jje = jj + BN < m ? jj + BN : m;
            for (size_t ll = 0; ll < k; ll += BK) {
                size_t lle = ll + BK < k ? ll + BK : k;
                for (size_t i = ii; i < iie; i++)
                    for (size_t l = ll; l < lle; l++) {
                        double aa = a[i * lda + l];
#pragma clang loop vectorize(enable)
                        for (size_t j = jj; j < jje; j++)
                            c[i * ldc + j] += aa * b[l * ldb + j];
                    }
            }
        }
    }
}
#else
__attribute__((optimize("O3", "tree-vectorize", "fast-math")))
void dgemm_blocked(size_t n, size_t m, size_t k, const double *a, size_t lda,
                   const double *b, size_t ldb, double *c, size_t ldc) {
    for (size_t ii = 0; ii < n; ii += BM) {
        size_t iie = ii + BM < n ? ii + BM : n;
        for (size_t jj = 0; jj < m; jj += BN) {
            size_t jje = jj + BN < m ? jj + BN : m;
            for (size_t ll = 0; ll < k; ll += BK) {
                size_t lle = ll + BK < k ? ll + BK : k;
                for (size_t i = ii; i < iie; i++)
                    for (size_t l = ll; l < lle; l++) {
                        double aa = a[i * lda + l];
                        for (size_t j = jj; j < jje; j++)
                            c[i * ldc + j] += aa * b[l * ldb + j];
                    }
            }
        }
    }
}
#endif
