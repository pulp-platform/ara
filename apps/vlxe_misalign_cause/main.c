// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential trap probe for issue #457: an unmasked misaligned
// indexed load must raise LD_ADDR_MISALIGNED (mcause=4) and report the faulting
// effective address in mtval - not ILLEGAL_INSTR (mcause=2) with mtval=0.
//
// idx_data = {1,4,8,12}; element 0 uses base+1, misaligned for vluxei32.
// We trap, record mcause/mtval, resume past the load, and print:
//   cause       = mcause
//   tval_off    = mtval - base  (link-independent; expect 1)
// Expected (Spike): cause=4, tval_off=1.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

volatile uint64_t g_cause = 0xbad;
volatile uint64_t g_tval  = 0xbad;
volatile uint64_t g_epc   = 0xbad;

// Ara runtime (apps/common/crt0.S) jumps to a weak mtvec_handler with no saved
// context. Record the trap CSRs and resume at trap_resume.
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

static volatile uint32_t idx_data[4] = {1, 4, 8, 12};
static volatile uint32_t mem_data[8] = {0x11111111, 0x22222222, 0x33333333,
                                        0x44444444, 0, 0, 0, 0};

int main() {
  asm volatile("fence" ::: "memory");
  asm volatile("vsetivli x0, 4, e32, m1, ta, ma");
  asm volatile("vle32.v v4, (%0)" ::"r"(idx_data));
  asm volatile("vluxei32.v v8, (%0), v4\n"
               ".global trap_resume\n"
               "trap_resume:\n" ::"r"(mem_data));
  asm volatile("fence" ::: "memory");

  uint64_t tval_off = g_tval - (uint64_t)(uintptr_t)mem_data;
  printf("cause=%d tval_off=%d\n", (int)g_cause, (int)tval_off);
  return 0;
}
