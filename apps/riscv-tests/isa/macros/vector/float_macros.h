// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Matteo Perotti <mperotti@iis.ee.ethz.ch>

#ifndef __FLOAT_MACROS_H__
#define __FLOAT_MACROS_H__

#include <stdint.h>

// Zero encoding is common to all the formats
#define pZero  0x0

// 16-bit IEEE 754 floats
#define qNaNh  0x7e00
#define sNaNh  0x7c01
#define pInfh  0x7c00
#define mInfh  0xfc00
#define pMaxh  0x7bff
#define mMaxh  0xfbff
#define mZeroh 0x8000

// 32-bit IEEE 754 floats
#define qNaNf  0x7fc00000
#define sNaNf  0x7f800001
#define pInff  0x7f800000
#define mInff  0xff800000
#define pMaxf  0x7f7fffff
#define mMaxf  0xff7fffff
#define mZerof 0x80000000

// 64-bit IEEE 754 floats
#define qNaNd  0x7ff8000000000000
#define sNaNd  0x7ff0000000000001
#define pInfd  0x7ff0000000000000
#define mInfd  0xfff0000000000000
#define pMaxd  0x7fefffffffffffff
#define mMaxd  0xffefffffffffffff
#define mZerod 0x8000000000000000

// Fflags
#define NV 0b10000 // Invalid Operation (e.g. Inf - Inf, or 0/0)
#define DZ 0b01000 // Divide by Zero    (e.g. x/0, x != 0)
#define OF 0b00100 // Overflow          (e.g. pMaxf + pMaxf)
#define UF 0b00010 // Underflow         (e.g. pMinf/3)
#define NX 0b00001 // Inexact           (e.g. 2/3)

// MSTATUS.FS helpers
#define MSTATUS_FS_MASK  0x6000
#define MSTATUS_FS_INIT  0x2000
#define MSTATUS_FS_CLEAN 0x4000
#define MSTATUS_FS_DIRTY 0x6000

// Rounding Mode in fcsr
#define RM_RNE 0x0
#define RM_RTZ 0x1
#define RM_RDN 0x2
#define RM_RUP 0x3
#define RM_RMM 0x4

// vfclass output
#define CLASS_mInf  0x001
#define CLASS_mNorm 0x002
#define CLASS_mSub  0x004
#define CLASS_mZero 0x008
#define CLASS_pZero 0x010
#define CLASS_pSub  0x020
#define CLASS_pNorm 0x040
#define CLASS_pInf  0x080
#define CLASS_sNAN  0x100
#define CLASS_qNAN  0x200

typedef union double_hex {
  double      d;
  uint64_t ui64;
} double_hex;

// Check fcsr.fflags against an expected FFLAGS value
#define CHECK_FFLAGS(FFLAGS)                                                                             \
  do {                                                                                                   \
    uint64_t gold_ff = FFLAGS;                                                                           \
    uint64_t      ff;                                                                                    \
    asm volatile ("frflags %0" : "=r" (ff));                                                             \
    if (ff != gold_ff) {                                                                                 \
      printf("fflags check FAILED. Current fflags is 0x%02lx, while expecting 0x%02lx.\n", ff, gold_ff); \
      num_failed++;                                                                                      \
      return;                                                                                            \
    }                                                                                                    \
  } while(0)

// Change rounding-mode
#define CHANGE_RM(NEW_RM)                                                                              \
  do {                                                                                                 \
    asm volatile ("fsrm %0" :: "r" (NEW_RM));                                                          \
  } while(0)

// Check fcsr.fflags against an expected FFLAGS value
#define CLEAR_FFLAGS asm volatile ("fsflags %0" :: "r" (0))

// !!!!! mstatus is not accessible in user-mode !!!!!
// Make mstatus.FS Clean
#define CLEAR_FS                                                                                                                                  \
  do {                                                                                                                                            \
    uint64_t old_mstatus;                                                                                                                         \
    uint64_t new_mstatus;                                                                                                                         \
    asm volatile ("csrrs %0, mstatus, x0" : "=r"  (old_mstatus));                                                                                 \
    new_mstatus = old_mstatus & ~((uint64_t) MSTATUS_FS_MASK);                                                                                    \
    new_mstatus |= MSTATUS_FS_CLEAN;                                                                                                              \
    asm volatile ("csrrw x0, mstatus, %0" :: "r" (new_mstatus));                                                                                  \
  } while(0)
// Check if mstatus.FS is Clean
#define CHECK_FS_CLEAN                                                                                                                            \
  do {                                                                                                                                            \
    uint64_t fs;                                                                                                                                  \
    asm volatile ("csrrs %0, mstatus, x0" : "=r" (fs));                                                                                           \
    if ((fs & MSTATUS_FS_MASK) != MSTATUS_FS_CLEAN) {                                                                                             \
      printf("mstatus.FS check FAILED. Current mstatus.FS is 0x%02x, while expecting 0x%02x (Clean).\n", fs & MSTATUS_FS_MASK, MSTATUS_FS_CLEAN); \
      num_failed++;                                                                                                                               \
      return;                                                                                                                                     \
    }                                                                                                                                             \
  } while(0)
// Check if mstatus.FS is Dirty
#define CHECK_FS_DIRTY                                                                                                                            \
  do {                                                                                                                                            \
    uint64_t fs;                                                                                                                                  \
    asm volatile ("csrrs %0, mstatus, x0" : "=r" (fs));                                                                                           \
    if ((fs & MSTATUS_FS_MASK) != MSTATUS_FS_DIRTY) {                                                                                             \
      printf("mstatus.FS check FAILED. Current mstatus.FS is 0x%02x, while expecting 0x%02x (Dirty).\n", fs & MSTATUS_FS_MASK, MSTATUS_FS_DIRTY); \
      num_failed++;                                                                                                                               \
      return;                                                                                                                                     \
    }                                                                                                                                             \
  } while(0)

// NaN-Box a 16-bit IEEE 754 half float in a 64-bit double
// This is useful if we want to specify the IEEE 754 encoding of a floating-point variable
#define BOX_HALF_IN_DOUBLE(VAR_NAME, VAL_16B)                             \
  do {                                                                    \
    double_hex nan_boxed_val;                                             \
    nan_boxed_val.ui64 = ((uint64_t) 0xffffffffffff << 16) | VAL_16B;     \
    VAR_NAME = nan_boxed_val.d;                                           \
  } while(0)

#define BOX_FLOAT_IN_DOUBLE(VAR_NAME, VAL_32B)                        \
  do {                                                                \
    double_hex nan_boxed_val;                                         \
    nan_boxed_val.ui64 = ((uint64_t) 0xffffffff << 32) | VAL_32B;     \
    VAR_NAME = nan_boxed_val.d;                                       \
  } while(0)

#define BOX_DOUBLE_IN_DOUBLE(VAR_NAME, VAL_64B) \
  do {                                          \
    double_hex nan_boxed_val;                   \
    nan_boxed_val.ui64 = VAL_64B;               \
    VAR_NAME = nan_boxed_val.d;                 \
  } while(0)

#endif // __FLOAT_MACROS_H__
