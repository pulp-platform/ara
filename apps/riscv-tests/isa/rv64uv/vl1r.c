// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include "vector_macros.h"

static volatile uint8_t  OUTPUT [256] __attribute__ ((aligned (64)));

void TEST_CASE1(void) {
  VSET(256,e8,m1);
  static volatile uint8_t GOLD[256];
  uint8_t counter = 0;
  for(int i = 0 ; i < 256; i++) {
    GOLD[i] = counter;
    counter++;
  }
  MEMBARRIER;
  __asm__ volatile ("vl1r.v v1, (%0)"::"r" (GOLD));
  VEC_CMP_BUFF_U8(1,v1,OUTPUT,GOLD);
}

void TEST_CASE2(void) {
  VSET(256,e8,m1);
  volatile uint8_t GOLD[256];
  uint8_t counter = 0;
  for(int i = 0 ; i < 256; i++) {
    GOLD[i] = counter;
    counter++;
  }
  MEMBARRIER;
  __asm__ volatile ("vl1r.v v2, (%0)"::"r" (GOLD));
  VEC_CMP_BUFF_U8(1,v2,OUTPUT,GOLD);
}


int main(void){
  INIT_CHECK();
  enable_vec();
  TEST_CASE1();
  TEST_CASE2();
  EXIT_CHECK();
}
