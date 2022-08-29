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

// Author: Matteo Perotti

#ifndef FCONV2D_H
#define FCONV2D_H

#include <stdint.h>
#include <stdio.h>

void fconv2d_3x3(double *o, double *i, double *f, int64_t R, int64_t C,
                 int64_t F);
void fconv2d_vec_4xC_slice_init_3x3(double *o, int64_t C);
void fconv2d_vec_4xC_slice_preload_3x3(double *i, int64_t C, int64_t F);
void fconv2d_vec_4xC_slice_move_3x3(int64_t C, int64_t F);
void fconv2d_vec_4xC_3x3(double *o, double *i, double *f, int64_t C, int64_t F);

void fconv2d_7x7(double *o, double *i, double *f, int64_t R, int64_t C,
                 int64_t F);
void fconv2d_7x7_block(double *o, double *i, double *f, int64_t R, int64_t C,
                       int64_t n_, int64_t F);

#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Threshold for FP numbers comparison during the final check
#define THRESHOLD 0.000000000001
// #define THRESHOLD 0

#endif
