// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

typedef union {
  uint64_t i;
  uint16_t h;
  float    f;
  double   d;
} v_fconv;

static inline v_fconv _i(uint64_t i) {
  v_fconv r;
  r.i   = i;
  return  r;
}

static inline v_fconv _h(float f) {
  /*Copyright (c) 2005-2021, NumPy Developers.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above
    copyright notice, this list of conditions and the following
    disclaimer in the documentation and/or other materials provided
    with the distribution.

    * Neither the name of the NumPy Developers nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/

  // Source: https://github.com/numpy/numpy/blob/master/numpy/core/src/npymath/halffloat.c

  v_fconv r;
  r.f = f;

  uint32_t f_exp, f_sig;
  uint16_t h_sgn, h_exp, h_sig;

  h_sgn = (uint16_t) ((r.i&0x80000000u) >> 16);
  f_exp = (r.i&0x7f800000u);

  /* Exponent overflow/NaN converts to signed inf/NaN */
  if (f_exp >= 0x47800000u) {
    if (f_exp == 0x7f800000u) {
      /* Inf or NaN */
      f_sig = (r.i&0x007fffffu);
      if (f_sig != 0) {
        /* NaN - propagate the flag in the significand... */
        uint16_t ret = (uint16_t) (0x7c00u + (f_sig >> 13));
        /* ...but make sure it stays a NaN */
        if (ret == 0x7c00u) {
          ret++;
        }
        r.i = (uint16_t) h_sgn + ret;
        return r;
      } else {
        /* signed inf */
        r.i = (uint16_t) (h_sgn + 0x7c00u);
        return r;
      }
    } else {
      r.i = (uint16_t) (h_sgn + 0x7c00u);
      return r;
    }
  }

  /* Exponent underflow converts to a subnormal half or signed zero */
  if (f_exp <= 0x38000000u) {
    /*
     * Signed zeros, subnormal floats, and floats with small
     * exponents all convert to signed zero half-floats.
     */
    if (f_exp < 0x33000000u) {
      r.i = h_sgn;
      return r;
    }
    /* Make the subnormal significand */
    f_exp >>= 23;
    f_sig = (0x00800000u + (r.i&0x007fffffu));
    f_sig >>= (113 - f_exp);
    f_sig += 0x00001000u;
    h_sig = (uint16_t) (f_sig >> 13);
    /*
     * If the rounding causes a bit to spill into h_exp, it will
     * increment h_exp from zero to one and h_sig will be zero.
     * This is the correct result.
     */
    r.i = (uint16_t) (h_sgn + h_sig);
    return r;
  }

  /* Regular case with no overflow or underflow */
  h_exp = (uint16_t) ((f_exp - 0x38000000u) >> 13);
  /* Handle rounding by adding 1 to the bit beyond half precision */
  f_sig = (r.i&0x007fffffu);
  f_sig += 0x00001000u;
  h_sig = (uint16_t) (f_sig >> 13);
  r.i = (uint16_t) h_sgn + h_exp + h_sig;
  return  r;
}

static inline v_fconv _f(float f) {
  v_fconv r;
  r.f   = f;
  return  r;
}

static inline v_fconv _d(double d) {
  v_fconv r;
  r.d   = d;
  return  r;
}
