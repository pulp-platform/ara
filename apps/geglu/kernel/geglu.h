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

#ifndef _GEGLU_H_
#define _GEGLU_H_

#include <stddef.h>

// o = gelu_tanh(g) * u, with gelu_tanh(g) = 0.5 * g * (1 + tanh(t)),
// t = sqrt(2/pi) * (g + 0.044715 * g^3), computed as g / (1 + exp(-2t))
void geglu_vec(const float *g, const float *u, float *o, size_t len);

#endif
