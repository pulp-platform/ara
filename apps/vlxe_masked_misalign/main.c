// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential probe for issue #456: a masked indexed load whose
// *masked-off* element has a misaligned effective address must NOT trap (per
// the RVV spec, masked-off elements generate neither exceptions nor accesses).
//
//   vsetivli 4, e32, m1, ta, mu
//   v0 = 0b1110  (element 0 masked-off; elements 1..3 active)
//   v4 = idx{1,4,8,12}   ; element 0 idx=1 -> base+1 is misaligned for e32
//   vluxei32.v v8, (base), v4, v0.t
//
// Element 0 is masked off, so its misaligned address must be ignored: no trap.
// v8 is pre-filled with 0xdead and the policy is mask-undisturbed, so v8[0]
// keeps 0xdead while v8[1..3] receive mem[base+4/8/12].
//
// Expected (Spike, and Ara after the #456 fix):
//   cause=0 o0=57005 o1=8738 o2=13107 o3=17476
//     (0xdead=57005, 0x2222=8738, 0x3333=13107, 0x4444=17476)

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

// g_cause stays 0 if no trap occurs (the expected, correct behaviour).
volatile uint64_t g_cause = 0;
volatile uint64_t g_tval  = 0;
volatile uint64_t g_epc   = 0;

// Ara runtime (apps/common/crt0.S) jumps to a weak mtvec_handler with no saved
// context. Record the trap CSRs and resume at trap_resume. Present only so an
// (incorrect) trapping run terminates instead of hanging.
asm(".global mtvec_handler\n"
    ".align 2\n"
    "mtvec_handler:\n"
    "  addi sp, sp, -16\n"
    "  sd   t0, 0(sp)\n"
    "  sd   t1, 8(sp)\n"
    "  csrr t0, mcause\n  la t1, g_cause\n  sd t0, 0(t1)\n"
    "  csrr t0, mtval\n   la t1, g_tval\n   sd t0, 0(t1)\n"
    "  csrr t0, mepc\n    la t1, g_epc\n    sd t0, 0(t1)\n"
    "  la   t0, trap_resume\n  csrw mepc, t0\n"
    "  ld   t0, 0(sp)\n  ld t1, 8(sp)\n  addi sp, sp, 16\n"
    "  mret\n");

// Spike runtime (riscv-tests benchmarks crt.S) saves context and calls
// handle_trap(mcause, mepc, sp), then sets mepc to the return value.
extern char trap_resume[];
uintptr_t handle_trap(uintptr_t cause, uintptr_t epc, uintptr_t regs) {
  uint64_t tval;
  asm volatile("csrr %0, mtval" : "=r"(tval));
  g_cause = cause;
  g_tval  = tval;
  g_epc   = epc;
  return (uintptr_t)trap_resume;
}

static volatile uint32_t mem_data[8] = {0x1111, 0x2222, 0x3333, 0x4444,
                                        0, 0, 0, 0};
static volatile uint32_t idx_data[4] = {1, 4, 8, 12};
static volatile uint8_t  mask_data[1] = {0x0E}; // bit0=0, bits1..3=1
static volatile uint32_t result[4]   = {0, 0, 0, 0};

int main() {
  asm volatile("fence" ::: "memory");

  // Pre-fill v8 with 0xdead (mask-undisturbed keeps masked-off lanes).
  asm volatile("vsetivli x0, 4, e32, m1, ta, mu\n"
               "li       t0, 0xdead\n"
               "vmv.v.x  v8, t0\n" ::: "t0");

  // Load the mask register v0 = 0b1110.
  asm volatile("vsetivli x0, 1, e8, m1, ta, ma");
  asm volatile("vle8.v v0, (%0)" ::"r"(mask_data));

  // Load the index vector and perform the masked indexed load.
  asm volatile("vsetivli x0, 4, e32, m1, ta, mu");
  asm volatile("vle32.v v4, (%0)" ::"r"(idx_data));
  asm volatile("vluxei32.v v8, (%0), v4, v0.t\n"
               ".global trap_resume\n"
               "trap_resume:\n" ::"r"(mem_data));

  // Store v8 back to memory for read-out.
  asm volatile("vse32.v v8, (%0)" ::"r"(result));
  asm volatile("fence" ::: "memory");

  printf("R: cause=%d o0=%d o1=%d o2=%d o3=%d\n", (int)g_cause,
         (int)result[0], (int)result[1], (int)result[2], (int)result[3]);
  return 0;
}
