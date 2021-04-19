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

#ifndef EW_H
#define EW_H

// Ara supports the following element widths.
typedef enum { EW8 = 8, EW16 = 16, EW32 = 32, EW64 = 64 } ew_t;

// Standard element width of the vector elements.
// Should be defined through the Makefile!
// #define SEW EW64

// Type of the vector elements
#if (SEW == 8)
#define velement_t int8_t
#elif (SEW == 16)
#define velement_t int16_t
#elif (SEW == 32)
#define velement_t int32_t
#elif (SEW == 64)
#define velement_t int64_t
#endif

#endif // EW_H
