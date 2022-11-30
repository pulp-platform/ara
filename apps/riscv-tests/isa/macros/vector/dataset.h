// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

#ifndef __DATASET_H__
#define __DATASET_H__

#define SIZE 16
#define L_SIZE 1024

static volatile uint64_t Au64[SIZE] __attribute__((aligned(128)));
static volatile uint32_t Au32[SIZE] __attribute__((aligned(128)));
static volatile uint16_t Au16[SIZE] __attribute__((aligned(128)));
static volatile uint8_t  Au8 [SIZE] __attribute__((aligned(128)));
static volatile int64_t  Ai64[SIZE] __attribute__((aligned(128)));
static volatile int32_t  Ai32[SIZE] __attribute__((aligned(128)));
static volatile int16_t  Ai16[SIZE] __attribute__((aligned(128)));
static volatile int8_t   Ai8 [SIZE] __attribute__((aligned(128)));
static volatile uint64_t Af64[SIZE] __attribute__((aligned(128)));
static volatile uint32_t Af32[SIZE] __attribute__((aligned(128)));
static volatile uint16_t Af16[SIZE] __attribute__((aligned(128)));

static volatile uint64_t Ru64[SIZE] __attribute__((aligned(128)));
static volatile uint32_t Ru32[SIZE] __attribute__((aligned(128)));
static volatile uint16_t Ru16[SIZE] __attribute__((aligned(128)));
static volatile uint8_t  Ru8 [SIZE] __attribute__((aligned(128)));
static volatile int64_t  Ri64[SIZE] __attribute__((aligned(128)));
static volatile int32_t  Ri32[SIZE] __attribute__((aligned(128)));
static volatile int16_t  Ri16[SIZE] __attribute__((aligned(128)));
static volatile int8_t   Ri8 [SIZE] __attribute__((aligned(128)));
static volatile uint64_t Rf64[SIZE] __attribute__((aligned(128)));
static volatile uint32_t Rf32[SIZE] __attribute__((aligned(128)));
static volatile uint16_t Rf16[SIZE] __attribute__((aligned(128)));

static volatile uint64_t Lu64[L_SIZE] __attribute__((aligned(128)));
static volatile uint32_t Lu32[L_SIZE] __attribute__((aligned(128)));
static volatile uint16_t Lu16[L_SIZE] __attribute__((aligned(128)));
static volatile uint8_t  Lu8 [L_SIZE] __attribute__((aligned(128)));

static volatile uint64_t Xf64[1] __attribute__((aligned(128)));
static volatile uint32_t Xf32[1] __attribute__((aligned(128)));
static volatile uint16_t Xf16[1] __attribute__((aligned(128)));

#undef SIZE

#endif  // __DATASET__H__
