// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>
//         Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "vector_macros.h"
#include "float_macros.h"

// This instruction writes a mask to a register, with a layout of elements as described in section "Mask Register Layout"
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  //               0.2434,  0.7285,  0.7241, -0.2678,  0.0027, -0.7114,  0.2622,  0.8701, -0.5786, -0.4229,  0.5981,  0.6968,  0.7217, -0.2842,  0.1328,  0.1659
  VLOAD_16(v2,     0x33ca,  0x39d4,  0x39cb,  0xb449,  0x1975,  0xb9b1,  0x3432,  0x3af6,  0xb8a1,  0xb6c4,  0x38c9,  0x3993,  0x39c6,  0xb48c,  0x3040,  0x314f);
  //               0.7319,  0.0590,  0.7593, -0.6606, -0.4758,  0.8530,  0.0453,  0.0987,  0.1777,  0.3047,  0.2330, -0.3467, -0.4153,  0.7080,  0.3142, -0.9492
  VLOAD_16(v3,     0x39db,  0x2b8c,  0x3a13,  0xb949,  0xb79d,  0x3ad3,  0x29cc,  0x2e51,  0x31b0,  0x34e0,  0x3375,  0xb58c,  0xb6a5,  0x39aa,  0x3041,  0xbb98);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(1, v1,  0x0);

  VSET(16, e32, m1);
  //                       +0,        sNaN, -0.34645590, -0.06222415,  0.96037650, -0.81018746, -0.69337404,  0.70466602, -0.30920035, -0.31596854, -0.92116749,  0.51336122,  0.22002794,  0.48599416,  0.69166088,  0.85755372
  VLOAD_32(v2,     0x00000000,  0xffffffff,  0xbeb162ab,  0xbd7edebf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  0x3e614f01,  0x3ef8d43a,  0x3f3110b0,  0x3f5b88a4);
  //                       -0,        sNaN,  0.39402914, -0.81853813,  0.24656086, -0.71423489, -0.44735566, -0.25510681, -0.94378990, -0.30138883,  0.19188073, -0.29310879, -0.22981364, -0.58626360, -0.80913633, -0.00670803
  VLOAD_32(v3,     0x80000000,  0xffffffff,  0x3ec9be30,  0xbf518bb7,  0x3e7c7a73,  0xbf36d819,  0xbee50bcd,  0xbe829d5c,  0xbf719c37,  0xbe9a4fa3,  0x3e447c62,  0xbe96125b,  0xbe6b5444,  0xbf16155f,  0xbf4f238f,  0xbbdbcefe);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(2, v1,  0x1);

  VSET(16, e64, m1);
  //               0.8643613633211786,  0.4842301798024149,  0.9229840140784857, -0.9479687162489723, -0.1308855743137316, -0.3798019472030296,  0.1570811980936915, -0.7665403705017886, -0.3736408604742532,  0.4947226024634424, -0.3032110323317654,  0.8998114670494881,  0.6283940115157876,  0.1053912590957002, -0.2936564640984622,  0.4329957213663693
  VLOAD_64(v2,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0x3fed8915c5665532,  0xbfee55c27d3d743e,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0x3fc41b3c98507fe0,  0xbfe8877fabcbce12,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfd367cf3ee9af68,  0x3feccb416af162fc,  0x3fe41bcdc20ecd40,  0x3fbafaebeb19acf0,  0xbfd2cb447b63f610,  0x3fdbb633afa4e520);
  //              -0.3562510538138417, -0.0135629748736219,  0.6176167733891369,  0.9703747829163081, -0.0909539316920625, -0.1057326828885887, -0.8792039527057112, -0.1745056251010144,  0.3110320594479206,  0.3238986651420683, -0.9079294226891812, -0.9490909352855985,  0.6962970677624296,  0.7585780695949504, -0.5927175227484118, -0.7793965434104730
  VLOAD_64(v3,     0xbfd6ccd13852f170,  0xbf8bc6e7ac263f80,  0x3fed8915c5665532,  0x3fef0d4f6aafa2f6,  0xbfb748c1c20f5de0,  0xbfbb114c0f1ff4b0,  0xbfec227053ec5198,  0xbfc6563348637140,  0x3fd3e7f302d586b4,  0x3fd4bac177803510,  0xbfed0dc20130d694,  0xbfee5ef3f3ff6a12,  0x3fe64810c9cae3fe,  0x3fe84645840bf0a2,  0xbfe2f78abcff0ede,  0xbfe8f0d105120796);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(3, v1,  0x4);
};

// Simple random test with similar values + 1 subnormal (masked)
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  //               0.2434,  0.7285,  0.7241, -0.2678,  0.0027, -0.7114,  0.2622,  0.8701, -0.5786, -0.4229,  0.5981,  0.6968,  0.7217, -0.2842,  0.1328,  0.1659
  VLOAD_16(v2,     0x33ca,  0x39d4,  0x39cb,  0xb449,  0x1975,  0xb9b1,  0x3432,  0x3af6,  0xb8a1,  0xb6c4,  0x38c9,  0x3993,  0x39c6,  0xb48c,  0x3040,  0x314f);
  //               0.7319,  0.7285,  0.7593, -0.6606, -0.4758,  0.8530,  0.0453,  0.0987,  0.1777,  0.3047,  0.2330, -0.3467, -0.4153,  0.7080,  0.3142, -0.9492
  VLOAD_16(v3,     0x39db,  0x39d4,  0x3a13,  0xb949,  0xb79d,  0x3ad3,  0x29cc,  0x2e51,  0x31b0,  0x34e0,  0x3375,  0xb58c,  0xb6a5,  0x39aa,  0x3507,  0xbb98);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v1, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(4, v1,  0x0002);

  VSET(16, e32, m1);
  //               0x00000000,  0.09933749, -0.34645590, -0.06222415,  0.96037650, -0.81018746, -0.69337404,  0.70466602, -0.30920035, -0.31596854, -0.92116749,  0.51336122,  0.22002794,  0.48599416,  0.69166088,  0.85755372
  VLOAD_32(v2,     0x00000000,  0x3dcb7174,  0xbeb162ab,  0xbd7edebf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  0x3e614f01,  0x3ef8d43a,  0x3f3110b0,  0x3f5d88a4);
  //               0x00000000, -0.64782482,  0.39402914, -0.81853813,  0.24656086, -0.71423489, -0.44735566, -0.25510681, -0.94378990, -0.30138883,  0.19188073, -0.29310879, -0.22981364, -0.58626360, -0.80913633,  0.85755372
  VLOAD_32(v3,     0x00000000,  0xbf25d7d9,  0x3ec9be30,  0xbf518bb7,  0x3e7c7a73,  0xbf36d819,  0xbee50bcd,  0xbe829d5c,  0xbf719c37,  0xbe9a4fa3,  0x3e447c62,  0xbe96125b,  0xbe6b5444,  0xbf16155f,  0xbf4f238f,  0x3f5d88a4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v1, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(5, v1,  0x8000);

  VSET(16, e64, m1);
  //               0.8643613633211786,  0.4842301798024149,  0.9229840140784857, -0.9479687162489723, -0.1308855743137316, -0.3798019472030296,  0.1570811980936915, -0.7665403705017886, -0.3736408604742532,  0.4947226024634424, -0.3032110323317654,  0.8998114670494881,  0.6283940115157876,  0.1053912590957002, -0.2936564640984622, -0.7793965434104730
  VLOAD_64(v2,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0x3fed8915c5665532,  0xbfee55c27d3d743e,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0x3fc41b3c98507fe0,  0xbfe8877fabcbce12,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfd367cf3ee9af68,  0x3feccb416af162fc,  0x3fe41bcdc20ecd40,  0x3fbafaebeb19acf0,  0xbfd2cb447b63f610,  0xbfe8f0d105120796);
  //               0.8643613633211786,  0.4842301798024149,  0.6176167733891369,  0.9703747829163081, -0.0909539316920625, -0.1057326828885887, -0.8792039527057112, -0.1745056251010144,  0.3110320594479206,  0.3238986651420683, -0.9079294226891812, -0.9490909352855985,  0.6962970677624296,  0.7585780695949504, -0.5927175227484118, -0.7793965434104730
  VLOAD_64(v3,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0x3fed8915c5665532,  0xbfee55c27d3d743e,  0xbfb748c1c20f5de0,  0xbfbb114c0f1ff4b0,  0xbfec227053ec5198,  0xbfc6563348637140,  0x3fd3e7f302d586b4,  0x3fd4bac177803510,  0xbfed0dc20130d694,  0xbfee5ef3f3ff6a12,  0x3fe64810c9cae3fe,  0x3fe84645840bf0a2,  0xbfe2f78abcff0ede,  0xbfe8f0d105120796);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v1, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(6, v1,  0x800a);
};

// Simple random test with similar values (vector-scalar)
void TEST_CASE3(void) {
  VSET(16, e16, m1);
  double dscalar_16;
  //                             -0.2649
  BOX_HALF_IN_DOUBLE(dscalar_16,  0xb43d);
  //              -0.0651,  0.5806,  0.2563, -0.4783,  0.7393, -0.2649, -0.4590,  0.5469, -0.9082,  0.6235, -0.8276, -0.7939, -0.0236, -0.1166,  0.4026,  0.0022
  VLOAD_16(v2,     0xac2a,  0x38a5,  0x341a,  0xb7a7,  0x39ea,  0xb43d,  0xb758,  0x3860,  0xbb44,  0x38fd,  0xba9f,  0xba5a,  0xa60b,  0xaf76,  0x3671,  0x1896);
  asm volatile("vmfeq.vf v1, v2, %[A]" :: [A] "f" (dscalar_16));
  VSET(1, e16, m1);
  VCMP_U16(7, v1,  0x0020);

  VSET(16, e32, m1);
  double dscalar_32;
  //                               0.80517912
  BOX_FLOAT_IN_DOUBLE(dscalar_32,  0x3f4e2038);
  //              -0.15601152, -0.92020410, -0.29387674,  0.98594254,  0.88163614, -0.44641387,  0.88191622,  0.15161350, -0.79952192, -0.03668820, -0.38464722, -0.54745716,  0.09956384,  0.21655059, -0.37557366, -0.79342169
  VLOAD_32(v2,     0xbe1fc17c,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0x3f4e2038,  0xbf4b1daf);
  asm volatile("vmfeq.vf v1, v2, %[A]" :: [A] "f" (dscalar_32));
  VSET(1, e16, m1);
  VCMP_U16(8, v1,  0x7ffe);

  VSET(16, e64, m1);
  double dscalar_64;
  //                               -0.3394093097660049
  BOX_DOUBLE_IN_DOUBLE(dscalar_64,  0xbfd5b8e1d359c984);
  //                0.8852775142880511, -0.1502080091211320, -0.7804423569145378,  0.4585094341291300,  0.8417440789882031, -0.1215927835809432,  0.9442717441528423, -0.3993868853091622,  0.5719771249018739,  0.0497853851400327,  0.6627817945481365,  0.2150621318612425, -0.8506676370622683, -0.4531982633526939,  0.5943189287417812, -0.5034380636605356
  VLOAD_64(v2,      0x3fec543182780b14,  0xbfc33a041b62e250,  0xbfe8f9623feb8e20,  0xbfd5b8e1d359c984,  0x3feaef91475b6422,  0xbfbf20b464e8e5d0,  0x3fee377960758bfa,  0xbfd98f8e02b6aa78,  0x3fe24da2f8b06fde,  0x3fa97d7851fd8b80,  0x3fe535822a7efd70,  0x3fcb8727eb79dda0,  0xbfeb38ab561e5658,  0xbfdd013349ed0b50,  0x3fe304a9214adedc,  0xbfe01c2a245f7960);
  asm volatile("vmfeq.vf v1, v2, %[A]" :: [A] "f" (dscalar_64));
  VSET(1, e16, m1);
  VCMP_U16(9, v1,  0x0008);
};

// Simple random test with similar values (vector-scalar) (masked)
void TEST_CASE4(void) {
  VSET(16, e16, m1);
  double dscalar_16;
  //                             -0.2649
  BOX_HALF_IN_DOUBLE(dscalar_16,  0xb43d);
  //               -0.2649,  0.5806, -0.2649, -0.4783, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649, -0.2649,
  VLOAD_16(v2,      0xb43d,  0x7653,  0xad3d,  0x033d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d,  0xb43d);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_16));
  VSET(1, e16, m1);
  VCMP_U16(10, v1,  0xaaa0);

  VSET(16, e32, m1);
  double dscalar_32;
  //                               0.80517912
  BOX_FLOAT_IN_DOUBLE(dscalar_32,  0x3f4e2038);
  //                0.80517912,  0.80517912, -0.29387674,  0.98594254,  0.88163614, -0.44641387,  0.88191622,  0.15161350, -0.79952192, -0.03668820, -0.38464722, -0.54745716,  0.09956384,  0.21655059, -0.37557366, -0.79342169
  VLOAD_32(v2,      0x3f4e2038,  0x3f4e2038,  0xbe967703,  0x3f7c66bb,  0x3f61b2e8,  0xbee4905c,  0x3f61c543,  0x3e1b4092,  0xbf4cad78,  0xbd16465d,  0xbec4f07b,  0xbf0c2627,  0x3dcbe820,  0x3e5dbf70,  0xbec04b31,  0xbf4b1daf);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_32));
  VSET(1, e16, m1);
  VCMP_U16(11, v1,  0x0002);

  VSET(16, e64, m1);
  double dscalar_64;
  //                               -0.3394093097660049
  BOX_DOUBLE_IN_DOUBLE(dscalar_64,  0xbfd5b8e1d359c984);
  //                 0.8852775142880511, -0.1502080091211320, -0.7804423569145378, -0.3394093097660049,  0.8417440789882031, -0.1215927835809432,  0.9442717441528423, -0.3993868853091622,  0.5719771249018739,  0.0497853851400327,  0.6627817945481365,  0.2150621318612425, -0.8506676370622683, -0.4531982633526939,  0.5943189287417812, -0.5034380636605356
  VLOAD_64(v2,       0x3fec543182780b14,  0xbfc33a041b62e250,  0xbfe8f9623feb8e20,  0xbfd5b8e1d359c984,  0x3feaef91475b6422,  0xbfbf20b464e8e5d0,  0x3fee377960758bfa,  0xbfd98f8e02b6aa78,  0x3fe24da2f8b06fde,  0x3fa97d7851fd8b80,  0x3fe535822a7efd70,  0x3fcb8727eb79dda0,  0xbfeb38ab561e5658,  0xbfdd013349ed0b50,  0x3fe304a9214adedc,  0xbfe01c2a245f7960);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vf v1, v2, %[A], v0.t" :: [A] "f" (dscalar_64));
  VSET(1, e16, m1);
  VCMP_U16(12, v1,  0x0008);
};

// Check if only the correct destination bits are written
void TEST_CASE5(void) {
  // Fill 64-bits with 1
  VSET(1, e64, m1);
  VLOAD_64(v1, 0xffffffffffffffff);
  // Perform vmfeq.vv on 16 different elements, and then check that the last (64 - 16 = 48) bits were not overwritten with zeroes
  VSET(16, e16, m1);
  //               0.2434,  0.7285,  0.7241, -0.2678,  0.0027, -0.7114,  0.2622,  0.8701, -0.5786, -0.4229,  0.5981,  0.6968,  0.7217, -0.2842,  0.1328,  0.1659
  VLOAD_16(v2,     0x33ca,  0x39d4,  0x39cb,  0xb449,  0x1975,  0xb9b1,  0x3432,  0x3af6,  0xb8a1,  0xb6c4,  0x38c9,  0x3993,  0x39c6,  0xb48c,  0x3040,  0x314f);
  //               0.7319,  0.0590,  0.7593, -0.6606, -0.4758,  0.8530,  0.0453,  0.0987,  0.1777,  0.3047,  0.2330, -0.3467, -0.4153,  0.7080,  0.3142, -0.9492
  VLOAD_16(v3,     0x33ca,  0x2b8c,  0x3a13,  0xb949,  0xb79d,  0x3ad3,  0x29cc,  0x2e51,  0x31b0,  0x34e0,  0x3375,  0xb58c,  0xb6a5,  0x39aa,  0x3041,  0xbb98);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e64, m1);
  VCMP_U64(13, v1,  0xffffffffffff0001);

  // Fill 64-bits with 1
  VSET(1, e64, m1);
  VLOAD_64(v1, 0xffffffffffffffff);
  // Perform vmfeq.vv on 16 different elements, and then check that the last (64 - 16 = 48) bits were not overwritten with zeroes
  VSET(16, e32, m1);
  //              -0.72077256,        sNaN, -0.34645590, -0.06222415,  0.96037650, -0.81018746, -0.69337404,  0.70466602, -0.30920035, -0.31596854, -0.92116749,  0.51336122,  0.22002794,  0.48599416,  0.69166088,  0.85755372
  VLOAD_32(v2,     0x70000000,  0xffffffff,  0xbeb162ab,  0xbd7edebf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  0x3e614f01,  0x3ef8d43a,  0x3f3110b0,  0x3f5b88a4);
  //               0.79994357,        sNaN, -0.34645590, -0.81853813,  0.24656086, -0.71423489, -0.44735566, -0.25510681, -0.94378990, -0.30138883,  0.19188073, -0.29310879, -0.22981364, -0.58626360, -0.80913633, -0.00670803
  VLOAD_32(v3,     0x80000000,  0xffffffff,  0xbeb162ab,  0xbf518bb7,  0x3e7c7a73,  0xbf36d819,  0xbee50bcd,  0xbe829d5c,  0xbf719c37,  0xbe9a4fa3,  0x3e447c62,  0xbe96125b,  0xbe6b5444,  0xbf16155f,  0xbf4f238f,  0xbbdbcefe);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e64, m1);
  VCMP_U64(14, v1,  0xffffffffffff0004);

  // Fill 64-bits with 1
  VSET(1, e64, m1);
  VLOAD_64(v1, 0xffffffffffffffff);
  // Perform vmfeq.vv on 16 different elements, and then check that the last (64 - 16 = 48) bits were not overwritten with zeroes
  VSET(16, e64, m1);
  //               0.8643613633211786,  0.4842301798024149,  0.9229840140784857, -0.9479687162489723, -0.1308855743137316, -0.3798019472030296,  0.1570811980936915, -0.7665403705017886, -0.3736408604742532,  0.4947226024634424, -0.3032110323317654,  0.8998114670494881,  0.6283940115157876,  0.1053912590957002, -0.2936564640984622,  0.4329957213663693
  VLOAD_64(v2,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0xbf3180f63f75db3c,  0xbfee55c27d3d743e,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0x3fc41b3c98507fe0,  0xbfe8877fabcbce12,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfd367cf3ee9af68,  0x3feccb416af162fc,  0x3fe41bcdc20ecd40,  0x3fbafaebeb19acf0,  0xbfd2cb447b63f610,  0x3fdbb633afa4e520);
  //               0.8643613633211786, -0.0135629748736219,  0.6176167733891369,  0.9703747829163081, -0.0909539316920625, -0.1057326828885887, -0.8792039527057112, -0.1745056251010144,  0.3110320594479206,  0.3238986651420683, -0.9079294226891812, -0.9490909352855985,  0.6962970677624296,  0.7585780695949504, -0.5927175227484118, -0.7793965434104730
  VLOAD_64(v3,     0x3feba8d9296c7e74,  0xbf8bc6e7ac263f80,  0x3fed8915c5665532,  0x3fef0d4f6aafa2f6,  0xbfb748c1c20f5de0,  0xbfbb114c0f1ff4b0,  0xbfec227053ec5198,  0xbfc6563348637140,  0x3fd3e7f302d586b4,  0x3fd4bac177803510,  0xbfed0dc20130d694,  0xbfee5ef3f3ff6a12,  0x3fe64810c9cae3fe,  0x3fe84645840bf0a2,  0xbfe2f78abcff0ede,  0xbfe8f0d105120796);
  asm volatile("vmfeq.vv v1, v2, v3");
  VSET(1, e64, m1);
  VCMP_U64(15, v1,  0xffffffffffff0001);
};

// Write to v0 during a masked operation, WAR dependency should be respected
void TEST_CASE6(void) {
  VSET(16, e16, m1);
  //               0.2434,  0.7285,  0.7241,  0.7241,  0.0027, -0.7114,  0.8701,  0.8701, -0.5786, -0.4229,  0.6968,  0.6968,  0.7217, -0.2842,  0.1659,  0.1659
  VLOAD_16(v2,     0x33ca,  0x39d4,  0x39cb,  0xb449,  0x1975,  0xb9b1,  0x3af6,  0x3af6,  0xb8a1,  0xb6c4,  0x3993,  0x3993,  0x39c6,  0xb48c,  0x314f,  0x314f);
  //               0.2434,  0.7285, -0.2678, -0.2678,  0.0027, -0.7114,  0.2622,  0.2622, -0.5786, -0.4229,  0.5981,  0.5981,  0.7217, -0.2842,  0.1328,  0.1328
  VLOAD_16(v3,     0x33ca,  0x39d4,  0xb449,  0x39cb,  0x1975,  0xb9b1,  0x3432,  0x3432,  0xb8a1,  0xb6c4,  0x38c9,  0x38c9,  0x39c6,  0xb48c,  0x3040,  0x3040);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(16, v0,  0x2222);

  VSET(16, e32, m1);
  //               0x00000000,  0.09933749, -0.34645590, -0.06222415,  0.96037650, -0.81018746, -0.69337404,  0.70466602, -0.30920035, -0.31596854, -0.92116749,  0.51336122,  0.22002794,  0.48599416,  0.69166088,  0.85755372
  VLOAD_32(v2,     0x00000000,  0x3dcb7174,  0xbeb162ab,  0xbd7edebf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  0x3e614f01,  0x3ef8d43a,  0x3f3110b0,  0x3f5d88a4);
  //               0x00000000,  0.09933749,  0.39402914, -0.81853813,  0.96037650, -0.81018746, -0.44735566, -0.25510681, -0.30920035, -0.31596854,  0.19188073, -0.29310879,  0.22002794,  0.48599416, -0.80913633, -0.30138883
  VLOAD_32(v3,     0x00000000,  0x3dcb7174,  0x3ec9be30,  0xbf518bb7,  0x3f75db3c,  0xbf4f6872,  0xbee50bcd,  0xbe829d5c,  0xbe9e4f82,  0xbea1c6a1,  0x3e447c62,  0xbe96125b,  0x3e614f01,  0x3ef8d43a,  0xbf4f238f,  0xbe9a4fa3);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(17, v0,  0x2222);

  VSET(16, e64, m1);
  //               0.8643613633211786,  0.4842301798024149,  0.9229840140784857, -0.8792039527057112, -0.1308855743137316, -0.3798019472030296,  0.1570811980936915, -0.7665403705017886, -0.3736408604742532,  0.4947226024634424, -0.3032110323317654,  0.8998114670494881,  0.6283940115157876,  0.1053912590957002, -0.2936564640984622, -0.7793965434104730
  VLOAD_64(v2,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0x3fed8915c5665532,  0xbfec227053ec5198,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0x3fc41b3c98507fe0,  0xbfe8877fabcbce12,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfd367cf3ee9af68,  0x3feccb416af162fc,  0x3fe41bcdc20ecd40,  0x3fbafaebeb19acf0,  0xbfd2cb447b63f610,  0xbfe8f0d105120796);
  //               0.8643613633211786,  0.4842301798024149, -0.8792039527057112,  0.9703747829163081, -0.1308855743137316, -0.3798019472030296, -0.8792039527057112, -0.1745056251010144, -0.3736408604742532,  0.4947226024634424, -0.9079294226891812, -0.9490909352855985,  0.6283940115157876,  0.1053912590957002, -0.5927175227484118, -0.3032110323317654
  VLOAD_64(v3,     0x3feba8d9296c7e74,  0x3fdefda0947f3460,  0xbfec227053ec5198,  0x9fee55c27d3d743e,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0xbfec227053ec5198,  0xbfc6563348637140,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfed0dc20130d694,  0xbfee5ef3f3ff6a12,  0x3fe41bcdc20ecd40,  0x3fbafaebeb19acf0,  0xbfe2f78abcff0ede,  0xbfd367cf3ee9af68);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3, v0.t");
  VSET(1, e16, m1);
  VCMP_U16(18, v0,  0x2222);
};

// Test sNaN/qNaN behaviour
void TEST_CASE7(void) {
  CLEAR_FFLAGS;
  // First, give only qNaN (no exception is generated)
  VSET(16, e16, m1);
  CHECK_FFLAGS(0);
  VLOAD_16(v2,      qNaNh, qNaNh, 0x39cb, qNaNh,  0x1975,  0xb9b1,  0x3af6,  0x3af6,  0xb8a1,  0xb6c4,  0x3993,  0x3993,   qNaNh, 0xb48c,  qNaNh,  qNaNh);
  VLOAD_16(v3,     0x33ca, qNaNh,  qNaNh, 0x39cb, 0x1975,  0xb9b1,  0x3432,  0x3432,  0xb8a1,  0xb6c4,  0x38c9,  0x38c9,  0x39c6,  qNaNh,  qNaNh,  0x3040);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(19, v0,  0x0330);

  VSET(16, e32, m1);
  VLOAD_32(v2,     0x3f75db3c,       qNaNf,       qNaNf,       qNaNf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  qNaNf,       qNaNf,  0x3f3110b0,  qNaNf);
  VLOAD_32(v3,     0x3f75db3c,  0x3dcb7174,       qNaNf,  0xbf518bb7,  0x3f75db3c,  0xbf4f6872,  0xbee50bcd,  0xbe829d5c,  0xbe9e4f82,  0xbea1c6a1,  0x3e447c62,  0xbe96125b,  qNaNf,  0x3ef8d43a,       qNaNf,  qNaNf);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(20, v0,  0x0331);

  VSET(16, e64, m1);
  VLOAD_64(v2,     qNaNd,               qNaNd,  0x3fed8915c5665532,  0xbfec227053ec5198,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0x3fc41b3c98507fe0,  0xbfe8877fabcbce12,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfd367cf3ee9af68,  0x3feccb416af162fc,  qNaNd,               qNaNd,  0xbfd2cb447b63f610,  qNaNd);
  VLOAD_64(v3,     qNaNd,  0x3fdefda0947f3460,               qNaNd,  0x9fee55c27d3d743e,  0xbfc0c0dbc6990b38,  0xbfd84eacd38c6ca4,  0xbfec227053ec5198,  0xbfc6563348637140,  0xbfd7e9bb5b0beaf8,  0x3fdfa988fd8b0a24,  0xbfed0dc20130d694,  0xbfee5ef3f3ff6a12,  qNaNd,  0x3fbafaebeb19acf0,               qNaNd,  qNaNd);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(21, v0,  0x0330);
  CHECK_FFLAGS(0);

  // Give sNaN (Invalid operation)
  VSET(16, e32, m1);
  VLOAD_32(v2,     0x3f75db3c,       sNaNf,       sNaNf,       qNaNf,  0x3f75db3c,  0xbf4f6872,  0xbf3180f6,  0x3f3464fe,  0xbe9e4f82,  0xbea1c6a1,  0xbf6bd1a2,  0x3f036ba4,  qNaNf,       qNaNf,  0x3f3110b0,  qNaNf);
  VLOAD_32(v3,     0x3f75db3c,  0x3dcb7174,       qNaNf,  0xbf518bb7,  0x3f75db3c,  0xbf4f6872,  0xbee50bcd,  0xbe829d5c,  0xbe9e4f82,  0xbea1c6a1,  0x3e447c62,  0xbe96125b,  qNaNf,  0x3ef8d43a,       qNaNf,  qNaNf);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vmfeq.vv v0, v2, v3");
  VSET(1, e16, m1);
  VCMP_U16(22, v0,  0x0331);
  CHECK_FFLAGS(NV);
};

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

//  TEST_CASE5();
  TEST_CASE6();
  TEST_CASE7();

  EXIT_CHECK();
}
