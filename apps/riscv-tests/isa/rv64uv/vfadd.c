// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

// Notes: hard to check if FS is Dirtied by the first vector FP instruction
// since it is not accessible in U mode and it is dirtied before the first vfp
// operation

// Simple random test with similar values + 1 subnormal
void TEST_CASE1(void) {
  /*
    VSET(16, e8, m1);
    // Enable this test only with 8-bit floating-point support on
    VLOAD_8(v2, 0b11001100, 0b01011011, 0b11001100, 0b01011011, 0b11001100,
    0b01011011, 0b11001100, 0b01011011, 0b11001100, 0b01011011, 0b11001100,
    0b01011011, 0b11001100, 0b01011011, 0b11001100, 0b01011011); VLOAD_8(v3,
    0b01011011, 0b11001100, 0b01011011, 0b11001100, 0b01011011, 0b11001100,
    0b01011011, 0b11001100, 0b01011011, 0b11001100, 0b01011011, 0b11001100,
    0b01011011, 0b11001100, 0b01011011, 0b11001100); asm volatile("vfadd.vv v1,
    v2, v3"); VCMP_U8(0, v1, 0b01011010, 0b01011010, 0b01011010, 0b01011010,
    0b01011010, 0b01011010, 0b01011010, 0b01011010, 0b01011010, 0b01011010,
    0b01011010, 0b01011010, 0b01011010, 0b01011010, 0b01011010, 0b01011010);
  */

  VSET(16, e16, m1);
  //             -0.8896, -0.3406,  0.7324, -0.6846, -0.2969, -0.7739,  0.5737,
  //             0.4331,  0.8940, -0.4900,  0.4219,  0.4639,  0.6694,  0.4382,
  //             0.1356,  0.5337
  VLOAD_16(v2, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  //             -0.8164,  0.6533, -0.4685,  0.6284,  0.1666,  0.9438,  0.0445,
  //             -0.1342, -0.8071, -0.3167, -0.8350,  0.2178, -0.0896, -0.3057,
  //             -0.3064,  0.2073
  VLOAD_16(v3, 0xba88, 0x393a, 0xb77f, 0x3907, 0x3155, 0x3b8d, 0x29b3, 0xb04b,
           0xba75, 0xb511, 0xbaae, 0x32f8, 0xadbc, 0xb4e4, 0xb4e7, 0x8010);
  asm volatile("vfadd.vv v1, v2, v3");
  //             -1.7061,  0.3127,  0.2639, -0.0562, -0.1302,  0.1699,  0.6182,
  //             0.2988,  0.0869, -0.8066, -0.4131,  0.6816,  0.5801,  0.1326,
  //             -0.1708,  0.7412
  VCMP_U16(1, v1, 0xbed3, 0x3501, 0x3439, 0xab30, 0xb02b, 0x3170, 0x38f2,
           0x34c8, 0x2d90, 0xba74, 0xb69c, 0x3974, 0x38a4, 0x303e, 0xb177,
           0x800f);

  VSET(16, e32, m1);
  //             -0.28968573,  0.40292332,  0.33936000,  0.53889370, 0.39942014,
  //             -0.27004066,  0.78120714, -0.15632398, -0.49984047,
  //             -0.69259918, -0.03384063, -0.62385744,  0.00338853, 0.33711585,
  //             -0.34673852,  0.11450682
  VLOAD_32(v2, 0xbe9451b0, 0x3ece4bf7, 0x3eadc098, 0x3f09f4f0, 0x3ecc80cc,
           0xbe8a42c5, 0x3f47fd31, 0xbe201365, 0xbeffeb17, 0xbf314e2e,
           0xbd0a9c78, 0xbf1fb51f, 0x3b5e1209, 0x3eac9a73, 0xbeb187b6,
           0x3dea828d);
  //             -0.62142891,  0.63306540,  0.26511025,  0.85738784,
  //             -0.78492641, -0.44331804, -0.84668529,  0.13981950, 0.84909225,
  //             0.23569171,  0.34283128,  0.56619811,  0.22596644,  0.55843508,
  //             0.53194439,  0.02510819
  VLOAD_32(v3, 0xbf1f15f7, 0x3f221093, 0x3e87bc88, 0x3f5b7dc5, 0xbf48f0f0,
           0xbee2fa95, 0xbf58c05e, 0x3e0f2cd8, 0x3f595e1c, 0x3e71592b,
           0x3eaf8795, 0x3f10f25c, 0x3e6763bf, 0x3f0ef59a, 0x3f082d82,
           0x3ccdafb0);
  asm volatile("vfadd.vv v1, v2, v3");
  //             -0.91111463,  1.03598869,  0.60447025,  1.39628148,
  //             -0.38550627, -0.71335870, -0.06547815, -0.01650448, 0.34925178,
  //             -0.45690745,  0.30899066, -0.05765933,  0.22935496, 0.89555097,
  //             0.18520588,  0.13961500
  VCMP_U32(2, v1, 0xbf693ecf, 0x3f849b47, 0x3f1abe90, 0x3fb2b95a, 0xbec56114,
           0xbf369ead, 0xbd861968, 0xbc873468, 0x3eb2d121, 0xbee9efc6,
           0x3e9e3406, 0xbd6c2c30, 0x3e6adc07, 0x3f6542d4, 0x3e3da69c,
           0x3e0ef73c);

  VSET(16, e64, m1);
  //             -0.1192486190170796,  0.7099687505713703, -0.6001652243371716,
  //             -0.9559723926483070,  0.7987976623002717, -0.3314459653039117,
  //             0.7678805321182058, -0.3118871679402779, -0.7580588930783800,
  //             0.5940681950113129,  0.6471754222100761,  0.4175915562917139,
  //             -0.3690504607938143,  0.0740574148132984, -0.1493616685664843,
  //             0.3560295367616439
  VLOAD_64(v2, 0xbfbe8713d6c58260, 0x3fe6b810629c5a40, 0xbfe3348db3573060,
           0xbfee97536a49b50a, 0x3fe98fc01d766dee, 0xbfd536692357c5dc,
           0x3fe8927a3195d944, 0xbfd3f5f598961d8c, 0xbfe84204b946d5d6,
           0x3fe3029b4da55ad8, 0x3fe4b5a93b255a44, 0x3fdab9d1ef56f430,
           0xbfd79e85d2ebb8f0, 0x3fb2f56d3ea64090, 0xbfc31e487ce26ff0,
           0x3fd6c9301c334858);
  //             -0.7765903295164327,  0.4195489676706889, -0.3911414124398265,
  //             0.6922029856623244,  0.5664741772288600, -0.1412820433489181,
  //             -0.1847941224896075, -0.4907136082532593, -0.9146160877742129,
  //             -0.7130864084314152, -0.5516927493459973, -0.4203081001100177,
  //             0.6487326796833275, -0.5631384800254344, -0.0996872955425372,
  //             -0.4382844162164241
  VLOAD_64(v3, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  asm volatile("vfadd.vv v1, v2, v3");
  //             -0.8958389485335123,  1.1295177182420593, -0.9913066367769980,
  //             -0.2637694069859826,  1.3652718395291317, -0.4727280086528298,
  //             0.5830864096285984, -0.8026007761935372, -1.6726749808525929,
  //             -0.1190182134201023,  0.0954826728640787, -0.0027165438183039,
  //             0.2796822188895132, -0.4890810652121360, -0.2490489641090214,
  //             -0.0822548794547802
  VCMP_U64(3, v1, 0xbfecaab6714de71e, 0x3ff212812bc1a28f, 0xbfefb8c8b2287a88,
           0xbfd0e199142c2ac0, 0x3ff5d82748ced68d, 0xbfde412cfa444b84,
           0x3fe2a8a4d48319b8, 0xbfe9aee7d2afdaca, 0xbffac346d73996c9,
           0xbfbe77fa46448730, 0x3fb8718d6d492fc0, 0xbf6641015b72d200,
           0x3fd1e6503fd9cd94, 0xbfdf4d1aab0b7434, 0xbfcfe0d621f9b7e8,
           0xbfb50ea7e131d810);
};

// Simple random test with similar values + 1 subnormal (masked)
// The numbers are the same of TEST_CASE1
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  VLOAD_16(v3, 0xba88, 0x393a, 0xb77f, 0x3907, 0x3155, 0x3b8d, 0x29b3, 0xb04b,
           0xba75, 0xb511, 0xbaae, 0x32f8, 0xadbc, 0xb4e4, 0xb4e7, 0x8010);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U16(4, v1, 0, 0x3501, 0, 0xab30, 0, 0x3170, 0, 0x34c8, 0, 0xba74, 0,
           0x3974, 0, 0x303e, 0, 0x800f);

  VSET(16, e32, m1);
  VLOAD_32(v2, 0xbe9451b0, 0x3ece4bf7, 0x3eadc098, 0x3f09f4f0, 0x3ecc80cc,
           0xbe8a42c5, 0x3f47fd31, 0xbe201365, 0xbeffeb17, 0xbf314e2e,
           0xbd0a9c78, 0xbf1fb51f, 0x3b5e1209, 0x3eac9a73, 0xbeb187b6,
           0x3dea828d);
  VLOAD_32(v3, 0xbf1f15f7, 0x3f221093, 0x3e87bc88, 0x3f5b7dc5, 0xbf48f0f0,
           0xbee2fa95, 0xbf58c05e, 0x3e0f2cd8, 0x3f595e1c, 0x3e71592b,
           0x3eaf8795, 0x3f10f25c, 0x3e6763bf, 0x3f0ef59a, 0x3f082d82,
           0x3ccdafb0);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U32(5, v1, 0, 0x3f849b47, 0, 0x3fb2b95a, 0, 0xbf369ead, 0, 0xbc873468, 0,
           0xbee9efc6, 0, 0xbd6c2c30, 0, 0x3f6542d4, 0, 0x3e0ef73c);

  VSET(16, e64, m1);
  VLOAD_64(v2, 0xbfbe8713d6c58260, 0x3fe6b810629c5a40, 0xbfe3348db3573060,
           0xbfee97536a49b50a, 0x3fe98fc01d766dee, 0xbfd536692357c5dc,
           0x3fe8927a3195d944, 0xbfd3f5f598961d8c, 0xbfe84204b946d5d6,
           0x3fe3029b4da55ad8, 0x3fe4b5a93b255a44, 0x3fdab9d1ef56f430,
           0xbfd79e85d2ebb8f0, 0x3fb2f56d3ea64090, 0xbfc31e487ce26ff0,
           0x3fd6c9301c334858);
  VLOAD_64(v3, 0xbfe8d9d3f67536d2, 0x3fdad9e3e9cdd5bc, 0xbfd90875fda29450,
           0x3fe62686e0339faa, 0x3fe2208e74273f2c, 0xbfc21587add90b50,
           0xbfc7a755744afe30, 0xbfdf67da0cc99808, 0xbfed4488f52c57bc,
           0xbfe6d19a966debbe, 0xbfe1a7778d7c344c, 0xbfdae653f20dd9d4,
           0x3fe4c26b0962c342, 0xbfe2053afd5a822c, 0xbfb9851b4a2e8ff0,
           0xbfdc0cda147fbe5c);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U64(6, v1, 0, 0x3ff212812bc1a28f, 0, 0xbfd0e199142c2ac0, 0,
           0xbfde412cfa444b84, 0, 0xbfe9aee7d2afdaca, 0, 0xbfbe77fa46448730, 0,
           0xbf6641015b72d200, 0, 0xbfdf4d1aab0b7434, 0, 0xbfb50ea7e131d810);
};

// Edge-case tests
void TEST_CASE3(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, pInfh, pInfh, mInfh, qNaNh, pMaxh, pMaxh, pZero, mZeroh, pZero,
           pMaxh, pZero, qNaNh, mInfh, pInfh, qNaNh, qNaNh);
  VLOAD_16(v3, mInfh, pInfh, mInfh, pZero, pMaxh, mMaxh, pZero, mZeroh, mZeroh,
           mZeroh, mMaxh, 0x1, 0xba88, pZero, qNaNh, 0xba88);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U16(7, v1, qNaNh, pInfh, mInfh, qNaNh, pInfh, pZero, pZero, mZeroh,
           pZero, pMaxh, mMaxh, qNaNh, mInfh, pInfh, qNaNh, qNaNh);

  VSET(16, e32, m1);
  VLOAD_32(v2, pInff, pInff, mInff, qNaNf, pMaxf, pMaxf, pZero, mZerof, pZero,
           pMaxf, pZero, qNaNf, mInff, pInff, qNaNf, qNaNf);
  VLOAD_32(v3, mInff, pInff, mInff, pZero, pMaxf, mMaxf, pZero, mZerof, mZerof,
           mZerof, mMaxf, 0x1, 0xbf48f0f0, pZero, qNaNf, 0xbf48f0f0);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U32(8, v1, qNaNf, pInff, mInff, qNaNf, pInff, pZero, pZero, mZerof,
           pZero, pMaxf, mMaxf, qNaNf, mInff, pInff, qNaNf, qNaNf);

  VSET(16, e64, m1);
  VLOAD_64(v2, pInfd, pInfd, mInfd, qNaNd, pMaxd, pMaxd, pZero, mZerod, pZero,
           pMaxd, pZero, qNaNd, mInfd, pInfd, qNaNd, qNaNd);
  VLOAD_64(v3, mInfd, pInfd, mInfd, pZero, pMaxd, mMaxd, pZero, mZerod, mZerod,
           mZerod, mMaxd, 0x1, 0xbfd90875fda29450, pZero, qNaNd,
           0xbfd90875fda29450);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U64(9, v1, qNaNd, pInfd, mInfd, qNaNd, pInfd, pZero, pZero, mZerod,
           pZero, pMaxd, mMaxd, qNaNd, mInfd, pInfd, qNaNd, qNaNd);
};

// Imprecise exceptions
// If the check is done immediately after the vector instruction, it fails as it
// is completed before the "faulty" operations are executed by Ara's FPU
void TEST_CASE4(void) {
  // Overflow + Inexact
  CLEAR_FFLAGS;
  VSET(16, e16, m1);
  CHECK_FFLAGS(0);
  VLOAD_16(v2, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh,
           pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh);
  VLOAD_16(v3, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh,
           pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh, pMaxh);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U16(10, v1, pInfh, pInfh, pInfh, pInfh, pInfh, pInfh, pInfh, pInfh,
           pInfh, pInfh, pInfh, pInfh, pInfh, pInfh, pInfh, pInfh);
  CHECK_FFLAGS(OF | NX);

  // Invalid operation, overflow
  CLEAR_FFLAGS;
  VSET(16, e32, m1);
  CHECK_FFLAGS(0);
  VLOAD_32(v2, pInff, pInff, pInff, pInff, pInff, pInff, pInff, pInff, pInff,
           pInff, pInff, pInff, pInff, pInff, pInff, pInff);
  VLOAD_32(v3, mInff, mInff, mInff, mInff, mInff, mInff, mInff, mInff, mInff,
           mInff, mInff, mInff, mInff, mInff, mInff, mInff);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U32(11, v1, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf,
           qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf, qNaNf);
  CHECK_FFLAGS(NV);

  // Invalid operation, overflow, inexact
  CLEAR_FFLAGS;
  VSET(16, e64, m1);
  CHECK_FFLAGS(0);
  VLOAD_64(v2, pMaxd, pInfd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd,
           pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd);
  VLOAD_64(v3, pMaxd, mInfd, 8000000000000001, pMaxd, pMaxd, pMaxd, pMaxd,
           pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd, pMaxd);
  asm volatile("vfadd.vv v1, v2, v3");
  VCMP_U64(12, v1, pInfd, qNaNd, pMaxd, pInfd, pInfd, pInfd, pInfd, pInfd,
           pInfd, pInfd, pInfd, pInfd, pInfd, pInfd, pInfd, pInfd);
  CHECK_FFLAGS(NV | OF | NX);
};

// Different rounding-mode + Back-to-back rm change and vfp operation
// Index 12 (starting from 0) rounds differently for RNE and RTZ
void TEST_CASE5(void) {
  VSET(16, e16, m1);
  //             -0.8896, -0.3406,  0.7324, -0.6846, -0.2969, -0.7739,  0.5737,
  //             0.4331,  0.8940, -0.4900,  0.4219,  0.4639,  0.6694,  0.4382,
  //             0.1356,  0.5337
  VLOAD_16(v2, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  //             -0.8164,  0.6533, -0.4685,  0.6284,  0.1666,  0.9438,  0.0445,
  //             -0.1342, -0.8071, -0.3167, -0.8350,  0.2178, -0.0896, -0.3057,
  //             -0.3064,  0.2073
  VLOAD_16(v3, 0xba88, 0x393a, 0xb77f, 0x3907, 0x3155, 0x3b8d, 0x29b3, 0xb04b,
           0xba75, 0xb511, 0xbaae, 0x32f8, 0xadbc, 0xb4e4, 0xb4e7, 0x8010);
  CHANGE_RM(RM_RTZ);
  asm volatile("vfadd.vv v1, v2, v3");
  //              -1.7061,  0.3127,  0.2639, -0.0562, -0.1302,  0.1699,  0.6182,
  //              0.2988,  0.0869, -0.8066, -0.4131,  0.6816,  0.5801,  0.1326,
  //              -0.1708,  0.7412
  VCMP_U16(13, v1, 0xbed3, 0x3501, 0x3439, 0xab30, 0xb02b, 0x3170, 0x38f2,
           0x34c8, 0x2d90, 0xba74, 0xb69c, 0x3974, 0x38a3, 0x303e, 0xb177,
           0x800f);

  VSET(16, e16, m1);
  //             -0.8896, -0.3406,  0.7324, -0.6846, -0.2969, -0.7739,  0.5737,
  //             0.4331,  0.8940, -0.4900,  0.4219,  0.4639,  0.6694,  0.4382,
  //             0.1356,  0.5337
  VLOAD_16(v2, 0xbb1e, 0xb573, 0x39dc, 0xb97a, 0xb4c0, 0xba31, 0x3897, 0x36ee,
           0x3b27, 0xb7d7, 0x36c0, 0x376c, 0x395b, 0x3703, 0x3057, 0x0001);
  //             -0.8164,  0.6533, -0.4685,  0.6284,  0.1666,  0.9438,  0.0445,
  //             -0.1342, -0.8071, -0.3167, -0.8350,  0.2178, -0.0896, -0.3057,
  //             -0.3064,  0.2073
  VLOAD_16(v3, 0xba88, 0x393a, 0xb77f, 0x3907, 0x3155, 0x3b8d, 0x29b3, 0xb04b,
           0xba75, 0xb511, 0xbaae, 0x32f8, 0xadbc, 0xb4e4, 0xb4e7, 0x8010);
  CHANGE_RM(RM_RNE);
  asm volatile("vfadd.vv v1, v2, v3");
  //              -1.7061,  0.3127,  0.2639, -0.0562, -0.1302,  0.1699,  0.6182,
  //              0.2988,  0.0869, -0.8066, -0.4131,  0.6816,  0.5801,  0.1326,
  //              -0.1708,  0.7412
  VCMP_U16(14, v1, 0xbed3, 0x3501, 0x3439, 0xab30, 0xb02b, 0x3170, 0x38f2,
           0x34c8, 0x2d90, 0xba74, 0xb69c, 0x3974, 0x38a4, 0x303e, 0xb177,
           0x800f);
};

// Simple random test with similar values (vector-scalar)
void TEST_CASE6(void) {
  VSET(16, e16, m1);
  //              -0.1481, -0.1797, -0.5454,  0.3228,  0.3237, -0.7212, -0.5195,
  //              -0.4500,  0.2681,  0.7300,  0.5059,  0.5830,  0.3198, -0.1713,
  //              -0.6431,  0.4841
  VLOAD_16(v2, 0xb0bd, 0xb1c0, 0xb85d, 0x352a, 0x352e, 0xb9c5, 0xb828, 0xb733,
           0x344a, 0x39d7, 0x380c, 0x38aa, 0x351e, 0xb17b, 0xb925, 0x37bf);
  double dscalar_16;
  //                         -0.9380
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);
  asm volatile("vfadd.vf v1, v2, %[A]" ::[A] "f"(dscalar_16));
  //               -1.0859, -1.1172, -1.4834, -0.6152, -0.6143, -1.6592,
  //               -1.4570, -1.3877, -0.6699, -0.2080, -0.4321, -0.3550,
  //               -0.6182, -1.1094, -1.5811, -0.4539
  VCMP_U16(15, v1, 0xbc58, 0xbc78, 0xbdef, 0xb8ec, 0xb8ea, 0xbea3, 0xbdd4,
           0xbd8d, 0xb95c, 0xb2a8, 0xb6ea, 0xb5ae, 0xb8f2, 0xbc70, 0xbe53,
           0xb743);

  VSET(16, e32, m1);
  //               0.86539453, -0.53925377, -0.47128764,  0.99265540,
  //               0.32128176, -0.47335613, -0.30028856,  0.44394016,
  //               -0.72540921, -0.26464799,  0.77351445, -0.21725702,
  //               -0.25191557, -0.53123665,  0.80404943,  0.81841671
  VLOAD_32(v2, 0x3f5d8a7f, 0xbf0a0c89, 0xbef14c9d, 0x3f7e1eaa, 0x3ea47f0b,
           0xbef25bbc, 0xbe99bf6c, 0x3ee34c20, 0xbf39b46b, 0xbe877ff1,
           0x3f46050b, 0xbe5e78a0, 0xbe80fb14, 0xbf07ff20, 0x3f4dd62f,
           0x3f5183c2);
  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);
  asm volatile("vfadd.vf v1, v2, %[A]" ::[A] "f"(dscalar_32));
  //              -0.09516734, -1.49981570, -1.43184948,  0.03209352,
  //              -0.63928008, -1.43391800, -1.26085043, -0.51662171,
  //              -1.68597102, -1.22520983, -0.18704742, -1.17781889,
  //              -1.21247745, -1.49179852, -0.15651244, -0.14214516
  VCMP_U32(16, v1, 0xbdc2e718, 0xbfbff9f6, 0xbfb746d8, 0x3d037480, 0xbf23a7dc,
           0xbfb78aa0, 0xbfa1638c, 0xbf044152, 0xbfd7cde6, 0xbf9cd3ad,
           0xbe3f895c, 0xbf96c2c5, 0xbf9b3276, 0xbfbef341, 0xbe2044cc,
           0xbe118e80);

  VSET(16, e64, m1);
  //               -0.3488917150781869, -0.4501495513738740, 0.8731197104152684,
  //               0.3256432550932964,  0.6502591178769535, -0.3169358689246526,
  //               -0.5396694979141685, -0.5417807430937591,
  //               -0.7971574213160249, -0.1764794100111047, 0.3564275916066595,
  //               -0.3754449946313438,  0.6580947137446858,
  //               -0.3328857144699515,  0.1761214464164236,  0.1429774118511240
  VLOAD_64(v2, 0xbfd6543dea86cb60, 0xbfdccf40105d6e5c, 0x3febf098bf37400c,
           0x3fd4d756ceb279f4, 0x3fe4ceec35a6a266, 0xbfd448ad61fd7c88,
           0xbfe144f8f7861540, 0xbfe1564491a616b8, 0xbfe9825047ca1cd6,
           0xbfc696e097352100, 0x3fd6cfb5ac55edec, 0xbfd8074a7158dd78,
           0x3fe50f1ca5268668, 0xbfd54dffe23d0eec, 0x3fc68b25c63dcaf0,
           0x3fc24d1575fbd080);
  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);
  asm volatile("vfadd.vf v1, v2, %[A]" ::[A] "f"(dscalar_64));
  //                0.5619790110445508, 0.4607211747488638,  1.7839904365380062,
  //                1.2365139812160342,  1.5611298439996912, 0.5939348571980851,
  //                0.3712012282085693,  0.3690899830289787, 0.1137133048067129,
  //                0.7343913161116331,  1.2672983177293973, 0.5354257314913939,
  //                1.5689654398674235, 0.5779850116527863,  1.0869921725391614,
  //                1.0538481379738618
  VCMP_U64(17, v1, 0x3fe1fbbb682f314e, 0x3fdd7c74aa87bfa0, 0x3ffc8b398e54eb85,
           0x3ff3c8c2e265e9fc, 0x3ff8fa63498c9cb2, 0x3fe30183ac73d8ba,
           0x3fd7c1c2cbd9037c, 0x3fd79f2b9799008c, 0x3fbd1c50ad43d140,
           0x3fe7802237a54ebe, 0x3ff446da99cec6fa, 0x3fe1223524c62842,
           0x3ff91a7b814c8eb3, 0x3fe27eda6c540f88, 0x3ff16451e78104dd,
           0x3ff0dc8fdd78c58f);
};

// Simple random test with similar values (vector-scalar) (masked)
void TEST_CASE7(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 0xb0bd, 0xb1c0, 0xb85d, 0x352a, 0x352e, 0xb9c5, 0xb828, 0xb733,
           0x344a, 0x39d7, 0x380c, 0x38aa, 0x351e, 0xb17b, 0xb925, 0x37bf);
  double dscalar_16;
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_16));
  VCMP_U16(18, v1, 0, 0xbc78, 0, 0xb8ec, 0, 0xbea3, 0, 0xbd8d, 0, 0xb2a8, 0,
           0xb5ae, 0, 0xbc70, 0, 0xb743);

  VSET(16, e32, m1);
  VLOAD_32(v2, 0x3f5d8a7f, 0xbf0a0c89, 0xbef14c9d, 0x3f7e1eaa, 0x3ea47f0b,
           0xbef25bbc, 0xbe99bf6c, 0x3ee34c20, 0xbf39b46b, 0xbe877ff1,
           0x3f46050b, 0xbe5e78a0, 0xbe80fb14, 0xbf07ff20, 0x3f4dd62f,
           0x3f5183c2);
  double dscalar_32;
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_32));
  VCMP_U32(19, v1, 0, 0xbfbff9f6, 0, 0x3d037480, 0, 0xbfb78aa0, 0, 0xbf044152,
           0, 0xbf9cd3ad, 0, 0xbf96c2c5, 0, 0xbfbef341, 0, 0xbe118e80);

  VSET(16, e64, m1);
  VLOAD_64(v2, 0xbfd6543dea86cb60, 0xbfdccf40105d6e5c, 0x3febf098bf37400c,
           0x3fd4d756ceb279f4, 0x3fe4ceec35a6a266, 0xbfd448ad61fd7c88,
           0xbfe144f8f7861540, 0xbfe1564491a616b8, 0xbfe9825047ca1cd6,
           0xbfc696e097352100, 0x3fd6cfb5ac55edec, 0xbfd8074a7158dd78,
           0x3fe50f1ca5268668, 0xbfd54dffe23d0eec, 0x3fc68b25c63dcaf0,
           0x3fc24d1575fbd080);
  double dscalar_64;
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vf v1, v2, %[A], v0.t" ::[A] "f"(dscalar_64));
  VCMP_U64(20, v1, 0, 0x3fdd7c74aa87bfa0, 0, 0x3ff3c8c2e265e9fc, 0,
           0x3fe30183ac73d8ba, 0, 0x3fd79f2b9799008c, 0, 0x3fe7802237a54ebe, 0,
           0x3fe1223524c62842, 0, 0x3fe27eda6c540f88, 0, 0x3ff0dc8fdd78c58f);
};

// Raise exceptions only on active elements!
void TEST_CASE8(void) {
  // Overflow and Inexact. Invalid operation should not be raised.
  CLEAR_FFLAGS;
  VSET(16, e16, m1);
  CHECK_FFLAGS(0);
  VLOAD_16(v2, pInfh, pMaxh, pInfh, pMaxh, pInfh, pMaxh, pInfh, pMaxh, pInfh,
           pMaxh, pInfh, pMaxh, pInfh, pMaxh, pInfh, pMaxh);
  VLOAD_16(v3, mInfh, pMaxh, mInfh, pMaxh, mInfh, pMaxh, mInfh, pMaxh, mInfh,
           pMaxh, mInfh, pMaxh, mInfh, pMaxh, mInfh, pMaxh);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U16(21, v1, 0, pInfh, 0, pInfh, 0, pInfh, 0, pInfh, 0, pInfh, 0, pInfh,
           0, pInfh, 0, pInfh);
  CHECK_FFLAGS(OF | NX);

  // Invalid operation. Overflow and Inexact should not be raised.
  CLEAR_FFLAGS;
  VSET(16, e32, m1);
  CHECK_FFLAGS(0);
  VLOAD_32(v2, pMaxf, pInff, pMaxf, pInff, pMaxf, pInff, pMaxf, pInff, pMaxf,
           pInff, pMaxf, pInff, pMaxf, pInff, pMaxf, pInff);
  VLOAD_32(v3, pMaxf, mInff, pMaxf, mInff, pMaxf, mInff, pMaxf, mInff, pMaxf,
           mInff, pMaxf, mInff, pMaxf, mInff, pMaxf, mInff);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U32(22, v1, 0, qNaNf, 0, qNaNf, 0, qNaNf, 0, qNaNf, 0, qNaNf, 0, qNaNf,
           0, qNaNf, 0, qNaNf);
  CHECK_FFLAGS(NV);

  // No exception should be raised
  CLEAR_FFLAGS;
  VSET(16, e64, m1);
  CHECK_FFLAGS(0);
  VLOAD_64(v2, pMaxd, 0, pInfd, 0, pMaxd, 0, pMaxd, 0, pMaxd, 0, pMaxd, 0,
           pMaxd, 0, pMaxd, 0);
  VLOAD_64(v3, pMaxd, 0, mInfd, 0, pMaxd, 0, pMaxd, 0, pMaxd, 0, pMaxd, 0,
           pMaxd, 0, pMaxd, 0);
  VLOAD_8(v0, 0xAA, 0xAA);
  VCLEAR(v1);
  asm volatile("vfadd.vv v1, v2, v3, v0.t");
  VCMP_U64(23, v1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  CHECK_FFLAGS(0);
};

int main(void) {
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();

  TEST_CASE6();
  TEST_CASE7();
  TEST_CASE8();

  EXIT_CHECK();
}
