// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>
//         Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"
#include "float_macros.h"

// Simple random test with similar values (vector-scalar)
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  double dscalar_16;
  //                             -0.2649
  BOX_HALF_IN_DOUBLE(dscalar_16,  0xb43d);
  //              -0.0651,  0.5806,  0.2563, -0.4783,  0.7393, -0.2649, -0.4590,  0.5469, -0.9082,  0.6235, -0.8276, -0.7939, -0.0236, -0.1166,  0.4026,  0.0022
  VLOAD_16(v2,     0xac2a,  0x38a5,  0x341a,  0xb7a7,  0x39ea,  0xb43d,  0xb758,  0x3860,  0xbb44,  0x38fd,  0xba9f,  0xba5a,  0xa60b,  0xaf76,  0x3671,  0x1896);
  asm volatile("vmfgt.vf v1, v2, %[A]" :: [A] "f" (dscalar_16));
  VSET(1, e16, m1);
  VCMP_U16(1, v1,  0xf297);

  VSET(16, e32, m1);
  double dscalar_32;
  //                               0.80517912
  BOX_FLOAT_IN_DOUBLE(dscalar_32,  0x3f4e2038);
  //              -0.15601152, -0.92020410, -0.29387674,  0.98594254,  0.88163614, -0.44641387,  0.88191622,  0.15161350, -0.79952192, -0.03668820, -0.38464722, -0.54745716,  0.09956384,  0.21655059, -0.37557366, -0.79342169
  VLOAD_32(v2,     0xbe1fc17c,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0xbf4b1daf);
  asm volatile("vmfgt.vf v1, v2, %[A]" :: [A] "f" (dscalar_32));
  VSET(1, e16, m1);
  VCMP_U16(2, v1,  0x0000);

  VSET(16, e64, m1);
  double dscalar_64;
  //                               -0.3394093097660049
  BOX_DOUBLE_IN_DOUBLE(dscalar_64,  0xbfd5b8e1d359c984);
  //                0.8852775142880511, -0.1502080091211320, -0.7804423569145378,  0.4585094341291300,  0.8417440789882031, -0.1215927835809432,  0.9442717441528423, -0.3993868853091622,  0.5719771249018739,  0.0497853851400327,  0.6627817945481365,  0.2150621318612425, -0.8506676370622683, -0.4531982633526939,  0.5943189287417812, -0.5034380636605356
  VLOAD_64(v2,      0x3fec543182780b14,  0xbfc33a041b62e250,  0xbfe8f9623feb8e20,  0xbfd5b8e1d359c984,  0x3feaef91475b6422,  0xbfbf20b464e8e5d0,  0x3fee377960758bfa,  0xbfd98f8e02b6aa78,  0x3fe24da2f8b06fde,  0x3fa97d7851fd8b80,  0x3fe535822a7efd70,  0x3fcb8727eb79dda0,  0xbfeb38ab561e5658,  0xbfdd013349ed0b50,  0x3fe304a9214adedc,  0xbfe01c2a245f7960);
  asm volatile("vmfgt.vf v1, v2, %[A]" :: [A] "f" (dscalar_64));
  VSET(1, e16, m1);
  VCMP_U16(3, v1,  0x4f73);
};

// Simple random test with similar values (vector-scalar) (masked)
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  double dscalar_16;
  //                             -0.2649
  BOX_HALF_IN_DOUBLE(dscalar_16,  0xb43d);
  //               -0.2649,  0.5806, -0.2649, -0.4783, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649,
  VLOAD_16(v2,      0xb43d,  0x7653,  0xad3d,  0x033d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfgt.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_16));
  VSET(1, e16, m1);
  VCMP_U16(4, v1,  0x000a);

  VSET(16, e32, m1);
  double dscalar_32;
  //                               0.80517912
  BOX_FLOAT_IN_DOUBLE(dscalar_32,  0x3f4e2038);
  //                0.80517912,  0.80517912, -0.29387674,  0.98594254,  0.88163614, -0.44641387,  0.88191622,  0.15161350, -0.79952192, -0.03668820, -0.38464722, -0.54745716,  0.09956384,  0.21655059, -0.37557366, -0.79342169
  VLOAD_32(v2,      0x3f4e2038,  0x3f4e2038,  0xbe967703,  0x3f7c66bb,  0x3f61b2e8,  0xbee4905c,  0x3f61c543,  0x3e1b4092,  0xbf4cad78,  0xbd16465d,  0xbec4f07b,  0xbf0c2627,  0x3dcbe820,  0x3e5dbf70,  0xbec04b31,  0xbf4b1daf);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfgt.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_32));
  VSET(1, e16, m1);
  VCMP_U16(5, v1,  0x0008);

  VSET(16, e64, m1);
  double dscalar_64;
  //                               -0.3394093097660049
  BOX_DOUBLE_IN_DOUBLE(dscalar_64,  0xbfd5b8e1d359c984);
  //                 0.8852775142880511, -0.1502080091211320, -0.7804423569145378, -0.3394093097660049,  0.8417440789882031, -0.1215927835809432,  0.9442717441528423, -0.3993868853091622,  0.5719771249018739,  0.0497853851400327,  0.6627817945481365,  0.2150621318612425, -0.8506676370622683, -0.4531982633526939,  0.5943189287417812, -0.5034380636605356
  VLOAD_64(v2,       0x3fec543182780b14,  0xbfc33a041b62e250,  0xbfe8f9623feb8e20,  0xbfd5b8e1d359c984,  0x3feaef91475b6422,  0xbfbf20b464e8e5d0,  0x3fee377960758bfa,  0xbfd98f8e02b6aa78,  0x3fe24da2f8b06fde,  0x3fa97d7851fd8b80,  0x3fe535822a7efd70,  0x3fcb8727eb79dda0,  0xbfeb38ab561e5658,  0xbfdd013349ed0b50,  0x3fe304a9214adedc,  0xbfe01c2a245f7960);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfgt.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_64));
  VSET(1, e16, m1);
  VCMP_U16(6, v1,  0x0a22);
};

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();

  EXIT_CHECK();
}
