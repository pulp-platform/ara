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
// Fixed-register assembly port of the Cephes f32 exp() (`__exp_2xf32` from
// exp.h). e32/m1.
//
// The intrinsic version re-materializes the 14 Cephes constants on every call.
// Here they are broadcast once into v16..v29 before the strip-mine loop, so the
// hot path is only the ~24 arithmetic ops below.
//
// Register contract (must be free at the call site, m1):
//   in/out : VIN (clobbered as the working `x`), VD (= result `y`)
//   temps  : v6 (fx), v7 (t), v8 (tmp2), v9 (z), v11 (imm), v0 (mask)
//   consts : v16..v29  (set once by VEXP_CONST_INIT before the strip loop)
// VD and VIN must be distinct, and must not be any of v0/v6..v11/v16..v29.

#ifndef _EXP_ASM_H_
#define _EXP_ASM_H_

// Broadcast the Cephes constants into v16..v29. Call once, under e32/m1 at
// VLMAX, before the strip-mine loop.
//   v16=exp_hi v17=exp_lo v18=LOG2EF v19=C1 v20=C2
//   v21=p0 v22=p1 v23=p2 v24=p3 v25=p4 v26=p5
//   v27=one v28=zero v29=half
#define VEXP_CONST_INIT()                                                      \
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

// y = exp(x).  VIN holds x on entry (clobbered); VD receives y. e32/m1, vl set
// by the caller. Faithful op-by-op translation of __exp_2xf32().
#define VEXP_F32M1(VD, VIN)                                                    \
  do {                                                                         \
    asm volatile(                                                              \
        "vfmin.vv " #VIN ", " #VIN ", v16\n\t"   /* x = min(x, hi)        */    \
        "vfmax.vv " #VIN ", " #VIN ", v17\n\t"   /* x = max(x, lo)        */    \
        "vmv.v.v  v6, v29\n\t"                   /* fx = 0.5              */    \
        "vfmacc.vv v6, v18, " #VIN "\n\t"        /* fx += LOG2EF * x      */    \
        "vfcvt.x.f.v v7, v6\n\t"                 /* t  = (int)fx          */    \
        "vfcvt.f.x.v v7, v7\n\t"                 /* t  = (float)t         */    \
        "vmflt.vv v0, v6, v7\n\t"                /* mask = fx < t         */    \
        "vmerge.vvm v8, v28, v27, v0\n\t"        /* tmp2 = mask ? 1 : 0   */    \
        "vfsub.vv v6, v7, v8\n\t"                /* fx = t - tmp2 (floor) */    \
        "vfmul.vv v7, v6, v19\n\t"               /* t = fx * C1           */    \
        "vfmul.vv v9, v6, v20\n\t"               /* z = fx * C2           */    \
        "vfsub.vv " #VIN ", " #VIN ", v7\n\t"    /* x -= t                */    \
        "vfsub.vv " #VIN ", " #VIN ", v9\n\t"    /* x -= z                */    \
        "vfmul.vv v9, " #VIN ", " #VIN "\n\t"    /* z = x * x             */    \
        "vmv.v.v " #VD ", v21\n\t"               /* y = p0                */    \
        "vfmadd.vv " #VD ", " #VIN ", v22\n\t"   /* y = y*x + p1          */    \
        "vfmadd.vv " #VD ", " #VIN ", v23\n\t"   /* y = y*x + p2          */    \
        "vfmadd.vv " #VD ", " #VIN ", v24\n\t"   /* y = y*x + p3          */    \
        "vfmadd.vv " #VD ", " #VIN ", v25\n\t"   /* y = y*x + p4          */    \
        "vfmadd.vv " #VD ", " #VIN ", v26\n\t"   /* y = y*x + p5          */    \
        "vfmadd.vv " #VD ", v9, " #VIN "\n\t"    /* y = y*z + x           */    \
        "vfadd.vv " #VD ", " #VD ", v27\n\t"     /* y = y + 1             */    \
        "vfcvt.x.f.v v11, v6\n\t"                /* imm = (int)fx         */    \
        "vadd.vx v11, v11, %0\n\t"               /* imm += 127            */    \
        "vsll.vi v11, v11, 23\n\t"               /* imm <<= 23  (2^fx)    */    \
        "vfmul.vv " #VD ", " #VD ", v11\n\t"     /* y *= 2^fx             */    \
        ::"r"(127));                                                           \
  } while (0)

#endif // _EXP_ASM_H_
