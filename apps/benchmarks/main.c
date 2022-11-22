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
//         Samuel Riedel, ETH Zurich
//         Matteo Perotti, ETH Zurich

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "runtime.h"

#ifndef SPIKE
#include "printf.h"
#endif

#if defined(IMATMUL)
#include "benchmark/imatmul.bmark"

#elif defined(FMATMUL)
#include "benchmark/fmatmul.bmark"

#elif defined(ICONV2D)
#include "benchmark/iconv2d.bmark"

#elif defined(FCONV2D)
#include "benchmark/fconv2d.bmark"

#elif defined(FCONV3D)
#include "benchmark/fconv3d.bmark"

#elif defined(JACOBI2D)
#include "benchmark/jacobi2d.bmark"

#elif defined(DROPOUT)
#include "benchmark/dropout.bmark"

#elif defined(FFT)
#include "benchmark/fft.bmark"

#elif defined(DWT)
#include "benchmark/dwt.bmark"

#elif defined(EXP)
#include "benchmark/exp.bmark"

#elif defined(SOFTMAX)
#include "benchmark/softmax.bmark"

#elif defined(DOTPRODUCT)
#include "benchmark/dotproduct.bmark"

#elif defined(FDOTPRODUCT)
#include "benchmark/fdotproduct.bmark"

#elif defined(PATHFINDER)
#include "benchmark/pathfinder.bmark"

#elif defined(ROI_ALIGN)
#include "benchmark/roi_align.bmark"

#else
#error                                                                         \
    "Error, no kernel was specified. Please, run 'make bin/benchmarks ENV_DEFINES=-D${KERNEL}', where KERNEL contains the kernel to benchmark. For example: 'make bin/benchmarks ENV_DEFINES=-DIMATMUL'."

#endif
