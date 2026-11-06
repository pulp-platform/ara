// lp_compat.h - bare-metal compatibility layer for the linpack app.
//
// Replaces the host-side parts of linpack-ara2/src/common.h (stdlib/malloc/
// stdio/math/clock). Everything deterministic and cross-platform:
//  - lp_frand is byte-identical to linpack-ara2's frand(), so matrices filled
//    with the same seed are bit-identical across qemu-user / Spike / Verilator
//    RTL and the host reference build.
//  - Timing is done by the caller (or linpack.c) via runtime.h's
//    start_timer()/stop_timer(), which read the real `mcycle` CSR. Under RTL
//    simulation those are hardware cycles; frequency is NOT assumed anywhere.
//
// Build system injects -DNR_LANES=<L> -DVLEN=<bits> (apps/common/runtime.mk).
// Host builds (outside the Ara Makefile) fall back to NR_LANES=4.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifndef NR_LANES
#define NR_LANES 4
#endif
#ifndef VLEN
#define VLEN (1024 * NR_LANES)
#endif

// ---- problem sizes (override with -D on the make command line) -----------
// Default budget: ~6.2 MB of L2 (32 MB available). BIG=1 -> ~23 MB, still fits.
#ifndef DGEMM_SWEEP_N
#ifdef BIG
#define DGEMM_SWEEP_N 512
#else
#define DGEMM_SWEEP_N 256
#endif
#endif
#ifndef LINPACK_N
#ifdef BIG
#define LINPACK_N 1024
#else
#define LINPACK_N 512
#endif
#endif
#ifndef LINPACK_NB
#define LINPACK_NB 64
#endif
#if LINPACK_NB > 64
#error "LINPACK_NB > 64 exceeds the a21n panel buffer"
#endif
#ifndef LINPACK_MAX_N
#define LINPACK_MAX_N ((LINPACK_N > DGEMM_SWEEP_N) ? LINPACK_N : DGEMM_SWEEP_N)
#endif
// check_phase uses odd sizes 131x126x117, so the sweep buffers must cover it.
// (Not required when SKIP_CHECK drops the functional phase entirely - trimmed
// RTL runs use e.g. -DSKIP_CHECK=1 -DDGEMM_SWEEP_N=64.)
#if DGEMM_SWEEP_N < 132 && !(defined(SKIP_CHECK) && SKIP_CHECK)
#error "DGEMM_SWEEP_N must be >= 132 (check_phase uses 131x126x117 operands; or pass -DSKIP_CHECK=1)"
#endif

// Repetitions for the timing sweep (RTL sim is expensive; default 1).
#ifndef SWEEP_REPS
#define SWEEP_REPS 1
#endif

// ---- deterministic input generation (LCG) --------------------------------
static inline double lp_frand(unsigned *seed) {
    *seed = *seed * 1664525u + 1013904223u;
    return ((double)(*seed >> 8) / 16777216.0) - 0.5;
}

static inline void lp_fill(double *a, size_t n, unsigned seed) {
    for (size_t i = 0; i < n; i++)
        a[i] = lp_frand(&seed);
}

static inline double lp_fabs(double x) { return x < 0.0 ? -x : x; }

// FNV-1a over the raw bytes of a double array: cheap cross-platform
// fingerprint to prove qemu/Spike/RTL produce bit-identical results.
// Capped at LP_CHK_N doubles (64 KiB) to keep the scalar byte-loop cheap
// under RTL simulation; exact correctness is established separately by the
// element-wise max-diff check in main.c.
#define LP_CHK_N 8192
static inline uint64_t lp_checksum(const double *a, size_t n) {
    if (n > LP_CHK_N) n = LP_CHK_N;
    uint64_t h = 1469598103934665603ull;
    const unsigned char *p = (const unsigned char *)a;
    for (size_t i = 0; i < n * sizeof(double); i++) {
        h ^= p[i];
        h *= 1099511628211ull;
    }
    return h;
}

// ---- buffers (defined once in kernel/lp_data.c, placed in .l2) -----------
extern double lp_a[];    // LINPACK_N x LINPACK_N factorized in place
extern double lp_a0[];   // pristine copy for the HPL-style residual
extern double lp_b[];    // right-hand side
extern double lp_x[];    // solution
extern size_t lp_piv[];  // pivot records
extern double lp_a21n[]; // compact negated L21 panel (LINPACK_MAX_N x LINPACK_NB)
extern double lp_ga[];   // DGEMM sweep / check operands (DGEMM_SWEEP_N^2 each)
extern double lp_gb[];
extern double lp_gc[];
