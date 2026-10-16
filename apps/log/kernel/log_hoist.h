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
// Fixed-register assembly port of `__log_1xf64` / `__log_2xf32` (log.h).
// m1 only: too many live temps for LMUL > 1.
//
// Register contract (must be free at the call site, m1):
//   in/out : VS (x, preserved), VD (y)
//   temps  : v4 (x), v5 (y), v6 (e), v7 (z), v8 (tmp), v9 (imm0), v10 (adj),
//            v0 (mask), v3 (invalid_mask stash)
//   consts : v16..v25 (set once by VLOG_CONST_INIT_* before the strip loop)
// VD and VS must be distinct, and must not be any of v0/v3..v10/v16..v25.
// Only v0 can drive vmerge, so invalid_mask is parked in v3 while the second
// mask is live.

#ifndef _LOG_HOIST_H_
#define _LOG_HOIST_H_

// Broadcast the Cephes constants into v16..v25. Call once, under e32/m1 at
// VLMAX, before the strip-mine loop.
//   v16..v23=p1..p8 v24=zero v25=one
#define VLOG_CONST_INIT_F32()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((float)-1.1514610310E-1));           \
    asm volatile("vfmv.v.f v17, %0" ::"f"((float)1.1676998740E-1));            \
    asm volatile("vfmv.v.f v18, %0" ::"f"((float)-1.2420140846E-1));           \
    asm volatile("vfmv.v.f v19, %0" ::"f"((float)1.4249322787E-1));            \
    asm volatile("vfmv.v.f v20, %0" ::"f"((float)-1.6668057665E-1));           \
    asm volatile("vfmv.v.f v21, %0" ::"f"((float)2.0000714765E-1));            \
    asm volatile("vfmv.v.f v22, %0" ::"f"((float)-2.4999993993E-1));           \
    asm volatile("vfmv.v.f v23, %0" ::"f"((float)3.3333331174E-1));            \
    asm volatile("vmv.v.i  v24, 0");                                           \
    asm volatile("vfmv.v.f v25, %0" ::"f"((float)1.0));                        \
  } while (0)

// Same constants at e64/m1.
#define VLOG_CONST_INIT_F64()                                                  \
  do {                                                                         \
    asm volatile("vfmv.v.f v16, %0" ::"f"((double)-1.1514610310E-1));          \
    asm volatile("vfmv.v.f v17, %0" ::"f"((double)1.1676998740E-1));           \
    asm volatile("vfmv.v.f v18, %0" ::"f"((double)-1.2420140846E-1));          \
    asm volatile("vfmv.v.f v19, %0" ::"f"((double)1.4249322787E-1));           \
    asm volatile("vfmv.v.f v20, %0" ::"f"((double)-1.6668057665E-1));          \
    asm volatile("vfmv.v.f v21, %0" ::"f"((double)2.0000714765E-1));           \
    asm volatile("vfmv.v.f v22, %0" ::"f"((double)-2.4999993993E-1));          \
    asm volatile("vfmv.v.f v23, %0" ::"f"((double)3.3333331174E-1));           \
    asm volatile("vmv.v.i  v24, 0");                                           \
    asm volatile("vfmv.v.f v25, %0" ::"f"((double)1.0));                       \
  } while (0)

// VD = log(VS) at e32/m1, vl set by the caller
#define VLOG_F32M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vmv.v.v    v4, " #VS "\n\t"       /* x = arg                      */  \
        "vmfle.vv   v0, v4, v24\n\t"       /* invalid = x <= 0             */  \
        "vmand.mm   v3, v0, v0\n\t"        /* park invalid_mask            */  \
        "vfmax.vf   v4, v4, %[fmin]\n\t"   /* cut off denormals            */  \
        "vsrl.vi    v9, v4, 23\n\t"        /* imm0 = bits(x) >> 23         */  \
        "vand.vx    v4, v4, %[mant]\n\t"   /* keep the fractional part     */  \
        "vor.vx     v4, v4, %[hbits]\n\t"  /* x = mantissa | 0.5           */  \
        "vadd.vx    v9, v9, %[nbias]\n\t"  /* imm0 -= 127                  */  \
        "vfcvt.f.x.v v6, v9\n\t"           /* e = (float)imm0              */  \
        "vfadd.vf   v6, v6, %[fone]\n\t"   /* e += 1                       */  \
        "vmflt.vf   v0, v4, %[sqrth]\n\t"  /* mask = x < sqrt(0.5)         */  \
        "vmerge.vvm v8, v24, v4, v0\n\t"   /* tmp = mask ? x : 0           */  \
        "vfsub.vf   v4, v4, %[fone]\n\t"   /* x -= 1                       */  \
        "vmerge.vvm v10, v24, v25, v0\n\t" /* adj = mask ? 1 : 0           */  \
        "vfsub.vv   v6, v6, v10\n\t"       /* e -= adj                     */  \
        "vfadd.vv   v4, v4, v8\n\t"        /* x += tmp                     */  \
        "vfmul.vv   v7, v4, v4\n\t"        /* z = x*x                      */  \
        "vfmv.v.f   v5, %[p0]\n\t"         /* y = p0                       */  \
        "vfmadd.vv  v5, v4, v16\n\t"       /* y = y*x + p1                 */  \
        "vfmadd.vv  v5, v4, v17\n\t"                                           \
        "vfmadd.vv  v5, v4, v18\n\t"                                           \
        "vfmadd.vv  v5, v4, v19\n\t"                                           \
        "vfmadd.vv  v5, v4, v20\n\t"                                           \
        "vfmadd.vv  v5, v4, v21\n\t"                                           \
        "vfmadd.vv  v5, v4, v22\n\t"                                           \
        "vfmadd.vv  v5, v4, v23\n\t"       /* y = y*x + p8                 */  \
        "vfmul.vv   v5, v5, v4\n\t"        /* y *= x                       */  \
        "vfmul.vv   v5, v5, v7\n\t"        /* y *= z                       */  \
        "vfmacc.vf  v5, %[c2], v6\n\t"     /* y += C2 * e                  */  \
        "vfmul.vf   v8, v7, %[fhalf]\n\t"  /* tmp = z * 0.5                */  \
        "vfsub.vv   v5, v5, v8\n\t"        /* y -= tmp                     */  \
        "vfmul.vf   v8, v6, %[c1]\n\t"     /* tmp = e * C1                 */  \
        "vfadd.vv   v4, v4, v5\n\t"        /* x += y                       */  \
        "vfadd.vv   v4, v4, v8\n\t"        /* x += tmp                     */  \
        "vmand.mm   v0, v3, v3\n\t"        /* restore invalid_mask         */  \
        "vmerge.vim " #VD ", v4, -1, v0\n\t" /* NaN where x <= 0           */  \
        ::[fmin] "f"((float)1.17549435e-38), [mant] "r"(0x807fffffU),          \
          [hbits] "r"(0x3f000000U), [nbias] "r"(-127),                         \
          [fone] "f"((float)1.0), [sqrth] "f"((float)0.707106781186547524),    \
          [p0] "f"((float)7.0376836292E-2), [c2] "f"((float)-2.12194440e-4),   \
          [fhalf] "f"((float)0.5), [c1] "f"((float)0.693359375));              \
  } while (0)

// Same at e64/m1; the shift of 52 does not fit vsrl.vi, so use vsrl.vx
#define VLOG_F64M1(VD, VS)                                                     \
  do {                                                                         \
    asm volatile(                                                              \
        "vmv.v.v    v4, " #VS "\n\t"       /* x = arg                      */  \
        "vmfle.vv   v0, v4, v24\n\t"       /* invalid = x <= 0             */  \
        "vmand.mm   v3, v0, v0\n\t"        /* park invalid_mask            */  \
        "vfmax.vf   v4, v4, %[fmin]\n\t"   /* cut off denormals            */  \
        "vsrl.vx    v9, v4, %[shift]\n\t"  /* imm0 = bits(x) >> 52         */  \
        "vand.vx    v4, v4, %[mant]\n\t"   /* keep the fractional part     */  \
        "vor.vx     v4, v4, %[hbits]\n\t"  /* x = mantissa | 0.5           */  \
        "vadd.vx    v9, v9, %[nbias]\n\t"  /* imm0 -= 1023                 */  \
        "vfcvt.f.x.v v6, v9\n\t"           /* e = (double)imm0             */  \
        "vfadd.vf   v6, v6, %[fone]\n\t"   /* e += 1                       */  \
        "vmflt.vf   v0, v4, %[sqrth]\n\t"  /* mask = x < sqrt(0.5)         */  \
        "vmerge.vvm v8, v24, v4, v0\n\t"   /* tmp = mask ? x : 0           */  \
        "vfsub.vf   v4, v4, %[fone]\n\t"   /* x -= 1                       */  \
        "vmerge.vvm v10, v24, v25, v0\n\t" /* adj = mask ? 1 : 0           */  \
        "vfsub.vv   v6, v6, v10\n\t"       /* e -= adj                     */  \
        "vfadd.vv   v4, v4, v8\n\t"        /* x += tmp                     */  \
        "vfmul.vv   v7, v4, v4\n\t"        /* z = x*x                      */  \
        "vfmv.v.f   v5, %[p0]\n\t"         /* y = p0                       */  \
        "vfmadd.vv  v5, v4, v16\n\t"       /* y = y*x + p1                 */  \
        "vfmadd.vv  v5, v4, v17\n\t"                                           \
        "vfmadd.vv  v5, v4, v18\n\t"                                           \
        "vfmadd.vv  v5, v4, v19\n\t"                                           \
        "vfmadd.vv  v5, v4, v20\n\t"                                           \
        "vfmadd.vv  v5, v4, v21\n\t"                                           \
        "vfmadd.vv  v5, v4, v22\n\t"                                           \
        "vfmadd.vv  v5, v4, v23\n\t"       /* y = y*x + p8                 */  \
        "vfmul.vv   v5, v5, v4\n\t"        /* y *= x                       */  \
        "vfmul.vv   v5, v5, v7\n\t"        /* y *= z                       */  \
        "vfmacc.vf  v5, %[c2], v6\n\t"     /* y += C2 * e                  */  \
        "vfmul.vf   v8, v7, %[fhalf]\n\t"  /* tmp = z * 0.5                */  \
        "vfsub.vv   v5, v5, v8\n\t"        /* y -= tmp                     */  \
        "vfmul.vf   v8, v6, %[c1]\n\t"     /* tmp = e * C1                 */  \
        "vfadd.vv   v4, v4, v5\n\t"        /* x += y                       */  \
        "vfadd.vv   v4, v4, v8\n\t"        /* x += tmp                     */  \
        "vmand.mm   v0, v3, v3\n\t"        /* restore invalid_mask         */  \
        "vmerge.vim " #VD ", v4, -1, v0\n\t" /* NaN where x <= 0           */  \
        ::[fmin] "f"((double)2.2250738585072014e-308),                         \
          [shift] "r"(52), [mant] "r"(0x800fffffffffffffULL),                  \
          [hbits] "r"(0x3fe0000000000000ULL), [nbias] "r"(-1023),              \
          [fone] "f"((double)1.0), [sqrth] "f"((double)0.707106781186547524),  \
          [p0] "f"((double)7.0376836292E-2), [c2] "f"((double)-2.12194440e-4), \
          [fhalf] "f"((double)0.5), [c1] "f"((double)0.693359375));            \
  } while (0)

#endif // _LOG_HOIST_H_
