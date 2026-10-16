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
// Author: Hong Pang <hopang@iis.ee.ethz.ch>
//
// Fixed-register assembly port of `__cos_1xf64` / `__cos_2xf32` (cos.h).
// m1 only: too many live temps for LMUL > 1.
//
// Register contract (must be free at the call site, m1):
//   in/out : VS (x, preserved), VD (y)
//   temps  : v4 (x), v5 (y), v6 (y2), v7 (z), v8 (sign_bit), v9 (poly_mask),
//            v10 (scratch), v0 (mask)
//   consts : v16..v29 (set once by VCOS_CONST_INIT_* before the strip loop)
// VD and VS must be distinct, and must not be any of v0/v4..v10/v16..v29.

#ifndef _COS_HOIST_H_
#define _COS_HOIST_H_

// Broadcast the Cephes constants into v16..v29. Call once, under e32/m1 at
// VLMAX, before the strip-mine loop.
//   v16=FOPI v17=DP1 v18=DP2 v19=DP3 v20=coscof_p0 v21=coscof_p1 v22=coscof_p2
//   v23=half v24=one v25=sincof_p0 v26=sincof_p1 v27=sincof_p2
//   v28=zero v29=inv_sign_mask
#define VCOS_CONST_INIT_F32()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((float)1.27323954473516));           \
    asm volatile("vfmv.v.f v17, %0" ::"f"((float)-0.78515625));                \
    asm volatile("vfmv.v.f v18, %0" ::"f"((float)-2.4187564849853515625E-4));  \
    asm volatile("vfmv.v.f v19, %0" ::"f"((float)-3.77489497744594108E-8));    \
    asm volatile("vfmv.v.f v20, %0" ::"f"((float)2.443315711809948E-5));       \
    asm volatile("vfmv.v.f v21, %0" ::"f"((float)-1.388731625493765E-3));      \
    asm volatile("vfmv.v.f v22, %0" ::"f"((float)4.166664568298827E-2));       \
    asm volatile("vfmv.v.f v23, %0" ::"f"((float)0.5));                        \
    asm volatile("vfmv.v.f v24, %0" ::"f"((float)1.0));                        \
    asm volatile("vfmv.v.f v25, %0" ::"f"((float)-1.9515295891E-4));           \
    asm volatile("vfmv.v.f v26, %0" ::"f"((float)8.3321608736E-3));            \
    asm volatile("vfmv.v.f v27, %0" ::"f"((float)-1.6666654611E-1));           \
    asm volatile("vmv.v.i  v28, 0");                                           \
    asm volatile("vmv.v.x  v29, %0" ::"r"((uint64_t)0x7fffffffU));             \
  } while (0)

// Same constants at e64/m1.
#define VCOS_CONST_INIT_F64()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((double)1.27323954473516));          \
    asm volatile("vfmv.v.f v17, %0" ::"f"((double)-0.78515625));               \
    asm volatile("vfmv.v.f v18, %0" ::"f"((double)-2.4187564849853515625E-4)); \
    asm volatile("vfmv.v.f v19, %0" ::"f"((double)-3.77489497744594108E-8));   \
    asm volatile("vfmv.v.f v20, %0" ::"f"((double)2.443315711809948E-5));      \
    asm volatile("vfmv.v.f v21, %0" ::"f"((double)-1.388731625493765E-3));     \
    asm volatile("vfmv.v.f v22, %0" ::"f"((double)4.166664568298827E-2));      \
    asm volatile("vfmv.v.f v23, %0" ::"f"((double)0.5));                       \
    asm volatile("vfmv.v.f v24, %0" ::"f"((double)1.0));                       \
    asm volatile("vfmv.v.f v25, %0" ::"f"((double)-1.9515295891E-4));          \
    asm volatile("vfmv.v.f v26, %0" ::"f"((double)8.3321608736E-3));           \
    asm volatile("vfmv.v.f v27, %0" ::"f"((double)-1.6666654611E-1));          \
    asm volatile("vmv.v.i  v28, 0");                                           \
    asm volatile("vmv.v.x  v29, %0" ::"r"(0x7fffffffffffffffULL));             \
  } while (0)

// VD = cos(VS) at e32/m1, vl set by the caller
#define VCOS_F32M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vand.vv    v4, " #VS ", v29\n\t"  /* x = |angle|                  */  \
        "vfmul.vv   v5, v4, v16\n\t"       /* y = x * 4/pi                 */  \
        "vfcvt.x.f.v v10, v5\n\t"          /* emm2 = (int)y                */  \
        "vadd.vi    v10, v10, 1\n\t"       /* emm2 += 1                    */  \
        "vand.vi    v10, v10, -2\n\t"      /* emm2 &= ~1                   */  \
        "vfcvt.f.x.v v5, v10\n\t"          /* y = (float)emm2              */  \
        "vadd.vi    v10, v10, -2\n\t"      /* emm2 -= 2                    */  \
        "vxor.vi    v8, v10, -1\n\t"       /* emm0 = ~emm2                 */  \
        "vand.vi    v8, v8, 4\n\t"         /* emm0 &= 4                    */  \
        "vsll.vi    v8, v8, 29\n\t"        /* sign_bit = emm0 << 29        */  \
        "vand.vi    v10, v10, 2\n\t"       /* emm2 &= 2                    */  \
        "vmseq.vi   v0, v10, 0\n\t"        /* xMask = (emm2 == 0)          */  \
        "vmerge.vim v9, v28, -1, v0\n\t"   /* poly_mask = xMask ? ~0 : 0   */  \
        "vfmul.vv   v10, v5, v17\n\t"      /* x = ((x + y*DP1) + y*DP2)    */  \
        "vfadd.vv   v4, v4, v10\n\t"       /*         + y*DP3              */  \
        "vfmul.vv   v10, v5, v18\n\t"                                          \
        "vfadd.vv   v4, v4, v10\n\t"                                           \
        "vfmul.vv   v10, v5, v19\n\t"                                          \
        "vfadd.vv   v4, v4, v10\n\t"                                           \
        "vfmul.vv   v7, v4, v4\n\t"        /* z = x*x                      */  \
        "vmv.v.v    v5, v20\n\t"           /* cos poly, 0 <= x <= pi/4     */  \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfadd.vv   v5, v5, v21\n\t"                                           \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfadd.vv   v5, v5, v22\n\t"                                           \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfmul.vv   v10, v7, v23\n\t"      /* tmp = z * 0.5                */  \
        "vfsub.vv   v5, v5, v10\n\t"                                           \
        "vfadd.vv   v5, v5, v24\n\t"       /* y  = 1 - z/2 + poly          */  \
        "vmv.v.v    v6, v25\n\t"           /* sin poly, pi/4 <= x <= 0     */  \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfadd.vv   v6, v6, v26\n\t"                                           \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfadd.vv   v6, v6, v27\n\t"                                           \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfmul.vv   v6, v6, v4\n\t"                                            \
        "vfadd.vv   v6, v6, v4\n\t"        /* y2 = x + x*z*poly            */  \
        "vand.vv    v6, v6, v9\n\t"        /* select one of the two polys  */  \
        "vxor.vi    v10, v9, -1\n\t"                                           \
        "vand.vv    v5, v5, v10\n\t"                                           \
        "vfadd.vv   v5, v5, v6\n\t"                                            \
        "vxor.vv  " #VD ", v5, v8\n\t");   /* y ^= sign_bit                */  \
  } while (0)

// Same at e64/m1; the shift of 61 does not fit vsll.vi, so use vsll.vx
#define VCOS_F64M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vand.vv    v4, " #VS ", v29\n\t"  /* x = |angle|                  */  \
        "vfmul.vv   v5, v4, v16\n\t"       /* y = x * 4/pi                 */  \
        "vfcvt.x.f.v v10, v5\n\t"          /* emm2 = (int)y                */  \
        "vadd.vi    v10, v10, 1\n\t"       /* emm2 += 1                    */  \
        "vand.vi    v10, v10, -2\n\t"      /* emm2 &= ~1                   */  \
        "vfcvt.f.x.v v5, v10\n\t"          /* y = (double)emm2             */  \
        "vadd.vi    v10, v10, -2\n\t"      /* emm2 -= 2                    */  \
        "vxor.vi    v8, v10, -1\n\t"       /* emm0 = ~emm2                 */  \
        "vand.vi    v8, v8, 4\n\t"         /* emm0 &= 4                    */  \
        "vsll.vx    v8, v8, %0\n\t"        /* sign_bit = emm0 << 61        */  \
        "vand.vi    v10, v10, 2\n\t"       /* emm2 &= 2                    */  \
        "vmseq.vi   v0, v10, 0\n\t"        /* xMask = (emm2 == 0)          */  \
        "vmerge.vim v9, v28, -1, v0\n\t"   /* poly_mask = xMask ? ~0 : 0   */  \
        "vfmul.vv   v10, v5, v17\n\t"      /* x = ((x + y*DP1) + y*DP2)    */  \
        "vfadd.vv   v4, v4, v10\n\t"       /*         + y*DP3              */  \
        "vfmul.vv   v10, v5, v18\n\t"                                          \
        "vfadd.vv   v4, v4, v10\n\t"                                           \
        "vfmul.vv   v10, v5, v19\n\t"                                          \
        "vfadd.vv   v4, v4, v10\n\t"                                           \
        "vfmul.vv   v7, v4, v4\n\t"        /* z = x*x                      */  \
        "vmv.v.v    v5, v20\n\t"           /* cos poly, 0 <= x <= pi/4     */  \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfadd.vv   v5, v5, v21\n\t"                                           \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfadd.vv   v5, v5, v22\n\t"                                           \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfmul.vv   v5, v5, v7\n\t"                                            \
        "vfmul.vv   v10, v7, v23\n\t"      /* tmp = z * 0.5                */  \
        "vfsub.vv   v5, v5, v10\n\t"                                           \
        "vfadd.vv   v5, v5, v24\n\t"       /* y  = 1 - z/2 + poly          */  \
        "vmv.v.v    v6, v25\n\t"           /* sin poly, pi/4 <= x <= 0     */  \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfadd.vv   v6, v6, v26\n\t"                                           \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfadd.vv   v6, v6, v27\n\t"                                           \
        "vfmul.vv   v6, v6, v7\n\t"                                            \
        "vfmul.vv   v6, v6, v4\n\t"                                            \
        "vfadd.vv   v6, v6, v4\n\t"        /* y2 = x + x*z*poly            */  \
        "vand.vv    v6, v6, v9\n\t"        /* select one of the two polys  */  \
        "vxor.vi    v10, v9, -1\n\t"                                           \
        "vand.vv    v5, v5, v10\n\t"                                           \
        "vfadd.vv   v5, v5, v6\n\t"                                            \
        "vxor.vv  " #VD ", v5, v8\n\t"     /* y ^= sign_bit                */  \
        ::"r"(61));                                                            \
  } while (0)

#endif // _COS_HOIST_H_
