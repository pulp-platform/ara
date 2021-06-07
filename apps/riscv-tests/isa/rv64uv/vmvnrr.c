// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti
//
// For simplicity, this test depends on vl1r and vs1r

#include "vector_macros.h"

uint64_t counter;

//////////
// vs1r //
//////////

// 1 whole register load
void TEST_CASE1(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vector_0, uint8_t, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vector_0, uint8_t, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vector_0, uint8_t, 512);
  // Set vl and vtype to super short values
  VSET(1, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" :: "r" (gold_vector_0));
  // Move the content to another register
  asm volatile("vmv1r.v v1, v16");
  // Check that the whole register was loaded
  asm volatile("vs1r.v v1, (%0)" :: "r" (buf_vector_0));
  VMCMP(uint8_t, %hhu, 0, buf_vector_0, gold_vector_0);
}

//////////
// vs2r //
//////////

// 2 whole registers load
void TEST_CASE2(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vector_0, uint8_t, 1024);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vector_0, uint8_t, 1024);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vector_0, uint8_t, 1024);
  // Set vl and vtype to super short values
  VSET(1, e64, m4);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl2re8.v v16, (%0)" :: "r" (gold_vector_0));
  // Move the content to another register
  asm volatile("vmv2r.v v2, v16");
  // Check that the whole register was loaded
  asm volatile("vs2r.v v2, (%0)" :: "r" (buf_vector_0));
  VMCMP(uint8_t, %hhu, 1, buf_vector_0, gold_vector_0);
}

//////////
// vs4r //
//////////

// 4 whole registers load
void TEST_CASE3(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vector_0, uint8_t, 2048);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vector_0, uint8_t, 2048);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vector_0, uint8_t, 2048);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl4re8.v v16, (%0)" :: "r" (gold_vector_0));
  // Move the content to another register
  asm volatile("vmv4r.v v4, v16");
  // Check that the whole register was loaded
  asm volatile("vs4r.v v4, (%0)" :: "r" (buf_vector_0));
  VMCMP(uint8_t, %hhu, 2, buf_vector_0, gold_vector_0);
}


//////////
// vs8r //
//////////

// 8 whole registers load
void TEST_CASE4(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vector_0, uint8_t, 4096);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vector_0, uint8_t, 4096);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vector_0, uint8_t, 4096);
  // Set vl and vtype to super short values
  VSET(1, e64, m8);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  VCLEAR(v24);
  // Load a buffer from memory - whole register load
  asm volatile("vl8re8.v v16, (%0)" :: "r" (gold_vector_0));
  // Move the content to another register
  asm volatile("vmv8r.v v8, v16");
  // Check that the whole register was loaded
  asm volatile("vs8r.v v8, (%0)" :: "r" (buf_vector_0));
  VMCMP(uint8_t, %hhu, 3, buf_vector_0, gold_vector_0);
}

////////////
// Others //
////////////

// Check with initial vl == 0
void TEST_CASE5(void) {
  // Initialize a golden vector
  INIT_MEM_CNT(gold_vector_0, uint8_t, 512);
  // Initialize a zero golden vector
  INIT_MEM_ZEROES(zero_vector_0, uint8_t, 512);
  // Reserve space for a buffer in memory
  INIT_MEM_ZEROES(buf_vector_0, uint8_t, 512);
  // Set vl and vtype to super short values
  VSET(0, e64, m2);
  // Initialize register + neighbours to pattern value
  VCLEAR(v16);
  // Load a buffer from memory - whole register load
  asm volatile("vl1re8.v v16, (%0)" :: "r" (gold_vector_0));
  // Move the content to another register
  asm volatile("vmv1r.v v1, v16");
  // Check that the whole register was loaded
  asm volatile("vs1r.v v1, (%0)" :: "r" (buf_vector_0));
  VMCMP(uint8_t, %hhu, 4, buf_vector_0, gold_vector_0);
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
