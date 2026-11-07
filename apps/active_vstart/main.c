// SPDX-License-Identifier: Apache-2.0
// Check successful execution or precise rejection of active nonzero vstart.
#include <stdint.h>
#include "printf.h"

volatile uintptr_t trap_armed, trap_count, trap_cause, trap_value, trap_start;
asm(".pushsection .text\n.balign 4\n.global mtvec_handler\nmtvec_handler:\n"
    "la t0, trap_armed\nld t1, 0(t0)\nbeqz t1, 9f\n"
    "la t0, trap_count\nld t1, 0(t0)\naddi t1, t1, 1\nsd t1, 0(t0)\n"
    "la t0, trap_cause\ncsrr t1, mcause\nsd t1, 0(t0)\n"
    "la t0, trap_value\ncsrr t1, mtval\nsd t1, 0(t0)\n"
    "la t0, trap_start\ncsrr t1, vstart\nsd t1, 0(t0)\n"
    "csrr t0, mepc\naddi t0, t0, 4\ncsrw mepc, t0\n"
    "csrw vstart, zero\nmret\n9: li a0, 90\nj _fail\n.popsection\n");

static volatile uint32_t a[4] = {10, 20, 30, 40};
static volatile uint32_t b[4] = {1, 2, 3, 4};
static volatile uint8_t narrow[4] = {1, 128, 255, 7};
static volatile uint32_t old[4] = {101, 102, 103, 104};
static volatile uint32_t output[6];
static unsigned checks, errors;
static void check(uint64_t actual, uint64_t expected) {
  ++checks;
  if (actual != expected) ++errors;
}

#define TARGET(SETUP, OP)                                                      \
  asm volatile("csrw vstart, zero\n" SETUP                                    \
               "vle32.v v24, (%[old])\ncsrr t0, vl\n"                        \
               "csrw vstart, %[start]\n" OP "\n"                            \
               "csrr %[after], vstart\ncsrw vstart, zero\n"                  \
               "vse32.v v24, (%[out])\ncsrr %[vl], vl\nfence rw, rw\n"        \
               : [after] "=&r"(after), [vl] "=&r"(vl)                         \
               : [a] "r"(a), [b] "r"(b), [narrow] "r"(narrow),               \
                 [old] "r"(old), [out] "r"(output + 1),                       \
                 [start] "r"((uintptr_t)start)                                \
               : "t0", "t1", "t5", "v8", "v16", "v24", "memory")
static void run(unsigned kind, unsigned start) {
  uintptr_t after, vl;
  const unsigned before = errors;
  trap_count = trap_cause = trap_value = trap_start = 0;
  output[0] = UINT32_C(0x13579bdf);
  output[5] = UINT32_C(0x2468ace0);
  for (unsigned i = 1; i < 5; ++i) output[i] = UINT32_C(0xdeadbeef);
  trap_armed = 1;
  if (!kind) {
    TARGET("li t0, 4\nvsetvli t0, t0, e32, m1, tu, mu\n"
           "vle32.v v8, (%[a])\nvle32.v v16, (%[b])\n",
           "vadd.vv v24, v8, v16");
  } else {
    TARGET("li t0, 4\nvsetvli t0, t0, e8, m1, tu, mu\n"
           "vle8.v v8, (%[narrow])\n"
           "li t0, 4\nvsetvli t0, t0, e32, m4, tu, mu\n",
           "vsext.vf4 v24, v8");
  }
  trap_armed = 0;
  check(vl, 4);
  check(after, 0);
  check(trap_count <= 1, 1);
  if (trap_count) {
    check(start > 0 && start < 4, 1);
    check(trap_cause, 2);
    check(trap_value, kind ? UINT32_C(0x4a82ac57) : UINT32_C(0x02880c57));
    check(trap_start, start);
  }
  for (unsigned i = 0; i < 4; ++i) {
    uint32_t expected = old[i];
    if (!trap_count && i >= start)
      expected = kind ? (uint32_t)(int32_t)(int8_t)narrow[i] : a[i] + b[i];
    check(output[i + 1], expected);
  }
  check(output[0], UINT32_C(0x13579bdf));
  check(output[5], UINT32_C(0x2468ace0));
  printf("VSTART_CASE kind=%u start=%u traps=%u checks=%u errors=%u\n",
         kind, start, (unsigned)trap_count, checks, errors - before);
}
int main(void) {
  for (unsigned kind = 0; kind < 2; ++kind) {
    run(kind, 0);
    run(kind, 1);
    run(kind, 4);
  }
  printf("VSTART_DONE cases=6 checks=%u errors=%u\n", checks, errors);
  return errors ? 1 : 0;
}
