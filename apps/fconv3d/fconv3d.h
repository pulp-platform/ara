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

#ifndef FCONV3D_H
#define FCONV3D_H

#include <stdint.h>
#include <stdio.h>

void fconv3d_CHx7x7(double *o, double *i, double *f, int64_t M, int64_t N,
                    int64_t C, int64_t F);

void fconv3d_CHx7x7_block(double *o, double *i, double *f, int64_t M, int64_t N,
                          int64_t n_, int64_t C, int64_t F);

#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Threshold for FP numbers comparison during the final check
#define THRESHOLD 0.000000000001
// #define THRESHOLD 0

#endif
