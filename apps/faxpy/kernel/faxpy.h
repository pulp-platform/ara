// Copyright 2022 ETH Zurich and University of Bologna.
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

// Author: Hong Pang <hopang@iis.ee.ethz.ch>

#ifndef _FAXPY_H_
#define _FAXPY_H_

#include <stdint.h>
#include <string.h>

#include "riscv_vector.h"

void faxpy_v64b(const double a, const double *x, const double *y, size_t avl);
void faxpy_v64b_unrl(const double a, const double *x, const double *y, size_t avl);

// void faxpy_s64b(const double a, const double *x, const double *y, size_t avl);

#endif
