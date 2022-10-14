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

#ifndef FMATMUL_H
#define FMATMUL_H

#include <stdint.h>

void fmatmul(double *c, const double *a, const double *b, unsigned long int m,
             unsigned long int n, unsigned long int p);

void fmatmul_4x4(double *c, const double *a, const double *b,
                 unsigned long int m, unsigned long int n, unsigned long int p);
void fmatmul_vec_4x4_slice_init();
void fmatmul_vec_4x4(double *c, const double *a, const double *b,
                     unsigned long int n, unsigned long int p);

void fmatmul_8x8(double *c, const double *a, const double *b,
                 unsigned long int m, unsigned long int n, unsigned long int p);
void fmatmul_vec_8x8_slice_init();
void fmatmul_vec_8x8(double *c, const double *a, const double *b,
                     unsigned long int n, unsigned long int p);

void fmatmul_16x16(double *c, const double *a, const double *b,
                   unsigned long int m, unsigned long int n,
                   unsigned long int p);
void fmatmul_vec_16x16_slice_init();
void fmatmul_vec_16x16(double *c, const double *a, const double *b,
                       unsigned long int n, unsigned long int p);

#define DELTA 0.000001

extern int64_t event_trigger;

#endif
