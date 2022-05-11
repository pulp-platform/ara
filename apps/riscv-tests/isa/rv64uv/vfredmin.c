/*=================================================================================================
Project Name:    Ara
Author:          Xiaorui Yin <yinx@student.ethz.ch>
Organization:    ETH Zürich
File Name:       vfredmin.c
Created On:      2022/05/03

Description:     Dummy tests for floating-point minimum reduction

CopyRight Notice
All Rights Reserved
===================================================================================================
Modification    History:          
Date            By              Version         Change Description
---------------------------------------------------------------------------------------------------

=================================================================================================*/

#include "vector_macros.h"
#include "float_macros.h"

// Naive test
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  // 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 
  VLOAD_16(v2, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v3, 0x3c00);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U16(1, v1, 0x3c00);

  VSET(16, e32, m1);
  VLOAD_32(v2, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v3, 0x3F800000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U32(2, v1, 0x3F800000);

  VSET(16, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(3, v1, 0x3FF0000000000000);
  
  // Super lang vector length
  VSET(64, e32, m1);
  VLOAD_32(v2, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,

               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,

               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,

               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v3, 0x3F800000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U32(4, v1, 0x3F800000);
}

// Masked naive test
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  // 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 
  VLOAD_16(v2, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v3, 0x3c00);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U16(5, v1, 0x3c00);
 
  VSET(16, e32, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_32(v2, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v3, 0x3F800000);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U32(6, v1, 0x3F800000);
 
  VSET(16, e64, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U64(7, v1, 0x3FF0000000000000);
}

// Are we respecting the undisturbed tail policy?
void TEST_CASE3(void) {
  VSET(16, e16, m1);
  // 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 
  VLOAD_16(v2, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v3, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v1, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U16(8, v1, 0x3c00, 0x4000, 0x4200, 0x4400, 
                  0x4500, 0x4600, 0x4700, 0x4800,
                  0x3c00, 0x4000, 0x4200, 0x4400, 
                  0x4500, 0x4600, 0x4700, 0x4800);

  VSET(16, e32, m1);
  VLOAD_32(v2, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v3, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v1, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
               0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U32(9, v1, 0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
                  0x40A00000, 0x40C00000, 0x40E00000, 0x41000000, 
                  0x3F800000, 0x40000000, 0x40400000, 0x40800000, 
                  0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);

  VSET(16, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(10, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
}

// Odd number of elements, undisturbed policy
void TEST_CASE4(void) {
  VSET(1, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(11, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);

  VSET(3, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(12, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3ff0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);

  VSET(7, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(13, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3ff0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);

  VSET(15, e64, m1);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3");
  VCMP_U64(14, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
}

// Odd number of elements, undisturbed policy, and mask
void TEST_CASE5(void) {
  VSET(7, e16, m1);
  VLOAD_8(v0, 0x00, 0xff);
  // 1 2 3 4 5 6 7 8 1 2 3 4 5 6 7 8 
  VLOAD_16(v2, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v3, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  VLOAD_16(v1, 0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800,
               0x3c00, 0x4000, 0x4200, 0x4400, 
               0x4500, 0x4600, 0x4700, 0x4800);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U16(15, v1, 0x3c00, 0x4000, 0x4200, 0x4400, 
                   0x4500, 0x4600, 0x4700, 0x4800,
                   0x3c00, 0x4000, 0x4200, 0x4400, 
                   0x4500, 0x4600, 0x4700, 0x4800);

  VSET(1, e32, m1);
  VLOAD_8(v0, 0xff, 0x00);
  VLOAD_32(v2, 0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,
               0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v3, 0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,
               0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  VLOAD_32(v1, 0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,
               0x3F800000, 0x40000000, 0x40400000, 0x40800000,
               0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U32(16, v1, 0x3F800000, 0x40000000, 0x40400000, 0x40800000,
                   0x40A00000, 0x40C00000, 0x40E00000, 0x41000000,
                   0x3F800000, 0x40000000, 0x40400000, 0x40800000,
                   0x40A00000, 0x40C00000, 0x40E00000, 0x41000000);

  VSET(3, e64, m1);
  VLOAD_8(v0, 0xaa, 0x55);
  VLOAD_64(v2, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v3, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  VLOAD_64(v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
               0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
               0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
  asm volatile("vfredmin.vs v1, v2, v3, v0.t");
  VCMP_U64(17, v1, 0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000,
                   0x3FF0000000000000, 0x4000000000000000, 0x4008000000000000, 0x4010000000000000, 
                   0x4014000000000000, 0x4018000000000000, 0x401C000000000000, 0x4020000000000000);
}

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  EXIT_CHECK();
}
