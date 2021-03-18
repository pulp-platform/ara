#ifndef _ENV_ARIANE_H
#define _ENV_ARIANE_H

#include "encoding.h"

//-----------------------------------------------------------------------
// Begin Macro
//-----------------------------------------------------------------------

#define RVTEST_RV64U

#define RVTEST_RV64UF                                                          \
  .globl rvtest_init;                                                          \
  rvtest_init:                                                                 \
  RVTEST_FP_ENABLE;                                                            \
  ret

#define RVTEST_RV64UV                                                          \
  .globl rvtest_init;                                                          \
  rvtest_init:                                                                 \
  RVTEST_VECTOR_ENABLE;
ret

#define RVTEST_RV64M                                                           \
  .globl rvtest_init;                                                          \
  rvtest_init:                                                                 \
  RVTEST_ENABLE_MACHINE;                                                       \
  ret

#define RVTEST_RV64S                                                           \
  .globl rvtest_init;                                                          \
  rvtest_init:                                                                 \
  RVTEST_ENABLE_SUPERVISOR;                                                    \
  ret

#define RVTEST_ENABLE_SUPERVISOR                                               \
  li a0, MSTATUS_MPP &(MSTATUS_MPP >> 1);                                      \
  csrs mstatus, a0;                                                            \
  li a0, SIP_SSIP | SIP_STIP;                                                  \
  csrs mideleg, a0;

#define RVTEST_ENABLE_MACHINE                                                  \
  li a0, MSTATUS_MPP;                                                          \
  csrs mstatus, a0;

#define RVTEST_FP_ENABLE                                                       \
  li a0, MSTATUS_FS &(MSTATUS_FS >> 1);                                        \
  csrs mstatus, a0;                                                            \
  csrwi fcsr, 0

#define RVTEST_VECTOR_ENABLE                                                   \
  li a0, (MSTATUS_VS & (MSTATUS_VS >> 1)) | (MSTATUS_FS & (MSTATUS_FS >> 1));  \
  csrs mstatus, a0;                                                            \
  csrwi fcsr, 0;                                                               \
  csrwi vcsr, 0;

#define RISCV_MULTICORE_DISABLE                                                \
  csrr a0, mhartid;                                                            \
  1 : bnez a0, 1b

#define RVTEST_CODE_BEGIN                                                      \
  .globl main;                                                                 \
  .align 2;                                                                    \
  main:

//-----------------------------------------------------------------------
// End Macro
//-----------------------------------------------------------------------

#define RVTEST_CODE_END unimp

//-----------------------------------------------------------------------
// Pass/Fail Macro
//-----------------------------------------------------------------------

#define RVTEST_PASS                                                            \
  li a0, 0;                                                                    \
  j _eoc

#define TESTNUM gp
#define RVTEST_FAIL                                                            \
  fence;                                                                       \
  1 : beqz TESTNUM, 1b;                                                        \
  sll TESTNUM, TESTNUM, 1;                                                     \
  or TESTNUM, TESTNUM, 1;                                                      \
  addi a0, TESTNUM, 0;                                                         \
  j _fail

//-----------------------------------------------------------------------
// Data Section Macro
//-----------------------------------------------------------------------

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END

#endif
