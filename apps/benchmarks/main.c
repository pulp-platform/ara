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
#include <string.h>

#include "printf.h"
#include "runtime.h"

#if defined(IMATMUL)
#include "benchmark/imatmul.bmark"
#include "kernel/imatmul.h"

#elif defined(FMATMUL)
#include "benchmark/fmatmul.bmark"
#include "kernel/fmatmul.h"

#elif defined(ICONV2D)
#include "benchmark/iconv2d.bmark"
#include "kernel/iconv2d.h"

#elif defined(FCONV2D)
#include "benchmark/fconv2d.bmark"
#include "kernel/fconv2d.h"
#endif

#elif defined(FCONV3D)
#include "benchmark/fconv3d.bmark"
#include "kernel/fconv3d.h"
#endif
