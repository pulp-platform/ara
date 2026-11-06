// dgemm.h - DGEMM variant registry (BLAS-style leading dimensions)
// All kernels compute C += A*B, row-major, A is (n x k) with row stride lda,
// B is (k x m) with row stride ldb, C is (n x m) with row stride ldc.
// Variants:
//   v0 naive_scalar   : 3-loop ijk, forced scalar codegen -> baseline
//   v2 blocked_autovec: cache-blocked tiling, inner loop auto-vectorized
//   v3 rvv_packed     : hand RVV1.0 intrinsics, A-panel packing, MR x VL blocking
//   v4 rvv_tuned      : v3 engine with runtime-selected (MR, LMUL, KC)
//   v5 rvv_pipeline   : v3 engine + k-unrolled software pipelining
// (carried over verbatim from linpack-ara2/src/dgemm.h)
#pragma once
#include <stddef.h>

typedef void (*dgemm_fn)(size_t n, size_t m, size_t k, const double *a, size_t lda,
                         const double *b, size_t ldb, double *c, size_t ldc);

void dgemm_naive(size_t n, size_t m, size_t k, const double *a, size_t lda,
                 const double *b, size_t ldb, double *c, size_t ldc);
void dgemm_blocked(size_t n, size_t m, size_t k, const double *a, size_t lda,
                   const double *b, size_t ldb, double *c, size_t ldc);
void dgemm_rvv(size_t n, size_t m, size_t k, const double *a, size_t lda,
               const double *b, size_t ldb, double *c, size_t ldc);

// intrinsics engine configuration (MR, LMUL, KC, pipeline)
void dgemm_rvv_config(int mr, int lmul, int kc, int pipeline);
int  dgemm_rvv_current_mr(void);
int  dgemm_rvv_current_lmul(void);
int  dgemm_rvv_current_kc(void);
