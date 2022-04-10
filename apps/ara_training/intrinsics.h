// Copyright 2020 ETH Zurich and University of Bologna.
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

// Author: Matheus Cavalcante, ETH Zurich

#ifndef INTRINSICS_H
#define INTRINSICS_H

#include "sew.h"
#include <stdint.h>

/************
 *  VSETVL  *
 ************/

// Those functions set the vector length of the vector machine to
// MIN(MAXVL, vl), and return the result. They also set the standard
// element width to 8, 16, 32, or 64 bits.

inline uint64_t __vsetvl(uint64_t vl, ew_t ew) {
  uint64_t retval;
  switch (ew) {
  case EW8:
    asm volatile("vsetvli %[retval], %[vl], e8, ta, ma"
                 : [ retval ] "=r"(retval)
                 : [ vl ] "r"(vl));
    break;
  case EW16:
    asm volatile("vsetvli %[retval], %[vl], e16, ta, ma"
                 : [ retval ] "=r"(retval)
                 : [ vl ] "r"(vl));
    break;
  case EW32:
    asm volatile("vsetvli %[retval], %[vl], e32, ta, ma"
                 : [ retval ] "=r"(retval)
                 : [ vl ] "r"(vl));
    break;
  case EW64:
    asm volatile("vsetvli %[retval], %[vl], e64, ta, ma"
                 : [ retval ] "=r"(retval)
                 : [ vl ] "r"(vl));
    break;
  }
  return retval;
}

/*****************
 *  VECTOR LOAD  *
 *****************/

// The following macro generates functions that load vl sequential elements from
// the address addr into the destination vector vd.

// Calling convention: __vle__vd(addr) loads vl elements of width SEW from
// address addr into vector register vd. Example: __vle__v0(B)

#define __vle_generator(vd)                                                    \
  inline void __vle__##vd(void *addr) {                                        \
    switch (SEW) {                                                             \
    case EW8:                                                                  \
      asm volatile("vle8.v  " #vd ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW16:                                                                 \
      asm volatile("vle16.v " #vd ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW32:                                                                 \
      asm volatile("vle32.v " #vd ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW64:                                                                 \
      asm volatile("vle64.v " #vd ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    }                                                                          \
  }

// clang-format off
// Generate the intrinsics for all the destination vectors
__vle_generator(v0)
__vle_generator(v1)
__vle_generator(v2)
__vle_generator(v3)
__vle_generator(v4)
__vle_generator(v5)
__vle_generator(v6)
__vle_generator(v7)
// ... Add more if needed
// clang-format on

/******************
 *  VECTOR STORE  *
 ******************/

// The following macro generates functions that store vl elements from the
// source vector vs into the address addr.

// Calling convention: __vse__vs(addr) stores vl elements of width SEW from
// source register vs into address addr. Example: __vse__v3(C);

#define __vse_generator(vs)                                                    \
  inline void __vse__##vs(void *addr) {                                        \
    switch (SEW) {                                                             \
    case EW8:                                                                  \
      asm volatile("vse8.v  " #vs ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW16:                                                                 \
      asm volatile("vse16.v " #vs ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW32:                                                                 \
      asm volatile("vse32.v " #vs ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    case EW64:                                                                 \
      asm volatile("vse64.v " #vs ", (%[addr])" ::[addr] "r"(addr));           \
      break;                                                                   \
    }                                                                          \
  }

    // clang-format off
// Generate the intrinsics for all the source vectors
__vse_generator(v0)
__vse_generator(v1)
__vse_generator(v2)
__vse_generator(v3)
__vse_generator(v4)
__vse_generator(v5)
__vse_generator(v6)
__vse_generator(v7)
// ... Add more if needed
// clang-format on

/*************
 *  VMV.V.X  *
 *************/

// The following macro initializes vl elements of the destination vector vd with
// the scalar value scalar.

// Calling convention: __vmv_vx__vd(uint64_t scalar). Example: __vmv_vx__v0(0);

#define __vmv_vx_generator(vd)                                                 \
  inline void __vmv_vx__##vd(uint64_t scalar) {                                \
    asm volatile("vmv.v.x " #vd ", %[scalar]" ::[scalar] "r"(scalar));         \
  }

    // clang-format off
// Generate the intrinsics
__vmv_vx_generator(v0)
__vmv_vx_generator(v1)
__vmv_vx_generator(v2)
__vmv_vx_generator(v3)
__vmv_vx_generator(v4)
__vmv_vx_generator(v5)
__vmv_vx_generator(v6)
__vmv_vx_generator(v7)
// ... Add more if needed
// clang-format on

/*************
 *  VADD.VV  *
 *************/

// The following macro generates functions that add vectors vs1 and vs2 into
// destination vector vd.

// Calling convention: __vadd_vv__vd_vs1_vs2(). Example: __vadd_vv__v2_v1_v0();

#define __vadd_vv_generator(vd, vs1, vs2)                                      \
  inline void __vadd_vv__##vd##_##vs1##_##vs2() {                              \
    asm volatile("vadd.vv " #vd ", " #vs1 ", " #vs2);                          \
  }

    // clang-format off
// Generate the intrinsics
__vadd_vv_generator(v0, v0, v0)
__vadd_vv_generator(v0, v0, v1)
__vadd_vv_generator(v0, v0, v2)
__vadd_vv_generator(v0, v0, v3)
__vadd_vv_generator(v0, v1, v0)
__vadd_vv_generator(v0, v1, v1)
__vadd_vv_generator(v0, v1, v2)
__vadd_vv_generator(v0, v1, v3)
// ... Add more if needed
// clang-format on

/**************
 *  VMACC.VV  *
 **************/

// The following macro generates functions that multiplies vectors vs1 and vs2,
// add the result to vector vd, and store the final result back to vd.

// Calling convention: __vmacc_vv__vd_vs1_vs2(). Example:
// __vmacc_vv__v2_v1_v0();

#define __vmacc_vv_generator(vd, vs1, vs2)                                     \
  inline void __vmacc_vv__##vd##_##vs1##_##vs2() {                             \
    asm volatile("vmacc.vv " #vd ", " #vs1 ", " #vs2);                         \
  }

    // clang-format off
// Generate the intrinsics
__vmacc_vv_generator(v0, v0, v0)
__vmacc_vv_generator(v0, v0, v1)
__vmacc_vv_generator(v0, v0, v2)
// ... Add more if needed
// clang-format on

/**************
 *  VMACC.VX  *
 **************/

// The following macro generates functions that multiplies vectors vs1 and
// scalar value scalar, add the result to vector vd, and store the final result
// back to vd.

// Calling convention: __vmacc_vx__vd_vs1(scalar). Example:
// __vmacc_vx__v2_v1(2);

#define __vmacc_vx_generator(vd, vs1)                                          \
  inline void __vmacc_vx__##vd##_##vs1(uint64_t scalar) {                      \
    asm volatile("vmacc.vx " #vd ", %[scalar], " #vs1 ::[scalar] "r"(scalar)); \
  }

    // clang-format off
// Generate the intrinsics
__vmacc_vx_generator(v0, v1)
__vmacc_vx_generator(v0, v2)
__vmacc_vx_generator(v0, v3)
// ... Add more if needed
// clang-format on

/**************
 *  VMUL.VX  *
 **************/

// The following macro generates functions that multiplies vectors vs1 and
// scalar value scalar, and store the final result back to vd.

// Calling convention: __vmul_vx__vd_vs1(scalar). Example:
// __vmul_vx__v2_v1(2);

#define __vmul_vx_generator(vd, vs1)                                          \
  inline void __vmul_vx__##vd##_##vs1(uint64_t scalar) {                      \
    asm volatile("vmul.vx " #vd ", %[scalar], " #vs1 ::[scalar] "r"(scalar)); \
  }

    // clang-format off
// Generate the intrinsics
__vmul_vx_generator(v0, v1)
__vmul_vx_generator(v0, v2)
__vmul_vx_generator(v0, v3)
// ... Add more if needed
// clang-format on

/********************
 *  Masked VMUL.VX  *
 *******************/

// The following macro generates functions that multiplies the unmasked vectors vs1 and
// scalar value scalar, and store the final result back to vd. The elements of vd
// with masked index, keeps their previous value.
// The mask vector is contained in vm.

// Calling convention: __vmul_vx__vd_vs1_vm(scalar). Example:
// __vmul_vx__v2_v1_v0(2);

#define __vmul_vx_m_generator(vd, vs1, vm)                                        \
  inline void __vmul_vx_m__##vd##_##vs1##_##vm(uint64_t scalar) {                      \
    asm volatile("vmul.vx " #vd ", %[scalar], " #vs1 ", " #vm ".t" ::[scalar] "r"(scalar)); \
  }

    // clang-format off
// Generate the intrinsics
__vmul_vx_m_generator(v0, v1, v31)
__vmul_vx_m_generator(v0, v2, v31)
__vmul_vx_m_generator(v0, v3, v31)
// ... Add more if needed
// clang-format on

#endif // INTRINSICS_H
