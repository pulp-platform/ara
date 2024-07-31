// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti <mperotti@ethz.ch>
//
// Cheshire-related util

#ifndef __CHESHIRE_UTIL_H__
#define __CHESHIRE_UTIL_H__

#include "printf.h"

void cheshire_start() {
  // Initialize Cheshire's UART
  uint32_t rtc_freq = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
  uint64_t reset_freq = clint_get_core_freq(rtc_freq, 2500);
  uart_init(&__base_uart, reset_freq, __BOOT_BAUDRATE);
}

void cheshire_end() {
  // Flush teh UART
  uart_write_flush(&__base_uart);
}

#endif
