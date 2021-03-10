// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>
//         Matteo Perotti <mperotti@student.ethz.ch>

#include "vector_macros.h"
#include "float_macros.h"

void TEST_CASE1(void) {
  VSET(16, e16, m1);
  //              -0.1481, -0.1797, -0.5454,  0.3228,  0.3237, -0.7212, -0.5195, -0.4500,  0.2681,  0.7300,  0.5059,  0.5830,  0.3198, -0.1713, -0.6431,  0.4841
  VLOAD_16(v2,     0xb0bd,  0xb1c0,  0xb85d,  0x352a,  0x352e,  0xb9c5,  0xb828,  0xb733,  0x344a,  0x39d7,  0x380c,  0x38aa,  0x351e,  0xb17b,  0xb925,  0x37bf);
  double dscalar_16;
  //                            -0.9380
  BOX_HALF_IN_DOUBLE(dscalar_16, 0xbb81);
  VLOAD_8(v0, 0x0F, 0xAA);
  asm volatile("vfmerge.vfm v1, v2, %[A], v0" :: [A] "f" (dscalar_16));
  //               -0.9380, -0.9380, -0.9380, -0.9380,  0.3237, -0.7212, -0.5195, -0.4500,  0.2681, -0.9380,  0.5059, -0.9380,  0.3198, -0.9380, -0.6431, -0.9380
  VCMP_U16(1, v1,  0xbb81,  0xbb81,  0xbb81,  0xbb81,  0x352e,  0xb9c5,  0xb828,  0xb733,  0x344a,  0xbb81,  0x380c,  0xbb81,  0x351e,  0xbb81,  0xb925,  0xbb81);

  VSET(16, e32, m1);
  //               0.86539453, -0.53925377, -0.47128764,  0.99265540,  0.32128176, -0.47335613, -0.30028856,  0.44394016, -0.72540921, -0.26464799,  0.77351445, -0.21725702, -0.25191557, -0.53123665,  0.80404943,  0.81841671
  VLOAD_32(v2,     0x3f5d8a7f,  0xbf0a0c89,  0xbef14c9d,  0x3f7e1eaa,  0x3ea47f0b,  0xbef25bbc,  0xbe99bf6c,  0x3ee34c20,  0xbf39b46b,  0xbe877ff1,  0x3f46050b,  0xbe5e78a0,  0xbe80fb14,  0xbf07ff20,  0x3f4dd62f,  0x3f5183c2);
  double dscalar_32;
  //                             -0.96056187
  BOX_FLOAT_IN_DOUBLE(dscalar_32, 0xbf75e762);
  VLOAD_8(v0, 0x0F, 0xAA);
  asm volatile("vfmerge.vfm v1, v2, %[A], v0" :: [A] "f" (dscalar_32));
  //               -0.96056187, -0.96056187, -0.96056187, -0.96056187,  0.32128176, -0.47335613, -0.30028856,  0.44394016, -0.72540921, -0.96056187,  0.77351445, -0.96056187, -0.25191557, -0.96056187,  0.80404943, -0.96056187
  VCMP_U32(2, v1,  0xbf75e762,  0xbf75e762,  0xbf75e762,  0xbf75e762,  0x3ea47f0b,  0xbef25bbc,  0xbe99bf6c,  0x3ee34c20,  0xbf39b46b,  0xbf75e762,  0x3f46050b,  0xbf75e762,  0xbe80fb14,  0xbf75e762,  0x3f4dd62f,  0xbf75e762);

  VSET(16, e64, m1);
  //               -0.3488917150781869, -0.4501495513738740,  0.8731197104152684,  0.3256432550932964,  0.6502591178769535, -0.3169358689246526, -0.5396694979141685, -0.5417807430937591, -0.7971574213160249, -0.1764794100111047,  0.3564275916066595, -0.3754449946313438,  0.6580947137446858, -0.3328857144699515,  0.1761214464164236,  0.1429774118511240
  VLOAD_64(v2,      0xbfd6543dea86cb60,  0xbfdccf40105d6e5c,  0x3febf098bf37400c,  0x3fd4d756ceb279f4,  0x3fe4ceec35a6a266,  0xbfd448ad61fd7c88,  0xbfe144f8f7861540,  0xbfe1564491a616b8,  0xbfe9825047ca1cd6,  0xbfc696e097352100,  0x3fd6cfb5ac55edec,  0xbfd8074a7158dd78,  0x3fe50f1ca5268668,  0xbfd54dffe23d0eec,  0x3fc68b25c63dcaf0,  0x3fc24d1575fbd080);
  double dscalar_64;
  //                               0.9108707261227378
  BOX_DOUBLE_IN_DOUBLE(dscalar_64, 0x3fed25da5d7296fe);
  VLOAD_8(v0, 0x0F, 0xAA);
  asm volatile("vfmerge.vfm v1, v2, %[A], v0" :: [A] "f" (dscalar_64));
  //                0.9108707261227378,  0.9108707261227378,  0.9108707261227378,   0.9108707261227378,  0.6502591178769535, -0.3169358689246526, -0.5396694979141685, -0.5417807430937591  -0.7971574213160249,  0.9108707261227378,  0.3564275916066595,  0.9108707261227378,  0.6580947137446858,  0.9108707261227378,  0.1761214464164236,  0.9108707261227378
  VCMP_U64(3, v1,  0x3fed25da5d7296fe,  0x3fed25da5d7296fe,  0x3fed25da5d7296fe,   0x3fed25da5d7296fe,  0x3fe4ceec35a6a266,  0xbfd448ad61fd7c88,  0xbfe144f8f7861540,  0xbfe1564491a616b8,  0xbfe9825047ca1cd6,  0x3fed25da5d7296fe,  0x3fd6cfb5ac55edec,  0x3fed25da5d7296fe,  0x3fe50f1ca5268668,  0x3fed25da5d7296fe,  0x3fc68b25c63dcaf0,  0x3fed25da5d7296fe);
};

int main(void){
  enable_vec();
  enable_fp();

  TEST_CASE1();

  EXIT_CHECK();
}
