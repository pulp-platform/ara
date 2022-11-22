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
// Author: Matteo Perotti

#include <stdint.h>
#include <string.h>

#include "riscv_vector.h"

void exp_1xf64_bmark(double *exponents, double *results, size_t len);
void exp_1xf64_asm_bmark(double *exponents, double *results, size_t len);
void exp_2xf32_bmark(float *exponents, float *results, size_t len);

// Cannot use LMUL > 1 with this implmentation
// Hard to hardcode assembly registers in this function
// since the caller should know to spill to/from memory
// the correct ones.
inline vfloat64m1_t __exp_1xf64(vfloat64m1_t x, size_t gvl) {

  vfloat64m1_t exp_hi = vfmv_v_f_f64m1(88.3762626647949, gvl);
  vfloat64m1_t exp_lo = vfmv_v_f_f64m1(-88.3762626647949, gvl);

  vfloat64m1_t cephes_LOG2EF = vfmv_v_f_f64m1(1.44269504088896341, gvl);
  vfloat64m1_t cephes_exp_C1 = vfmv_v_f_f64m1(0.693359375, gvl);
  vfloat64m1_t cephes_exp_C2 = vfmv_v_f_f64m1(-2.12194440e-4, gvl);

  vfloat64m1_t cephes_exp_p0 = vfmv_v_f_f64m1(1.9875691500E-4, gvl);
  vfloat64m1_t cephes_exp_p1 = vfmv_v_f_f64m1(1.3981999507E-3, gvl);
  vfloat64m1_t cephes_exp_p2 = vfmv_v_f_f64m1(8.3334519073E-3, gvl);
  vfloat64m1_t cephes_exp_p3 = vfmv_v_f_f64m1(4.1665795894E-2, gvl);
  vfloat64m1_t cephes_exp_p4 = vfmv_v_f_f64m1(1.6666665459E-1, gvl);
  vfloat64m1_t cephes_exp_p5 = vfmv_v_f_f64m1(5.0000001201E-1, gvl);
  vfloat64m1_t tmp;
  vfloat64m1_t tmp2;
  vfloat64m1_t tmp4;
  vfloat64m1_t fx;

  vfloat64m1_t one = vfmv_v_f_f64m1(1.0, gvl);
  vfloat64m1_t zero = vfmv_v_f_f64m1(0.0, gvl);
  vfloat64m1_t z;
  vfloat64m1_t y;

  vbool64_t mask;
  vint64m1_t imm0;
  vint64m1_t tmp3;

  x = vfmin_vv_f64m1(x, exp_hi, gvl);
  x = vfmax_vv_f64m1(x, exp_lo, gvl);

  fx = vfmv_v_f_f64m1(0.5, gvl);
  fx = vfmacc_vv_f64m1(fx, x, cephes_LOG2EF, gvl);

  tmp3 = vfcvt_x_f_v_i64m1(fx, gvl);
  tmp = vfcvt_f_x_v_f64m1(tmp3, gvl);

  mask = vmflt_vv_f64m1_b64(fx, tmp, gvl);
  tmp2 = vmerge_vvm_f64m1(mask, zero, one, gvl);
  fx = vfsub_vv_f64m1(tmp, tmp2, gvl);
  tmp = vfmul_vv_f64m1(fx, cephes_exp_C1, gvl);
  z = vfmul_vv_f64m1(fx, cephes_exp_C2, gvl);
  x = vfsub_vv_f64m1(x, tmp, gvl);
  x = vfsub_vv_f64m1(x, z, gvl);

  z = vfmul_vv_f64m1(x, x, gvl);

  y = cephes_exp_p0;
  y = vfmadd_vv_f64m1(y, x, cephes_exp_p1, gvl);
  y = vfmadd_vv_f64m1(y, x, cephes_exp_p2, gvl);
  y = vfmadd_vv_f64m1(y, x, cephes_exp_p3, gvl);
  y = vfmadd_vv_f64m1(y, x, cephes_exp_p4, gvl);
  y = vfmadd_vv_f64m1(y, x, cephes_exp_p5, gvl);
  y = vfmadd_vv_f64m1(y, z, x, gvl);
  y = vfadd_vv_f64m1(y, one, gvl);

  imm0 = vfcvt_x_f_v_i64m1(fx, gvl);
  imm0 = vadd_vv_i64m1(imm0, vmv_v_x_i64m1(1023, gvl), gvl);
  imm0 = vsll_vv_i64m1(imm0, vmv_v_x_u64m1(52, gvl), gvl);

  tmp4 = vreinterpret_v_i64m1_f64m1(imm0);
  y = vfmul_vv_f64m1(y, tmp4, gvl);
  return y;
}

inline vfloat32m1_t __exp_2xf32(vfloat32m1_t x, size_t gvl) {

  vfloat32m1_t exp_hi = vfmv_v_f_f32m1(88.3762626647949, gvl);
  vfloat32m1_t exp_lo = vfmv_v_f_f32m1(-88.3762626647949, gvl);

  vfloat32m1_t cephes_LOG2EF = vfmv_v_f_f32m1(1.44269504088896341, gvl);
  vfloat32m1_t cephes_exp_C1 = vfmv_v_f_f32m1(0.693359375, gvl);
  vfloat32m1_t cephes_exp_C2 = vfmv_v_f_f32m1(-2.12194440e-4, gvl);

  vfloat32m1_t cephes_exp_p0 = vfmv_v_f_f32m1(1.9875691500E-4, gvl);
  vfloat32m1_t cephes_exp_p1 = vfmv_v_f_f32m1(1.3981999507E-3, gvl);
  vfloat32m1_t cephes_exp_p2 = vfmv_v_f_f32m1(8.3334519073E-3, gvl);
  vfloat32m1_t cephes_exp_p3 = vfmv_v_f_f32m1(4.1665795894E-2, gvl);
  vfloat32m1_t cephes_exp_p4 = vfmv_v_f_f32m1(1.6666665459E-1, gvl);
  vfloat32m1_t cephes_exp_p5 = vfmv_v_f_f32m1(5.0000001201E-1, gvl);
  vfloat32m1_t tmp;
  vfloat32m1_t tmp2;
  vfloat32m1_t tmp4;
  vfloat32m1_t fx;

  vfloat32m1_t one = vfmv_v_f_f32m1(1.0, gvl);
  vfloat32m1_t zero = vfmv_v_f_f32m1(0.0, gvl);
  vfloat32m1_t z;
  vfloat32m1_t y;

  vbool32_t mask;
  vint32m1_t imm0;
  vint32m1_t tmp3;

  x = vfmin_vv_f32m1(x, exp_hi, gvl);
  x = vfmax_vv_f32m1(x, exp_lo, gvl);

  fx = vfmv_v_f_f32m1(0.5, gvl);
  fx = vfmacc_vv_f32m1(fx, x, cephes_LOG2EF, gvl);

  tmp3 = vfcvt_x_f_v_i32m1(fx, gvl);
  tmp = vfcvt_f_x_v_f32m1(tmp3, gvl);

  mask = vmflt_vv_f32m1_b32(fx, tmp, gvl);
  tmp2 = vmerge_vvm_f32m1(mask, zero, one, gvl);
  fx = vfsub_vv_f32m1(tmp, tmp2, gvl);
  tmp = vfmul_vv_f32m1(fx, cephes_exp_C1, gvl);
  z = vfmul_vv_f32m1(fx, cephes_exp_C2, gvl);
  x = vfsub_vv_f32m1(x, tmp, gvl);
  x = vfsub_vv_f32m1(x, z, gvl);

  z = vfmul_vv_f32m1(x, x, gvl);

  y = cephes_exp_p0;
  y = vfmadd_vv_f32m1(y, x, cephes_exp_p1, gvl);
  y = vfmadd_vv_f32m1(y, x, cephes_exp_p2, gvl);
  y = vfmadd_vv_f32m1(y, x, cephes_exp_p3, gvl);
  y = vfmadd_vv_f32m1(y, x, cephes_exp_p4, gvl);
  y = vfmadd_vv_f32m1(y, x, cephes_exp_p5, gvl);
  y = vfmadd_vv_f32m1(y, z, x, gvl);
  y = vfadd_vv_f32m1(y, one, gvl);

  imm0 = vfcvt_x_f_v_i32m1(fx, gvl);
  imm0 = vadd_vv_i32m1(imm0, vmv_v_x_i32m1(0x7f, gvl), gvl);
  imm0 = vsll_vv_i32m1(imm0, vmv_v_x_u32m1(23, gvl), gvl);

  tmp4 = vreinterpret_v_i32m1_f32m1(imm0);
  y = vfmul_vv_f32m1(y, tmp4, gvl);
  return y;
}
