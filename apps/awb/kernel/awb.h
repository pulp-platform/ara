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

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdio.h>
#include <stdint.h>

#include "riscv_vector.h"

uint8_t clip_u8_f32_s(float f32);
float avg_8b_s(const uint8_t *i, size_t len);
void gw_awb_s(const uint8_t *i, uint64_t ch_size);
void gw_awb_v(const uint8_t *i, uint64_t ch_size);
