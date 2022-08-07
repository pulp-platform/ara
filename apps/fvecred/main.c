/*=================================================================================================
Project Name:    Ara
Author:          Xiaorui Yin <yinx@student.ethz.ch>
Organization:    ETH Zürich
File Name:       main.c
Created On:      2022/05/19

Description:

CopyRight Notice
All Rights Reserved
===================================================================================================
Modification    History:
Date            By              Version         Change Description
---------------------------------------------------------------------------------------------------

=================================================================================================*/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// #include "runtime.h"
#include "fvecred.h"
#include "printf.h"

#define VL_S 32
#define VL_M 128
#define VL_L 256

// The length of a vector register is 4096bits
// Maximal LMUL is 8, the maximal VL is 4096 * 8 / EW
#define VL_MAX_32 1024 // EW32
#define VL_MAX_64 512  // EW64

double rand_data[1024] = {
    -2414, -826,  2620,  604,   2140,  2114,  1363,  1198,  -39,   -1072, -1133,
    3348,  931,   1662,  -1099, 2502,  -798,  -1152, -1321, 1536,  -2872, 36,
    -2551, -4061, -3252, -710,  2471,  -689,  -1547, -1256, 2592,  1004,  -585,
    2631,  3511,  1209,  535,   -2287, 3961,  -3831, -159,  1143,  2169,  -538,
    1095,  3826,  -1687, -337,  -575,  1953,  -2877, 1159,  423,   -953,  774,
    -111,  3689,  -1253, 1271,  -1116, -540,  249,   2693,  -837,  3518,  1216,
    1769,  -3648, -3913, 239,   -1770, -1254, -3000, -174,  -536,  2272,  1200,
    3975,  1135,  3721,  -2540, -3489, 2045,  -3497, 3460,  -1877, -3151, -1962,
    1825,  -3531, 527,   -2947, -2247, 3350,  -2300, -1374, 1913,  -2205, -1981,
    -2623, -2033, 486,   -3379, 2816,  -1429, 1609,  3190,  2393,  1698,  1585,
    -2816, -3222, 3020,  1806,  3493,  -666,  -453,  -478,  1884,  1702,  -1998,
    -575,  2779,  -3682, 269,   3566,  2435,  -1813, -1949, 2363,  2447,  2273,
    3537,  -292,  -3472, -1395, -2793, 2982,  3877,  -18,   578,   2371,  70,
    1323,  3220,  1585,  3018,  -1722, 1094,  1992,  -1002, 3115,  -3459, -4092,
    -896,  -874,  -1390, 3836,  -2590, -3526, -282,  -2957, -1608, -1527, 476,
    2436,  840,   -1283, -1075, -2733, -161,  2170,  3404,  -750,  -3743, 1191,
    1606,  683,   -760,  2714,  -2419, 3578,  1777,  -2936, 923,   -750,  1277,
    1236,  2876,  682,   -524,  -3644, -1357, -3459, 1569,  -564,  -163,  -2395,
    1919,  3720,  1686,  -457,  -1373, -2196, -363,  2381,  655,   -2992, -3202,
    1606,  1044,  -3803, 1441,  -940,  2704,  1903,  -1256, -2234, -706,  2214,
    -577,  -416,  1542,  1118,  1227,  2185,  -344,  -1909, -1119, 1369,  4,
    -2932, 1570,  1214,  1549,  -439,  -1928, -3349, 1243,  1789,  2257,  2648,
    3046,  -2000, -3399, 294,   858,   -243,  2230,  -602,  2892,  -2744, 3953,
    -2441, 3691,  -2011, 1844,  2249,  -1013, 1143,  -1545, -1352, 46,    -2186,
    -656,  -2205, -2218, -1763, -1271, -1749, -740,  -1273, -1590, -3395, -1848,
    2175,  -1023, 1021,  2797,  -2591, -1099, -630,  -39,   -3007, -2146, 1658,
    2533,  3856,  -3075, 3437,  1892,  -1250, -3768, -802,  -2386, -3844, -727,
    2025,  3039,  -3272, -2119, 3320,  -3188, -3260, 1398,  2102,  -962,  668,
    -1749, 2138,  1947,  2675,  -1480, -2832, 3561,  777,   1887,  1334,  -283,
    1485,  -1941, -2203, -455,  -2970, -1283, 3238,  803,   3085,  3058,  -2840,
    2407,  -1612, 668,   907,   -98,   -3642, 2584,  -2916, -2225, 1872,  -2719,
    492,   2564,  942,   -3387, -3388, 2435,  -2054, -3139, -1447, -2110, 3692,
    -499,  590,   -1261, -427,  1580,  2783,  1646,  310,   -2830, 1174,  -288,
    -3485, -3230, 1769,  1419,  -221,  -904,  2211,  707,   -3735, 2619,  -1717,
    -694,  792,   -3524, 2205,  2849,  3142,  4069,  -2878, 3555,  -3256, 319,
    -807,  -1561, 214,   1221,  3423,  3729,  -2110, -901,  2966,  1047,  -1282,
    -2456, -1854, 3549,  462,   3281,  -2940, 534,   -1862, -3796, -406,  3733,
    -1605, 459,   622,   -3706, -2086, -855,  -253,  2480,  -265,  51,    -2169,
    -708,  -3515, 895,   -2093, 174,   2104,  -1242, 1497,  1983,  -1457, -2013,
    -776,  -1504, 3826,  -1416, 1127,  3460,  1011,  -2134, -3904, 3317,  1270,
    -758,  -2930, 764,   -210,  -3740, -3504, -1490, -558,  -1167, -2291, 659,
    -1601, 1779,  3427,  518,   450,   -264,  -605,  -3444, -3837, 3351,  2375,
    1902,  3045,  1604,  1362,  37,    3071,  -1000, -1244, 437,   -1284, -1508,
    -1260, 2967,  3482,  -2238, -1982, 2694,  120,   3127,  3945,  1925,  1119,
    -271,  700,   -1211, -108,  1847,  3318,  -1500, 3501,  2232,  -2543, -2729,
    4032,  -1416, 1055,  236,   -4012, 2656,  -60,   -2479, -547,  -3402, 2805,
    2739,  2053,  -1921, 1653,  -609,  -2450, 1787,  868,   -1125, 1693,  -3718,
    -1302, 1350,  -3817, -3930, -96,   2776,  -3787, -4010, 900,   3852,  -2806,
    2633,  -1672, -3499, -1782, -524,  -805,  -2869, 3564,  -1738, 1206,  -110,
    -1706, -3814, -3837, -819,  3110,  -597,  -3544, 2108,  -1047, 232,   -1624,
    512,   3332,  460,   -3426, -3615, -3474, 2850,  -3995, 1324,  3713,  -3388,
    4011,  2989,  -3799, -159,  -3298, -406,  3163,  -1645, 3397,  2744,  -984,
    1354,  -2198, -2202, 3192,  -3677, -1359, -3609, 2030,  -1746, 634,   1674,
    -4035, 247,   538,   3534,  3157,  -700,  -762,  -2521, 353,   1273,  1329,
    -1657, 3739,  -3453, -1311, -4085, 2023,  -659,  -1963, 619,   2661,  3480,
    -1007, -4062, -1700, 493,   -793,  -3525, -1910, 1169,  3742,  -1040, -1891,
    2580,  323,   -3108, -2225, -935,  3412,  2413,  -2664, -3010, 3231,  560,
    3080,  2540,  2826,  -234,  -2344, -3197, -2379, -3454, -399,  -1014, 722,
    4060,  -7,    -158,  1390,  1191,  42,    3804,  -4072, 2647,  217,   -2110,
    -1819, -2602, 3090,  3932,  -3760, -1294, 2353,  1704,  -3280, -3205, 3126,
    369,   1738,  -563,  -1481, -2439, -3220, -2055, -3729, -224,  -1644, -1280,
    -2775, -2994, 3480,  3243,  -959,  -3263, -3594, 2821,  218,   -3268, 1409,
    1567,  72,    -1485, -1962, 890,   2362,  -2143, -1729, 1925,  -3197, 3004,
    -3073, -2935, -4081, 449,   -3468, 1053,  -3826, 283,   -1802, 2744,  -1890,
    -3121, -1445, -3216, 3247,  2124,  -563,  -1171, 3704,  1543,  -2086, -840,
    -2312, 3653,  -1743, -3854, -1110, 1491,  -3332, 911,   -4021, -963,  -1134,
    -1265, 2862,  655,   2394,  -2863, 292,   -2316, -1069, 4,     1963,  1031,
    -4003, -2757, -2894, -772,  -944,  1808,  -3465, -4020, 3952,  -2607, 2125,
    -3832, -678,  -1336, -3649, -1086, 613,   -376,  3413,  1418,  -461,  581,
    -3338, 2708,  -1068, 774,   2812,  2740,  -1108, 1960,  -1485, -1725, -844,
    2065,  -364,  3952,  3330,  783,   -1511, -3253, 2795,  -3552, 308,   1674,
    -3374, 45,    -1891, -2419, 1707,  4020,  3163,  -545,  -3999, -2827, -3706,
    -133,  89,    -7,    25,    1217,  1712,  -1064, -433,  -783,  3771,  -1109,
    -2223, -3396, -1146, -3787, 3340,  -3857, -1739, -1414, -121,  477,   -2818,
    -2066, 3268,  1556,  -2933, 3315,  662,   -2511, 1157,  2932,  708,   3623,
    -874,  2117,  230,   2146,  -1127, -2475, -699,  -2599, -3597, 2309,  3307,
    1137,  200,   2112,  -3052, 172,   2540,  3389,  -333,  2783,  -2484, 657,
    -2563, 1010,  -94,   1764,  1464,  3050,  3465,  1152,  -815,  3393,  2136,
    3010,  3784,  -2634, 407,   555,   1776,  -2471, 1806,  -351,  2354,  -2973,
    541,   3894,  2143,  3169,  -1412, -362,  2157,  -3760, -2029, 1321,  -758,
    387,   -506,  884,   486,   967,   3655,  -441,  3563,  3231,  182,   793,
    -1973, 3032,  1840,  -2967, -2724, 2087,  -3231, 2870,  3498,  1435,  1526,
    1195,  1369,  -3105, -4034, -2183, -1062, -1529, -25,   3578,  -2445, -2740,
    1695,  1393,  -3994, 130,   1217,  3156,  640,   -1592, 3395,  3766,  -257,
    -3857, -2275, -3883, -654,  3883,  565,   -2463, -3863, -4069, 112,   -3621,
    1137,  -2096, -3106, -626,  -2101, -1518, 3395,  1292,  -393,  720,   3256,
    3925,  -191,  -2385, 865,   -1799, 1213,  1989,  772,   2828,  3314,  1709,
    1325,  949,   403,   -3257, -229,  -3023, 3461,  -3852, 3974,  1200,  -517,
    -2931, 2127,  -2448, -2640, 3980,  -1601, -1387, 2605,  -1931, 3795,  -2725,
    -444,  4000,  2577,  3034,  -907,  -2637, -1924, -220,  3320,  625,   -3991,
    3184,  -2115, -1356, -1761, -2150, 66,    -2420, 1146,  1755,  -408,  1968,
    -427,  2577,  -3661, 3178,  -3403, 2658,  2157,  2535,  1903,  -1949, 2506,
    -495,  708,   -1446, -1062, 2715,  1746,  1041,  3290,  2509,  3108,  -2337,
    3848};

void gen_rand_vec_64(double *vec, uint16_t vl) {
  for (uint16_t i = 0; i < vl; i++) {
    vec[i] = rand_data[i];
  }
}

void gen_rand_vec_32(float *vec, uint16_t vl) {
  for (uint16_t i = 0; i < vl; i++) {
    vec[i] = (float)rand_data[i];
  }
}

void verify_result_64(double *vec, double scalar, uint16_t vl, double res) {
  double sum = scalar;
  printf("Verifying Result\n");
  for (uint16_t i = 0; i < vl; i++)
    sum += vec[i];
  if (sum == res) {
    printf("PASS\n");
  } else {
    printf("FAIL\n");
    printf("ACT = %f, EXP = %f\n", res, sum);
  }
  printf("\n");
}

void verify_result_32(float *vec, float scalar, uint16_t vl, float res) {
  float sum = scalar;
  printf("Verifying Result\n");
  for (uint16_t i = 0; i < vl; i++)
    sum += vec[i];
  if (sum == res) {
    printf("PASS\n");
  } else {
    printf("FAIL\n");
    printf("ACT = %f, EXP = %f\n", res, sum);
  }
  printf("\n");
}

void vfredusum_32() {
  printf("\n");
  printf("======================\n");
  printf("vfredsum EW32\n");
  printf("======================\n");
  printf("\n");
  printf("\n");

  float vec1[VL_S], res1[VL_S];
  float vec2[VL_M], res2[VL_M];
  float vec3[VL_L], res3[VL_L];
  float vec4[VL_MAX_32], res4[VL_MAX_32];
  gen_rand_vec_32(vec1, VL_S);
  gen_rand_vec_32(vec2, VL_M);
  gen_rand_vec_32(vec3, VL_L);
  gen_rand_vec_32(vec4, VL_MAX_32);

  printf("======================\n");
  printf("VL=32\n");
  printf("======================\n");
  VSET(VL_S, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res1));
  verify_result_32(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128\n");
  printf("======================\n");
  VSET(VL_M, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec2));
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res2));
  verify_result_32(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256\n");
  printf("======================\n");
  VSET(VL_L, e32, m2);
  asm volatile("vle32.v v4, (%0);" ::"r"(vec3));
  asm volatile("vle32.v v6, (%0);" ::"r"(vec3));
  asm volatile("vfredsum.vs v2, v4, v6");
  asm volatile("vse32.v v2, (%0);" ::"r"(res3));
  verify_result_32(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=1024\n");
  printf("======================\n");
  VSET(VL_MAX_32, e32, m8);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle32.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfredsum.vs v16, v0, v8");
  asm volatile("vse32.v v16, (%0);" ::"r"(res4));
  verify_result_32(vec4, vec4[0], VL_MAX_32, res4[0]);
  printf("\n");
  printf("\n");

  // Issue a redundant vector add instruction to eliminate
  // the effect of stalls due to data denpendencies
  printf("======================\n");
  printf("VL=32 PRELOADED\n");
  printf("======================\n");
  VSET(VL_S, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res1));
  verify_result_32(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128 PRELOADED\n");
  printf("======================\n");
  VSET(VL_M, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec2));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res2));
  verify_result_32(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256 PRELOADED\n");
  printf("======================\n");
  VSET(VL_L, e32, m2);
  asm volatile("vle32.v v4, (%0);" ::"r"(vec3));
  asm volatile("vle32.v v6, (%0);" ::"r"(vec3));
  asm volatile("vfadd.vv v2, v4, v6");
  asm volatile("vfredsum.vs v2, v4, v6");
  asm volatile("vse32.v v2, (%0);" ::"r"(res3));
  verify_result_32(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=1024 PRELOADED\n");
  printf("======================\n");
  VSET(VL_MAX_32, e32, m8);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle32.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfadd.vv v16, v0, v8");
  asm volatile("vfredsum.vs v16, v0, v8");
  asm volatile("vse32.v v16, (%0);" ::"r"(res4));
  verify_result_32(vec4, vec4[0], VL_MAX_32, res4[0]);
  printf("\n");
  printf("\n");
}

void vfredosum_32() {
  printf("\n");
  printf("======================\n");
  printf("VFREDOSUM EW32\n");
  printf("======================\n");
  printf("\n");
  printf("\n");

  float vec1[VL_S], res1[VL_S];
  float vec2[VL_M], res2[VL_M];
  float vec3[VL_L], res3[VL_L];
  float vec4[VL_MAX_32], res4[VL_MAX_32];
  gen_rand_vec_32(vec1, VL_S);
  gen_rand_vec_32(vec2, VL_M);
  gen_rand_vec_32(vec3, VL_L);
  gen_rand_vec_32(vec4, VL_MAX_32);

  printf("======================\n");
  printf("VL=32\n");
  printf("======================\n");
  VSET(VL_S, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res1));
  verify_result_32(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128\n");
  printf("======================\n");
  VSET(VL_M, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec2));
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res2));
  verify_result_32(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256\n");
  printf("======================\n");
  VSET(VL_L, e32, m2);
  asm volatile("vle32.v v4, (%0);" ::"r"(vec3));
  asm volatile("vle32.v v6, (%0);" ::"r"(vec3));
  asm volatile("vfredosum.vs v2, v4, v6");
  asm volatile("vse32.v v2, (%0);" ::"r"(res3));
  verify_result_32(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=1024\n");
  printf("======================\n");
  VSET(VL_MAX_32, e32, m8);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle32.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfredosum.vs v16, v0, v8");
  asm volatile("vse32.v v16, (%0);" ::"r"(res4));
  verify_result_32(vec4, vec4[0], VL_MAX_32, res4[0]);
  printf("\n");
  printf("\n");

  // Issue a redundant vector add instruction to eliminate
  // the effect of stalls due to data denpendencies
  printf("======================\n");
  printf("VL=32 PRELOADED\n");
  printf("======================\n");
  VSET(VL_S, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res1));
  verify_result_32(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128 PRELOADED\n");
  printf("======================\n");
  VSET(VL_M, e32, m1);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle32.v v1, (%0);" ::"r"(vec2));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse32.v v2, (%0);" ::"r"(res2));
  verify_result_32(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256 PRELOADED\n");
  printf("======================\n");
  VSET(VL_L, e32, m2);
  asm volatile("vle32.v v4, (%0);" ::"r"(vec3));
  asm volatile("vle32.v v6, (%0);" ::"r"(vec3));
  asm volatile("vfadd.vv v2, v4, v6");
  asm volatile("vfredosum.vs v2, v4, v6");
  asm volatile("vse32.v v2, (%0);" ::"r"(res3));
  verify_result_32(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=1024 PRELOADED\n");
  printf("======================\n");
  VSET(VL_MAX_32, e32, m8);
  asm volatile("vle32.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle32.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfadd.vv v16, v0, v8");
  asm volatile("vfredosum.vs v16, v0, v8");
  asm volatile("vse32.v v16, (%0);" ::"r"(res4));
  verify_result_32(vec4, vec4[0], VL_MAX_32, res4[0]);
  printf("\n");
  printf("\n");
}

void vfredusum_64() {
  printf("\n");
  printf("======================\n");
  printf("VFREDUSUM EW64\n");
  printf("======================\n");
  printf("\n");
  printf("\n");

  double vec1[VL_S], res1[VL_S];
  double vec2[VL_M], res2[VL_M];
  double vec3[VL_L], res3[VL_L];
  double vec4[VL_MAX_64], res4[VL_MAX_64];
  gen_rand_vec_64(vec1, VL_S);
  gen_rand_vec_64(vec2, VL_M);
  gen_rand_vec_64(vec3, VL_L);
  gen_rand_vec_64(vec4, VL_MAX_64);

  printf("======================\n");
  printf("VL=32\n");
  printf("======================\n");
  VSET(VL_S, e64, m1);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle64.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse64.v v2, (%0);" ::"r"(res1));
  verify_result_64(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128\n");
  printf("======================\n");
  VSET(VL_M, e64, m2);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle64.v v2, (%0);" ::"r"(vec2));
  asm volatile("vfredsum.vs v4, v0, v2");
  asm volatile("vse64.v v4, (%0);" ::"r"(res2));
  verify_result_64(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256\n");
  printf("======================\n");
  VSET(VL_L, e64, m4);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec3));
  asm volatile("vle64.v v4, (%0);" ::"r"(vec3));
  asm volatile("vfredsum.vs v8, v0, v4");
  asm volatile("vse64.v v8, (%0);" ::"r"(res3));
  verify_result_64(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=512\n");
  printf("======================\n");
  VSET(VL_MAX_64, e64, m8);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle64.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfredsum.vs v16, v0, v8");
  asm volatile("vse64.v v16, (%0);" ::"r"(res4));
  verify_result_64(vec4, vec4[0], VL_MAX_64, res4[0]);
  printf("\n");
  printf("\n");

  // Issue a redundant vector add instruction to eliminate
  // the effect of stalls due to data denpendencies
  printf("======================\n");
  printf("VL=32 PRELOADED\n");
  printf("======================\n");
  VSET(VL_S, e64, m1);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle64.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredsum.vs v2, v0, v1");
  asm volatile("vse64.v v2, (%0);" ::"r"(res1));
  verify_result_64(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128 PRELOADED\n");
  printf("======================\n");
  VSET(VL_M, e64, m2);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle64.v v2, (%0);" ::"r"(vec2));
  asm volatile("vfadd.vv v4, v0, v2");
  asm volatile("vfredsum.vs v4, v0, v2");
  asm volatile("vse64.v v4, (%0);" ::"r"(res2));
  verify_result_64(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256 PRELOADED\n");
  printf("======================\n");
  VSET(VL_L, e64, m4);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec3));
  asm volatile("vle64.v v4, (%0);" ::"r"(vec3));
  asm volatile("vfadd.vv v8, v0, v4");
  asm volatile("vfredsum.vs v8, v0, v4");
  asm volatile("vse64.v v8, (%0);" ::"r"(res3));
  verify_result_64(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=512 PRELOADED\n");
  printf("======================\n");
  VSET(VL_MAX_64, e64, m8);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle64.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfadd.vv v16, v0, v8");
  asm volatile("vfredsum.vs v16, v0, v8");
  asm volatile("vse64.v v16, (%0);" ::"r"(res4));
  verify_result_64(vec4, vec4[0], VL_MAX_64, res4[0]);
  printf("\n");
  printf("\n");
}

void vfredosum_64() {
  printf("\n");
  printf("======================\n");
  printf("VFREDOSUM EW64\n");
  printf("======================\n");
  printf("\n");
  printf("\n");

  double vec1[VL_S], res1[VL_S];
  double vec2[VL_M], res2[VL_M];
  double vec3[VL_L], res3[VL_L];
  double vec4[VL_MAX_64], res4[VL_MAX_64];
  gen_rand_vec_64(vec1, VL_S);
  gen_rand_vec_64(vec2, VL_M);
  gen_rand_vec_64(vec3, VL_L);
  gen_rand_vec_64(vec4, VL_MAX_64);

  printf("======================\n");
  printf("VL=32\n");
  printf("======================\n");
  VSET(VL_S, e64, m1);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle64.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse64.v v2, (%0);" ::"r"(res1));
  verify_result_64(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128\n");
  printf("======================\n");
  VSET(VL_M, e64, m2);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle64.v v2, (%0);" ::"r"(vec2));
  asm volatile("vfredosum.vs v4, v0, v2");
  asm volatile("vse64.v v4, (%0);" ::"r"(res2));
  verify_result_64(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256\n");
  printf("======================\n");
  VSET(VL_L, e64, m4);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec3));
  asm volatile("vle64.v v4, (%0);" ::"r"(vec3));
  asm volatile("vfredosum.vs v8, v0, v4");
  asm volatile("vse64.v v8, (%0);" ::"r"(res3));
  verify_result_64(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=512\n");
  printf("======================\n");
  VSET(VL_MAX_64, e64, m8);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle64.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfredosum.vs v16, v0, v8");
  asm volatile("vse64.v v16, (%0);" ::"r"(res4));
  verify_result_64(vec4, vec4[0], VL_MAX_64, res4[0]);
  printf("\n");
  printf("\n");

  // Issue a redundant vector add instruction to eliminate
  // the effect of stalls due to data denpendencies
  printf("======================\n");
  printf("VL=32 PRELOADED\n");
  printf("======================\n");
  VSET(VL_S, e64, m1);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec1));
  asm volatile("vle64.v v1, (%0);" ::"r"(vec1));
  asm volatile("vfadd.vv v2, v0, v1");
  asm volatile("vfredosum.vs v2, v0, v1");
  asm volatile("vse64.v v2, (%0);" ::"r"(res1));
  verify_result_64(vec1, vec1[0], VL_S, res1[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=128 PRELOADED\n");
  printf("======================\n");
  VSET(VL_M, e64, m2);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec2));
  asm volatile("vle64.v v2, (%0);" ::"r"(vec2));
  asm volatile("vfadd.vv v4, v0, v2");
  asm volatile("vfredosum.vs v4, v0, v2");
  asm volatile("vse64.v v4, (%0);" ::"r"(res2));
  verify_result_64(vec2, vec2[0], VL_M, res2[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=256 PRELOADED\n");
  printf("======================\n");
  VSET(VL_L, e64, m4);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec3));
  asm volatile("vle64.v v4, (%0);" ::"r"(vec3));
  asm volatile("vfadd.vv v8, v0, v4");
  asm volatile("vfredosum.vs v8, v0, v4");
  asm volatile("vse64.v v8, (%0);" ::"r"(res3));
  verify_result_64(vec3, vec3[0], VL_L, res3[0]);
  printf("\n");
  printf("\n");

  printf("======================\n");
  printf("VL=512 PRELOADED\n");
  printf("======================\n");
  VSET(VL_MAX_64, e64, m8);
  asm volatile("vle64.v v0, (%0);" ::"r"(vec4));
  asm volatile("vle64.v v8, (%0);" ::"r"(vec4));
  asm volatile("vfadd.vv v16, v0, v8");
  asm volatile("vfredosum.vs v16, v0, v8");
  asm volatile("vse64.v v16, (%0);" ::"r"(res4));
  verify_result_64(vec4, vec4[0], VL_MAX_64, res4[0]);
  printf("\n");
  printf("\n");
}

int main() {
  vfredusum_32();
  vfredosum_32();
  vfredusum_64();
  vfredosum_64();
  return 0;
}
