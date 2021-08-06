// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>
//         Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

// Simple random test with similar values
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  //              -4628.000,   5116.000, -9928.000,   9392.000, -140.875,
  //              6112.000,   2598.000,   3210.000,   528.000, -3298.000,
  //              -3674.000,   368.250,   1712.000, -8584.000, -2080.000,
  //              4336.000
  VLOAD_16(v2, 0xec85, 0x6cff, 0xf0d9, 0x7096, 0xd867, 0x6df8, 0x6913, 0x6a45,
           0x6020, 0xea71, 0xeb2d, 0x5dc1, 0x66b0, 0xf031, 0xe810, 0x6c3c);
  asm volatile("vfsqrt.v v3, v2");
  //                nan,   71.500,   nan,   96.938,
  //                nan,   78.188,   50.969,   56.656,   22.984,   nan,
  //                nan,   19.188,   41.375,   nan,   nan,   65.875
  VCMP_U16(1, v3, 0x7e00, 0x5478, 0x7e00, 0x560e, 0x7e00, 0x54e2, 0x525f,
           0x5315, 0x4dbe, 0x7e00, 0x7e00, 0x4ccc, 0x512c, 0x7e00, 0x7e00,
           0x541d);

  VSET(16, e32, m1);
  //                53688.590, -5719.180, -59560.355, -34640.023, -22323.398,
  //                -52381.586,   19136.160,   13055.238, -68576.781,
  //                -35066.488,   62475.219, -25604.578,   54705.039,
  //                -19827.459,   17792.961, -28415.572
  VLOAD_32(v2, 0x4751b897, 0xc5b2b971, 0xc768a85b, 0xc7075006, 0xc6ae66cc,
           0xc74c9d96, 0x46958052, 0x464bfcf4, 0xc785f064, 0xc708fa7d,
           0x47740b38, 0xc6c80928, 0x4755b10a, 0xc69ae6eb, 0x468b01ec,
           0xc6ddff25);
  asm volatile("vfsqrt.v v3, v2");
  //                231.708,   nan,   nan,   nan,   nan,   nan,   138.334,
  //                114.260,   nan,   nan,   249.950,   nan,   233.891,   nan,
  //                133.390,   nan
  VCMP_U32(2, v3, 0x4367b53e, 0x7fc00000, 0x7fc00000, 0x7fc00000, 0x7fc00000,
           0x7fc00000, 0x430a5560, 0x42e484e0, 0x7fc00000, 0x7fc00000,
           0x4379f34f, 0x7fc00000, 0x4369e41e, 0x7fc00000, 0x430563e7,
           0x7fc00000);

  VSET(16, e64, m1);
  //              -2532126.867, -601715.939, -7176821.248,   9617114.284,
  //              -4651296.040, -9962642.835,   4027953.647,   7849763.850,
  //              -9544132.585, -8682313.823,   7018932.012,   639358.130,
  //              -7598169.215, -9585529.793, -4604984.668,   314584.590
  VLOAD_64(v2, 0xc143518f6efce4ae, 0xc1225ce7e096cbf0, 0xc15b609d4fd8b968,
           0x416257db4912ef24, 0xc151be4802974a67, 0xc16300925abc1630,
           0x414ebb18d2c34030, 0x415df1c8f662a87c, 0xc162343892b8d28c,
           0xc1608f693a52837e, 0x415ac66d00c810d8, 0x412382fc427c96a0,
           0xc15cfc164dc9e320, 0xc162486f39607ee9, 0xc151910e2ac0e818,
           0x411333625c861bc0);
  asm volatile("vfsqrt.v v3, v2");
  //                nan,   nan,   nan,   3101.147,   nan,   nan,   2006.976,
  //                2801.743,   nan,   nan,   2649.327,   799.599,   nan,   nan,
  //                nan,   560.878
  VCMP_U64(3, v3, 0x7ff8000000000000, 0x7ff8000000000000, 0x7ff8000000000000,
           0x40a83a4b64b82189, 0x7ff8000000000000, 0x7ff8000000000000,
           0x409f5be7acad5998, 0x40a5e37c6ac52c2f, 0x7ff8000000000000,
           0x7ff8000000000000, 0x40a4b2a7466e763d, 0x4088fcca333ab72d,
           0x7ff8000000000000, 0x7ff8000000000000, 0x7ff8000000000000,
           0x40818706fb9cc11b);
};

// Simple random test with similar values (masked)
// The numbers are the same of TEST_CASE1
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  //              -4628.000,   5116.000, -9928.000,   9392.000, -140.875,
  //              6112.000,   2598.000,   3210.000,   528.000, -3298.000,
  //              -3674.000,   368.250,   1712.000, -8584.000, -2080.000,
  //              4336.000
  VLOAD_16(v2, 0xec85, 0x6cff, 0xf0d9, 0x7096, 0xd867, 0x6df8, 0x6913, 0x6a45,
           0x6020, 0xea71, 0xeb2d, 0x5dc1, 0x66b0, 0xf031, 0xe810, 0x6c3c);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vfsqrt.v v3, v2, v0.t");
  //                0.000,   71.500,   0.000,   96.938,   0.000,   78.188,
  //                0.000,   56.656,   0.000,   nan,   0.000,   19.188,   0.000,
  //                nan,   0.000,   65.875
  VCMP_U16(4, v3, 0x0, 0x5478, 0x0, 0x560e, 0x0, 0x54e2, 0x0, 0x5315, 0x0,
           0x7e00, 0x0, 0x4ccc, 0x0, 0x7e00, 0x0, 0x541d);

  VSET(16, e32, m1);
  //                53688.590, -5719.180, -59560.355, -34640.023, -22323.398,
  //                -52381.586,   19136.160,   13055.238, -68576.781,
  //                -35066.488,   62475.219, -25604.578,   54705.039,
  //                -19827.459,   17792.961, -28415.572
  VLOAD_32(v2, 0x4751b897, 0xc5b2b971, 0xc768a85b, 0xc7075006, 0xc6ae66cc,
           0xc74c9d96, 0x46958052, 0x464bfcf4, 0xc785f064, 0xc708fa7d,
           0x47740b38, 0xc6c80928, 0x4755b10a, 0xc69ae6eb, 0x468b01ec,
           0xc6ddff25);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vfsqrt.v v3, v2, v0.t");
  //                0.000,   nan,   0.000,   nan,   0.000,   nan,   0.000,
  //                114.260,   0.000,   nan,   0.000,   nan,   0.000,   nan,
  //                0.000,   nan
  VCMP_U32(5, v3, 0x0, 0x7fc00000, 0x0, 0x7fc00000, 0x0, 0x7fc00000, 0x0,
           0x42e484e0, 0x0, 0x7fc00000, 0x0, 0x7fc00000, 0x0, 0x7fc00000, 0x0,
           0x7fc00000);

  VSET(16, e64, m1);
  //              -2532126.867, -601715.939, -7176821.248,   9617114.284,
  //              -4651296.040, -9962642.835,   4027953.647,   7849763.850,
  //              -9544132.585, -8682313.823,   7018932.012,   639358.130,
  //              -7598169.215, -9585529.793, -4604984.668,   314584.590
  VLOAD_64(v2, 0xc143518f6efce4ae, 0xc1225ce7e096cbf0, 0xc15b609d4fd8b968,
           0x416257db4912ef24, 0xc151be4802974a67, 0xc16300925abc1630,
           0x414ebb18d2c34030, 0x415df1c8f662a87c, 0xc162343892b8d28c,
           0xc1608f693a52837e, 0x415ac66d00c810d8, 0x412382fc427c96a0,
           0xc15cfc164dc9e320, 0xc162486f39607ee9, 0xc151910e2ac0e818,
           0x411333625c861bc0);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v3);
  asm volatile("vfsqrt.v v3, v2, v0.t");
  //                0.000,   nan,   0.000,   3101.147,   0.000,   nan,   0.000,
  //                2801.743,   0.000,   nan,   0.000,   799.599,   0.000, nan,
  //                0.000,   560.878
  VCMP_U64(6, v3, 0x0, 0x7ff8000000000000, 0x0, 0x40a83a4b64b82189, 0x0,
           0x7ff8000000000000, 0x0, 0x40a5e37c6ac52c2f, 0x0, 0x7ff8000000000000,
           0x0, 0x4088fcca333ab72d, 0x0, 0x7ff8000000000000, 0x0,
           0x40818706fb9cc11b);
};

int main(void) {
  enable_vec();
  enable_fp();
  // Change RM to RTZ since there are issues with FDIV + RNE in fpnew
  // Update: there are issues also with RTZ...
  CHANGE_RM(RM_RTZ);

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
