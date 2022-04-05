// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

#ifndef __VECTOR_MACROS_H__
#define __VECTOR_MACROS_H__

#include <stdint.h>
#include "dataset.h"
#include "rvv_debug_macros.h"
#include "encoding.h"
#include "float_conversion.h"

#ifdef __SPIKE__
#include <stdio.h>

// We need to activate the FP and V extensions manually
#define enable_vec() do { asm volatile ("csrs mstatus, %[bits];" :: [bits] "r" (MSTATUS_VS & (MSTATUS_VS >> 1))); } while (0);
#define enable_fp()  do { asm volatile ("csrs mstatus, %[bits];" :: [bits] "r" (MSTATUS_FS & (MSTATUS_FS >> 1))); } while (0);
#else
#include <printf.h>

// The FP and V extensions are activated in the crt0 script
#define enable_vec()
#define enable_fp()
#endif

/**************
 *  Counters  *
 **************/

// Counter for how many tests have failed
int num_failed;
// Pointer to the current test case
int test_case;

/************
 *  Macros  *
 ************/

#define read_vtype(buf) do { asm volatile ("csrr %[BUF], vtype" : [BUF] "=r" (buf)); } while (0);
#define read_vl(buf)    do { asm volatile ("csrr %[BUF], vl" : [BUF] "=r" (buf)); } while (0);
#define read_vxsat(buf) do { asm volatile ("csrr %[BUF], vxsat" : [BUF] "=r" (buf)); } while (0);
#define set_vxrm(val) do { asm volatile ("csrw vxrm, %0" :: "rK"(val)); } while (0);

#define vtype(golden_vtype, vlmul, vsew, vta, vma) (golden_vtype = vlmul << 0 | vsew << 3 | vta << 6 | vma << 7)

#define check_vtype_vl(casenum, vtype, golden_vtype, avl, vl)                                                      \
  printf("Checking vtype and vl #%d...\n", casenum);                                                               \
  if (vtype != golden_vtype || avl != vl) {                                                                        \
    printf("FAILED. Got vtype = %lx, expected vtype = %lx. avl = %lx, vl = %lx.\n", vtype, golden_vtype, avl, vl); \
    num_failed++;                                                                                                  \
    return;                                                                                                        \
  }                                                                                                                \
  printf("PASSED.\n");

#define check_vxsat(casenum, vxsat, golden_vxsat)                                                                  \
  printf("Checking vxsat #%d...\n", casenum);                                                               \
  if (vxsat != golden_vxsat) {                                                                        \
    printf("FAILED. Got vxsat = %lx, expected vxsat = %lx.\n", vxsat, golden_vxsat); \
    num_failed++;                                                                                                  \
    return;                                                                                                        \
  }                                                                                                                \
  printf("PASSED.\n");

// In order to avoid that scalar loads run ahead of vector stores,
// we use an instruction to ensure that all vector stores have been
// committed before continuing with scalar memory operations.
#define MEMORY_BARRIER // asm volatile ("fence");

// Zero-initialized variables can be problematic on bare-metal.
// Therefore, initialize them during runtime.
#define INIT_CHECK()  \
  num_failed = 0;     \
  test_case  = 0;     \

// Check at the final of the execution whether all the tests passed or not.
// Returns the number of failed tests.
#define EXIT_CHECK()                                                \
  do {                                                              \
    MEMORY_BARRIER;                                                 \
    if (num_failed > 0) {                                           \
      printf("ERROR: %s failed %d tests!\n", __FILE__, num_failed); \
      return num_failed;                                            \
    }                                                               \
    else {                                                          \
      printf("PASSED: %s!\n", __FILE__);                            \
      return 0;                                                     \
    }                                                               \
  } while(0);                                                       \

// Check the result against a scalar golden value
#define XCMP(casenum,act,exp)                                           \
  printf("Checking the results of the test case %d:\n", casenum);       \
  if (act != exp) {                                                     \
    printf("Index %d FAILED. Got %d, expected %d.\n", casenum, act, exp);\
    num_failed++;                                                       \
    return;                                                             \
  }                                                                     \
  printf("PASSED.\n");                                                  \

// Check the result against a floating-point scalar golden value
#define FCMP(casenum,act,exp)                                           \
  if(act != exp) {                                                      \
    printf("Index %d FAILED. Got %lf, expected %lf.\n",casenum, act, exp);       \
    num_failed++;                                                       \
    return;                                                             \
  }                                                                     \
  printf("PASSED.\n");

// Check the results against a vector of golden values
#define VCMP(T,str,casenum,vexp,act...)                                               \
  T vact[] = {act};                                                                   \
  printf("Checking the results of the test case %d:\n", casenum);                     \
  MEMORY_BARRIER;                                                                     \
  for (unsigned int i = 0; i < sizeof(vact)/sizeof(T); i++) {                         \
    if (vexp[i] != vact[i]) {                                                         \
      printf("Index %d FAILED. Got "#str", expected "#str".\n", i, vexp[i], vact[i]); \
      num_failed++;                                                                   \
      return;                                                                         \
    }                                                                                 \
  }                                                                                   \
  printf("PASSED.\n");

// Check the results against an in-memory vector of golden values
#define VMCMP(T,str,casenum,vexp,vgold,size)                                          \
  printf("Checking the results of the test case %d:\n", casenum);                     \
  MEMORY_BARRIER;                                                                     \
  for (unsigned int i = 0; i < size; i++) {                                           \
    if (vexp[i] != vgold[i]) {                                                        \
      printf("Index %d FAILED. Got "#str", expected "#str".\n", i, vexp[i], vgold[i]);\
      num_failed++;                                                                   \
      return;                                                                         \
    }                                                                                 \
  }                                                                                   \
  printf("PASSED.\n");

// Macros to set vector length, type and multiplier
// Don't use this to set VL == 0 since the compiler puts rs1 == x0
#define VSET(VLEN,VTYPE,LMUL)                                                          \
  do {                                                                                 \
  asm volatile ("vsetvli t0, %[A]," #VTYPE "," #LMUL ", ta, ma \n" :: [A] "r" (VLEN)); \
  } while(0)

// Macros to set vector length equal to zero
#define VSET_ZERO(VTYPE,LMUL)                                                              \
  do {                                                                                     \
    int vset_zero_buf;                                                                     \
    asm volatile("li %0, 0" : "=r" (vset_zero_buf));                                       \
    asm volatile("vsetvli x0, %0," #VTYPE "," #LMUL ", ta, ma \n" :: "r" (vset_zero_buf)); \
  } while(0)

#define VSETMAX(VTYPE,LMUL)                                                            \
  do {                                                                                 \
  int64_t scalar = -1;                                                                 \
  asm volatile ("vsetvli t1, %[A]," #VTYPE "," #LMUL", ta, ma \n":: [A] "r" (scalar)); \
  } while(0)

// Macro to load a vector register with data from the stack
#define VLOAD(datatype,loadtype,vreg,vec...)                                \
  do {                                                                      \
    volatile datatype V ##vreg[] = {vec};                                   \
    MEMORY_BARRIER;                                                         \
    asm volatile ("vl"#loadtype".v "#vreg", (%0)  \n":: [V] "r"(V ##vreg)); \
  } while(0)

// Macro to store a vector register into the pointer vec
#define VSTORE(T, storetype, vreg, vec)                                   \
  do {                                                                    \
    T* vec ##_t = (T*) vec;                                               \
    asm volatile ("vs"#storetype".v "#vreg", (%0)\n" : "+r" (vec ##_t));  \
    MEMORY_BARRIER;                                                       \
  } while(0)

// Macro to reset the whole register back to zero
#define VCLEAR(register)                                                                          \
  do {                                                                                            \
    MEMORY_BARRIER;                                                                               \
    uint64_t vtype; uint64_t vl; uint64_t vlmax;                                                  \
    asm volatile("csrr %[vtype], vtype" : [vtype] "=r" (vtype));                                  \
    asm volatile("csrr %[vl], vl" : [vl] "=r" (vl));                                              \
    asm volatile("vsetvl %[vlmax], zero, %[vtype]" : [vlmax] "=r" (vlmax) : [vtype] "r" (vtype)); \
    asm volatile("vmv.v.i "#register", 0");                                                       \
    asm volatile("vsetvl zero, %[vl], %[vtype]" :: [vl] "r" (vl), [vtype] "r" (vtype));           \
  } while(0)

// Macro to initialize a vector with progressive values from a counter
#define INIT_MEM_CNT(vec_name, size) \
  counter = 0;                          \
  for (int i = 0 ; i < size; i++) {     \
    vec_name[i] = counter;              \
    counter++;                          \
  }                                     \

// Macro to initialize a vector with zeroes
// The vector is initialized on the stack, use this function with caution
// Easy to go in the UART address space
#define INIT_MEM_ZEROES(vec_name, size) \
  for (int i = 0 ; i < size; i++) {        \
    vec_name[i] = 0;                       \
  }                                        \

/***************************
 *  Type-dependant macros  *
 ***************************/

// Vector comparison
#define VCMP_U64(casenum,vect,act...) {VSTORE_U64(vect); VCMP(uint64_t,%lu, casenum,Ru64,act)}
#define VCMP_U32(casenum,vect,act...) {VSTORE_U32(vect); VCMP(uint32_t,%u,  casenum,Ru32,act)}
#define VCMP_U16(casenum,vect,act...) {VSTORE_U16(vect); VCMP(uint16_t,%hu, casenum,Ru16,act)}
#define VCMP_U8(casenum,vect,act...)  {VSTORE_U8(vect);  VCMP(uint8_t, %hhu,casenum,Ru8, act)}

#define VVCMP_U64(casenum,ptr64,act...) {VCMP(uint64_t,%lu,casenum,ptr64,act)}
#define VVCMP_U32(casenum,ptr32,act...) {VCMP(uint32_t,%u, casenum,ptr32,act)}
#define VVCMP_U16(casenum,ptr16,act...) {VCMP(uint16_t,%hu,casenum,ptr16,act)}
#define VVCMP_U8(casenum,ptr8,act...)  {VCMP(uint8_t, %hhu,casenum,ptr8, act)}

#define VCMP_I64(casenum,vect,act...) {VSTORE_I64(vect); VCMP(int64_t,%ld, casenum,Ri64,act)}
#define VCMP_I32(casenum,vect,act...) {VSTORE_I32(vect); VCMP(int32_t,%d,  casenum,Ri32,act)}
#define VCMP_I16(casenum,vect,act...) {VSTORE_I16(vect); VCMP(int16_t,%hd, casenum,Ri16,act)}
#define VCMP_I8(casenum,vect,act...)  {VSTORE_I8(vect);  VCMP(int8_t, %hhd,casenum,Ri8, act)}

#define VCMP_F64(casenum,vect,act...) {VSTORE_F64(vect); VCMP(double,%lf,casenum,Rf64,act)}
#define VCMP_F32(casenum,vect,act...) {VSTORE_F32(vect); VCMP(float, %f, casenum,Rf32,act)}

// Vector load
#define VLOAD_64(vreg,vec...) VLOAD(uint64_t,e64,vreg,vec)
#define VLOAD_32(vreg,vec...) VLOAD(uint32_t,e32,vreg,vec)
#define VLOAD_16(vreg,vec...) VLOAD(uint16_t,e16,vreg,vec)
#define VLOAD_8(vreg,vec...)  VLOAD(uint8_t, e8, vreg,vec)

// Vector store
#define VSTORE_U64(vreg) VSTORE(uint64_t,e64,vreg,Ru64)
#define VSTORE_U32(vreg) VSTORE(uint32_t,e32,vreg,Ru32)
#define VSTORE_U16(vreg) VSTORE(uint16_t,e16,vreg,Ru16)
#define VSTORE_U8(vreg)  VSTORE(uint8_t ,e8 ,vreg,Ru8 )

#define VSTORE_I64(vreg) VSTORE(int64_t,e64,vreg,Ri64)
#define VSTORE_I32(vreg) VSTORE(int32_t,e32,vreg,Ri32)
#define VSTORE_I16(vreg) VSTORE(int16_t,e16,vreg,Ri16)
#define VSTORE_I8(vreg)  VSTORE(int8_t ,e8 ,vreg,Ri8 )

#define VSTORE_F64(vreg) VSTORE(double,e64,vreg,Rf64)
#define VSTORE_F32(vreg) VSTORE(float, e32,vreg,Rf32)

#endif // __VECTOR_MACROS_H__
