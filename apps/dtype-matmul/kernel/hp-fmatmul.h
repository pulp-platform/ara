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

#define THRESHOLD 0.001

// Help calculate performance
// How many parallel elements in an ELEN-wide FPU data bus?
#define DTYPE_FACTOR 4

extern int64_t event_trigger;

void hp_fmatmul(_Float16 *c, const _Float16 *a, const _Float16 *b,
                const unsigned int m, const unsigned int n,
                const unsigned int p);

void hp_fmatmul_4x4(_Float16 *c, const _Float16 *a, const _Float16 *b,
                    const unsigned int m, const unsigned int n,
                    const unsigned int p);
void hp_fmatmul_vec_4x4_slice_init();
void hp_fmatmul_vec_4x4(_Float16 *c, const _Float16 *a, const _Float16 *b,
                        const unsigned int n, const unsigned int p);

void hp_fmatmul_8x8(_Float16 *c, const _Float16 *a, const _Float16 *b,
                    const unsigned int m, const unsigned int n,
                    const unsigned int p);
void hp_fmatmul_vec_8x8_slice_init();
void hp_fmatmul_vec_8x8(_Float16 *c, const _Float16 *a, const _Float16 *b,
                        const unsigned int n, const unsigned int p);

void hp_fmatmul_16x16(_Float16 *c, const _Float16 *a, const _Float16 *b,
                      const unsigned int m, const unsigned int n,
                      const unsigned int p);
void hp_fmatmul_vec_16x16_slice_init();
void hp_fmatmul_vec_16x16(_Float16 *c, const _Float16 *a, const _Float16 *b,
                          const unsigned int n, const unsigned int p);

int hp_fmatmul_verify(_Float16 *result, _Float16 *gold, size_t R, size_t C,
                      _Float16 threshold);

#endif
