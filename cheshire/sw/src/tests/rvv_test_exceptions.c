// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Vincenzo Maisto <vincenzo.maisto2@unina.it>

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "params.h"
#include "util.h"
#include "encoding.h"
#include "rvv_test.h"

#include "cheshire_util.h"

uint64_t dummy[3];

int main(void) {
    cheshire_start();

    // Vector configuration parameters and variables
    uint64_t avl = RVV_TEST_AVL(64);
    uint64_t vl;
    vcsr_dump_t vcsr_state = {0};

    // Helper variables and arrays
    uint64_t array_load [RVV_TEST_AVL(64)];
    uint64_t array_store [RVV_TEST_AVL(64)] = {0};
    uint64_t* address_load = array_load;
    uint64_t* address_store = array_store;
    uint64_t* address_misaligned;
    uint64_t vstart_read;

    RVV_TEST_CLEAN_EXCEPTION();
    INIT_RVV_TEST_SOC_REGFILE;
    RESET_SOC_CSR;

    // Enalbe RVV
    enable_rvv();
    vcsr_dump ( vcsr_state );

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    // START OF TESTS
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////
    // TEST: Legal encoding
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    asm volatile("vmv.v.i   v0 ,  1");
    RVV_TEST_ASSERT_EXCEPTION(0)

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: Illegal encoding
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    asm volatile("vmv.v.i   v1 ,  1");
    RVV_TEST_ASSERT_EXCEPTION(1)
    RVV_TEST_CLEAN_EXCEPTION()

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: vstart update
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    vstart_read = -1;
    // CSR <-> vector instrucitons
    asm volatile ("csrs  vstart, 1");
    asm volatile ("csrr  %0, vstart" : "=r"(vstart_read));
    RVV_TEST_ASSERT ( vstart_read == (uint64_t)1 );

    //////////////////////////////////////////////////////////////////
    // TEST: vstart automatic reset
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    // NOTE: This relied on non-zero vstart support for arithmetic instructions, i.e., operand request
    // NOTE2: supporting vstart != 0 for arithmetic instructions is NOT a spec requirement
    asm volatile ("vmv.v.i  v24, -1");
    asm volatile ("csrs     vstart, 1");
    asm volatile ("vadd.vv  v0, v24, v24");
    asm volatile ("csrr     %0, vstart" : "=r"(vstart_read));
    RVV_TEST_ASSERT ( vstart_read == (uint64_t)0 );

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: These instructions should WB asap to ROB
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    // Vector permutation/arithmetic
    asm volatile("vmv.v.i   v0 ,  1");
    asm volatile("csrr      %0 , vl" : "=r"(vl));

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: These intructions should WB to CVA6 only after WB from PEs
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    address_load = array_load;
    // initialize
    for ( uint64_t i = 0; i < vl; i++ ) {
        array_load[i] = -i;
    }

    // Vector load
    _VLD(v24, address_load)
    // Vector store
    _VST(v16, address_store)
    // Vector load
    _VLD(v8, address_load)

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: Legal non-zero vstart on vector instructions
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    asm volatile("csrs     vstart, 3");
    asm volatile("vadd.vv	 v24   , v16, v16");
    RVV_TEST_ASSERT_EXCEPTION(0)

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: Legal non-zero vstart on vector CSR
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, avl );

    asm volatile("csrs     vstart, 3");
    asm volatile("vsetvli  x0    , x0, e64, m8, ta, ma" );
    RVV_TEST_ASSERT_EXCEPTION(0)

    asm volatile("csrs     vstart, 22");
    _VLD(v24, address_load)
    RVV_TEST_ASSERT_EXCEPTION(0)

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: EEW misaligned loads
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, 1 );

    // Get a valid byte-misaligned address
    address_misaligned = (void*)(((uint64_t)(&dummy[1]) | 1));
    // Exception only for EEW > 8
    _VLD(v16, address_misaligned)
    if (EEW > 8) {
      RVV_TEST_ASSERT_EXCEPTION(1)
    } else {
      RVV_TEST_ASSERT_EXCEPTION(0)
    }
    RVV_TEST_CLEAN_EXCEPTION()

    RVV_TEST_CLEANUP();

    //////////////////////////////////////////////////////////////////
    // TEST: EEW misaligned stores
    //////////////////////////////////////////////////////////////////
    RVV_TEST_INIT( vl, 1 );

    // Get a byte-misaligned address
    address_misaligned = (void*)(((uint64_t)(&dummy[1]) | 1));
    // Exception only for EEW > 8
    _VST(v24, address_misaligned)
    if (EEW > 8) {
      RVV_TEST_ASSERT_EXCEPTION(1)
    } else {
      RVV_TEST_ASSERT_EXCEPTION(0)
    }
    RVV_TEST_CLEAN_EXCEPTION()

    RVV_TEST_CLEANUP();

    ////////////////////////////////////////////////////////////////////
    // Missing tests for unimplemented features:
    // TEST: Illegal non-zero vstart
    ////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    // END OF TESTS
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////

#if (PRINTF == 1)
    printf("Test SUCCESS!\r\n");
#endif

  cheshire_end();

  return 0;
}
