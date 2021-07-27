// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti

#include "vector_macros.h"

uint64_t counter;

// Vectors are statically allocated not to exceed the stack and go in the UART address space

uint8_t  gold_vec_8b[4096];
uint16_t gold_vec_16b[2048];
uint32_t gold_vec_32b[1024];
uint64_t gold_vec_64b[512];

uint8_t  zero_vec_8b[4096];
uint16_t zero_vec_16b[2048];
uint32_t zero_vec_32b[1024];
uint64_t zero_vec_64b[512];

uint8_t  buf_vec_8b[4096];
uint16_t buf_vec_16b[2048];
uint32_t buf_vec_32b[1024];
uint64_t buf_vec_64b[512];

////////////
// vl1reX //
////////////

// 1 whole register load
void TEST_CASE1(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, 512);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" :: "r" (gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(512, e8, m1);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 0, buf_vec_8b, gold_vec_8b, 512);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v17, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 0, buf_vec_8b, zero_vec_8b, 512);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, 256);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, 256);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, 256);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re16.v v16, (%0)" :: "r" (gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(256, e16, m1);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, %hu, 1, buf_vec_16b, gold_vec_16b, 256);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v17, buf_vec_16b);
  VMCMP(uint16_t, %hu, 1, buf_vec_16b, zero_vec_16b, 256);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, 128);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, 128);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, 128);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re32.v v16, (%0)" :: "r" (gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(128, e32, m1);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, %u, 2, buf_vec_32b, gold_vec_32b, 128);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v17, buf_vec_32b);
  VMCMP(uint32_t, %u, 2, buf_vec_32b, zero_vec_32b, 128);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, 64);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, 64);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, 64);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re64.v v16, (%0)" :: "r" (gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(64, e64, m1);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, %lu, 3, buf_vec_64b, gold_vec_64b, 64);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v17, buf_vec_64b);
  VMCMP(uint64_t, %lu, 3, buf_vec_64b, zero_vec_64b, 64);
}

////////////
// vl2reX //
////////////

// 2 whole registers load
void TEST_CASE2(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, 1024);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, 1024);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, 1024);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re8.v v16, (%0)" :: "r" (gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(1024, e8, m2);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 4, buf_vec_8b, gold_vec_8b, 1024);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v18, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 4, buf_vec_8b, zero_vec_8b, 1024);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, 512);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re16.v v16, (%0)" :: "r" (gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(512, e16, m2);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, %hu, 5, buf_vec_16b, gold_vec_16b, 512);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v18, buf_vec_16b);
  VMCMP(uint16_t, %hu, 5, buf_vec_16b, zero_vec_16b, 512);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, 256);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, 256);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, 256);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re32.v v16, (%0)" :: "r" (gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(256, e32, m2);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, %u, 6, buf_vec_32b, gold_vec_32b, 256);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v18, buf_vec_32b);
  VMCMP(uint32_t, %u, 6, buf_vec_32b, zero_vec_32b, 256);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, 128);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, 128);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, 128);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re64.v v16, (%0)" :: "r" (gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(128, e64, m2);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, %lu, 7, buf_vec_64b, gold_vec_64b, 128);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v18, buf_vec_64b);
  VMCMP(uint64_t, %lu, 7, buf_vec_64b, zero_vec_64b, 128);
}

////////////
// vl4reX //
////////////

// 4 whole registers load
void TEST_CASE3(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, 2048);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, 2048);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, 2048);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re8.v v16, (%0)" :: "r" (gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(2048, e8, m4);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 8, buf_vec_8b, gold_vec_8b, 2048);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v20, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 8, buf_vec_8b, zero_vec_8b, 2048);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, 1024);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, 1024);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, 1024);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re16.v v16, (%0)" :: "r" (gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(1024, e16, m4);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, %hu, 9, buf_vec_16b, gold_vec_16b, 1024);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v20, buf_vec_16b);
  VMCMP(uint16_t, %hu, 9, buf_vec_16b, zero_vec_16b, 1024);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, 512);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re32.v v16, (%0)" :: "r" (gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(512, e32, m4);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, %u, 10, buf_vec_32b, gold_vec_32b, 512);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v20, buf_vec_32b);
  VMCMP(uint32_t, %u, 10, buf_vec_32b, zero_vec_32b, 512);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, 256);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, 256);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, 256);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re64.v v16, (%0)" :: "r" (gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(256, e64, m4);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, %lu, 11, buf_vec_64b, gold_vec_64b, 256);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v20, buf_vec_64b);
  VMCMP(uint64_t, %lu, 11, buf_vec_64b, zero_vec_64b, 256);
}

////////////
// vl8reX //
////////////

// 8 whole registers load
void TEST_CASE4(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, 4096);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, 4096);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, 4096);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re8.v v16, (%0)" :: "r" (gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(4096, e8, m8);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 12, buf_vec_8b, gold_vec_8b, 4096);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v24, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 12, buf_vec_8b, zero_vec_8b, 4096);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_16b, 2048);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_16b, 2048);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_16b, 2048);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re16.v v16, (%0)" :: "r" (gold_vec_16b));
  // Change vtype and vl to match the whole register
  VSET(2048, e16, m8);
  // Check that the whole register was loaded
  VSTORE(uint16_t, e16, v16, buf_vec_16b);
  VMCMP(uint16_t, %hu, 13, buf_vec_16b, gold_vec_16b, 2048);
  // Check that the neighbour registers are okay
  VSTORE(uint16_t, e16, v24, buf_vec_16b);
  VMCMP(uint16_t, %hu, 13, buf_vec_16b, zero_vec_16b, 2048);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_32b, 1024);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_32b, 1024);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_32b, 1024);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re32.v v16, (%0)" :: "r" (gold_vec_32b));
  // Change vtype and vl to match the whole register
  VSET(1024, e32, m8);
  // Check that the whole register was loaded
  VSTORE(uint32_t, e32, v16, buf_vec_32b);
  VMCMP(uint32_t, %u, 14, buf_vec_32b, gold_vec_32b, 1024);
  // Check that the neighbour registers are okay
  VSTORE(uint32_t, e32, v24, buf_vec_32b);
  VMCMP(uint32_t, %u, 14, buf_vec_32b, zero_vec_32b, 1024);

  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_64b, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_64b, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_64b, 512);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re64.v v16, (%0)" :: "r" (gold_vec_64b));
  // Change vtype and vl to match the whole register
  VSET(512, e64, m8);
  // Check that the whole register was loaded3
  VSTORE(uint64_t, e64, v16, buf_vec_64b);
  VMCMP(uint64_t, %lu, 15, buf_vec_64b, gold_vec_64b, 512);
  // Check that the neighbour registers are okay
  VSTORE(uint64_t, e64, v24, buf_vec_64b);
  VMCMP(uint64_t, %lu, 15, buf_vec_64b, zero_vec_64b, 512);
}

////////////
// Others //
////////////

// Check with initial vl == 0
void TEST_CASE5(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vec_8b, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vec_8b, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vec_8b, 512);
  // Set vl and vtype to super short values
  VSET(0, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" :: "r" (gold_vec_8b));
  // Change vtype and vl to match the whole register
  VSET(512, e8, m1);
  // Check that the whole register was loaded
  VSTORE(uint8_t, e8, v16, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 16, buf_vec_8b, gold_vec_8b, 512);
  // Check that the neighbour registers are okay
  VSTORE(uint8_t, e8, v17, buf_vec_8b);
  VMCMP(uint8_t, %hhu, 16, buf_vec_8b, zero_vec_8b, 512);
}

int main(void){
  INIT_CHECK();
  enable_vec();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  EXIT_CHECK();
}
