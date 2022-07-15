// Modified version of:
// "RISC-V VECTOR EXP FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona 2019""
// Find details on the original version below
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

//
// RISC-V VECTOR EXP FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona 2019"
// This RISC-V Vector implementation is based on the original code presented by Julien Pommier

/*
   AVX implementation of sin, cos, sincos, exp and log
   Based on "sse_mathfun.h", by Julien Pommier
   http://gruntthepeon.free.fr/ssemath/
   Copyright (C) 2012 Giovanni Garberoglio
   Interdisciplinary Laboratory for Computational Science (LISC)
   Fondazione Bruno Kessler and University of Trento
   via Sommarive, 18
   I-38123 Trento (Italy)
  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.
  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:
  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
  (this is the zlib license)
*/

#include <stdint.h>
#include <string.h>

#include <riscv_vector.h>
#include "printf.h"
#include "runtime.h"

extern size_t N_f64;

extern double exponents_f64[] __attribute__((aligned(4 * NR_LANES)));
extern double results_f64[] __attribute__((aligned(4 * NR_LANES)));
extern double gold_results_f64[] __attribute__((aligned(4 * NR_LANES)));

extern size_t N_f32;

extern float exponents_f32[] __attribute__((aligned(4 * NR_LANES)));
extern float results_f32[] __attribute__((aligned(4 * NR_LANES)));
extern float gold_results_f32[] __attribute__((aligned(4 * NR_LANES)));

#define THRESHOLD 1
#define FABS(x) ((x < 0) ? -x : x)

#define CHECK

inline vfloat64m1_t __exp_1xf64(vfloat64m1_t x, size_t gvl);
inline vfloat32m1_t __exp_2xf32(vfloat32m1_t x, size_t gvl);
void exp_1xf64_bmark(double* exponents, double* results, size_t len);
void exp_2xf32_bmark(float* exponents, float* results, size_t len);
int similarity_check(double a, double b, double threshold);

int similarity_check(double a, double b, double threshold) {
  double diff = a - b;
  if (FABS(diff) > threshold)
    return 0;
  else
    return 1;
}

void exp_1xf64_bmark(double* exponents, double* results, size_t len) {

  size_t avl = len;
  vfloat64m1_t exp_vec, res_vec;

  for (size_t vl = vsetvl_e64m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e64m1(avl);
    // Load vector
    exp_vec = vle64_v_f64m1(exponents, vl);
    // Compute
    res_vec = __exp_1xf64(exp_vec, vl);
    // Store
    vse64_v_f64m1(results, res_vec, vl);
    // Bump pointers
    exponents += vl;
    results   += vl;
  }
}

void exp_2xf32_bmark(float* exponents, float* results, size_t len) {

  size_t avl = len;
  vfloat32m1_t exp_vec, res_vec;

  for (size_t vl = vsetvl_e32m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    vl = vsetvl_e32m1(avl);
    // Load vector
    exp_vec = vle32_v_f32m1(exponents, vl);
    // Compute
    res_vec = __exp_2xf32(exp_vec, vl);
    // Store
    vse32_v_f32m1(results, res_vec, vl);
    // Bump pointers
    exponents += vl;
    results   += vl;
  }
}

// Cannot use LMUL > 1 with this implmentation
// Hard to hardcode assembly registers in this function
// since the caller should know to spill to/from memory
// the correct ones.
inline vfloat64m1_t __exp_1xf64(vfloat64m1_t x, size_t gvl) {

vfloat64m1_t   exp_hi        = vfmv_v_f_f64m1(88.3762626647949,gvl);
vfloat64m1_t   exp_lo        = vfmv_v_f_f64m1(-88.3762626647949,gvl);

vfloat64m1_t   cephes_LOG2EF = vfmv_v_f_f64m1(1.44269504088896341,gvl);
vfloat64m1_t   cephes_exp_C1 = vfmv_v_f_f64m1(0.693359375,gvl);
vfloat64m1_t   cephes_exp_C2 = vfmv_v_f_f64m1(-2.12194440e-4,gvl);

vfloat64m1_t   cephes_exp_p0 = vfmv_v_f_f64m1(1.9875691500E-4,gvl);
vfloat64m1_t   cephes_exp_p1 = vfmv_v_f_f64m1(1.3981999507E-3,gvl);
vfloat64m1_t   cephes_exp_p2 = vfmv_v_f_f64m1(8.3334519073E-3,gvl);
vfloat64m1_t   cephes_exp_p3 = vfmv_v_f_f64m1(4.1665795894E-2,gvl);
vfloat64m1_t   cephes_exp_p4 = vfmv_v_f_f64m1(1.6666665459E-1,gvl);
vfloat64m1_t   cephes_exp_p5 = vfmv_v_f_f64m1(5.0000001201E-1,gvl);
vfloat64m1_t   tmp;
vfloat64m1_t   tmp2;
vfloat64m1_t   tmp4;
vfloat64m1_t   fx;

vfloat64m1_t   one = vfmv_v_f_f64m1(1.0,gvl);
vfloat64m1_t   zero = vfmv_v_f_f64m1(0.0,gvl);
vfloat64m1_t   z;
vfloat64m1_t   y;

vbool64_t  mask;
vint64m1_t  imm0;
vint64m1_t  tmp3;

        x     = vfmin_vv_f64m1(x, exp_hi,gvl);
        x     = vfmax_vv_f64m1(x, exp_lo,gvl);

        fx    = vfmv_v_f_f64m1(0.5,gvl);
        fx    = vfmacc_vv_f64m1(fx,x,cephes_LOG2EF,gvl);

        tmp3  = vfcvt_x_f_v_i64m1(fx,gvl);
        tmp   = vfcvt_f_x_v_f64m1(tmp3,gvl);

        mask  = vmflt_vv_f64m1_b64(fx,tmp,gvl);
        tmp2  = vmerge_vvm_f64m1(mask,zero,one, gvl);
        fx    = vfsub_vv_f64m1(tmp,tmp2,gvl);
        tmp   = vfmul_vv_f64m1(fx, cephes_exp_C1,gvl);
        z     = vfmul_vv_f64m1(fx, cephes_exp_C2,gvl);
        x     = vfsub_vv_f64m1(x,tmp,gvl);
        x     = vfsub_vv_f64m1(x,z,gvl);

        z     = vfmul_vv_f64m1(x,x,gvl);

        y     = cephes_exp_p0;
        y     = vfmadd_vv_f64m1(y,x,cephes_exp_p1,gvl);
        y     = vfmadd_vv_f64m1(y,x,cephes_exp_p2,gvl);
        y     = vfmadd_vv_f64m1(y,x,cephes_exp_p3,gvl);
        y     = vfmadd_vv_f64m1(y,x,cephes_exp_p4,gvl);
        y     = vfmadd_vv_f64m1(y,x,cephes_exp_p5,gvl);
        y     = vfmadd_vv_f64m1(y,z,x,gvl);
        y     = vfadd_vv_f64m1(y, one,gvl);

        imm0  = vfcvt_x_f_v_i64m1(fx,gvl);
        imm0  = vadd_vv_i64m1(imm0, vmv_v_x_i64m1(1023,gvl),gvl);
        imm0  = vsll_vv_i64m1(imm0, vmv_v_x_u64m1(52,gvl),gvl);

        tmp4  = vreinterpret_v_i64m1_f64m1(imm0);
        y     = vfmul_vv_f64m1(y, tmp4,gvl);
        return y;
}

inline vfloat32m1_t __exp_2xf32(vfloat32m1_t x , size_t gvl) {

vfloat32m1_t   exp_hi        = vfmv_v_f_f32m1(88.3762626647949,gvl);
vfloat32m1_t   exp_lo        = vfmv_v_f_f32m1(-88.3762626647949,gvl);

vfloat32m1_t   cephes_LOG2EF = vfmv_v_f_f32m1(1.44269504088896341,gvl);
vfloat32m1_t   cephes_exp_C1 = vfmv_v_f_f32m1(0.693359375,gvl);
vfloat32m1_t   cephes_exp_C2 = vfmv_v_f_f32m1(-2.12194440e-4,gvl);

vfloat32m1_t   cephes_exp_p0 = vfmv_v_f_f32m1(1.9875691500E-4,gvl);
vfloat32m1_t   cephes_exp_p1 = vfmv_v_f_f32m1(1.3981999507E-3,gvl);
vfloat32m1_t   cephes_exp_p2 = vfmv_v_f_f32m1(8.3334519073E-3,gvl);
vfloat32m1_t   cephes_exp_p3 = vfmv_v_f_f32m1(4.1665795894E-2,gvl);
vfloat32m1_t   cephes_exp_p4 = vfmv_v_f_f32m1(1.6666665459E-1,gvl);
vfloat32m1_t   cephes_exp_p5 = vfmv_v_f_f32m1(5.0000001201E-1,gvl);
vfloat32m1_t   tmp;
vfloat32m1_t   tmp2;
vfloat32m1_t   tmp4;
vfloat32m1_t   fx;

vfloat32m1_t   one = vfmv_v_f_f32m1(1.0,gvl);
vfloat32m1_t   zero = vfmv_v_f_f32m1(0.0,gvl);
vfloat32m1_t   z;
vfloat32m1_t   y;

vbool32_t  mask;
vint32m1_t  imm0;
vint32m1_t  tmp3;

        x     = vfmin_vv_f32m1(x, exp_hi,gvl);
        x     = vfmax_vv_f32m1(x, exp_lo,gvl);

        fx    = vfmv_v_f_f32m1(0.5,gvl);
        fx    = vfmacc_vv_f32m1(fx,x,cephes_LOG2EF,gvl);

        tmp3  = vfcvt_x_f_v_i32m1(fx,gvl);
        tmp   = vfcvt_f_x_v_f32m1(tmp3,gvl);

        mask  = vmflt_vv_f32m1_b32(fx,tmp,gvl);
        tmp2  = vmerge_vvm_f32m1(mask,zero,one, gvl);
        fx    = vfsub_vv_f32m1(tmp,tmp2,gvl);
        tmp   = vfmul_vv_f32m1(fx, cephes_exp_C1,gvl);
        z     = vfmul_vv_f32m1(fx, cephes_exp_C2,gvl);
        x     = vfsub_vv_f32m1(x,tmp,gvl);
        x     = vfsub_vv_f32m1(x,z,gvl);

        z     = vfmul_vv_f32m1(x,x,gvl);

        y     = cephes_exp_p0;
        y     = vfmadd_vv_f32m1(y,x,cephes_exp_p1,gvl);
        y     = vfmadd_vv_f32m1(y,x,cephes_exp_p2,gvl);
        y     = vfmadd_vv_f32m1(y,x,cephes_exp_p3,gvl);
        y     = vfmadd_vv_f32m1(y,x,cephes_exp_p4,gvl);
        y     = vfmadd_vv_f32m1(y,x,cephes_exp_p5,gvl);
        y     = vfmadd_vv_f32m1(y,z,x,gvl);
        y     = vfadd_vv_f32m1(y,one,gvl);

        imm0  = vfcvt_x_f_v_i32m1(fx,gvl);
        imm0  = vadd_vv_i32m1(imm0, vmv_v_x_i32m1(0x7f,gvl),gvl);
        imm0  = vsll_vv_i32m1(imm0, vmv_v_x_u32m1(23,gvl),gvl);

        tmp4  = vreinterpret_v_i32m1_f32m1(imm0);
        y     = vfmul_vv_f32m1(y, tmp4, gvl);
        return y;
}

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  FEXP  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  int error = 0;
  int64_t runtime;

  printf("Executing exponential on %d 64-bit data...\n", N_f64);

  start_timer();
  exp_1xf64_bmark(exponents_f64, results_f64, N_f64);
  stop_timer();

  runtime = get_timer();
  printf("The execution took %d cycles.\n", runtime);

  printf("Executing exponential on %d 32-bit data...\n", N_f32);
  start_timer();
  exp_2xf32_bmark(exponents_f32, results_f32, N_f32);
  stop_timer();

  runtime = get_timer();
  printf("The execution took %d cycles.\n", runtime);

#ifdef CHECK
  printf("Checking results:\n");

  for (uint64_t i = 0; i < N_f64; ++i) {
    if (!similarity_check(results_f64[i], gold_results_f64[i], THRESHOLD)) {
      error = 1;
      printf("64-bit error at index %d. %f != %f\n", i, results_f64[i], gold_results_f64[i]);
    }
  }
  for (uint64_t i = 0; i < N_f32; ++i) {
    if (!similarity_check(results_f32[i], gold_results_f32[i], THRESHOLD)) {
      error = 1;
      printf("32-bit error at index %d. %f != %f\n", i, results_f32[i], gold_results_f32[i]);
    }
  }
#endif

  return error;
}
