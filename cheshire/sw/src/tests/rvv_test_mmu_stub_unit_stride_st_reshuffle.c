// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti  <mperotti@iis.ee.ethz.ch>

#include "regs/cheshire.h"
#include "dif/clint.h"
#include "dif/uart.h"
#include "params.h"
#include "util.h"
#include "encoding.h"
#include "rvv_test.h"

#include "cheshire_util.h"

#if (EXTENSIVE_TEST == 1)
#define VL_LIMIT_LOW      ELMMAX
#define VL_LIMIT_HIGH     0
#define VSTART_LIMIT_LOW  vl + 1
#define VSTART_LIMIT_HIGH 0
#else
#define VL_LIMIT_LOW      3*ARA_NR_LANES + 1
#define VL_LIMIT_HIGH     ELMMAX - (3*ARA_NR_LANES + 1)
#define VSTART_LIMIT_LOW  2*ARA_NR_LANES + 1
#define VSTART_LIMIT_HIGH vl - 2*ARA_NR_LANES - 1
#endif

#define INIT_NONZERO_VAL_V0 99
#define INIT_NONZERO_VAL_V8 84
#define INIT_NONZERO_VAL_ST_0 44
#define INIT_NONZERO_VAL_ST_1 65

// Derived parameters
uint64_t stub_req_rsp_lat = 10;

// If lanes == 8 and eew == 8, these vectors are too large to be instantiated in the stack.
// In all the other cases, the stack is the preferred choice since everything outside of the
// stack should be preloaded with the slow JTAG, and the simulation time increases
#if !((ARA_NR_LANES < 8) || (EEW > 8))
    // Helper variables and arrays
    _DTYPE array_load    [ELMMAX];
    _DTYPE array_store_0 [ELMMAX];
    _DTYPE array_store_1 [ELMMAX];
#endif

// Check an array in the byte range [start_byte, end_byte) to see if it corresponds to a repetition of
// gold_size-byte gold values. For example:
// arr: 0x88 0x4A 0x32 0x4A
// gold: 0x32 0x4A
// gold_size: 2 [byte]
// start_byte: 0 (included)
// end_byte: 3 (non included)
// return value: 1
int check_byte_arr(const void* arr, uint64_t start_byte, uint64_t end_byte, int64_t gold,  uint64_t gold_size) {
  const uint8_t* mem_bytes = (const uint8_t*)arr;

  // Iterate over each byte of the array
  for (uint64_t i = start_byte; i < end_byte; i++) {
    // Dynamically calculate the expected byte
    uint8_t expected_byte = (gold >> ((i % gold_size) * 8)) & 0xFF;
    if (expected_byte != mem_bytes[i]) return 0;
  }
  // Everything's good
  return 1;
}

int main(void) {
    cheshire_start();

    // Clean the exception variable
    RVV_TEST_CLEAN_EXCEPTION();

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

// See note above
#if (ARA_NR_LANES < 8) || (EEW > 8)
    // Helper variables and arrays
    _DTYPE array_load    [ELMMAX];
    _DTYPE array_store_0 [ELMMAX];
    _DTYPE array_store_1 [ELMMAX];
#endif

    _DTYPE* address_load    = array_load;
    _DTYPE* address_store_0 = array_store_0;
    _DTYPE* address_store_1 = array_store_1;

    // Enalbe RVV
    enable_rvv();
    vcsr_dump ( vcsr_state );

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    // START OF TESTS
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////

    for (uint64_t ew = 0; ew < 4; ew++) {
      // Loop through different avl, from 0 to avlmax
      for (uint64_t avl = 0; (avl <= VL_LIMIT_LOW || avl >= VL_LIMIT_HIGH) && avl <= ELMMAX; avl++) {
        // Reset vl, vstart, reset exceptions.
        RVV_TEST_INIT(vl, avl);
        for (uint64_t vstart_val = 0; (vstart_val <= VSTART_LIMIT_LOW || vstart_val >= VSTART_LIMIT_HIGH) && vstart_val < vl; vstart_val++) {

          // Calculate vl and vstart byte in memory for fixed EEW
          // Original encoding of vregs, before shuffling
          uint64_t eew_src     = 1 << (3 - ew);
          // Post-shuffle vregs encoding
          uint64_t eew_dst     = EEW / 8;
          // vstart and vl bytes in the memory array
          uint64_t vstart_byte = vstart_val * eew_dst;
          uint64_t vl_byte     = vl         * eew_dst;

          // Reset vl, vstart, reset exceptions.
          RVV_TEST_INIT(vl, avl);
          // Random latency
          STUB_REQ_RSP_LAT((stub_req_rsp_lat++ % MAX_LAT_P2) + 1);

          // Set up the source EEW and reset v0 and v8 with same encoding
          switch(ew) {
            case 0:
              _VSETVLI_64(vl, -1)
              break;
            case 1:
              _VSETVLI_32(vl, -1)
              break;
            case 2:
              _VSETVLI_16(vl, -1)
              break;
            default:
              _VSETVLI_8(vl, -1)
          }
          asm volatile("vmv.v.x v8, %0" :: "r" (INIT_NONZERO_VAL_V8));

          // Set up the target EEW
          _VSETVLI(vl, avl)

          // Init memory
          for (uint64_t i = 0; i < vl; i++) {
            address_store_1[i] = INIT_NONZERO_VAL_ST_1;
          }

          // Setup vstart
          asm volatile("csrs vstart, %0" :: "r"(vstart_val));

          // Store v8 (force reshuffle)
          _VST(v8, address_store_1)

          *rf_rvv_debug_reg = 0xF0000001;

          // Check that vstart is correctly reset at zero
          vstart_read = -1;
          asm volatile("csrr %0, vstart" : "=r"(vstart_read));
          ASSERT_EQ(vstart_read, 0)

          *rf_rvv_debug_reg = 0xF0000002;

          // Check that there was no exception
          RVV_TEST_ASSERT_EXCEPTION(0)
          RVV_TEST_CLEAN_EXCEPTION()

          *rf_rvv_debug_reg = 0xF0000003;

          // Store test - prestart
          int retval = check_byte_arr(address_store_1, 0, vstart_byte, INIT_NONZERO_VAL_ST_1, eew_dst);
          ASSERT_TRUE(retval);

          *rf_rvv_debug_reg = 0xF0000004;

          // Store test - body
          retval = check_byte_arr(address_store_1, vstart_byte, vl_byte, INIT_NONZERO_VAL_V8, eew_src);
          ASSERT_TRUE(retval);

          *rf_rvv_debug_reg = 0xF0000005;

          // Clean-up
          RVV_TEST_CLEANUP();

        // Jump from limit low to limit high if limit high is higher than low
        if ((VSTART_LIMIT_LOW) < (VSTART_LIMIT_HIGH))
          if (vstart_val == VSTART_LIMIT_LOW)
            vstart_val = VSTART_LIMIT_HIGH;

          ret_cnt++;
        }

        // Jump from limit low to limit high if limit high is higher than low
        if ((VL_LIMIT_LOW) < (VL_LIMIT_HIGH))
          if (avl == VL_LIMIT_LOW)
            avl = VL_LIMIT_HIGH;
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
