// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"
#include <stdint.h>

int main(void) {
  INIT_CHECK();
  enable_vec();
  uint64_t scalar = 314;
  uint64_t scalar2 = 0;
  __asm__ volatile("vsetvl t0, %[A], %[B]" ::[A] "r"(scalar), [B] "r"(scalar2));
  scalar = 15;
  scalar2 = 5;
  __asm__ volatile("vsetvl t0, %[A], %[B]" ::[A] "r"(scalar), [B] "r"(scalar2));
  scalar = 255;
  scalar2 = 10;
  __asm__ volatile("vsetvl t0, %[A], %[B]" ::[A] "r"(scalar), [B] "r"(scalar2));
  scalar = 69;
  scalar2 = 15;
  __asm__ volatile("vsetvl t0, %[A], %[B]" ::[A] "r"(scalar), [B] "r"(scalar2));
  return (0);
}
