#ifndef _PATHFINDER_H_
#define _PATHFINDER_H_

#include <stdint.h>

#include "riscv_vector.h"

#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

int *run(int *wall, int *result_s, int *src, uint32_t cols, uint32_t rows,
         uint32_t num_runs);
void run_vector(int *wall, int *result_v, uint32_t cols, uint32_t rows,
                uint32_t num_runs);
void run_vector_short_m4(int *wall, int *result_v, uint32_t cols, uint32_t rows,
                         uint32_t num_runs, int neutral_value);

#endif
