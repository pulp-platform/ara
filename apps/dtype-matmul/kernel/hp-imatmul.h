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

// Author: Matheus Cavalcante, ETH Zurich
//         Samuel Riedel, ETH Zurich

#ifndef MATMUL_H
#define MATMUL_H

#include "util.h"
#include <stdint.h>
#include <string.h>

// Help calculate performance
// How many parallel elements in an ELEN-wide FPU data bus?
#define DTYPE_FACTOR 4

extern int64_t event_trigger;

void hp_imatmul(int16_t *c, const int16_t *a, const int16_t *b,
                const unsigned int m, const unsigned int n,
                const unsigned int p);

void hp_imatmul_4x4(int16_t *c, const int16_t *a, const int16_t *b,
                    const unsigned int m, const unsigned int n,
                    const unsigned int p);
void hp_imatmul_vec_4x4_slice_init();
void hp_imatmul_vec_4x4(int16_t *c, const int16_t *a, const int16_t *b,
                        const unsigned int n, const unsigned int p);

void hp_imatmul_8x8(int16_t *c, const int16_t *a, const int16_t *b,
                    const unsigned int m, const unsigned int n,
                    const unsigned int p);
void hp_imatmul_vec_8x8_slice_init();
void hp_imatmul_vec_8x8(int16_t *c, const int16_t *a, const int16_t *b,
                        const unsigned int n, const unsigned int p);

void hp_imatmul_16x16(int16_t *c, const int16_t *a, const int16_t *b,
                      const unsigned int m, const unsigned int n,
                      const unsigned int p);
void hp_imatmul_vec_16x16_slice_init();
void hp_imatmul_vec_16x16(int16_t *c, const int16_t *a, const int16_t *b,
                          const unsigned int n, const unsigned int p);

int hp_imatmul_verify(int16_t *result, int16_t *gold, size_t R, size_t C);

#endif
