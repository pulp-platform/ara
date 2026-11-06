// linpack.h - public surface of the Linpack kernel chain.
#pragma once
#include <stddef.h>
#include <stdint.h>

// Full Linpack run on the static .l2 buffers (see linpack.c). Timed ROI is
// blocked_lu + lu_solve (mcycle). Returns the checksum of the factorized
// matrix for cross-platform fingerprinting.
uint64_t linpack_run(size_t n, size_t nb, int mr, int lmul, int kc, int pipe,
                     unsigned seed, double *resid_out, int64_t *cycles_out);
double linpack_residual(const double *a0, const double *x, const double *b, size_t n);
