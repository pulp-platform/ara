// Regression test for the per-vreg EEW tracker on segment loads.
//
// `vlseg4e16.v v8, (rs1)` writes 4 destination vregs (v8..v11). The
// dispatcher must tag all 4 destinations with EEW=16 so a subsequent
// read at EEW=16 does not see a tracker mismatch and reshuffle the
// data. This test stores v8..v11 back to memory and checks the
// elements bit-for-bit.

#include <stdint.h>
#ifdef SPIKE
#include <stdio.h>
#else
#include "printf.h"
#endif

// 16 int16 inputs, viewed as 4 segments of 4 elements:
//   segment 0: in_buf[0..3]
//   segment 1: in_buf[4..7]
//   segment 2: in_buf[8..11]
//   segment 3: in_buf[12..15]
// vlseg4e16 demuxes by element-within-segment:
//   v8  = {in[0],  in[4],  in[8],  in[12]}
//   v9  = {in[1],  in[5],  in[9],  in[13]}
//   v10 = {in[2],  in[6],  in[10], in[14]}
//   v11 = {in[3],  in[7],  in[11], in[15]}
static const int16_t in_buf[16] = {
     1,  2,  3,  4,
    11, 12, 13, 14,
    21, 22, 23, 24,
    31, 32, 33, 34,
};

int main(void) {
  int16_t v8_out[4], v9_out[4], v10_out[4], v11_out[4];
  int fail = 0;

  printf("=== seg_test ===\n");

  asm volatile ("vsetivli x0, 4, e16, m1, ta, ma");

  asm volatile ("vlseg4e16.v v8, (%0)" :: "r"(in_buf) : "memory");
  asm volatile ("vse16.v v8,  (%0)"   :: "r"(v8_out)  : "memory");
  asm volatile ("vse16.v v9,  (%0)"   :: "r"(v9_out)  : "memory");
  asm volatile ("vse16.v v10, (%0)"   :: "r"(v10_out) : "memory");
  asm volatile ("vse16.v v11, (%0)"   :: "r"(v11_out) : "memory");

  printf("element  v8  v9  v10 v11\n");
  for (int i = 0; i < 4; i++) {
    printf("  [%d]    %d  %d  %d  %d\n",
           i, v8_out[i], v9_out[i], v10_out[i], v11_out[i]);
    int base = i == 0 ? 1 : i == 1 ? 11 : i == 2 ? 21 : 31;
    if (v8_out[i]  != base + 0) fail++;
    if (v9_out[i]  != base + 1) fail++;
    if (v10_out[i] != base + 2) fail++;
    if (v11_out[i] != base + 3) fail++;
  }

  if (fail == 0)
    printf("*** seg_test PASS ***\n");
  else
    printf("*** seg_test FAIL: %d mismatches ***\n", fail);

  return fail;
}
