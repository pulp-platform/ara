// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti

#include "vector_macros.h"

uint64_t counter;

// Vectors are statically allocated not to exceed the stack and go in the UART
// address space

// Maximum size: (VLEN/8 Bytes * (MAX_LMUL == 8)) = VLEN
// Define VLEN before compiling me
// #define VLEN 4096
uint8_t gold_vec_8b[VLEN];
uint16_t gold_vec_16b[VLEN / 2];
uint32_t gold_vec_32b[VLEN / 4];
uint64_t gold_vec_64b[VLEN / 8];

uint8_t zero_vec_8b[VLEN];
uint16_t zero_vec_16b[VLEN / 2];
uint32_t zero_vec_32b[VLEN / 4];
uint64_t zero_vec_64b[VLEN / 8];

uint8_t buf_vec_8b[VLEN];
uint16_t buf_vec_16b[VLEN / 2];
uint32_t buf_vec_32b[VLEN / 4];
uint64_t buf_vec_64b[VLEN / 8];

////////////
// vl1reX //
////////////

// 1 whole register load
void TEST_CASE1(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, VLEN / 8);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, VLEN / 8);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, VLEN / 8);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" ::"r"(gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 8, e8, m1);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 0, buf_vec_8b, gold_vec_8b, VLEN / 8);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v17, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 0, buf_vec_8b, zero_vec_8b, VLEN / 8);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, VLEN / 16);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, VLEN / 16);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, VLEN / 16);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re16.v v16, (%0)" ::"r"(gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 16, e16, m1);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, % hu, 1, buf_vec_16b, gold_vec_16b, VLEN / 16);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v17, buf_vec_16b);
  VMCMP(uint16_t, % hu, 1, buf_vec_16b, zero_vec_16b, VLEN / 16);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, VLEN / 32);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, VLEN / 32);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, VLEN / 32);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re32.v v16, (%0)" ::"r"(gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 32, e32, m1);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, % u, 2, buf_vec_32b, gold_vec_32b, VLEN / 32);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v17, buf_vec_32b);
  VMCMP(uint32_t, % u, 2, buf_vec_32b, zero_vec_32b, VLEN / 32);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, VLEN / 64);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, VLEN / 64);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, VLEN / 64);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re64.v v16, (%0)" ::"r"(gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 64, e64, m1);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, % lu, 3, buf_vec_64b, gold_vec_64b, VLEN / 64);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v17, buf_vec_64b);
  VMCMP(uint64_t, % lu, 3, buf_vec_64b, zero_vec_64b, VLEN / 64);
}

////////////
// vl2reX //
////////////

// 2 whole registers load
void TEST_CASE2(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, VLEN / 4);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, VLEN / 4);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, VLEN / 4);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re8.v v16, (%0)" ::"r"(gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 4, e8, m2);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 4, buf_vec_8b, gold_vec_8b, VLEN / 4);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v18, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 4, buf_vec_8b, zero_vec_8b, VLEN / 4);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, VLEN / 8);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, VLEN / 8);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, VLEN / 8);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re16.v v16, (%0)" ::"r"(gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 8, e16, m2);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, % hu, 5, buf_vec_16b, gold_vec_16b, VLEN / 8);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v18, buf_vec_16b);
  VMCMP(uint16_t, % hu, 5, buf_vec_16b, zero_vec_16b, VLEN / 8);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, VLEN / 16);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, VLEN / 16);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, VLEN / 16);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re32.v v16, (%0)" ::"r"(gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 16, e32, m2);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, % u, 6, buf_vec_32b, gold_vec_32b, VLEN / 16);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v18, buf_vec_32b);
  VMCMP(uint32_t, % u, 6, buf_vec_32b, zero_vec_32b, VLEN / 16);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, VLEN / 32);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, VLEN / 32);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, VLEN / 32);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re64.v v16, (%0)" ::"r"(gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 32, e64, m2);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, % lu, 7, buf_vec_64b, gold_vec_64b, VLEN / 32);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v18, buf_vec_64b);
  VMCMP(uint64_t, % lu, 7, buf_vec_64b, zero_vec_64b, VLEN / 32);
}

////////////
// vl4reX //
////////////

// 4 whole registers load
void TEST_CASE3(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, VLEN / 2);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, VLEN / 2);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, VLEN / 2);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re8.v v16, (%0)" ::"r"(gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 2, e8, m4);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 8, buf_vec_8b, gold_vec_8b, VLEN / 2);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v20, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 8, buf_vec_8b, zero_vec_8b, VLEN / 2);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, VLEN / 4);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, VLEN / 4);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, VLEN / 4);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re16.v v16, (%0)" ::"r"(gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 4, e16, m4);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, % hu, 9, buf_vec_16b, gold_vec_16b, VLEN / 4);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v20, buf_vec_16b);
  VMCMP(uint16_t, % hu, 9, buf_vec_16b, zero_vec_16b, VLEN / 4);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, VLEN / 8);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, VLEN / 8);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, VLEN / 8);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re32.v v16, (%0)" ::"r"(gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 8, e32, m4);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, % u, 10, buf_vec_32b, gold_vec_32b, VLEN / 8);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v20, buf_vec_32b);
  VMCMP(uint32_t, % u, 10, buf_vec_32b, zero_vec_32b, VLEN / 8);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, VLEN / 16);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, VLEN / 16);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, VLEN / 16);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re64.v v16, (%0)" ::"r"(gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 16, e64, m4);
  // Check that the whole register was loaded
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, % lu, 11, buf_vec_64b, gold_vec_64b, VLEN / 16);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v20, buf_vec_64b);
  VMCMP(uint64_t, % lu, 11, buf_vec_64b, zero_vec_64b, VLEN / 16);
}

////////////
// vl8reX //
////////////

// 8 whole registers load
void TEST_CASE4(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, VLEN);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, VLEN);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, VLEN);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re8.v v16, (%0)" ::"r"(gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(VLEN, e8, m8);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 12, buf_vec_8b, gold_vec_8b, VLEN);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v24, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 12, buf_vec_8b, zero_vec_8b, VLEN);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, VLEN / 2);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, VLEN / 2);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, VLEN / 2);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re16.v v16, (%0)" ::"r"(gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 2, e16, m8);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, % hu, 13, buf_vec_16b, gold_vec_16b, VLEN / 2);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v24, buf_vec_16b);
  VMCMP(uint16_t, % hu, 13, buf_vec_16b, zero_vec_16b, VLEN / 2);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, VLEN / 4);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, VLEN / 4);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, VLEN / 4);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re32.v v16, (%0)" ::"r"(gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 4, e32, m8);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, % u, 14, buf_vec_32b, gold_vec_32b, VLEN / 4);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v24, buf_vec_32b);
  VMCMP(uint32_t, % u, 14, buf_vec_32b, zero_vec_32b, VLEN / 4);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, VLEN / 8);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, VLEN / 8);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, VLEN / 8);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re64.v v16, (%0)" ::"r"(gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 8, e64, m8);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, % lu, 15, buf_vec_64b, gold_vec_64b, VLEN / 8);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v24, buf_vec_64b);
  VMCMP(uint64_t, % lu, 15, buf_vec_64b, zero_vec_64b, VLEN / 8);
}

////////////
// Others //
////////////

// Check with initial vl == 0
void TEST_CASE5(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, VLEN / 8);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, VLEN / 8);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, VLEN / 8);
  // Set vl and vtype to super short values
  VSET(0, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" ::"r"(gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(VLEN / 8, e8, m1);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 16, buf_vec_8b, gold_vec_8b, VLEN / 8);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v17, buf_vec_8b);
  VMCMP(uint8_t, % hhu, 16, buf_vec_8b, zero_vec_8b, VLEN / 8);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  EXIT_CHECK();
}
