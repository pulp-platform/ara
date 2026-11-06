// main.c - bare-metal driver for the linpack app on Ara (CVA6 + Ara2 vector
// unit). Follows the official apps/fmatmul conventions: runtime.h for timing
// (mcycle CSR = real cycles under Verilator RTL), printf.h for output,
// -DNR_LANES/-DVLEN injected by apps/common/runtime.mk.
//
// Phases (each prints machine-parsable "RES," lines):
//   [1] functional check  : odd-size DGEMM (131x126x117), every RVV config vs
//                           the scalar reference. Reduction order is identical
//                           (ascending k), so results must match bit-exactly.
//                           Skip with -DSKIP_CHECK=1 (saves RTL sim time).
//   [2] timing sweep      : v0 scalar / v2 auto-vectorized / hand-written RVV
//                           configs at N=DGEMM_SWEEP_N. -DFULL_SWEEP=1 runs
//                           all 26 kernel instances instead of the 6 anchors.
//   [3] linpack chain     : blocked LU + solve at N=LINPACK_N, nb in {32,64},
//                           HPL-style residual + checksum.
//
// Ideal-Dispatcher mode (-DARA_IDEAL_DGEMM_ONLY=1): only phase [2] runs (the
// DGEMM kernel is fire-and-forget vector code, so its timing is valid without
// scalar execution; its *results* are meaningless in that mode).
//
// Compiler-comparison mode (-DE7_MODE=1, driven by scripts/e7_run.sh):
// phase [1] shrinks to a light gate (odd sizes 71x66x57, v2 + two rvv
// configs only), phase [2] keeps v0/v2 + two anchor kernels, phase [3] is
// skipped. The object of study is kernel *codegen* under different
// compilers/flags, so identical semantics must hold for every combo while
// sim time stays small.
#include <stdint.h>
#include <stddef.h>
#include "runtime.h"
#include "printf.h"
#include "kernel/lp_compat.h"
#include "kernel/dgemm.h"
#include "kernel/linpack.h"

// v0 is O(N^3) scalar; cap its size to keep RTL sim time sane (FLOPs == cycles
// there, roughly). Override with -DSCALAR_N=...
#ifndef SCALAR_N
#define SCALAR_N ((DGEMM_SWEEP_N < 128) ? DGEMM_SWEEP_N : 128)
#endif

typedef struct { int mr, lmul, kc, pipe; } cfg_t;

// Anchor configs for E1/E3 (paper-relevant points). FULL_SWEEP=1 -> all 26.
static const cfg_t anchor_cfgs[] = {
    {4, 1, 64, 0},    // v3: minimal register blocking
    {8, 2, 128, 0},   // v4: tuned point
    {8, 2, 128, 1},   // v5: + software pipelining
    {16, 2, 128, 0},  //    VRF-overflow candidate (vregs=36 > 32)
    {8, 4, 128, 0},   //    VRF-overflow candidate (vregs=38 > 32)
    {2, 1, 64, 0},    //    minimal-issue candidate
};
#define N_ANCHOR (sizeof(anchor_cfgs) / sizeof(anchor_cfgs[0]))

// Valid (MR, LMUL) instantiations of the engine (see dgemm_rvv.c).
static int valid_cfg(int mr, int lmul) {
    if (lmul != 1 && lmul != 2 && lmul != 4 && lmul != 8) return 0;
    if (mr == 2 || mr == 4) return 1;
    if (mr == 8) return lmul <= 4;
    if (mr == 16) return lmul <= 2;
    return 0;
}

static double gf_pc, g_util; // last computed metrics (for VCD_DUMP brevity)

static void report_row(const char *phase, const char *var, int mr, int lmul,
                       int kc, int pipe, size_t n, int64_t cycles, uint64_t chk) {
    printf("RES,phase=%s,var=%s,mr=%d,lmul=%d,kc=%d,pipe=%d,N=%d,cycles=%lu,"
           "fpcyc=%.3f,util=%.2f,chk=%08lx%08lx\n",
           phase, var, mr, lmul, kc, pipe, (int)n, (unsigned long)cycles,
           gf_pc, g_util, (unsigned long)(chk >> 32), (unsigned long)chk);
}

// ---------------------------------------------------------------- phase 1
static int check_phase(void) {
#ifdef E7_MODE
    const size_t n = 71, m = 66, k = 57; // light gate: ~6x cheaper in RTL sim
#else
    const size_t n = 131, m = 126, k = 117; // odd sizes, tails exercised
#endif
    int fails = 0;

    lp_fill(lp_ga, n * k, 1001); // A: n x k, lda = k
    lp_fill(lp_gb, k * m, 1002); // B: k x m, ldb = m
    for (size_t i = 0; i < n * m; i++) { lp_gc[i] = 0.0; lp_a[i] = 0.0; }

    dgemm_naive(n, m, k, lp_ga, k, lp_gb, m, lp_a, m); // reference C -> lp_a
    uint64_t ref_chk = lp_checksum(lp_a, n * m);

    // v2 auto-vectorized
    for (size_t i = 0; i < n * m; i++) lp_gc[i] = 0.0;
    dgemm_blocked(n, m, k, lp_ga, k, lp_gb, m, lp_gc, m);
    double d2 = 0.0;
    for (size_t i = 0; i < n * m; i++) {
        double d = lp_fabs(lp_gc[i] - lp_a[i]);
        if (d > d2) d2 = d;
    }
    printf("CHK,var=v2_autovec,maxdiff=%.12f,ref=%08lx%08lx\n", d2,
           (unsigned long)(ref_chk >> 32), (unsigned long)ref_chk);
    // v2 legitimately reassociates the FP reduction when auto-vectorizing,
    // so allow a tolerance here. Hand-written kernels keep the scalar
    // reduction order and must stay bit-exact below.
    if (d2 > 1e-9) fails++;

    // all valid hand-written configs (E7_MODE: only the two sweep anchors)
    for (int mr = 2; mr <= 16; mr <<= 1) {
        for (int lmul = 1; lmul <= 8; lmul <<= 1) {
            if (!valid_cfg(mr, lmul)) continue;
#ifdef E7_MODE
            if (!(mr == 4 && lmul == 1) && !(mr == 8 && lmul == 2)) continue;
#endif
            dgemm_rvv_config(mr, lmul, 64, 0);
            for (size_t i = 0; i < n * m; i++) lp_gc[i] = 0.0;
            dgemm_rvv(n, m, k, lp_ga, k, lp_gb, m, lp_gc, m);
            double d = 0.0;
            for (size_t i = 0; i < n * m; i++) {
                double e = lp_fabs(lp_gc[i] - lp_a[i]);
                if (e > d) d = e;
            }
            printf("CHK,var=rvv,mr=%d,lmul=%d,maxdiff=%.12f\n", mr, lmul, d);
            if (d != 0.0) fails++;
        }
    }
    printf("CHECK_PHASE,%s,fails=%d\n", fails ? "FAIL" : "PASS", fails);
    return fails;
}

// ---------------------------------------------------------------- phase 2
static void sweep_one(const char *var, cfg_t c, size_t n) {
    dgemm_rvv_config(c.mr, c.lmul, c.kc, c.pipe);
    int64_t best = -1;
    uint64_t chk = 0;
    for (int r = 0; r < SWEEP_REPS; r++) {
        start_timer();
        dgemm_rvv(n, n, n, lp_ga, n, lp_gb, n, lp_gc, n);
        stop_timer();
        int64_t t = get_timer();
        if (best < 0 || t < best) best = t;
    }
    chk = lp_checksum(lp_gc, n * n);
    double fl = 2.0 * (double)n * (double)n * (double)n;
    gf_pc = best > 0 ? fl / (double)best : 0.0;
    g_util = 100.0 * gf_pc / (2.0 * NR_LANES);
    report_row("swp", var, c.mr, c.lmul, c.kc, c.pipe, n, best, chk);
}

static void sweep_phase(void) {
    const size_t n = DGEMM_SWEEP_N;
    lp_fill(lp_ga, n * n, 11);
    lp_fill(lp_gb, n * n, 22);
    for (size_t i = 0; i < n * n; i++) lp_gc[i] = 0.0;

    // v0 scalar (capped size); skipped in ONLY_MR (E3 single-variant) mode
#ifndef ONLY_MR
    {
        int64_t best = -1;
        for (int r = 0; r < SWEEP_REPS; r++) {
            start_timer();
            dgemm_naive(SCALAR_N, SCALAR_N, SCALAR_N, lp_ga, n, lp_gb, n, lp_gc, n);
            stop_timer();
            int64_t t = get_timer();
            if (best < 0 || t < best) best = t;
        }
        double fl = 2.0 * (double)SCALAR_N * (double)SCALAR_N * (double)SCALAR_N;
        gf_pc = best > 0 ? fl / (double)best : 0.0;
        g_util = 100.0 * gf_pc / (2.0 * NR_LANES);
        report_row("swp", "v0_scalar", 0, 0, 0, 0, SCALAR_N, best, 0);
    }
    // v2 auto-vectorized
    {
        int64_t best = -1;
        for (int r = 0; r < SWEEP_REPS; r++) {
            start_timer();
            dgemm_blocked(n, n, n, lp_ga, n, lp_gb, n, lp_gc, n);
            stop_timer();
            int64_t t = get_timer();
            if (best < 0 || t < best) best = t;
        }
        uint64_t chk = lp_checksum(lp_gc, n * n);
        double fl = 2.0 * (double)n * (double)n * (double)n;
        gf_pc = best > 0 ? fl / (double)best : 0.0;
        g_util = 100.0 * gf_pc / (2.0 * NR_LANES);
        report_row("swp", "v2_autovec", 0, 0, 0, 0, n, best, chk);
    }
#endif // !ONLY_MR

#if defined(ONLY_MR)
    // E3 parallel mode: exactly one hand-written config per process
    // (-DONLY_MR=8 -DONLY_LMUL=2 -DONLY_PIPE=0, kc fixed 128). v0/v2 and the
    // linpack chain are skipped so a 26-variant sweep fans out to 26 jobs.
    {
        cfg_t c = {ONLY_MR, ONLY_LMUL, 128, ONLY_PIPE};
        sweep_one("rvv", c, n);
    }
#elif defined(FULL_SWEEP)
    for (int pipe = 0; pipe <= 1; pipe++)
        for (int mr = 2; mr <= 16; mr <<= 1)
            for (int lmul = 1; lmul <= 8; lmul <<= 1) {
                if (!valid_cfg(mr, lmul)) continue;
                cfg_t c = {mr, lmul, 128, pipe};
                sweep_one("rvv", c, n);
            }
#else
#ifdef VCD_DUMP
    // waveform mode: single tuned kernel only, to bound the .fst size
    {
        cfg_t c = {8, 2, 128, 0};
        sweep_one("rvv", c, n);
    }
#else
#ifdef E7_MODE
    // compiler comparison: the two anchor kernels only (codegen study)
    for (size_t i = 0; i < 2; i++)
        sweep_one("rvv", anchor_cfgs[i], n);
#else
    for (size_t i = 0; i < N_ANCHOR; i++)
        sweep_one("rvv", anchor_cfgs[i], n);
#endif
#endif
#endif
}

// ---------------------------------------------------------------- phase 3
#if !defined(ARA_IDEAL_DGEMM_ONLY) && !defined(E7_MODE)
static void linpack_phase(void) {
    const size_t n = LINPACK_N;
    const size_t nbs[] = {32, 64};
    const cfg_t cfgs[] = {{8, 2, 128, 0}, {4, 1, 64, 0}};
    for (size_t b = 0; b < sizeof(nbs) / sizeof(nbs[0]); b++) {
        if (nbs[b] > (size_t)LINPACK_NB) continue;
        for (size_t c = 0; c < sizeof(cfgs) / sizeof(cfgs[0]); c++) {
            double resid = 0.0;
            int64_t cyc = 0;
            uint64_t chk = linpack_run(n, nbs[b], cfgs[c].mr, cfgs[c].lmul,
                                       cfgs[c].kc, cfgs[c].pipe, 42, &resid, &cyc);
            double fl = (2.0 / 3.0) * (double)n * (double)n * (double)n
                        + 2.0 * (double)n * (double)n;
            gf_pc = cyc > 0 ? fl / (double)cyc : 0.0;
            g_util = 100.0 * gf_pc / (2.0 * NR_LANES);
            printf("RES,phase=lp,var=linpack,mr=%d,lmul=%d,kc=%d,pipe=%d,N=%d,"
                   "nb=%d,cycles=%lu,fpcyc=%.3f,util=%.2f,resid=%.9f,chk=%08lx%08lx\n",
                   cfgs[c].mr, cfgs[c].lmul, cfgs[c].kc, cfgs[c].pipe, (int)n,
                   (int)nbs[b], (unsigned long)cyc, gf_pc, g_util, resid,
                   (unsigned long)(chk >> 32), (unsigned long)chk);
        }
    }
}
#endif // !ARA_IDEAL_DGEMM_ONLY && !E7_MODE

int main(void) {
    printf("\n");
    printf("==============================================\n");
    printf("  LINPACK on Ara2 (RVV 1.0) - RTL-measured    \n");
    printf("==============================================\n");
    printf("CFG,lanes=%d,vlen=%d,sweepN=%d,linpackN=%d,nbMax=%d,reps=%d,mode=%s\n",
           NR_LANES, VLEN, DGEMM_SWEEP_N, LINPACK_N, LINPACK_NB, SWEEP_REPS,
#ifdef E7_MODE
           "e7"
#elif defined(ARA_IDEAL_DGEMM_ONLY)
           "ideal"
#else
           "full"
#endif
    );

    int fails = 0;
#ifndef SKIP_CHECK
    fails += check_phase();
#endif

    sweep_phase();

#if !defined(ARA_IDEAL_DGEMM_ONLY) && !defined(E7_MODE) && !defined(SKIP_CHAIN)
    linpack_phase();
#endif

    printf("DONE,fails=%d\n", fails);
    return fails;
}
