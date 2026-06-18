// Copyright 2026 ETH Zurich and University of Bologna.
// SPDX-License-Identifier: Apache-2.0
//
// Spike-vs-Ara differential trap probe for issue #460: a masked vmerge whose
// destination is v0 (also the mask source) must raise an illegal-instruction
// exception (mcause=2). vmv.v.* (vm=1) with vd=v0 stays legal.
//
//   vsetivli x8, 10, e8, m4
//   vmv.v.x v0, -1        ; legal (vm=1), must NOT trap
//   vmv.v.x v20, 0x33     ; legal
//   marker = 1            ; proves setup did not trap
//   vmerge.vim v0, v20, -2, v0  ; illegal -> trap, mcause=2
// Expected (both): cause=2, marker=1.

#include <stdint.h>
#ifdef SPIKE
#include "util.h"
#include <stdio.h>
#elif defined ARA_LINUX
#include <stdio.h>
#else
#include "printf.h"
#endif

volatile uint64_t g_cause  = 0xbad;
volatile uint64_t g_marker = 0;

asm(".global mtvec_handler\n"
    ".align 2\n"
    "mtvec_handler:\n"
    "  addi sp, sp, -16\n"
    "  sd   t0, 0(sp)\n"
    "  sd   t1, 8(sp)\n"
    "  csrr t0, mcause\n  la t1, g_cause\n  sd t0, 0(t1)\n"
    "  la   t0, trap_resume\n  csrw mepc, t0\n"
    "  ld   t0, 0(sp)\n  ld t1, 8(sp)\n  addi sp, sp, 16\n"
    "  mret\n");

extern char trap_resume[];
uintptr_t handle_trap(uintptr_t cause, uintptr_t epc, uintptr_t regs) {
  (void)epc;
  (void)regs;
  g_cause = cause;
  return (uintptr_t)trap_resume;
}

int main() {
  asm volatile("fence" ::: "memory");
  asm volatile("vsetivli x8, 10, e8, m4");
  asm volatile("li t0, -1\n vmv.v.x v0, t0" ::: "t0");   // legal (vm=1)
  asm volatile("li t0, 0x33\n vmv.v.x v20, t0" ::: "t0"); // legal
  g_marker = 1;                                           // setup did not trap
  asm volatile("vmerge.vim v0, v20, -2, v0\n"             // illegal
               ".global trap_resume\n"
               "trap_resume:\n");
  asm volatile("fence" ::: "memory");

  printf("cause=%d marker=%d\n", (int)g_cause, (int)g_marker);
  return 0;
}
