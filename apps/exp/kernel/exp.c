// Modified version of:
// "RISC-V VECTOR EXP FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona
// 2019"" Find details on the original version below Author: Matteo Perotti
// <mperotti@iis.ee.ethz.ch>

//
// RISC-V VECTOR EXP FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona
// 2019" This RISC-V Vector implementation is based on the original code
// presented by Julien Pommier

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

#include "exp.h"

void exp_1xf64_bmark(double *exponents, double *results, size_t len) {

  size_t avl = len;
  vfloat64m1_t exp_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
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
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}

void exp_2xf32_bmark(float *exponents, float *results, size_t len) {

  size_t avl = len;
  vfloat32m1_t exp_vec, res_vec;

#ifdef VCD_DUMP
  // Start dumping VCD
  event_trigger = +1;
#endif
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
    results += vl;
  }
#ifdef VCD_DUMP
  // Stop dumping VCD
  event_trigger = -1;
#endif
}

// Intermix the instructions
// Unroll the loop and preload x
void exp_1xf64_asm_bmark(double *exponents, double *results, size_t len) {

  size_t avl = len;
  vfloat64m1_t exp_vec, res_vec;

  for (size_t vl = vsetvl_e64m1(avl); avl > 0; avl -= vl) {
    // Strip-mine
    asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(avl));

    // Compute

    // v30 x
    // v14 tmp3
    // v15 tmp
    // v0  mask
    // v16 tmp2
    // v17 z
    // v5  y
    // v18 imm0
    // v19 tmpmv

    // During the first iteration, load the constants and input
    if (avl == len) {
      // Load vector
      asm("vle64.v v30, (%0)" ::"r"(exponents));
      asm("vfmv.v.f v31, %0" ::"f"(88.3762626647949) : "v31"); // exp_hi
      asm("vfmin.vv     v30, v31, v30" ::: "v30");
      asm("vfmv.v.f v1,  %0" ::"f"(-88.3762626647949) : "v1"); // exp_lo
      asm("vfmax.vv     v30, v1, v30" ::: "v30");
      asm("vfmv.v.f v2,  %0" ::"f"(1.44269504088896341)
          : "v2");                                // cephes_LOG2EF
      asm("vfmv.v.f v13, %0" ::"f"(0.5) : "v13"); // fx
      asm("vfmacc.vv    v13, v30, v2" ::: "v13");
      asm("vfmv.v.f v3,  %0" ::"f"(0.693359375) : "v3"); // cephes_exp_C1
      asm("vfcvt.x.f.v  v14, v13" ::: "v14");
      asm("vfmv.v.f v4,  %0" ::"f"(-2.12194440e-4) : "v4"); // cephes_exp_C2
      asm("vfcvt.f.x.v  v15, v14" ::: "v15");
      asm("vfmv.v.f v5,  %0" ::"f"(1.9875691500E-4) : "v5"); // cephes_exp_p0
      asm("vmflt.vv v0, v13, v15" ::: "v0");
      asm("vfmv.v.f v6,  %0" ::"f"(1.3981999507E-3) : "v6"); // cephes_exp_p1
      asm("vmv.v.i  v12, 0" ::: "v12");                      // zero
      asm("vmerge.vvm	v16, v12, v1, v0" ::: "v16");
      asm("vfmv.v.f v7,  %0" ::"f"(8.3334519073E-3) : "v7"); // cephes_exp_p2
      asm("vfsub.vv v13, v15, v6" ::: "v13");
      asm("vfmv.v.f v8,  %0" ::"f"(4.1665795894E-2) : "v8"); // cephes_exp_p3
      asm("vfmul.vv v15, v13, v3" ::: "v15");
      asm("vfmv.v.f v9,  %0" ::"f"(1.6666665459E-1) : "v9"); // cephes_exp_p4
      asm("vfmul.vv v17, v13, v4" ::: "v17");
      asm("vfmv.v.f v10, %0" ::"f"(5.0000001201E-1) : "v10"); // cephes_exp_p5
      asm("vfmul.vv v17, v13, v4" ::: "v17");
      asm("vfmv.v.f v11, %0" ::"f"(1.0) : "v11"); // one
    } else {
      asm("vfmin.vv     v30, v31, v30" ::: "v30");
      asm("vfmax.vv     v30, v1, v30" ::: "v30");
      asm("vfmv.v.f v13, %0" ::"f"(0.5) : "v13"); // fx
      asm("vfmacc.vv    v13, v30, v2" ::: "v13");
      asm("vfcvt.x.f.v  v14, v13" ::: "v14");
      asm("vfcvt.f.x.v  v15, v14" ::: "v15");
      asm("vmflt.vv v0, v13, v15" ::: "v0");
      asm("vmerge.vvm	v16, v12, v1, v0" ::: "v16");
      asm("vfsub.vv v13, v15, v6" ::: "v13");
      asm("vfmul.vv v15, v13, v3" ::: "v15");
      asm("vfmul.vv v17, v13, v4" ::: "v17");
      asm("vfmul.vv v17, v13, v4" ::: "v17");
    }

    asm("vfmul.vv v17, v13, v4" ::: "v17");
    asm("vfsub.vv v30, v30, v15" ::: "v30");
    asm("vfsub.vv v30, v30, v17" ::: "v30");
    asm("vfmul.vv v17, v30, v30" ::: "v17");

    asm("vfmadd.vv	v5, v30, v6" ::: "v5");
    asm("vfmadd.vv	v5, v30, v7" ::: "v5");
    asm("vfmadd.vv	v5, v30, v8" ::: "v5");
    asm("vfmadd.vv	v5, v30, v9" ::: "v5");
    asm("vfmadd.vv	v5, v30, v10" ::: "v5");
    asm("vfmadd.vv	v5, v17, v30" ::: "v5");

    // Preload vector
    if (avl - vl > 0) {
      exponents += vl;
      asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(avl - vl));
      asm("vle64.v v30, (%0)" ::"r"(exponents));
      asm volatile("vsetvli zero, %0, e64, m1, ta, ma" ::"r"(avl));
    }

    asm("vfadd.vv	v5, v5, v11" ::: "v5");

    asm("vfcvt.x.f.v  v18, v13" ::: "v18");
    asm("vmv.v.x v19, %0" ::"r"(1023) : "v19");
    asm("vadd.vv v18, v18, v19" ::: "v8");
    asm("vmv.v.x v19, %0" ::"r"(52) : "v19");
    asm("vsll.vv v18, v18, v19" ::: "v18");
    asm("vfmul.vv v5, v5, v18" ::: "v5");

    // Store
    asm("vse64.v v5, (%0)" ::"r"(results));

    // Bump pointers
    results += vl;
    exponents += vl;
  }
}

/*
    Base algorithm

    asm("vfmv.v.f v31, %0" :: "f" ( 88.3762626647949)   : "v31"); // exp_hi
    asm("vfmv.v.f v1,  %0" :: "f" (-88.3762626647949)   : "v1");  // exp_lo
    asm("vfmv.v.f v2,  %0" :: "f" (1.44269504088896341) : "v2");  //
   cephes_LOG2EF asm("vfmv.v.f v3,  %0" :: "f" (0.693359375)         : "v3"); //
   cephes_exp_C1 asm("vfmv.v.f v4,  %0" :: "f" (-2.12194440e-4)      : "v4"); //
   cephes_exp_C2 asm("vfmv.v.f v5,  %0" :: "f" (1.9875691500E-4)     : "v5"); //
   cephes_exp_p0 asm("vfmv.v.f v6,  %0" :: "f" (1.3981999507E-3)     : "v6"); //
   cephes_exp_p1 asm("vfmv.v.f v7,  %0" :: "f" (8.3334519073E-3)     : "v7"); //
   cephes_exp_p2 asm("vfmv.v.f v8,  %0" :: "f" (4.1665795894E-2)     : "v8"); //
   cephes_exp_p3 asm("vfmv.v.f v9,  %0" :: "f" (1.6666665459E-1)     : "v9"); //
   cephes_exp_p4 asm("vfmv.v.f v10, %0" :: "f" (5.0000001201E-1)     : "v10");
   // cephes_exp_p5 asm("vfmv.v.f v11, %0" :: "f" (1.0)                 :
   "v11"); // one asm("vmv.v.i  v12, 0"  ::                           : "v12");
   // zero asm("vfmv.v.f v13, %0" :: "f" (0.5)                 : "v13"); // fx

    asm("vfmin.vv     v30, v31, v30"    ::: "v30");
    asm("vfmax.vv     v30, v1, v30"     ::: "v30");
    asm("vfmacc.vv    v13, v30, v2"     ::: "v13");
    asm("vfcvt.x.f.v  v14, v13"         ::: "v14");
    asm("vfcvt.f.x.v  v15, v14"         ::: "v15");
    asm("vmflt.vv v0, v13, v15"         ::: "v0");
    asm("vmerge.vvm	v16, v12, v1, v0" ::: "v16");

    asm("vfsub.vv v13, v15, v6"  ::: "v13");
    asm("vfmul.vv v15, v13, v3"  ::: "v15");
    asm("vfmul.vv v17, v13, v4"  ::: "v17");
    asm("vfsub.vv v30, v30, v15" ::: "v30");
    asm("vfsub.vv v30, v30, v17" ::: "v30");
    asm("vfmul.vv v17, v30, v30" ::: "v17");

    asm("vfmadd.vv	v5, v30, v6"  ::: "v5");
    asm("vfmadd.vv	v5, v30, v7"  ::: "v5");
    asm("vfmadd.vv	v5, v30, v8"  ::: "v5");
    asm("vfmadd.vv	v5, v30, v9"  ::: "v5");
    asm("vfmadd.vv	v5, v30, v10" ::: "v5");
    asm("vfmadd.vv	v5, v17, v30" ::: "v5");
    asm("vfadd.vv	v5, v5, v11"      ::: "v5");

    asm("vfcvt.x.f.v  v18, v13" ::: "v18");
    asm("vmv.v.x v19, %0"       :: "r" (1023) : "v19");
    asm("vadd.vv v18, v18, v19" ::: "v8");
    asm("vmv.v.x v19, %0"       :: "r" (52) : "v19");
    asm("vsll.vv v18, v18, v19" ::: "v18");
    asm("vfmul.vv v5, v5, v18"  ::: "v5");
*/
