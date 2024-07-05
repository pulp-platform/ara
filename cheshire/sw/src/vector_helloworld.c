// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti <mperotti@ethz.ch>
//
// Simple vector memcpy for Hello World!

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "params.h"
#include "util.h"

#include "cheshire_util.h"
#include "vector_util.h"

unsigned char buf[64];

int main(void) {
    cheshire_start();
    enable_rvv();

    const unsigned char str[] = "Hello Vector World!\r\n";
    vuint8m1_t str_v;

    // Copy the hello world string to buf
    str_v = __riscv_vle8_v_u8m1(str, sizeof(str));
    __riscv_vse8_v_u8m1(buf, str_v, sizeof(str));

    // Print buf
    printf("%s", str_v);

    cheshire_end();

    return 0;
}
