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
}

void exp_2xf32_bmark(float *exponents, float *results, size_t len) {

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
    results += vl;
  }
}
