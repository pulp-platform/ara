// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//y
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

// Simple random test with similar values + 1 subnormal
void TEST_CASE1(void) {
/*// ------E16------------
  VSET(16, e16, m1);

  VLOAD_16(v1 ,0x3a07, 0x093e, 0x09d8, 0x313b, 0x05ac, 0x3487, 0x19a4, 0xb900,
           0x8914, 0x8005, 0x3876, 0x3045, 0x0006, 0x000d, 0x3525, 0xf6ab);
 asm volatile("vfrec7.v v2, v1");
 VCMP_U16(1, v2, 0x03f9, 0x0d42, 0x0dd9,0x03fe,0x11b4,0x03fb,0x01eb,
           0x83f9,0x8d1d,0xb106,0x03f9,0x03ff,0x3205,0x2e84,0x03fb,0x83f8);
           
// ------E32------------         
  VSET(5, e32, m1);
     VLOAD_32(v1,0x31cb3a60,0xa2632640 , 0x00000001, 0x0e87cde5, 
     0x3d8809bb,0x301909bb,0x0bda73da,0x000077ce,
     0x3e5801fb,0x01bd2e10, 0x11101012,0x12000004 , 
     0xeebbbf48,0x2d68699c,0x1468bef0 ,0xa33f5db0);
          
  asm volatile("vfrec7.v v2, v1");
VCMP_U32(2, v2, 0x02cb3cd3, 0x926341e9, 0x3fff0000, 0x258849d6,
                0x007f000F),0x04191de2,0x28da0023,0x3870c183,
                0x007f0004,0x32bd35f4,0x231074d6,0x2200fff8,
                0x807f0000,0x0769fd9c,0x2069c9ec,0x913f3b6c);   
*/
// ------E64------------ 
  VSET(1, e32, m1);
  //               0.6660375425590812, -0.9603615652916235, -0.1168804546788573,
  //               -0.3258082002843947,  0.0488865860405421,
  //               -0.1515621417461690, -0.1189568642850463,
  //               -0.1213016259965920, -0.1369814061459547, 0.5914369694708146,
  //               0.7538814889966272,  0.2346701936201294,  0.9227364529293489,
  //               0.9447507336323382, -0.4250995717346850, -0.0882167932097473
  VLOAD_32(v1, 0x7f765432);/*
   0x3fa907a9a083b220, 0xbfc36663650e4608,  0xbfbe73f501bd2e10, 0xbfbf0d9f949b6370,
   0xbfc1889b51c74ac0,0x3fe2ed0d3930b850, 0x3fe81fcc12899c0a, 0x3fce09ac4378e388,
   0x3fed870e9905133a, 0x3fee3b65e3fa5532, 0xbfdb34d4d5893894, 0xbfb6956031cb3a*/
  asm volatile("vfrec7.v v2, v1");

/*
  VCMP_U64(3, v2,0x0000000000000001,0x8000000000000001,0x8000000000000008,0x8000000000000003,
 0x000000000000014,0x8000000000000006,0x8000000000000008,0x8000000000000008,
 0x8000000000000007,0x0000000000000001,0x0000000000000001,0x0000000000000004,
 0x0000000000000001,0x0000000000000001,0x8000000000000002,0x800000000000000B); */
 /*
  VSET(1, e64, m1);
  VLOAD_64(v1,0x0123567889101114);
  asm volatile("vfrec7.v v2, v1");
  VCMP_U64(3, v2,0x007F000000000001);
  */
 
  };

int main(void) {
  enable_vec();
  enable_fp();
  // Change RM to RTZ since there are issues with FDIV + RNE in fpnew
  // Update: there are issues also with RTZ...
  CHANGE_RM(RM_RTZ);

  TEST_CASE1();
  
  EXIT_CHECK();

  
}
