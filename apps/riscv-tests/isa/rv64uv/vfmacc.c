// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "float_macros.h"
#include "vector_macros.h"

// Simple random test with similar values
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  //              -0.6353, -0.2290,  0.6870, -0.1031,  0.5410,  0.4211, -0.4939,
  //              -0.8779, -0.3213, -0.6846,  0.9229,  0.0103, -0.5068,  0.8706,
  //              0.6309, -0.3054
  VLOAD_16(v2, 0xb915, 0xb354, 0x397f, 0xae9a, 0x3854, 0x36bd, 0xb7e7, 0xbb06,
           0xb524, 0xb97a, 0x3b62, 0x2142, 0xb80e, 0x3af7, 0x390c, 0xb4e3);
  //              -0.8042, -0.9463,  0.4431,  0.3757, -0.5259, -0.1290,  0.4697,
  //              0.0952, -0.9995,  0.8823, -0.6128, -0.5010, -0.9976,  0.0081,
  //              0.9746, -0.7734
  VLOAD_16(v3, 0xba6f, 0xbb92, 0x3717, 0x3603, 0xb835, 0xb021, 0x3784, 0x2e17,
           0xbbff, 0x3b0f, 0xb8e7, 0xb802, 0xbbfb, 0x2022, 0x3bcc, 0xba30);
  //               0.6509,  0.3452,  0.9360,  0.3616, -0.4258, -0.0945, -0.7295,
  //               -0.7734,  0.3411, -0.1519, -0.3557,  0.6060,  0.2598,
  //               -0.0171, -0.8042, -0.4419
  VLOAD_16(v1, 0x3935, 0x3586, 0x3b7d, 0x35c9, 0xb6d0, 0xae0d, 0xb9d6, 0xba30,
           0x3575, 0xb0dc, 0xb5b1, 0x38d9, 0x3428, 0xa45e, 0xba6f, 0xb712);
  asm volatile("vfmacc.vv v1, v2, v3");
  //               1.1621,  0.5620,  1.2402,  0.3228, -0.7100, -0.1489, -0.9614,
  //               -0.8569,  0.6621, -0.7559, -0.9209,  0.6006,  0.7651,
  //               -0.0100, -0.1895, -0.2057
  VCMP_U16(1, v1, 0x3ca6, 0x387f, 0x3cf6, 0x352a, 0xb9af, 0xb0c4, 0xbbb1,
           0xbadb, 0x394c, 0xba0c, 0xbb5f, 0x38ce, 0x3a1f, 0xa123, 0xb20f,
           0xb295);

  VSET(16, e32, m1);
  //               0.72754014,  0.34003398,  0.70107144, -0.41727209,
  //               -0.52331781, -0.11821542, -0.16069038,  0.30835113,
  //               -0.59407759, -0.53240144, -0.92390168,  0.33251825,
  //               -0.45979658,  0.32465541, -0.99342769, -0.16221718
  VLOAD_32(v2, 0x3f3a4012, 0x3eae18ef, 0x3f33796b, 0xbed5a4b0, 0xbf05f828,
           0xbdf21aed, 0xbe248c05, 0x3e9de033, 0xbf181578, 0xbf084b76,
           0xbf6c84d2, 0x3eaa3fd5, 0xbeeb6a75, 0x3ea6393c, 0xbf7e5147,
           0xbe261c43);
  //               0.95104939, -0.11575679,  0.13276713,  0.22784369,
  //               0.93318671, -0.32301557,  0.41414812,  0.81797487,
  //               -0.21847244, -0.00211347, -0.72070456, -0.58624452,
  //               0.07381243, -0.16745377,  0.55389816, -0.23427610
  VLOAD_32(v3, 0x3f7377f9, 0xbded11e6, 0x3e07f41b, 0x3e694fdb, 0x3f6ee553,
           0xbea5624c, 0x3ed40b39, 0x3f5166cd, 0xbe5fb73d, 0xbb0a8224,
           0xbf388018, 0xbf16141f, 0x3d972af9, 0xbe2b7900, 0x3f0dcc45,
           0xbe6fe613);
  //              -0.07459558, -0.00461283, -0.97654468,  0.94394064,
  //              0.24971253,  0.97819000,  0.55116856, -0.97427863, 0.61764765,
  //              0.86367106,  0.48787504, -0.26353455, -0.22228357, 0.40454853,
  //              0.64000225, -0.51787829
  VLOAD_32(v1, 0xbd98c591, 0xbb97273a, 0xbf79fed5, 0x3f71a618, 0x3e7fb4a4,
           0x3f7a6aa9, 0x3f0d1962, 0xbf796a53, 0x3f1e1e28, 0x3f5d198c,
           0x3ef9cac2, 0xbe86ee00, 0xbe639e4e, 0x3ecf20fc, 0x3f23d730,
           0xbf0493ac);
  asm volatile("vfmacc.vv v1, v2, v3");
  //               0.61733103, -0.04397407, -0.88346541,  0.84886783,
  //               -0.23864070,  1.01637542,  0.48461893, -0.72205520,
  //               0.74743724,  0.86479628,  1.15373516, -0.45847154,
  //               -0.25622228,  0.35018376,  0.08974451, -0.47987467
  VCMP_U32(2, v1, 0x3f1e0968, 0xbd341e29, 0xbf622aca, 0x3f594f67, 0xbe745e3a,
           0x3f821897, 0x3ef81ff9, 0xbf38d89b, 0x3f3f580c, 0x3f5d634a,
           0x3f93ad98, 0xbeeabcc8, 0xbe832f91, 0x3eb34b49, 0x3db7cbf5,
           0xbef5b222);

  VSET(16, e64, m1);
  //              -0.8992497708533775,  0.5795977429472710, -0.9421852470430045,
  //              0.3407052467776674, -0.1137141395145149,  0.3284679540868891,
  //              0.9781857174570949,  0.6033619236526551, -0.1287683269222892,
  //              0.6555379481826638,  0.6785468173738887,  0.6923267883951645,
  //              0.2185923779321672, -0.1310544396012536, -0.7596952716763763,
  //              -0.4011231994121780,
  VLOAD_64(v2, 0xbfecc6a774980626, 0x3fe28c1090d967fc, 0xbfee2661acda592c,
           0x3fd5ce1d611f1590, 0xbfbd1c5eae4ec060, 0x3fd5059e742594fc,
           0x3fef4d4c223c8f84, 0x3fe34ebdaa37ac76, 0xbfc07b7b047228c0,
           0x3fe4fa2ab8176850, 0x3fe5b6a7d0ad9fa2, 0x3fe6278a8249a986,
           0x3fcbfad5c52fcfd8, 0xbfc0c664520a9f78, 0xbfe84f6c7558d3f0,
           0xbfd9ac00a3c919a8);
  //               0.3028184794479449,  0.5016121947684244,  0.1900289524299839,
  //               0.3294240614689632,  0.5945396967575391, -0.8758223026547887,
  //               0.3719808177193829,  0.9159354723876536,  0.0805670751146079,
  //               0.1775335284298603, -0.7021940272509897,  0.9279338928738479,
  //               -0.7358371767028979,  0.2529700403354449,
  //               -0.8333759771774525, -0.4016540133317048,
  VLOAD_64(v3, 0x3fd36160c2769da4, 0x3fe00d350479c3ea, 0x3fc852de63fd6e08,
           0x3fd51548a8a19488, 0x3fe306781d37ea9a, 0xbfec06bc7e604fb8,
           0x3fd7ce88a1b60584, 0x3fed4f57e864d750, 0x3fb4a00b38c069f0,
           0x3fc6b96b2d465dc0, 0xbfe6785f9bcfaa42, 0x3fedb1a26b57c7d6,
           0xbfe78bfa6823d662, 0x3fd030a94086f244, 0xbfeaab0418e7f974,
           0xbfd9b4b308e446c8);
  //              -0.0664052564688480, -0.6742544994800144,  0.4321518669568931,
  //              -0.1627512425330113,  0.0193121553139675, -0.3517684494272582,
  //              -0.4834881433176264,  0.8328623424117183,  0.0264604353835154,
  //              0.0322804237161178, -0.8345203693668675,  0.7175251091228996,
  //              -0.7419013213335950, -0.2977694001417877,  0.4556506623709609,
  //              -0.7832443836668095,
  VLOAD_64(v1, 0xbfb0ffef54d0f220, 0xbfe5937e2c0e5202, 0x3fdba8604ddf0d80,
           0xbfc4d508600804d8, 0x3f93c690cdf47e40, 0xbfd6835fd0838044,
           0xbfdef17840e363cc, 0x3feaa6ceed574e1a, 0x3f9b1871c270c340,
           0x3fa0870f4852d0c0, 0xbfeab4640fc8d962, 0x3fe6f5f737b7bbe2,
           0xbfe7bda7d6ff9552, 0xbfd30ea762d6f1ec, 0x3fdd296165522d4c,
           0xbfe910568693fcea);
  asm volatile("vfmacc.vv v1, v2, v3");
  //              -0.3387147047225807, -0.3835212035574087,  0.2531093914663254,
  //              -0.0505147363757267, -0.0482954147100367, -0.6394480093239447,
  //              -0.1196218202565150,  1.3855029309732363,  0.0160859479159849,
  //              0.1486603886766570, -1.3109918917369803,  1.3599586010192732,
  //              -0.9027497195599737, -0.3309222470138559,  1.0887624517613512,
  //              -0.6221316407824544,
  VCMP_U64(3, v1, 0xbfd5ad8070dd4c48, 0xbfd88b9c84a68118, 0x3fd032f1bbaa2211,
           0xbfa9dd1149664d37, 0xbfa8ba2d3573e621, 0xbfe4765babf13c96,
           0xbfbe9f891de3c4d6, 0x3ff62b051f10acd5, 0x3f9078d5b0e5b2ba,
           0x3fc3074db9c9d78e, 0xbff4f9d2a2454dd5, 0x3ff5c263f334aac4,
           0xbfece353613f76db, 0xbfd52dd4811c5fc3, 0x3ff16b922d36d831,
           0xbfe3e8809d5ef572);
};

// Simple random test with similar values (masked, the numbers are taken from
// TEST_CASE1)
void TEST_CASE2(void) {
  VSET(16, e16, m1);
  VLOAD_16(v2, 0xb915, 0xb354, 0x397f, 0xae9a, 0x3854, 0x36bd, 0xb7e7, 0xbb06,
           0xb524, 0xb97a, 0x3b62, 0x2142, 0xb80e, 0x3af7, 0x390c, 0xb4e3);
  VLOAD_16(v3, 0xba6f, 0xbb92, 0x3717, 0x3603, 0xb835, 0xb021, 0x3784, 0x2e17,
           0xbbff, 0x3b0f, 0xb8e7, 0xb802, 0xbbfb, 0x2022, 0x3bcc, 0xba30);
  VLOAD_16(v1, 0x3935, 0x3586, 0x3b7d, 0x35c9, 0xb6d0, 0xae0d, 0xb9d6, 0xba30,
           0x3575, 0xb0dc, 0xb5b1, 0x38d9, 0x3428, 0xa45e, 0xba6f, 0xb712);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vv v1, v2, v3, v0.t");
  VCMP_U16(4, v1, 0x3935, 0x387f, 0x3b7d, 0x352a, 0xb6d0, 0xb0c4, 0xb9d6,
           0xbadb, 0x3575, 0xba0c, 0xb5b1, 0x38ce, 0x3428, 0xa123, 0xba6f,
           0xb295);

  VSET(16, e32, m1);
  VLOAD_32(v2, 0x3f3a4012, 0x3eae18ef, 0x3f33796b, 0xbed5a4b0, 0xbf05f828,
           0xbdf21aed, 0xbe248c05, 0x3e9de033, 0xbf181578, 0xbf084b76,
           0xbf6c84d2, 0x3eaa3fd5, 0xbeeb6a75, 0x3ea6393c, 0xbf7e5147,
           0xbe261c43);
  VLOAD_32(v3, 0x3f7377f9, 0xbded11e6, 0x3e07f41b, 0x3e694fdb, 0x3f6ee553,
           0xbea5624c, 0x3ed40b39, 0x3f5166cd, 0xbe5fb73d, 0xbb0a8224,
           0xbf388018, 0xbf16141f, 0x3d972af9, 0xbe2b7900, 0x3f0dcc45,
           0xbe6fe613);
  VLOAD_32(v1, 0xbd98c591, 0xbb97273a, 0xbf79fed5, 0x3f71a618, 0x3e7fb4a4,
           0x3f7a6aa9, 0x3f0d1962, 0xbf796a53, 0x3f1e1e28, 0x3f5d198c,
           0x3ef9cac2, 0xbe86ee00, 0xbe639e4e, 0x3ecf20fc, 0x3f23d730,
           0xbf0493ac);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vv v1, v2, v3, v0.t");
  VCMP_U32(5, v1, 0xbd98c591, 0xbd341e29, 0xbf79fed5, 0x3f594f67, 0x3e7fb4a4,
           0x3f821897, 0x3f0d1962, 0xbf38d89b, 0x3f1e1e28, 0x3f5d634a,
           0x3ef9cac2, 0xbeeabcc8, 0xbe639e4e, 0x3eb34b49, 0x3f23d730,
           0xbef5b222);

  VSET(16, e64, m1);
  VLOAD_64(v2, 0xbfecc6a774980626, 0x3fe28c1090d967fc, 0xbfee2661acda592c,
           0x3fd5ce1d611f1590, 0xbfbd1c5eae4ec060, 0x3fd5059e742594fc,
           0x3fef4d4c223c8f84, 0x3fe34ebdaa37ac76, 0xbfc07b7b047228c0,
           0x3fe4fa2ab8176850, 0x3fe5b6a7d0ad9fa2, 0x3fe6278a8249a986,
           0x3fcbfad5c52fcfd8, 0xbfc0c664520a9f78, 0xbfe84f6c7558d3f0,
           0xbfd9ac00a3c919a8);
  VLOAD_64(v3, 0x3fd36160c2769da4, 0x3fe00d350479c3ea, 0x3fc852de63fd6e08,
           0x3fd51548a8a19488, 0x3fe306781d37ea9a, 0xbfec06bc7e604fb8,
           0x3fd7ce88a1b60584, 0x3fed4f57e864d750, 0x3fb4a00b38c069f0,
           0x3fc6b96b2d465dc0, 0xbfe6785f9bcfaa42, 0x3fedb1a26b57c7d6,
           0xbfe78bfa6823d662, 0x3fd030a94086f244, 0xbfeaab0418e7f974,
           0xbfd9b4b308e446c8);
  VLOAD_64(v1, 0xbfb0ffef54d0f220, 0xbfe5937e2c0e5202, 0x3fdba8604ddf0d80,
           0xbfc4d508600804d8, 0x3f93c690cdf47e40, 0xbfd6835fd0838044,
           0xbfdef17840e363cc, 0x3feaa6ceed574e1a, 0x3f9b1871c270c340,
           0x3fa0870f4852d0c0, 0xbfeab4640fc8d962, 0x3fe6f5f737b7bbe2,
           0xbfe7bda7d6ff9552, 0xbfd30ea762d6f1ec, 0x3fdd296165522d4c,
           0xbfe910568693fcea);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vv v1, v2, v3, v0.t");
  VCMP_U64(6, v1, 0xbfb0ffef54d0f220, 0xbfd88b9c84a68118, 0x3fdba8604ddf0d80,
           0xbfa9dd1149664d37, 0x3f93c690cdf47e40, 0xbfe4765babf13c96,
           0xbfdef17840e363cc, 0x3ff62b051f10acd5, 0x3f9b1871c270c340,
           0x3fc3074db9c9d78e, 0xbfeab4640fc8d962, 0x3ff5c263f334aac4,
           0xbfe7bda7d6ff9552, 0xbfd52dd4811c5fc3, 0x3fdd296165522d4c,
           0xbfe3e8809d5ef572);
};

// Simple random test with similar values (with scalar)
void TEST_CASE3(void) {
  VSET(16, e16, m1);
  //              0.7407, -0.1365,  0.0000, -0.8525, -0.0812,  0.9609, -0.3740,
  //              0.2800,  0.9692,  0.4045,  0.0205, -0.5503,  0.6499,  0.4470,
  //              -0.9360, -0.4426
  VLOAD_16(v3, 0x39ed, 0xb05e, 0x0000, 0xbad2, 0xad33, 0x3bb0, 0xb5fc, 0x347b,
           0x3bc1, 0x3679, 0x253e, 0xb867, 0x3933, 0x3727, 0xbb7d, 0xb715);
  double dscalar_16;
  //                             0.5757
  BOX_HALF_IN_DOUBLE(dscalar_16, 0x389b);
  //             -0.1472, -0.8906,  0.2247,  0.6118, -0.0908, -0.6450, -0.5415,
  //             0.0505, -0.4595,  0.1157, -0.3494,  0.6670, -0.9658, -0.2944,
  //             -0.8096, -0.3364
  VLOAD_16(v1, 0xb0b6, 0xbb20, 0x3331, 0x38e5, 0xadcf, 0xb929, 0xb855, 0x2a77,
           0xb75a, 0x2f68, 0xb597, 0x3956, 0xbbba, 0xb4b6, 0xba7a, 0xb562);
  asm volatile("vfmacc.vf v1, %[A], v3" ::[A] "f"(dscalar_16));
  //              0.2793, -0.9692,  0.2247,  0.1210, -0.1375, -0.0918, -0.7568,
  //              0.2118,  0.0986,  0.3486, -0.3376,  0.3501, -0.5918, -0.0371,
  //              -1.3486, -0.5913
  VCMP_U16(7, v1, 0x3478, 0xbbc1, 0x3331, 0x2fbf, 0xb067, 0xade0, 0xba0e,
           0x32c6, 0x2e4e, 0x3594, 0xb567, 0x359a, 0xb8bc, 0xa8bf, 0xbd65,
           0xb8bb);

  VSET(16, e32, m1);
  //              -0.79164708, -0.13258822, -0.94492996, -0.93729085,
  //              0.80344391,  0.77393818,  0.31253836, -0.42539355,
  //              -0.20085664, -0.63946086,  0.24876182, -0.45639724,
  //              0.92842573,  0.39117134, -0.70563781,  0.13946204
  VLOAD_32(v3, 0xbf4aa962, 0xbe07c535, 0xbf71e6ee, 0xbf6ff24b, 0x3f4dae80,
           0x3f4620d0, 0x3ea00507, 0xbed9cd2f, 0xbe4dad5d, 0xbf23b3b5,
           0x3e7ebb6b, 0xbee9ace6, 0x3f6dad4f, 0x3ec8479c, 0xbf34a4ae,
           0x3e0ecf23);
  double dscalar_32;
  //                              0.97630060
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0x3f79eed6);
  //              -0.43768027, -0.74227923,  0.60234988,  0.43624315,
  //              0.34759882,  0.65410614,  0.99296939, -0.31534156,
  //              -0.89647168,  0.47623411, -0.68185741,  0.77072626,
  //              0.19827089, -0.16254151,  0.81625229, -0.24369264
  VLOAD_32(v1, 0xbee017a1, 0xbf3e0603, 0x3f1a339a, 0x3edf5b43, 0x3eb1f879,
           0x3f277380, 0x3f7e333e, 0xbea17473, 0xbf657f2b, 0x3ef3d4f5,
           0xbf2e8e35, 0x3f454e51, 0x3e4b0786, 0xbe267148, 0x3f50f5e9,
           0xbe798a90);
  asm volatile("vfmacc.vf v1, %[A], v3" ::[A] "f"(dscalar_32));
  //              -1.21056581, -0.87172520, -0.32018578,
  //              -0.47883448,  1.13200164,  1.40970242,  1.29810071,
  //              -0.73065352, -1.09256816, -0.14807191, -0.43899110,
  //              0.32514536,  1.10469353,  0.21935931,  0.12733769, -0.10753576
  VCMP_U32(8, v1, 0xbf9af3d2, 0xbf5f2962, 0xbea3ef65, 0xbef529cb, 0x3f90e56e,
           0x3fb47121, 0x3fa6282b, 0xbf3b0c1c, 0xbf8bd946, 0xbe17a02a,
           0xbee0c371, 0x3ea67974, 0x3f8d6699, 0x3e609fb9, 0x3e0264cf,
           0xbddc3bb6);

  VSET(16, e64, m1);
  //              -0.1981785436218435,  0.2324321764718080,  0.3529425082887112,
  //              -0.4889737836823891,  0.1335009259637479, -0.7964186221277452,
  //              -0.2707335519445100,  0.8070543770008602, -0.1237072120160827,
  //              -0.2357903062216291, -0.0812498320849093,  0.8656662449573254,
  //              0.7178262144151533, -0.3106178959409680, -0.1410836751949509,
  //              0.6904294937898030
  VLOAD_64(v3, 0xbfc95dea1dcff710, 0x3fcdc0566a3e04a0, 0x3fd6969c2c9df760,
           0xbfdf4b58b2611a74, 0x3fc1168eef800078, 0xbfe97c42e7fed97a,
           0xbfd153b2d1e20588, 0x3fe9d363b369fec4, 0xbfbfab469de36f10,
           0xbfce2e6072f7c5c0, 0xbfb4ccc9fb9c3490, 0x3febb389b26af886,
           0x3fe6f86eae63fc74, 0xbfd3e129e2279a3c, 0xbfc20f07a57b1c48,
           0x3fe617ff9800ac5a);
  double dscalar_64;
  //                               0.8738839355493300
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3febf6db7175e482);
  //              -0.9433584234417285, -0.0696473591160720, -0.8171557896146857,
  //              -0.9495656113293445, -0.6353537919969880,  0.8159507202507001,
  //              0.0288919190409849, -0.6024741558584952, -0.9583084411212592,
  //              0.7665070398551490, -0.7817863527411446, -0.2155326059803253,
  //              -0.7807395886866346,  0.2528540140694266, -0.1740695080779533,
  //              0.7247829241803623
  VLOAD_64(v1, 0xbfee2ffe0122d3b6, 0xbfb1d468c9a80310, 0xbfea2623e6043a6c,
           0xbfee62d76bc21ae2, 0xbfe454d179c08866, 0x3fea1c44af53fb1a,
           0x3f9d95d7dd994d80, 0xbfe34777e1831e42, 0xbfeeaa7676c316f0,
           0x3fe88739c58a9cbe, 0xbfe90464d02f6f4c, 0xbfcb96928af41d88,
           0xbfe8fbd197034034, 0x3fd02ec29a45caf0, 0xbfc647e8de367aa0,
           0x3fe7316bf581b994);
  asm volatile("vfmacc.vf v1, %[A], v3" ::[A] "f"(dscalar_64));
  //              -1.1165434690834197,  0.1334713860074080, -0.5087250014486948,
  //              -1.3768719457941574, -0.5186894774163083,  0.1199732804009315,
  //              -0.2076977828175325,  0.1027976993173292, -1.0664141864137089,
  //              0.5604536790898100, -0.8527892757662274,  0.5409592190351925,
  //              -0.1534427913930433, -0.0185899752875187, -0.2973602653990804,
  //              1.3281381674327271
  VCMP_U64(9, v1, 0xbff1dd5caf44692a, 0x3fc1159722ed4311, 0xbfe04779a77c2679,
           0xbff607aae09f73e1, 0xbfe0991aacc90937, 0x3fbeb691a3b74133,
           0xbfca95d7485395ec, 0x3fba50f334ac0644, 0xbff11008526a327e,
           0x3fe1ef3c8dd3a2b9, 0xbfeb4a0cbc397482, 0x3fe14f89b5473a2f,
           0xbfc3a4036d6b8775, 0xbf9309401f92c802, 0xbfd307f359c13629,
           0x3ff5400dce9b1643);
};

// Simple random test with similar values (masked with scalar, values taken from
// TEST_CASE3)
void TEST_CASE4(void) {
  VSET(16, e16, m1);
  VLOAD_16(v3, 0x39ed, 0xb05e, 0x0000, 0xbad2, 0xad33, 0x3bb0, 0xb5fc, 0x347b,
           0x3bc1, 0x3679, 0x253e, 0xb867, 0x3933, 0x3727, 0xbb7d, 0xb715);
  double dscalar_16;
  BOX_HALF_IN_DOUBLE(dscalar_16, 0x389b);
  VLOAD_16(v1, 0xb0b6, 0xbb20, 0x3331, 0x38e5, 0xadcf, 0xb929, 0xb855, 0x2a77,
           0xb75a, 0x2f68, 0xb597, 0x3956, 0xbbba, 0xb4b6, 0xba7a, 0xb562);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vf v1, %[A], v3, v0.t" ::[A] "f"(dscalar_16));
  VCMP_U16(10, v1, 0xb0b6, 0xbbc1, 0x3331, 0x2fbf, 0xadcf, 0xade0, 0xb855,
           0x32c6, 0xb75a, 0x3594, 0xb597, 0x359a, 0xbbba, 0xa8bf, 0xba7a,
           0xb8bb);

  VSET(16, e32, m1);
  VLOAD_32(v3, 0xbf4aa962, 0xbe07c535, 0xbf71e6ee, 0xbf6ff24b, 0x3f4dae80,
           0x3f4620d0, 0x3ea00507, 0xbed9cd2f, 0xbe4dad5d, 0xbf23b3b5,
           0x3e7ebb6b, 0xbee9ace6, 0x3f6dad4f, 0x3ec8479c, 0xbf34a4ae,
           0x3e0ecf23);
  double dscalar_32;
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0x3f79eed6);
  VLOAD_32(v1, 0xbee017a1, 0xbf3e0603, 0x3f1a339a, 0x3edf5b43, 0x3eb1f879,
           0x3f277380, 0x3f7e333e, 0xbea17473, 0xbf657f2b, 0x3ef3d4f5,
           0xbf2e8e35, 0x3f454e51, 0x3e4b0786, 0xbe267148, 0x3f50f5e9,
           0xbe798a90);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vf v1, %[A], v3, v0.t" ::[A] "f"(dscalar_32));
  VCMP_U32(11, v1, 0xbee017a1, 0xbf5f2962, 0x3f1a339a, 0xbef529cb, 0x3eb1f879,
           0x3fb47121, 0x3f7e333e, 0xbf3b0c1c, 0xbf657f2b, 0xbe17a02a,
           0xbf2e8e35, 0x3ea67974, 0x3e4b0786, 0x3e609fb9, 0x3f50f5e9,
           0xbddc3bb6);

  VSET(16, e64, m1);
  VLOAD_64(v3, 0xbfc95dea1dcff710, 0x3fcdc0566a3e04a0, 0x3fd6969c2c9df760,
           0xbfdf4b58b2611a74, 0x3fc1168eef800078, 0xbfe97c42e7fed97a,
           0xbfd153b2d1e20588, 0x3fe9d363b369fec4, 0xbfbfab469de36f10,
           0xbfce2e6072f7c5c0, 0xbfb4ccc9fb9c3490, 0x3febb389b26af886,
           0x3fe6f86eae63fc74, 0xbfd3e129e2279a3c, 0xbfc20f07a57b1c48,
           0x3fe617ff9800ac5a);
  double dscalar_64;
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3febf6db7175e482);
  VLOAD_64(v1, 0xbfee2ffe0122d3b6, 0xbfb1d468c9a80310, 0xbfea2623e6043a6c,
           0xbfee62d76bc21ae2, 0xbfe454d179c08866, 0x3fea1c44af53fb1a,
           0x3f9d95d7dd994d80, 0xbfe34777e1831e42, 0xbfeeaa7676c316f0,
           0x3fe88739c58a9cbe, 0xbfe90464d02f6f4c, 0xbfcb96928af41d88,
           0xbfe8fbd197034034, 0x3fd02ec29a45caf0, 0xbfc647e8de367aa0,
           0x3fe7316bf581b994);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vfmacc.vf v1, %[A], v3, v0.t" ::[A] "f"(dscalar_64));
  VCMP_U64(12, v1, 0xbfee2ffe0122d3b6, 0x3fc1159722ed4311, 0xbfea2623e6043a6c,
           0xbff607aae09f73e1, 0xbfe454d179c08866, 0x3fbeb691a3b74133,
           0x3f9d95d7dd994d80, 0x3fba50f334ac0644, 0xbfeeaa7676c316f0,
           0x3fe1ef3c8dd3a2b9, 0xbfe90464d02f6f4c, 0x3fe14f89b5473a2f,
           0xbfe8fbd197034034, 0xbf9309401f92c802, 0xbfc647e8de367aa0,
           0x3ff5400dce9b1643);
};

int main(void) {
  INIT_CHECK();
  enable_vec();
  enable_fp();

  TEST_CASE1();
  TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();

  EXIT_CHECK();
}
