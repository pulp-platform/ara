// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti  <mperotti@iis.ee.ethz.ch>
// Vincenzo Maisto <vincenzo.maisto2@unina.it>

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "params.h"
#include "util.h"
#include "encoding.h"
#include "rvv_test.h"

#include "cheshire_util.h"

#define INIT_NONZERO_VAL_V0 99

// Derived parameters
uint64_t stub_req_rsp_lat = 10;

int main(void) {
    cheshire_start();

    // This initialization is controlled through "defines" in the various
    // derived tests.
    INIT_RVV_TEST_SOC_REGFILE;
    VIRTUAL_MEMORY_ON;
    STUB_EX_OFF;
    STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

    // Vector configuration parameters and variables
    uint64_t avl_original = RVV_TEST_AVL(64);
    uint64_t vl, vstart_read;
    vcsr_dump_t vcsr_state = {0};

    // Helper variables and arrays
    _DTYPE array_load [VLMAX];
    _DTYPE array_store [VLMAX];
    _DTYPE* address_load = array_load;
    _DTYPE* address_store = array_store;

    // Enalbe RVV
    enable_rvv();
    vcsr_dump ( vcsr_state );

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    // START OF TESTS
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////
    // TEST: vstore, vl >= 0, vstart >= vl
    //////////////////////////////////////////////////////////////////

    // Loop through different avl, from 0 to avlmax
    for (uint64_t avl = 0; avl <= ARA_NR_LANES + 2; avl++) {
      // Reset vl, vstart, reset exceptions.
      RVV_TEST_INIT(vl, avl);
      for (uint64_t vstart_val = vl; vstart_val <= vl + ARA_NR_LANES + 2; vstart_val++) {
        // Reset vl, vstart, reset exceptions.
        RVV_TEST_INIT(vl, avl);
        STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

        // Init memory
        for (uint64_t i = 0; i < ARA_NR_LANES + 1; i++) {
          address_store[i] = INIT_NONZERO_VAL_ST;
        }
        asm volatile("vmv.v.x v0, %0" :: "r" (INIT_NONZERO_VAL_V0));

        // Setup vstart
        asm volatile("csrs vstart, %0" :: "r"(vstart_val));
        // Store
        _VST(v0, address_store)

        // Check that vstart was reset at zero
        vstart_read = -1;
        asm volatile("csrr %0, vstart" : "=r"(vstart_read));
        ASSERT_EQ(vstart_read, 0)
        // Check that there was no exception
        RVV_TEST_ASSERT_EXCEPTION(0)
        RVV_TEST_CLEAN_EXCEPTION()

        // Elements in memory should not have been touched
        for (uint64_t i = 0; i < ARA_NR_LANES + 1; i++) {
          ASSERT_EQ(address_store[i], INIT_NONZERO_VAL_ST)
        }

        // Clean-up
        RVV_TEST_CLEANUP();

        ret_cnt++;
      }
    }

    //////////////////////////////////////////////////////////////////
    // TEST: vload, vl >= 0, vstart >= vl
    //////////////////////////////////////////////////////////////////

    // Loop through different avl, from 0 to avlmax
    for (uint64_t avl = 0; avl <= ARA_NR_LANES + 2; avl++) {
      // Reset vl, vstart, reset exceptions.
      RVV_TEST_INIT(vl, avl);
      for (uint64_t vstart_val = vl; vstart_val <= vl + ARA_NR_LANES + 2; vstart_val++) {
        // Reset vl, vstart, reset exceptions.
        RVV_TEST_INIT(vl, avl);
        STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

        // Init memory
        for (uint64_t i = 0; i < ARA_NR_LANES + 1; i++) {
          address_store[i] = INIT_NONZERO_VAL_ST;
        }
        for (uint64_t i = 0; i < ARA_NR_LANES + 1; i++) {
          address_load[i]  = vl + vstart_val + i + MAGIC_NUM;
        }
        asm volatile("vmv.v.x v0, %0" :: "r" (INIT_NONZERO_VAL_V0));

        // Setup vstart
        asm volatile("csrs vstart, %0" :: "r"(vstart_val));
        // Load the whole register (nothing should happen)
        _VLD(v0, address_load)

        // Check that vstart was reset at zero
        vstart_read = -1;
        asm volatile("csrr %0, vstart" : "=r"(vstart_read));
        ASSERT_EQ(vstart_read, 0)
        // Check that there was no exception
        RVV_TEST_ASSERT_EXCEPTION(0)
        RVV_TEST_CLEAN_EXCEPTION()

        // Store the old content of the v0 reg
        RVV_TEST_INIT(vl, ARA_NR_LANES + 2);
        _VST(v0, address_store)

        // We should have
        for (uint64_t i = 0; i < ARA_NR_LANES + 1; i++) {
          ASSERT_EQ(address_store[i], INIT_NONZERO_VAL_V0)
        }

        // Clean-up
        RVV_TEST_CLEANUP();

        ret_cnt++;
      }
    }

    //////////////////////////////////////////////////////////////////
    // TEST: previous tests should not mess up with regular stores
    //////////////////////////////////////////////////////////////////

    // Loop through different avl, from 0 to avlmax
    for (uint64_t avl = 0; avl <= ARA_NR_LANES + 2; avl++) {
      // Reset vl, vstart, reset exceptions.
      RVV_TEST_INIT(vl, avl);
      for (uint64_t vstart_val = 0; vstart_val < vl; vstart_val++) {
        // Reset vl, vstart, reset exceptions.
        RVV_TEST_INIT(vl, avl);
        STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

        // Init memory
        for (uint64_t i = 0; i < vl; i++) {
          address_store[i] = INIT_NONZERO_VAL_ST;
        }
        for (uint64_t i = 0; i < vl; i++) {
          address_load[i]  = vl + vstart_val + i + MAGIC_NUM;
        }
        asm volatile("vmv.v.x v0, %0" :: "r" (INIT_NONZERO_VAL_V0));

        // Load the whole register
        _VLD(v0, address_load)

        // Setup vstart
        asm volatile("csrs vstart, %0" :: "r"(vstart_val));

        // Store
        _VST(v0, address_store)

        // Check that vstart was reset at zero
        vstart_read = -1;
        asm volatile("csrr %0, vstart" : "=r"(vstart_read));
        ASSERT_EQ(vstart_read, 0)
        // Check that there was no exception
        RVV_TEST_ASSERT_EXCEPTION(0)
        RVV_TEST_CLEAN_EXCEPTION()

        // Prestart elements
        for (uint64_t i = 0; i < vstart_val; i++) {
          ASSERT_EQ(address_store[i], INIT_NONZERO_VAL_ST)
        }

        // Body elements
        for (uint64_t i = vstart_val; i < vl; i++) {
          ASSERT_EQ(address_store[i], address_load[i])
        }

        // Clean-up
        RVV_TEST_CLEANUP();

        ret_cnt++;
      }
    }

    //////////////////////////////////////////////////////////////////
    // TEST: previous tests should not mess up with regular loads
    //////////////////////////////////////////////////////////////////

    // Loop through different avl, from 0 to avlmax
    for (uint64_t avl = 0; avl <= ARA_NR_LANES + 2; avl++) {
      // Reset vl, vstart, reset exceptions.
      RVV_TEST_INIT(vl, avl);
      for (uint64_t vstart_val = 0; vstart_val < vl; vstart_val++) {
        // Reset vl, vstart, reset exceptions.
        RVV_TEST_INIT(vl, avl);
        STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

        // Init memory
        for (uint64_t i = 0; i < vl; i++) {
          address_store[i] = INIT_NONZERO_VAL_ST;
        }
        for (uint64_t i = 0; i < vl; i++) {
          address_load[i]  = vl + vstart_val + i + MAGIC_NUM;
        }
        asm volatile("vmv.v.x v0, %0" :: "r" (INIT_NONZERO_VAL_V0));

        // Setup vstart
        asm volatile("csrs vstart, %0" :: "r"(vstart_val));
        // Load the whole register (nothing should happen)
        _VLD(v0, address_load)

        // Check that vstart was reset at zero
        vstart_read = -1;
        asm volatile("csrr %0, vstart" : "=r"(vstart_read));
        ASSERT_EQ(vstart_read, 0)
        // Check that there was no exception
        RVV_TEST_ASSERT_EXCEPTION(0)
        RVV_TEST_CLEAN_EXCEPTION()

        // Store
        _VST(v0, address_store)

        // Prestart elements
        for (uint64_t i = 0; i < vstart_val; i++) {
          ASSERT_EQ(address_store[i], INIT_NONZERO_VAL_V0)
        }

        // Body elements
        for (uint64_t i = vstart_val; i < vl; i++) {
          ASSERT_EQ(address_store[i], address_load[i])
        }

        // Clean-up
        RVV_TEST_CLEANUP();

        ret_cnt++;
      }
    }

    // Clean-up the SoC CSRs
    RESET_SOC_CSR;

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    // END OF TESTS
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////

#if (PRINTF == 1)
    printf("Test SUCCESS!\r\n");
#endif

    cheshire_end();

    // If we did not return before, the test passed
    return RET_CODE_SUCCESS;
}
