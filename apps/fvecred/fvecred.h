/*=================================================================================================
Project Name:    Ara
Author:          Xiaorui Yin <yinx@student.ethz.ch>
Organization:    ETH Zürich
File Name:       fvecred.h
Created On:      2022/05/22

Description:

CopyRight Notice
All Rights Reserved
===================================================================================================
Modification    History:
Date            By              Version         Change Description
---------------------------------------------------------------------------------------------------

=================================================================================================*/

#ifndef FVECRED_H

// Marcos copied from riscv_tests
#define VSET(VLEN, VTYPE, LMUL)                                                \
  do {                                                                         \
    asm volatile("vsetvli t0, %[A]," #VTYPE "," #LMUL                          \
                 ", ta, ma \n" ::[A] "r"(VLEN));                               \
  } while (0)

#endif // !FVECRED_H
