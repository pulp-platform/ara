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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#ifndef _DOTPRODUCT_H_
#define _DOTPRODUCT_H_

#include <stdint.h>
#include <string.h>

#include <riscv_vector.h>

int64_t dotp_v64b(int64_t *a, int64_t *b, uint64_t avl);
int32_t dotp_v32b(int32_t *a, int32_t *b, uint64_t avl);
int16_t dotp_v16b(int16_t *a, int16_t *b, uint64_t avl);
int8_t dotp_v8b(int8_t *a, int8_t *b, uint64_t avl);

int64_t dotp_s64b(int64_t *a, int64_t *b, uint64_t avl);
int32_t dotp_s32b(int32_t *a, int32_t *b, uint64_t avl);
int16_t dotp_s16b(int16_t *a, int16_t *b, uint64_t avl);
int8_t dotp_s8b(int8_t *a, int8_t *b, uint64_t avl);

#endif
