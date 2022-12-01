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

// Author: Chi Zhang, ETH Zurich <chizhang@iis.ee.ethz.ch>

#ifndef _SPMV_H
#define _SPMV_H

#include <stdint.h>

void spmv_csr_idx32(int32_t N_ROW, int32_t *CSR_PROW, int32_t *CSR_INDEX,
                    double *CSR_DATA, double *IN_VEC, double *OUT_VEC);

int spmv_verify(int32_t N_ROW, int32_t *CSR_PROW, int32_t *CSR_INDEX,
                double *CSR_DATA, double *IN_VEC, double *OUT_VEC);

#endif
