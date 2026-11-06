// linpack.c - Linpack-style benchmark: right-looking blocked LU with partial
// pivoting on top of the RVV DGEMM kernel, triangular solve, HPL-style residual.
//
// Ported from linpack-ara2/src/linpack.c. Differences to the host original:
//  * no libc: buffers are the static .l2 arrays from lp_data.c, sizes are
//    compile-time (LINPACK_N / LINPACK_NB), no malloc/free.
//  * timing reads the `mcycle` CSR via runtime.h (real cycles under RTL
//    simulation). ROI = blocked_lu + lu_solve, exactly the host version's
//    t0..t1 window: input fill/copy and the residual check stay untimed.
//
// Blocked step for block column k0 (block size nb):
//   1. panel_lu: unblocked factorization of the nb panel columns (rank-1
//      updates restricted to panel columns), full-row pivoting swaps.
//   2. U12 = L11^-1 * U12 via forward-substitution axpys over trailing cols.
//   3. A22 -= L21 * U12 as one RVV DGEMM (L21 negated into a compact panel).
// FLOP count: 2/3*n^3 + 2*n^2.
#include "runtime.h"
#include "lp_compat.h"
#include "dgemm.h"

// unblocked factorization of columns [lo, lo+nb) over rows [lo, n);
// rank-1 updates touch only panel columns; row swaps are full rows.
static void panel_lu(double *a, size_t n, size_t lo, size_t nb, size_t *piv) {
    const size_t hi = lo + nb < n ? lo + nb : n; // panel column bound
    for (size_t c = lo; c < hi; c++) {
        size_t p = c;
        double mx = lp_fabs(a[c * n + c]);
        for (size_t r = c + 1; r < n; r++) {
            double v = lp_fabs(a[r * n + c]);
            if (v > mx) { mx = v; p = r; }
        }
        piv[c] = p;
        if (p != c) // full-row swap (covers L21 columns, U12 and A22)
            for (size_t j = 0; j < n; j++) {
                double t = a[c * n + j];
                a[c * n + j] = a[p * n + j];
                a[p * n + j] = t;
            }
        if (a[c * n + c] == 0.0) continue;
        double d = 1.0 / a[c * n + c];
        for (size_t r = c + 1; r < n; r++) a[r * n + c] *= d;
        for (size_t r = c + 1; r < n; r++) { // rank-1 inside panel only
            double f = a[r * n + c];
            if (f == 0.0) continue;
            for (size_t j = c + 1; j < hi; j++) a[r * n + j] -= f * a[c * n + j];
        }
    }
}

static void blocked_lu(double *a, size_t n, size_t nb, size_t *piv, double *a21n) {
    for (size_t k0 = 0; k0 < n; k0 += nb) {
        size_t kb = n - k0 < nb ? n - k0 : nb;
        size_t hi = k0 + kb;           // first row/col of A22
        panel_lu(a, n, k0, kb, piv);
        if (hi >= n) break;
        // U12 = L11^-1 U12 : row (k0+i) -= L[k0+i][k0+j] * row(k0+j)
        for (size_t i = 1; i < kb; i++)
            for (size_t j = 0; j < i; j++) {
                double f = a[(k0 + i) * n + k0 + j];
                if (f == 0.0) continue;
                for (size_t c = hi; c < n; c++)
                    a[(k0 + i) * n + c] -= f * a[(k0 + j) * n + c];
            }
        // A22 -= L21 * U12 : negated compact L21 -> C += (-L21) x U12
        size_t m2 = n - hi;
        for (size_t r = 0; r < m2; r++)
            for (size_t kk = 0; kk < kb; kk++)
                a21n[r * kb + kk] = -a[(hi + r) * n + k0 + kk];
        dgemm_rvv(m2, m2, kb, a21n, kb, &a[k0 * n + hi], n, &a[hi * n + hi], n);
    }
}

// solve L*U*x = P*b (sequential transpositions recorded in piv)
static void lu_solve(const double *a, size_t n, const size_t *piv, const double *b, double *x) {
    for (size_t i = 0; i < n; i++) x[i] = b[i];
    for (size_t c = 0; c < n; c++) {
        size_t p = piv[c];
        if (p != c) { double t = x[c]; x[c] = x[p]; x[p] = t; }
    }
    for (size_t j = 0; j < n; j++)          // forward: unit lower L
        for (size_t i = j + 1; i < n; i++) x[i] -= a[i * n + j] * x[j];
    for (size_t i = n; i-- > 0;) {          // backward: upper U
        double s = x[i];
        for (size_t j = i + 1; j < n; j++) s -= a[i * n + j] * x[j];
        x[i] = s / a[i * n + i];
    }
}

// HPL-style normalized residual ||A*x-b||_inf / (||A||_inf * ||x||_inf * eps * n)
double linpack_residual(const double *a0, const double *x, const double *b, size_t n) {
    double norm_a = 0.0;
    for (size_t i = 0; i < n; i++) {
        double s = 0.0;
        for (size_t j = 0; j < n; j++) s += lp_fabs(a0[i * n + j]);
        if (s > norm_a) norm_a = s;
    }
    double norm_x = 0.0;
    for (size_t i = 0; i < n; i++)
        if (lp_fabs(x[i]) > norm_x) norm_x = lp_fabs(x[i]);
    double norm_r = 0.0;
    for (size_t i = 0; i < n; i++) {
        double s = -b[i];
        for (size_t j = 0; j < n; j++) s += a0[i * n + j] * x[j];
        if (lp_fabs(s) > norm_r) norm_r = lp_fabs(s);
    }
    double denom = norm_a * norm_x * 2.220446049250313e-16 * (double)n;
    return norm_r / (denom > 0 ? denom : 1e-300);
}

// Full Linpack run on the static buffers. Returns the checksum of the
// factorized matrix (cross-platform fingerprint), writes the residual and the
// mcycle count of the timed ROI (blocked_lu + lu_solve).
uint64_t linpack_run(size_t n, size_t nb, int mr, int lmul, int kc, int pipe,
                     unsigned seed, double *resid_out, int64_t *cycles_out) {
    double *a = lp_a, *a0 = lp_a0, *b = lp_b, *x = lp_x;
    size_t *piv = lp_piv;
    double *a21n = lp_a21n;

    lp_fill(a, n * n, seed);
    lp_fill(b, n, seed * 7 + 1);
    for (size_t i = 0; i < n * n; i++) a0[i] = a[i];

    dgemm_rvv_config(mr, lmul, kc, pipe);
    start_timer();
    blocked_lu(a, n, nb, piv, a21n);
    lu_solve(a, n, piv, b, x);
    stop_timer();

    if (cycles_out) *cycles_out = get_timer();
    if (resid_out) *resid_out = linpack_residual(a0, x, b, n);
    return lp_checksum(a, n * n);
}
