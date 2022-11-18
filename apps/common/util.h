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
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//
// Utility functions for Ara software environment (header file)

#ifndef __UTIL_H__
#define __UTIL_H__

#ifdef GATE_SIM
#define NO_PRINTF
#endif

#ifdef VCD_DUMP
#pragma message("VCD_DUMP successfully initialized")
#define NO_PRINTF
#define NO_TIMER
#endif

// Don't measure performance
#ifdef NO_TIMER
#define start_timer()
#define stop_timer()
#define get_timer() 0
#endif

// Don't print anything
#ifdef NO_PRINTF
#define printf_(...)
#endif

#define FABS(x) ((x < 0) ? -x : x)

#define FABS(x) ((x < 0) ? -x : x)
#define MIN(a, b) ((a) <= (b) ? (a) : (b))

// Floating-point similarity check with threshold
int similarity_check(double a, double b, double threshold);
int similarity_check_32b(float a, float b, float threshold);

// Dummy declaration for libm exp
int *__errno(void);

#endif
