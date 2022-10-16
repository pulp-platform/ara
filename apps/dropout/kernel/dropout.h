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

#ifndef _DROPOUT_H_
#define _DROPOUT_H_

#include <stdio.h>

#include <riscv_vector.h>

#define INTRINSICS
// Use asm, by default
#undef INTRINSICS

#include "runtime.h"

#ifndef SPIKE
#include "printf.h"
#endif

void dropout_gold(const unsigned int n, const float *i, const float scale,
                  const uint8_t *sel_ptr, float *o);
void dropout_vec(const unsigned int n, const float *i, const float scale,
                 const uint8_t *sel_ptr, float *o);

#endif
