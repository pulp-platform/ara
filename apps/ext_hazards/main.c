// SPDX-License-Identifier: Apache-2.0
// Reproduce late destination-load writes during integer extension.
#include <stdint.h>
#include "printf.h"

struct region {
  uint64_t before[8], data[128], after[8];
};
static volatile struct region source, unused_source, destination, output;
static unsigned errors, checks;

static uint8_t pattern(unsigned buffer, unsigned byte, unsigned id) {
  return (uint8_t)(0x31u + buffer * 71u + byte * 29u +
                   (byte >> 3) * 17u + id * 23u);
}
static void check(uint64_t actual, uint64_t expected) {
  ++checks;
  if (actual != expected) ++errors;
}
static void initialize(unsigned id) {
  volatile struct region *regions[] = {&source, &unused_source, &destination, &output};
  for (unsigned b = 0; b < 4; ++b) {
    for (unsigned i = 0; i < 8; ++i) {
      regions[b]->before[i] = UINT64_C(0x13579bdf2468ace0) ^ (b * 17u + i);
      regions[b]->after[i] = UINT64_C(0xfedcba9876543210) ^ (b * 17u + i);
    }
    for (unsigned i = 0; i < 128; ++i) {
      uint64_t value = 0;
      for (unsigned j = 0; j < 8; ++j)
        value |= (uint64_t)pattern(b, i * 8u + j, id) << (j * 8u);
      regions[b]->data[i] = value;
    }
  }
}
#define EXEC(SEW, OP)                                                         \
  asm volatile("fence rw, rw\ncsrw vstart, zero\n"                             \
               "vsetvli %[vl], zero, e" #SEW ", m4, tu, mu\n"                 \
               "vl4re8.v v8, (%[src])\nvl4re8.v v16, (%[unused])\n"             \
               "vl4re8.v v24, (%[dst])\n"                                    \
               "vsetvli %[vl], %[n], e" #SEW ", m4, tu, mu\n"                 \
               OP "\ncsrr %[after], vl\ncsrr %[start], vstart\n"             \
               "vs4r.v v24, (%[out])\nfence rw, rw\n"                         \
               : [vl] "=&r"(vl), [after] "=&r"(after), [start] "=&r"(start)    \
               : [src] "r"(source.data), [unused] "r"(unused_source.data),     \
                 [dst] "r"(destination.data), [out] "r"(output.data),           \
                 [n] "r"((uintptr_t)count)                                    \
               : "v8", "v9", "v10", "v11", "v16", "v17", "v18", "v19",     \
                 "v24", "v25", "v26", "v27", "memory")
static void run(unsigned id) {
  const unsigned sew = id < 2 ? 32 : 64;
  const unsigned count = 8192u / sew;
  const unsigned before = errors;
  uintptr_t vl, after, start;
  initialize(id);
  switch (id) {
  case 0: EXEC(32, "vzext.vf4 v24, v8"); break;
  case 1: EXEC(32, "vsext.vf4 v24, v8"); break;
  case 2: EXEC(64, "vzext.vf8 v24, v8"); break;
  default: EXEC(64, "vsext.vf8 v24, v8"); break;
  }
  check(vl, count);
  check(after, count);
  check(start, 0);
  for (unsigned i = 0; i < count; ++i) {
    uint64_t expected = pattern(0, i, id);
    if ((id & 1u) && (expected & 128u)) expected |= UINT64_MAX << 8;
    if (sew == 32) expected &= UINT32_MAX;
    uint64_t actual = output.data[i * sew / 64] >> ((i * sew) % 64);
    if (sew == 32) actual &= UINT32_MAX;
    check(actual, expected);
  }
  volatile struct region *regions[] = {&source, &unused_source, &destination, &output};
  for (unsigned b = 0; b < 4; ++b)
    for (unsigned i = 0; i < 8; ++i) {
      check(regions[b]->before[i], UINT64_C(0x13579bdf2468ace0) ^ (b * 17u + i));
      check(regions[b]->after[i], UINT64_C(0xfedcba9876543210) ^ (b * 17u + i));
    }
  printf("EXT_CASE %u checks=%u errors=%u\n", id, checks, errors - before);
}
int main(void) {
  // The official runtime enables vector state before it enters U mode.
  asm volatile("csrw vstart, zero" : : : "memory");
  uintptr_t vlenb;
  asm volatile("csrr %0, vlenb" : "=r"(vlenb));
  check(vlenb, 256);
  if (vlenb == 256) for (unsigned id = 0; id < 4; ++id) run(id);
  printf("EXT_DONE cases=4 checks=%u errors=%u\n", checks, errors);
  return errors ? 1 : 0;
}
