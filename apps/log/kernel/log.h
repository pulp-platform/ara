// Modified version of:
// "RISC-V VECTOR LOG FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona
// 2019"" Find details on the original version below Author: Matteo Perotti
// <mperotti@iis.ee.ethz.ch>

// RISC-V VECTOR LOG FUNCTION Version by Cristóbal Ramírez Lazo, "Barcelona
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

#include <stdio.h>
#include <string.h>

#include "rivec/vector_defines.h"

void log_1xf64_bmark(double *args, double *results, size_t len);
void log_2xf32_bmark(float *args, float *results, size_t len);

inline _MMR_f64 __log_1xf64(_MMR_f64 x, unsigned long int gvl) {

  _MMR_i64 _x_i;
  _MMR_u64 imm0_u;
  _MMR_i64 imm0;
  _MMR_f64 e;
  _MMR_MASK_i64 invalid_mask = _MM_VFLE_f64(x, _MM_SET_f64(0.0f, gvl), gvl);

  x = _MM_MAX_f64(x, _MM_CAST_f64_i64(_MM_SET_i64(0x0010000000000000, gvl)),
                  gvl); /* cut off denormalized stuff */
  imm0_u = _MM_SRL_i64(_MM_CAST_u64_f64(x),
                       _MM_CAST_u64_i64(_MM_SET_i64(52, gvl)), gvl);
  imm0 = _MM_CAST_i64_u64(imm0_u);
  /* keep only the fractional part */
  _x_i = _MM_AND_i64(_MM_CAST_i64_f64(x), _MM_SET_i64(~0x7ff0000000000000, gvl),
                     gvl);
  _x_i = _MM_OR_i64(_x_i, _MM_CAST_i64_f64(_MM_SET_f64(0.5f, gvl)), gvl);
  x = _MM_CAST_f64_i64(_x_i);
  imm0 = _MM_SUB_i64(imm0, _MM_SET_i64(1023, gvl), gvl);
  e = _MM_VFCVT_F_X_f64(imm0, gvl);
  e = _MM_ADD_f64(e, _MM_SET_f64(1.0f, gvl), gvl);

  _MMR_MASK_i64 mask =
      _MM_VFLT_f64(x, _MM_SET_f64(0.707106781186547524, gvl), gvl);
  _MMR_f64 tmp = _MM_MERGE_f64(_MM_SET_f64(0.0f, gvl), x, mask, gvl);

  x = _MM_SUB_f64(x, _MM_SET_f64(1.0f, gvl), gvl);
  e = _MM_SUB_f64(
      e,
      _MM_MERGE_f64(_MM_SET_f64(0.0f, gvl), _MM_SET_f64(1.0f, gvl), mask, gvl),
      gvl);
  x = _MM_ADD_f64(x, tmp, gvl);

  _MMR_f64 z = _MM_MUL_f64(x, x, gvl);
  _MMR_f64 y;

  y = _MM_MADD_f64(_MM_SET_f64(7.0376836292E-2, gvl), x,
                   _MM_SET_f64(-1.1514610310E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(1.1676998740E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(-1.2420140846E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(1.4249322787E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(-1.6668057665E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(2.0000714765E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(-2.4999993993E-1, gvl), gvl);
  y = _MM_MADD_f64(y, x, _MM_SET_f64(3.3333331174E-1, gvl), gvl);
  y = _MM_MUL_f64(y, z, gvl);
  y = _MM_MACC_f64(y, e, _MM_SET_f64(-2.12194440e-4, gvl), gvl);
  tmp = _MM_MUL_f64(z, _MM_SET_f64(0.5f, gvl), gvl);
  y = _MM_SUB_f64(y, tmp, gvl);
  tmp = _MM_MUL_f64(e, _MM_SET_f64(0.693359375, gvl), gvl);
  x = _MM_ADD_f64(x, y, gvl);
  x = _MM_ADD_f64(x, tmp, gvl);
  x = _MM_MERGE_f64(x, _MM_CAST_f64_i64(_MM_SET_i64(0xffffffffffffffff, gvl)),
                    invalid_mask, gvl);

  return x;
}

inline _MMR_f32 __log_2xf32(_MMR_f32 x, unsigned long int gvl) {

  _MMR_i32 _x_i;
  _MMR_u32 imm0_u;
  _MMR_i32 imm0;
  _MMR_f32 e;

  _MMR_MASK_i32 invalid_mask = _MM_VFLE_f32(x, _MM_SET_f32(0.0f, gvl), gvl);

  x = _MM_MAX_f32(x, _MM_CAST_f32_i32(_MM_SET_i32(0x00800000, gvl)),
                  gvl); /* cut off denormalized stuff */
  imm0_u = _MM_SRL_i32(_MM_CAST_u32_f32(x),
                       _MM_CAST_u32_i32(_MM_SET_i32(23, gvl)), gvl);
  imm0 = _MM_CAST_i32_u32(imm0_u);
  /* keep only the fractional part */
  _x_i = _MM_AND_i32(_MM_CAST_i32_f32(x), _MM_SET_i32(~0x7f800000, gvl), gvl);
  _x_i = _MM_OR_i32(_x_i, _MM_CAST_i32_f32(_MM_SET_f32(0.5f, gvl)), gvl);
  x = _MM_CAST_f32_i32(_x_i);
  imm0 = _MM_SUB_i32(imm0, _MM_SET_i32(0x7f, gvl), gvl);
  e = _MM_VFCVT_F_X_f32(imm0, gvl);
  e = _MM_ADD_f32(e, _MM_SET_f32(1.0f, gvl), gvl);

  _MMR_MASK_i32 mask =
      _MM_VFLT_f32(x, _MM_SET_f32(0.707106781186547524, gvl), gvl);
  _MMR_f32 tmp = _MM_MERGE_f32(_MM_SET_f32(0.0f, gvl), x, mask, gvl);

  x = _MM_SUB_f32(x, _MM_SET_f32(1.0f, gvl), gvl);
  e = _MM_SUB_f32(
      e,
      _MM_MERGE_f32(_MM_SET_f32(0.0f, gvl), _MM_SET_f32(1.0f, gvl), mask, gvl),
      gvl);
  x = _MM_ADD_f32(x, tmp, gvl);

  _MMR_f32 z = _MM_MUL_f32(x, x, gvl);
  _MMR_f32 y;

  y = _MM_MADD_f32(_MM_SET_f32(7.0376836292E-2, gvl), x,
                   _MM_SET_f32(-1.1514610310E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(1.1676998740E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(-1.2420140846E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(1.4249322787E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(-1.6668057665E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(2.0000714765E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(-2.4999993993E-1, gvl), gvl);
  y = _MM_MADD_f32(y, x, _MM_SET_f32(3.3333331174E-1, gvl), gvl);
  y = _MM_MUL_f32(y, z, gvl);
  y = _MM_MACC_f32(y, e, _MM_SET_f32(-2.12194440e-4, gvl), gvl);
  tmp = _MM_MUL_f32(z, _MM_SET_f32(0.5f, gvl), gvl);
  y = _MM_SUB_f32(y, tmp, gvl);
  tmp = _MM_MUL_f32(e, _MM_SET_f32(0.693359375, gvl), gvl);
  x = _MM_ADD_f32(x, y, gvl);
  x = _MM_ADD_f32(x, tmp, gvl);
  x = _MM_MERGE_f32(x, _MM_CAST_f32_i32(_MM_SET_i32(0xffffffff, gvl)),
                    invalid_mask, gvl);

  return x;
}
