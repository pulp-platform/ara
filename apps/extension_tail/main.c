// SPDX-License-Identifier: Apache-2.0
#include <stdint.h>
#include "printf.h"
struct region { uint64_t before[8], data[128], after[8]; };
static volatile struct region source, destination, output;
static volatile uint8_t selection[32];
static unsigned checks, errors;
static uint8_t pattern(unsigned b, unsigned i, unsigned id) {
  return (uint8_t)(0x31u + b * 71u + i * 29u + (i >> 3) * 17u + id * 23u);
}
static void check(uint64_t actual, uint64_t expected) {
  ++checks;
  if (actual != expected) ++errors;
}
static void initialize(unsigned id) {
  volatile struct region *regions[] = {&source, &destination, &output};
  for (unsigned b = 0; b < 3; ++b) {
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
// Use x5 for export. This isolates an existing x8/v8 name collision.
#define EXEC(OP)                                                              \
  asm volatile("csrw vstart, zero\nli t0, 256\n"                             \
               "vsetvli t0, t0, e32, m4, tu, mu\n"                           \
               "vle32.v v8, (%[old])\ncsrr t0, vl\n"                         \
               "li t0, 256\nvsetvli t0, t0, e8, m1, tu, mu\n"               \
               "vle8.v v11, (%[src])\ncsrr t0, vl\n"                         \
               "vlm.v v0, (%[mask])\ncsrr t0, vl\n"                          \
               "vsetvli %[vl], %[length], e32, m4, tu, mu\n"                 \
               "csrw vstart, %[initial_start]\n"                             \
               OP "\ncsrr %[after], vl\ncsrr %[start], vstart\n"             \
               "mv t0, %[out]\nvs4r.v v8, (t0)\nfence rw, rw\n"                          \
               : [vl] "=&r"(vl), [after] "=&r"(after), [start] "=&r"(start)    \
               : [old] "r"(destination.data), [src] "r"(source.data),          \
                 [mask] "r"(selection), [length] "r"((uintptr_t)length),      \
                 [initial_start] "r"((uintptr_t)initial_start),               \
                 [out] "r"(output.data)                                       \
               : "t0", "v0", "v8", "v9", "v10", "v11", "memory")
static void run(unsigned id) {
  uintptr_t vl, after, start;
  const unsigned before = errors;
  const unsigned length = id == 6 ? 0 : 255;
  const unsigned initial_start = id == 7 ? 255 : 0;
  initialize(id);
  for (unsigned i = 0; i < 32; ++i) selection[i] = id == 5 ? 0 : 0x55;
  if (id == 1) { EXEC("vsext.vf4 v8, v11"); }
  else if (id == 4 || id == 5) { EXEC("vzext.vf4 v8, v11, v0.t"); }
  else { EXEC("vzext.vf4 v8, v11"); }
  check(vl, length); check(after, length); check(start, 0);
  for (unsigned i = 0; i < 256; ++i) {
    const unsigned inactive = i < initial_start || i >= length ||
        ((id == 4 || id == 5) && !(selection[i / 8] & (1u << (i % 8))));
    uint32_t expected = pattern(0, i, id);
    if (id == 1 && (expected & 128u)) expected |= UINT32_MAX << 8;
    if (inactive) {
      expected = 0;
      for (unsigned b = 0; b < 4; ++b) {
        const unsigned offset = i * 4 + b;
        expected |= (uint32_t)(offset >= 768 ? pattern(0, offset - 768, id)
                                            : pattern(1, offset, id)) << (b * 8u);
      }
    }
    uint32_t actual = output.data[i / 2] >> ((i % 2) * 32);
    if (inactive && initial_start < length && actual == UINT32_MAX) check(1, 1);
    else check(actual, expected);
  }
  volatile struct region *regions[] = {&source, &destination, &output};
  for (unsigned b = 0; b < 3; ++b)
    for (unsigned i = 0; i < 8; ++i) {
      check(regions[b]->before[i], UINT64_C(0x13579bdf2468ace0) ^ (b * 17u + i));
      check(regions[b]->after[i], UINT64_C(0xfedcba9876543210) ^ (b * 17u + i));
    }
  printf("TAIL_CASE %u checks=%u errors=%u\n", id, checks, errors - before);
}
int main(void) {
  static const unsigned ids[] = {0, 1, 4, 5, 6, 7};
  for (unsigned i = 0; i < 6; ++i) run(ids[i]);
  printf("TAIL_DONE cases=6 checks=%u errors=%u\n", checks, errors);
  return errors ? 1 : 0;
}
