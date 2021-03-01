// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

#ifndef __RVV_DEBUG_MACROS__
#define __RVV_DEBUG_MACROS__

//Functions to print buffers
#define PRINT_BUFFER_U64(A)                                    \
  do {                                                         \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(uint64_t); i++) \
    VPRINTF("%016x\n",A[i]);                                   \
    MEMBARRIER;                                                \
  } while(0)

#define PRINT_BUFFER_U32(A)                                    \
  do {                                                         \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(uint32_t); i++) \
    VPRINTF("%08x\n",A[i]);                                    \
    MEMBARRIER;                                                \
  } while(0)

#define PRINT_BUFFER_U16(A)                                    \
  do {                                                         \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(uint16_t); i++) \
    VPRINTF("%04x\n",A[i]);                                    \
    MEMBARRIER;                                                \
  } while(0)

#define PRINT_BUFFER_U8(A)                                    \
  do {                                                        \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(uint8_t); i++) \
    VPRINTF("%02x\n",A[i]);                                   \
    MEMBARRIER;                                               \
  } while(0)

#define PRINT_BUFFER_F64(A)                                   \
  do {                                                        \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(double); i++)  \
    VPRINTF("Buffer Debug %d: %.17g\n",i,A[i]);               \
    MEMBARRIER;                                               \
  } while(0)

#define PRINT_BUFFER_F32(A)                                   \
  do {                                                        \
  for(unsigned int i = 0; i < sizeof(A)/sizeof(float); i++)   \
    VPRINTF("Buffer Debug %d: %0.9g\n",i,A[i]);               \
    MEMBARRIER;                                               \
  } while(0)

//Debuging Macros

#define DEBUG_F64(register)               \
  do {                                    \
  double buffer ##register[VLEN_CUR];     \
  VSTORE_64(register,buffer ##register);  \
  PRINT_BUFFER_F64(buffer ##register);    \
  } while(0)

#define DEBUG_F32(register)               \
  do {                                    \
  float buffer ##register[VLEN_CUR];      \
  VSTORE_32(register,buffer ##register);  \
  PRINT_BUFFER_F32(buffer ##register);    \
  } while(0)

#define DEBUG_U8(register)               \
  do {                                   \
  uint8_t buffer ##register[VLEN_CUR];   \
  VSTORE_8(register,buffer ##register);  \
  PRINT_BUFFER_U8(buffer ##register);    \
  } while(0)


#define DEBUG_8(register) DEBUG_U8(register)

#define DEBUG_U16(register)               \
  do {                                    \
  uint16_t buffer ##register[VLEN_CUR];   \
  VSTORE_16(register,buffer ##register);  \
  PRINT_BUFFER_U16(buffer ##register);    \
  } while(0)

#define DEBUG_16(register) DEBUG_U16(register)

#define DEBUG_U32(register)               \
  do {                                    \
  uint32_t buffer ##register[VLEN_CUR];   \
  VSTORE_32(register,buffer ##register);  \
  PRINT_BUFFER_U32(buffer ##register);    \
  } while(0)

#define DEBUG_32(register) DEBUG_U32(register)

#define DEBUG_U64(register)               \
  do {                                    \
  uint64_t buffer ##register[VLEN_CUR];   \
  VSTORE_64(register,buffer ##register);  \
  PRINT_BUFFER_U64(buffer ##register);    \
  } while(0)

#define DEBUG_64(register) DEBUG_U64(register)

#endif // __RVV_DEBUG_MACROS__
