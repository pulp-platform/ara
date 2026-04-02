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

#ifndef _GEMV_H
#define _GEMV_H

void gemv_v64b_m4(double *a, double* b, double* c, int M, int M_core, int N);
void gemv_v32b_m4(float *a, float* b, float* c, int M, int M_core, int N);
void gemv_v16b_m4(_Float16 *a, _Float16* b, _Float16* c, int M, int M_core, int N);

// void init_gemv_data(const unsigned long int m_row,
//                     const unsigned long int v_len, double *matrix,
//                     double *vector, double a, double b, double c);

// void gemv_rowwise(const unsigned long int m_row, const unsigned long int v_len,
//                   double *matrix, double *vector, double *dest);

// void gemv_rowwise_small_than_slice(const unsigned long int m_row,
//                                    const unsigned long int v_len,
//                                    double *matrix, double *vector,
//                                    double *dest);

// int gemv_verify(const unsigned long int m_row, const unsigned long int v_len,
//                 double *matrix, double *vector, double *dest);

#endif
