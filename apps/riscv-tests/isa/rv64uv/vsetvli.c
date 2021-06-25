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
  __asm__ volatile("vsetvli t0, %[A], e8, m1" ::[A] "r"(scalar));
  scalar = 15;
  __asm__ volatile("vsetvli t0, %[A], e16, m2" ::[A] "r"(scalar));
  scalar = 255;
  __asm__ volatile("vsetvli t0, %[A], e32, m4" ::[A] "r"(scalar));
  scalar = 69;
  __asm__ volatile("vsetvli t0, %[A], e64, m8" ::[A] "r"(scalar));
  scalar = 69;
  __asm__ volatile("vsetvli t0, %[A], e128, m8" ::[A] "r"(scalar));
  scalar = 15;
  __asm__ volatile("vsetvli t0, %[A], e8, m8" ::[A] "r"(scalar));
  scalar = 10000;
  __asm__ volatile("vsetvli t0, %[A], e16, m2" ::[A] "r"(scalar));
  return (0);
}
