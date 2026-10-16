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
// Fixed-register assembly port of `__exp_1xf64` / `__exp_2xf32` (exp.h).
// m1 only: too many live temps for LMUL > 1.
//
// Register contract (must be free at the call site, m1):
//   in/out : VS (x, preserved), VD (y)
//   temps  : v4 (x), v5 (y), v6 (fx), v7 (t), v8 (tmp2), v9 (z), v10 (imm),
//            v0 (mask)
//   consts : v16..v29 (set once by VEXP_CONST_INIT_* before the strip loop)
// VD and VS must be distinct, and must not be any of v0/v4..v10/v16..v29.

#ifndef _EXP_HOIST_H_
#define _EXP_HOIST_H_

// Broadcast the Cephes constants into v16..v29. Call once, under e32/m1 at
// VLMAX, before the strip-mine loop.
//   v16=exp_hi v17=exp_lo v18=LOG2EF v19=C1 v20=C2
//   v21=p0 v22=p1 v23=p2 v24=p3 v25=p4 v26=p5  v27=one v28=zero v29=half
#define VEXP_CONST_INIT_F32()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((float)88.3762626647949));           \
    asm volatile("vfmv.v.f v17, %0" ::"f"((float)-88.3762626647949));          \
    asm volatile("vfmv.v.f v18, %0" ::"f"((float)1.44269504088896341));        \
    asm volatile("vfmv.v.f v19, %0" ::"f"((float)0.693359375));                \
    asm volatile("vfmv.v.f v20, %0" ::"f"((float)-2.12194440e-4));             \
    asm volatile("vfmv.v.f v21, %0" ::"f"((float)1.9875691500E-4));            \
    asm volatile("vfmv.v.f v22, %0" ::"f"((float)1.3981999507E-3));            \
    asm volatile("vfmv.v.f v23, %0" ::"f"((float)8.3334519073E-3));            \
    asm volatile("vfmv.v.f v24, %0" ::"f"((float)4.1665795894E-2));            \
    asm volatile("vfmv.v.f v25, %0" ::"f"((float)1.6666665459E-1));            \
    asm volatile("vfmv.v.f v26, %0" ::"f"((float)5.0000001201E-1));            \
    asm volatile("vfmv.v.f v27, %0" ::"f"((float)1.0));                        \
    asm volatile("vmv.v.i  v28, 0");                                           \
    asm volatile("vfmv.v.f v29, %0" ::"f"((float)0.5));                        \
  } while (0)

// Same constants at e64/m1.
#define VEXP_CONST_INIT_F64()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((double)88.3762626647949));          \
    asm volatile("vfmv.v.f v17, %0" ::"f"((double)-88.3762626647949));         \
    asm volatile("vfmv.v.f v18, %0" ::"f"((double)1.44269504088896341));       \
    asm volatile("vfmv.v.f v19, %0" ::"f"((double)0.693359375));               \
    asm volatile("vfmv.v.f v20, %0" ::"f"((double)-2.12194440e-4));            \
    asm volatile("vfmv.v.f v21, %0" ::"f"((double)1.9875691500E-4));           \
    asm volatile("vfmv.v.f v22, %0" ::"f"((double)1.3981999507E-3));           \
    asm volatile("vfmv.v.f v23, %0" ::"f"((double)8.3334519073E-3));           \
    asm volatile("vfmv.v.f v24, %0" ::"f"((double)4.1665795894E-2));           \
    asm volatile("vfmv.v.f v25, %0" ::"f"((double)1.6666665459E-1));           \
    asm volatile("vfmv.v.f v26, %0" ::"f"((double)5.0000001201E-1));           \
    asm volatile("vfmv.v.f v27, %0" ::"f"((double)1.0));                       \
    asm volatile("vmv.v.i  v28, 0");                                           \
    asm volatile("vfmv.v.f v29, %0" ::"f"((double)0.5));                       \
  } while (0)

// VD = exp(VS) at e32/m1, vl set by the caller
#define VEXP_F32M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vfmin.vv   v4, " #VS ", v16\n\t"  /* x = min(x, hi)                */ \
        "vfmax.vv   v4, v4, v17\n\t"       /* x = max(x, lo)               */  \
        "vmv.v.v    v6, v29\n\t"           /* fx = 0.5                     */  \
        "vfmacc.vv  v6, v18, v4\n\t"       /* fx += LOG2EF * x             */  \
        "vfcvt.x.f.v v7, v6\n\t"           /* t = (int)fx                  */  \
        "vfcvt.f.x.v v7, v7\n\t"           /* t = (float)t                 */  \
        "vmflt.vv   v0, v6, v7\n\t"        /* mask = fx < t                */  \
        "vmerge.vvm v8, v28, v27, v0\n\t"  /* tmp2 = mask ? 1 : 0          */  \
        "vfsub.vv   v6, v7, v8\n\t"        /* fx = t - tmp2 (floor)        */  \
        "vfmul.vv   v7, v6, v19\n\t"       /* t = fx * C1                  */  \
        "vfmul.vv   v9, v6, v20\n\t"       /* z = fx * C2                  */  \
        "vfsub.vv   v4, v4, v7\n\t"        /* x -= t                       */  \
        "vfsub.vv   v4, v4, v9\n\t"        /* x -= z                       */  \
        "vfmul.vv   v9, v4, v4\n\t"        /* z = x * x                    */  \
        "vmv.v.v    v5, v21\n\t"           /* y = p0                       */  \
        "vfmadd.vv  v5, v4, v22\n\t"       /* y = y*x + p1                 */  \
        "vfmadd.vv  v5, v4, v23\n\t"                                           \
        "vfmadd.vv  v5, v4, v24\n\t"                                           \
        "vfmadd.vv  v5, v4, v25\n\t"                                           \
        "vfmadd.vv  v5, v4, v26\n\t"                                           \
        "vfmadd.vv  v5, v9, v4\n\t"        /* y = y*z + x                  */  \
        "vfadd.vv   v5, v5, v27\n\t"       /* y = y + 1                    */  \
        "vfcvt.x.f.v v10, v6\n\t"          /* imm = (int)fx                */  \
        "vadd.vx    v10, v10, %0\n\t"      /* imm += 127                   */  \
        "vsll.vi    v10, v10, 23\n\t"      /* imm <<= 23   (2^fx)          */  \
        "vfmul.vv " #VD ", v5, v10\n\t"    /* y *= 2^fx                    */  \
        ::"r"(127));                                                           \
  } while (0)

// Same at e64/m1; the shift of 52 does not fit vsll.vi, so use vsll.vx
#define VEXP_F64M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vfmin.vv   v4, " #VS ", v16\n\t"  /* x = min(x, hi)                */ \
        "vfmax.vv   v4, v4, v17\n\t"       /* x = max(x, lo)               */  \
        "vmv.v.v    v6, v29\n\t"           /* fx = 0.5                     */  \
        "vfmacc.vv  v6, v18, v4\n\t"       /* fx += LOG2EF * x             */  \
        "vfcvt.x.f.v v7, v6\n\t"           /* t = (int)fx                  */  \
        "vfcvt.f.x.v v7, v7\n\t"           /* t = (double)t                */  \
        "vmflt.vv   v0, v6, v7\n\t"        /* mask = fx < t                */  \
        "vmerge.vvm v8, v28, v27, v0\n\t"  /* tmp2 = mask ? 1 : 0          */  \
        "vfsub.vv   v6, v7, v8\n\t"        /* fx = t - tmp2 (floor)        */  \
        "vfmul.vv   v7, v6, v19\n\t"       /* t = fx * C1                  */  \
        "vfmul.vv   v9, v6, v20\n\t"       /* z = fx * C2                  */  \
        "vfsub.vv   v4, v4, v7\n\t"        /* x -= t                       */  \
        "vfsub.vv   v4, v4, v9\n\t"        /* x -= z                       */  \
        "vfmul.vv   v9, v4, v4\n\t"        /* z = x * x                    */  \
        "vmv.v.v    v5, v21\n\t"           /* y = p0                       */  \
        "vfmadd.vv  v5, v4, v22\n\t"       /* y = y*x + p1                 */  \
        "vfmadd.vv  v5, v4, v23\n\t"                                           \
        "vfmadd.vv  v5, v4, v24\n\t"                                           \
        "vfmadd.vv  v5, v4, v25\n\t"                                           \
        "vfmadd.vv  v5, v4, v26\n\t"                                           \
        "vfmadd.vv  v5, v9, v4\n\t"        /* y = y*z + x                  */  \
        "vfadd.vv   v5, v5, v27\n\t"       /* y = y + 1                    */  \
        "vfcvt.x.f.v v10, v6\n\t"          /* imm = (int)fx                */  \
        "vadd.vx    v10, v10, %0\n\t"      /* imm += 1023                  */  \
        "vsll.vx    v10, v10, %1\n\t"      /* imm <<= 52   (2^fx)          */  \
        "vfmul.vv " #VD ", v5, v10\n\t"    /* y *= 2^fx                    */  \
        ::"r"(1023), "r"(52));                                                 \
  } while (0)

// VEXP_F64M1 on a second temp bank, for 2x unrolling: v11 (x), v12 (y),
// v13 (fx), v14 (t), v15 (tmp2), v30 (z), v31 (imm). v0 is still the mask.
#define VEXP_F64M1_ALT(VD, VS)                                                 \
  do {                                                                         \
    asm volatile(                                                              \
        "vfmin.vv   v11, " #VS ", v16\n\t"                                     \
        "vfmax.vv   v11, v11, v17\n\t"                                         \
        "vmv.v.v    v13, v29\n\t"                                              \
        "vfmacc.vv  v13, v18, v11\n\t"                                         \
        "vfcvt.x.f.v v14, v13\n\t"                                             \
        "vfcvt.f.x.v v14, v14\n\t"                                             \
        "vmflt.vv   v0, v13, v14\n\t"                                          \
        "vmerge.vvm v15, v28, v27, v0\n\t"                                     \
        "vfsub.vv   v13, v14, v15\n\t"                                         \
        "vfmul.vv   v14, v13, v19\n\t"                                         \
        "vfmul.vv   v30, v13, v20\n\t"                                         \
        "vfsub.vv   v11, v11, v14\n\t"                                         \
        "vfsub.vv   v11, v11, v30\n\t"                                         \
        "vfmul.vv   v30, v11, v11\n\t"                                         \
        "vmv.v.v    v12, v21\n\t"                                              \
        "vfmadd.vv  v12, v11, v22\n\t"                                         \
        "vfmadd.vv  v12, v11, v23\n\t"                                         \
        "vfmadd.vv  v12, v11, v24\n\t"                                         \
        "vfmadd.vv  v12, v11, v25\n\t"                                         \
        "vfmadd.vv  v12, v11, v26\n\t"                                         \
        "vfmadd.vv  v12, v30, v11\n\t"                                         \
        "vfadd.vv   v12, v12, v27\n\t"                                         \
        "vfcvt.x.f.v v31, v13\n\t"                                             \
        "vadd.vx    v31, v31, %0\n\t"                                          \
        "vsll.vx    v31, v31, %1\n\t"                                          \
        "vfmul.vv " #VD ", v12, v31\n\t"                                       \
        ::"r"(1023), "r"(52));                                                 \
  } while (0)

// VEXP_F32M1 on the same second temp bank as VEXP_F64M1_ALT
#define VEXP_F32M1_ALT(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vfmin.vv   v11, " #VS ", v16\n\t"  /* x = min(x, hi)                */ \
        "vfmax.vv   v11, v11, v17\n\t"       /* x = max(x, lo)               */  \
        "vmv.v.v    v13, v29\n\t"           /* fx = 0.5                     */  \
        "vfmacc.vv  v13, v18, v11\n\t"       /* fx += LOG2EF * x             */  \
        "vfcvt.x.f.v v14, v13\n\t"           /* t = (int)fx                  */  \
        "vfcvt.f.x.v v14, v14\n\t"           /* t = (float)t                 */  \
        "vmflt.vv   v0, v13, v14\n\t"        /* mask = fx < t                */  \
        "vmerge.vvm v15, v28, v27, v0\n\t"  /* tmp2 = mask ? 1 : 0          */  \
        "vfsub.vv   v13, v14, v15\n\t"        /* fx = t - tmp2 (floor)        */  \
        "vfmul.vv   v14, v13, v19\n\t"       /* t = fx * C1                  */  \
        "vfmul.vv   v30, v13, v20\n\t"       /* z = fx * C2                  */  \
        "vfsub.vv   v11, v11, v14\n\t"        /* x -= t                       */  \
        "vfsub.vv   v11, v11, v30\n\t"        /* x -= z                       */  \
        "vfmul.vv   v30, v11, v11\n\t"        /* z = x * x                    */  \
        "vmv.v.v    v12, v21\n\t"           /* y = p0                       */  \
        "vfmadd.vv  v12, v11, v22\n\t"       /* y = y*x + p1                 */  \
        "vfmadd.vv  v12, v11, v23\n\t"                                           \
        "vfmadd.vv  v12, v11, v24\n\t"                                           \
        "vfmadd.vv  v12, v11, v25\n\t"                                           \
        "vfmadd.vv  v12, v11, v26\n\t"                                           \
        "vfmadd.vv  v12, v30, v11\n\t"        /* y = y*z + x                  */  \
        "vfadd.vv   v12, v12, v27\n\t"       /* y = y + 1                    */  \
        "vfcvt.x.f.v v31, v13\n\t"          /* imm = (int)fx                */  \
        "vadd.vx    v31, v31, %0\n\t"      /* imm += 127                   */  \
        "vsll.vi    v31, v31, 23\n\t"      /* imm <<= 23   (2^fx)          */  \
        "vfmul.vv " #VD ", v12, v31\n\t"    /* y *= 2^fx                    */  \
        ::"r"(127));                                                           \
  } while (0)

#endif // _EXP_HOIST_H_
