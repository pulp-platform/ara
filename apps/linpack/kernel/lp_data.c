// lp_data.c - all large buffers of the linpack app, placed in the L2 scratchpad
// via section(".l2") (see apps/common/arch.link.ld: L2 @ 0x80000000, 32 MB).
// Alignment follows the official fmatmul app: one full vector (32 * NR_LANES
// bytes), so unit-stride vector loads/stores never split across beats.
//
// Memory budget (doubles):
//   default (N=512 sweep 256):  a+a0 2*2MB + a21n 256KB + ga/gb/gc 3*512KB ~= 6.2MB
//   BIG     (N=1024 sweep 512): a+a0 2*8MB + a21n 512KB + ga/gb/gc 3*2MB ~= 23.5MB
//
// NOTE: these arrays are intentionally left uninitialized (NOBITS). If your
// loader/run flow ever shows garbage (bss not cleared), give each array an
// explicit `= {}` initializer so it lands in .data instead.
#include "lp_compat.h"

#define LP_ALIGN (32 * NR_LANES)
#define LP_SEC __attribute__((aligned(LP_ALIGN), section(".l2"), used))

double lp_a[(size_t)LINPACK_MAX_N * LINPACK_MAX_N] LP_SEC;
double lp_a0[(size_t)LINPACK_MAX_N * LINPACK_MAX_N] LP_SEC;
double lp_b[LINPACK_MAX_N] LP_SEC;
double lp_x[LINPACK_MAX_N] LP_SEC;
size_t lp_piv[LINPACK_MAX_N] LP_SEC;
double lp_a21n[(size_t)LINPACK_MAX_N * LINPACK_NB] LP_SEC;

double lp_ga[(size_t)DGEMM_SWEEP_N * DGEMM_SWEEP_N] LP_SEC;
double lp_gb[(size_t)DGEMM_SWEEP_N * DGEMM_SWEEP_N] LP_SEC;
double lp_gc[(size_t)DGEMM_SWEEP_N * DGEMM_SWEEP_N] LP_SEC;
