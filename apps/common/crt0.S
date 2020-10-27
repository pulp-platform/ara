// Copyright 2020 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Samuel Riedel, ETH Zurich
//         Matheus Cavalcante, ETH Zurich

.globl _start
.globl _eoc
.globl _fail
.section .text;
.section .text.init;

#define MSTATUS_FS          0x00006000
#define MSTATUS_VS          0x00000600

_start:
    // Initialize global pointer
    .option push
    .option norelax
    1:auipc gp, %pcrel_hi(__global_pointer$)
      addi  gp, gp, %pcrel_lo(1b)
    .option pop

    /* reset vector */
    j reset_vector
reset_vector:
    li      x1, 0
    li      x4, 0
    li      x5, 0
    li      x6, 0
    li      x7, 0
    li      x8, 0
    li      x9, 0
    li      x10, 0
    li      x11, 0
    li      x12, 0
    li      x13, 0
    li      x14, 0
    li      x15, 0
    li      x16, 0
    li      x17, 0
    li      x18, 0
    li      x19, 0
    li      x20, 0
    li      x10, 0
    li      x21, 0
    li      x22, 0
    li      x23, 0
    li      x24, 0
    li      x25, 0
    li      x26, 0
    li      x27, 0
    li      x28, 0
    li      x29, 0
    li      x30, 0
    li      x31, 0
    // Activate FP Extension
    li      sp, (MSTATUS_FS & (MSTATUS_FS >> 1))
    csrs    mstatus, sp
    csrwi   fcsr, 0
    // Activate Vector Extension
    li      sp, (MSTATUS_VS & (MSTATUS_VS >> 1))
    csrs    mstatus, sp
    // Initialize stack at the end of the DRAM region
    la      sp, dram_end_address_reg
    ld      sp, 0(sp)
    // Call main
    call    main

_eoc:
    la t0, eoc_address_reg
    sw a0, 0(t0)
    jal x0, _eoc

_fail:
    la t0, eoc_address_reg
    sw a0, 0(t0)
    jal x0, _eoc

.section .data
