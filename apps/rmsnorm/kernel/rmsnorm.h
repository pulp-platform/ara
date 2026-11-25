// Copyright 2026 ETH Zurich and University of Bologna.
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

#ifndef _RMSNORM_H_
#define _RMSNORM_H_

#include <stdint.h>

#include "riscv_vector.h"

// y = x / sqrt(mean(x^2) + eps) * gamma, per row of d elements
void rmsnorm_vec(const float *x, const float *gamma, float *y, uint64_t rows,
                 uint64_t d, float eps);

#endif
