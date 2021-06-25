// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile uint8_t OUTPUT[256] __attribute__((aligned(64)));

void TEST_CASE1(void) {
  VSET(256, e8, m1);
  volatile uint8_t GOLD[256];
  uint8_t counter = 0;
  for (int i = 0; i < 256; i++) {
    GOLD[i] = counter;
    counter++;
  }
  MEMBARRIER;
  __asm__ volatile("vle8.v v1, (%[A])" ::[A] "r"(GOLD));
  __asm__ volatile("vs1r.v v1, (%[A])" ::[A] "r"(OUTPUT));
  VEC_CMP_BUFF_U8(1, v1, OUTPUT, GOLD);
}

void TEST_CASE2(void) {
  VSET(256, e8, m1);
  volatile uint8_t GOLD[256];
  uint8_t counter = 0;
  for (int i = 0; i < 256; i++) {
    GOLD[i] = counter;
    counter++;
  }
  MEMBARRIER;
  __asm__ volatile("vle8.v v2, (%[A])" ::[A] "r"(GOLD));
  __asm__ volatile("vs1r.v v2, (%[A])" ::[A] "r"(OUTPUT));
  VEC_CMP_BUFF_U8(1, v2, OUTPUT, GOLD);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
