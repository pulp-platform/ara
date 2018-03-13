#pragma once
#include "rvblas.h"

extern volatile uint64_t aratest;

#define TEST_START(tag) do { aratest = ((tag) << 2 | 3); } while(0)
#define   TEST_END(tag) do { aratest = ((tag) << 2 | 1); } while(0)

extern uint32_t in_dim;

extern char in_A[];
extern char in_B[];
extern char in_C[];

extern char in_alpha[];
extern char in_beta[];

extern char out_exp[];
