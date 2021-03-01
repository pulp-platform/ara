// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Basile Bougenot <bbougenot@student.ethz.ch>

#include "vector_macros.h"

void TEST_CASE1() {
  VSET(4,e32,m1);
  VLOAD_F32(v4,_f(9.812321).i,_f(3.14159265).i,_f(-6.432423).i,_f(-190.53).i);
  VLOAD_F32(v6,_f(16.2321).i,_f(1.149265).i,_f(-19.431223).i,_f(-122.63).i);
  __asm__ volatile ("vfwmul.vv v2, v4, v6");
  VSET(4,e64,m1);
  VEC_CMP_F64(1,v2,_d(159.27456640270975).i,_d(3.6105227413693797).i,_d(124.98984743100027).i,_d(23364.693226998905).i);
}


// void TEST_CASE2() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(9.812321).i,_f(3.14159265).i,_f(-6.432423).i,_f(-190.53).i);
//   VLOAD_F32(v6,_f(16.2321).i,_f(1.149265).i,_f(-19.431223).i,_f(-122.63).i);
//   VLOAD_U32(v0,13,0,0,0);
//   CLEAR(v2);
//   __asm__ volatile ("vfwmul.vv v2, v4, v6, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(2,v2,_d(159.27456640270975).i,_d(0).i,_d(124.98984743100027).i,_d(23364.693226998905).i);
// }

void TEST_CASE3() {
  VSET(4,e32,m1);
  VLOAD_F32(v4,_f(9.812321).i,_f(3.14159265).i,_f(-6.432423).i,_f(-190.53).i);
  FLOAD32(f10,_f(7.34253).i);
  __asm__ volatile ("vfwmul.vf v2, v4, f10");
  VSET(4,e64,m1);
  VEC_CMP_F64(3,v2,_d(72.047256956722777).i,_d(23.067238237762808).i,_d(-47.230258237361568).i,_d(-1398.9721888223285).i);
}


// void TEST_CASE4() {
//   VSET(4,e32,m1);
//   VLOAD_F32(v4,_f(9.812321).i,_f(3.14159265).i,_f(-6.432423).i,_f(-190.53).i);
//   VLOAD_U32(v0,13,0,0,0);
//   FLOAD32(f10,_f(7.34253).i);
//   CLEAR(v2);
//   __asm__ volatile ("vfwmul.vf v2, v4, f10, v0.t");
//   VSET(4,e64,m1);
//   VEC_CMP_F64(4,v2,_d(72.047256956722777).i,_d(0).i,_d(-47.230258237361568).i,_d(-1398.9721888223285).i);
// }


int main(void){
  INIT_CHECK();
  enable_vec();
  enable_fp();
  TEST_CASE1();
  TEST_CASE3();
  // TEST_CASE2();
  // TEST_CASE4();
  EXIT_CHECK();
}
