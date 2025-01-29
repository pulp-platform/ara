// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Vincenzo Maisto <vincenzo.maisto2@unina.it>
// Matteo Perotti  <mperotti@iis.ee.ethz.ch>

#ifndef __RVV_RVV_TEST_H__
#define __RVV_RVV_TEST_H__

#include "regs/cheshire.h"

#if (PRINTF == 1)
#include "printf.h"
#endif

/////////////////
// SEW and EEW //
/////////////////

// Public defines
#if EEW == 64
#define _DTYPE                   __DTYPE(64)
#define _VSETVLI(vl,avl)          _VSETVLI_64(vl, avl)
#define _VLD(vreg,address_load)  __VLD(vreg,64,address_load)
#define _VST(vreg,address_store) __VST(vreg,64,address_store)
#define _VLD_IDX(vd,vs2,address_load)  __VLD_IDX(vd,vs2,64,address_load)
#define _VST_IDX(vs1,vs2,address_store) __VST_IDX(vs1,vs2,64,address_store)
#elif EEW == 32
#define _DTYPE                   __DTYPE(32)
#define _VSETVLI(vl,avl)          _VSETVLI_32(vl, avl)
#define _VLD(vreg,address_load)  __VLD(vreg,32,address_load)
#define _VST(vreg,address_store) __VST(vreg,32,address_store)
#define _VLD_IDX(vd,vs2,address_load)  __VLD_IDX(vd,vs2,32,address_load)
#define _VST_IDX(vs1,vs2,address_store) __VST_IDX(vs1,vs2,32,address_store)
#elif EEW == 16
#define _DTYPE                   __DTYPE(16)
#define _VSETVLI(vl,avl)          _VSETVLI_16(vl, avl)
#define _VLD(vreg,address_load)  __VLD(vreg,16,address_load)
#define _VST(vreg,address_store) __VST(vreg,16,address_store)
#define _VLD_IDX(vd,vs2,address_load)  __VLD_IDX(vd,vs2,16,address_load)
#define _VST_IDX(vs1,vs2,address_store) __VST_IDX(vs1,vs2,16,address_store)
#elif EEW == 8
#define _DTYPE                   __DTYPE(8)
#define _VSETVLI(vl,avl)          _VSETVLI_8(vl, avl)
#define _VLD(vreg,address_load)  __VLD(vreg,8,address_load)
#define _VST(vreg,address_store) __VST(vreg,8,address_store)
#define _VLD_IDX(vd,vs2,address_load)  __VLD_IDX(vd,vs2,8,address_load)
#define _VST_IDX(vs1,vs2,address_store) __VST_IDX(vs1,vs2,8,address_store)
#else
#error "ERROR: No EEW was defined. Please specify one in [8,16,32,64]."
#endif

#define _VADD(vd,vs1,vs2) asm volatile ("vadd.vv "#vd", "#vs1", "#vs2"");

// Private defines
#define __DTYPE(eew)                  uint##eew##_t
#define __VLD(vreg,eew,address_load)  asm volatile ("vle"#eew".v "#vreg", (%0)"  : "+&r"(address_load));
#define __VST(vreg,eew,address_store) asm volatile ("vse"#eew".v "#vreg", (%0)"  : "+&r"(address_store));
#define __VLD_IDX(vd,vs2,eew,address_load)  asm volatile ("vluxei"#eew".v "#vd", (%0), "#vs2 : "+&r"(address_load));
#define __VST_IDX(vs1,vs2,eew,address_store) asm volatile ("vsuxei"#eew".v "#vs1", (%0), "#vs2 : "+&r"(address_store));

///////////////////////
// Reshuffle helpers //
///////////////////////

#define VSETVLI(vl, avl, eew, lmul) { asm volatile("vsetvli  %0, %1, e"#eew", m"#lmul", ta, ma \n\t" : "=r" (vl) :"r" (avl) ); }

#define _VSETVLI_64(vl, avl) { VSETVLI(vl, avl, 64, 8); }
#define _VSETVLI_32(vl, avl) { VSETVLI(vl, avl, 32, 8); }
#define _VSETVLI_16(vl, avl) { VSETVLI(vl, avl, 16, 8); }
#define _VSETVLI_8(vl, avl)  { VSETVLI(vl, avl, 8,  8); }

//////////////////
// Return codes //
//////////////////

#define RET_CODE_SUCCESS     0
#define RET_CODE_FAIL       -1
#define RET_CODE_WRONG_CASE -2

///////////////////////
// SoC-level regfile //
///////////////////////

#define INIT_RVV_TEST_SOC_REGFILE \
volatile uint32_t *rf_stub_ex_en      = reg32(&__base_regs, CHESHIRE_STUB_EX_EN_REG_OFFSET);       \
volatile uint32_t *rf_stub_no_ex_lat  = reg32(&__base_regs, CHESHIRE_STUB_NO_EX_LAT_REG_OFFSET);   \
volatile uint32_t *rf_req_rsp_lat     = reg32(&__base_regs, CHESHIRE_STUB_REQ_RSP_LAT_REG_OFFSET); \
volatile uint32_t *rf_virt_mem_en     = reg32(&__base_regs, CHESHIRE_ARA_VIRT_MEM_EN_REG_OFFSET);  \
volatile uint32_t *rf_rvv_debug_reg   = reg32(&__base_regs, CHESHIRE_RVV_DEBUG_REG_REG_OFFSET);    \
volatile uint32_t *rf_mmu_req_gen_en  = reg32(&__base_regs, CHESHIRE_MMU_REQ_GEN_EN_REG_OFFSET);   \
volatile uint32_t *rf_mmu_req_gen_lat = reg32(&__base_regs, CHESHIRE_MMU_REQ_GEN_LAT_REG_OFFSET);

//////////////////////
// Print facilities //
//////////////////////

#define PRINT_INIT                                                          \
  uint32_t rtc_freq   = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET); \
  uint64_t reset_freq = clint_get_core_freq(rtc_freq, 2500);                \
  uart_init(&__base_uart, reset_freq, 115200);                              \
  char uart_print_str[] = {'0', '\r', '\n'};
#define PRINT_CHAR(byte)                          \
  uart_print_str[0] = (char) byte;                \
  PRINT(uart_print_str)
#define PRINT(str)                                \
  uart_write_str(&__base_uart, str, sizeof(str)); \
  uart_write_flush(&__base_uart);

/////////////////////
// Stub management //
/////////////////////

// Enable virtual memory Ara->STUB requests
#define VIRTUAL_MEMORY(val) *rf_virt_mem_en = val;
#define VIRTUAL_MEMORY_ON   *rf_virt_mem_en = 1;
#define VIRTUAL_MEMORY_OFF  *rf_virt_mem_en = 0;
// Enable/disable exceptions from the stub. This registers also resets the status of the stub
// for what conerns the exceptions (e.g., the counter for the no-ex-latency).
#define STUB_EX(val) *rf_stub_ex_en = val;
#define STUB_EX_ON   *rf_stub_ex_en = 1;
#define STUB_EX_OFF  *rf_stub_ex_en = 0;
// Stub req-2-resp latency
#define STUB_REQ_RSP_LAT(lat) *rf_req_rsp_lat = lat;
// Exception latency (per transaction)
#define STUB_NO_EX_LAT(lat) *rf_stub_no_ex_lat = lat;
// Enable MMU req gen
#define MMU_REQ_GEN_EN(val) *rf_mmu_req_gen_en = val;
// MMU req gen ans-to-req latency
#define MMU_REQ_GEN_LAT(lat) *rf_mmu_req_gen_lat = lat;
// Reset SoC-CSRs
#define RESET_SOC_CSR *rf_virt_mem_en     = 0; \
                      *rf_stub_ex_en      = 0; \
                      *rf_req_rsp_lat     = 0; \
                      *rf_stub_no_ex_lat  = 0; \
                      *rf_mmu_req_gen_en  = 0; \
                      *rf_mmu_req_gen_lat = 0; \
                      *rf_rvv_debug_reg   = 0;

///////////////
// RVV Tests //
///////////////

// Helper test variables
typedef uint64_t vcsr_dump_t [5];
volatile uint64_t exception;
volatile uint64_t mtval;
volatile uint64_t mcause;
volatile uint64_t magic_out;
// Return counter to ease debug
volatile uint64_t ret_cnt;

#if (PRINTF == 1)
#define FAIL { printf("FAIL. retval: \d\n", ret_cnt + 1); return ret_cnt + 1; }
#else
#define FAIL { return ret_cnt + 1; }
#endif

#define ASSERT_EQ(var, gold) if (var != gold) FAIL
#define ASSERT_TRUE(val)  { if (!val) FAIL };
#define ASSERT_FALSE(val) { if ( val) FAIL };

// Helper test macros
#define RVV_TEST_INIT(vl, avl)            vl = reset_v_state ( avl ); exception = 0;
#define RVV_TEST_CLEANUP()                RVV_TEST_ASSERT_EXCEPTION(0); exception = 0;
// BUG: Can't return a non-zero value from here...
// #define RVV_TEST_ASSERT( expression ) if ( !expression ) { return -1; }
// Quick workaround:
#define RVV_TEST_ASSERT( expression )     if ( !(expression) ) FAIL
#define RVV_TEST_ASSERT_EXCEPTION( val )  RVV_TEST_ASSERT ( exception == (uint64_t)(val) );
#define RVV_TEST_ASSERT_EXCEPTION_EXTENDED( valid, tval, cause )  RVV_TEST_ASSERT ( ( exception == (uint64_t)(valid) )    \
                                                                            & ( mtval == (uint64_t)(tval) ) \
                                                                            & ( mcause == (uint64_t)(cause) ) \
                                                                            );
#define RVV_TEST_CLEAN_EXCEPTION()        exception = 0; mtval = 0; mcause = 0;

#define VLMAX (1024 * ARA_NR_LANES)
#define VLBMAX VLMAX
#define ELMMAX VLMAX / (EEW / 8)
#ifndef RVV_TEST_AVL
  #define RVV_TEST_AVL(EEW) (VLMAX / (EEW))
#endif

#ifndef _ENABLE_RVV_
#define _ENABLE_RVV_
void enable_rvv() {
  // Enalbe RVV by seting MSTATUS.VS
  asm volatile (" li      t0, %0       " :: "i"(MSTATUS_VS));
  asm volatile (" csrs    mstatus, t0" );
}
#endif

uint64_t reset_v_state ( uint64_t avl ) {
    uint64_t vl_local = 0;

	asm volatile (
    "fence                                \n\t"
#if EEW == 64
	  "vsetvli  %0, %1, e64, m8, ta, ma \n\t"
#elif EEW == 32
	  "vsetvli  %0, %1, e32, m8, ta, ma \n\t"
#elif EEW == 16
	  "vsetvli  %0, %1, e16, m8, ta, ma \n\t"
#elif EEW == 8
	  "vsetvli  %0, %1, e8, m8, ta, ma \n\t"
#endif
	  "csrw	    vstart, 0                   \n\t"
	  "csrw	    vcsr  , 0                   \n\t"
    "fence                                \n\t"
	: "=r" (vl_local)  : "r" (avl) :
  );

    return vl_local;
}

void vcsr_dump ( vcsr_dump_t vcsr_state ) {
	asm volatile (
		"csrr  %0, vstart \n\t"
		"csrr  %1, vtype  \n\t"
		"csrr  %2, vl     \n\t"
		"csrr  %3, vcsr   \n\t"
		"csrr  %4, vlenb  \n\t"
		: "=r" (vcsr_state[0]),
		  "=r" (vcsr_state[1]),
		  "=r" (vcsr_state[2]),
		  "=r" (vcsr_state[3]),
		  "=r" (vcsr_state[4])
  );
}

// Override default weak trap vector
void trap_vector () {
    // Set exception flag
    exception = 1;

    // Save tval and mcause
    mtval = 0;
    mcause = 0;
    asm volatile ("csrr %0, mtval" : "=r"(mtval));
    asm volatile ("csrr %0, mcause" : "=r"(mcause));

    // Move PC ahead
    // NOTE: PC = PC + 4, valid only for non-compressed trapping instructions
    asm volatile (
        "nop;"
        "csrr	t6, mepc;"
        "addi	t6, t6, 4; # PC = PC + 4, valid only for non-compressed trapping instructions\n"
        "csrw	mepc, t6;"
        "nop;"
    );
}

#define INIT_NONZERO_VAL_ST 37
#define MAGIC_NUM 5

// Maximum STUB req-rsp latency (power of 2 to speed up the code)
#define MAX_LAT_P2 8

#define MEM_BUS_BYTE 4 * ARA_NR_LANES

// Helper
#define LOG2_4Ki 12
// Max number of bursts in a single AXI unit-stride memory op
// 16 lanes, 16 KiB vector register (LMUL == 8)
// MAX 256 beats in a burst (BUS_WIDTH_min == 8B): 16KiB / (256 * 8B) = 8
// No 4KiB page crossings: max bursts -> 16KiB / 4KiB + 1 = 5
// Use a safe value higher than the previous bounds
#define MAX_BURSTS 16

typedef struct axi_burst_log_s {
  // Number of bursts in this AXI transaction
  uint64_t bursts;
  // Number of vector elemetns per AXI burst
  uint64_t burst_vec_elm[MAX_BURSTS];
  // Start address of each AXI burst
  uint64_t burst_start_addr[MAX_BURSTS];
} axi_burst_log_t;
axi_burst_log_t axi_log;

// Get the number of elements correctly processed before the exception at burst T in [0,N_BURSTS-1].
uint64_t get_body_elm_pre_exception(axi_burst_log_t *axi_log, uint64_t T) {
  // Calculate how many elements before exception
  uint64_t elm = 0;
  for (int i = 0; i < T; i++) {
    elm += axi_log->burst_vec_elm[i];
  }
  return elm;
}

// Get the number of bursts per vector unit-stride memory operation from an address and a number of elements
// with 2^(enc_ew) Byte each, and a memory bus of 2^(log2_balign) Byte.
axi_burst_log_t* get_unit_stride_bursts(axi_burst_log_t *axi_log, uint64_t addr, uint64_t vl_eff, uint64_t enc_ew, uint64_t log2_balign) {
  // Requests are aligned to the memory bus
  uint64_t aligned_addr = (addr >> log2_balign) << log2_balign;

  // Calculate the number of elements per burst
  uint64_t start_addr_misaligned = addr;
  uint64_t start_addr            = aligned_addr;
  uint64_t final_addr = start_addr_misaligned + (vl_eff << enc_ew);
  uint64_t end_addr;
  axi_log->bursts = 0;
   while (start_addr < final_addr) {
    // Find the end address (minimum address among the various limits)
    // Burst cannot be made of more than 256 beats
    uint64_t end_addr_lim_0 = start_addr + (256 << log2_balign);
    // Burst cannot cross 4KiB pages
    uint64_t end_addr_lim_1 = ((start_addr >> LOG2_4Ki) << LOG2_4Ki) + (1 << LOG2_4Ki);
    // The end address is finally limited by the vector length
    uint64_t end_addr_lim_2 = start_addr_misaligned + (vl_eff << enc_ew);
    // Find the minimum end address
    if (end_addr_lim_0 < end_addr_lim_1 && end_addr_lim_0 < end_addr_lim_2) {
      end_addr = end_addr_lim_0;
    } else if (end_addr_lim_1 < end_addr_lim_0 && end_addr_lim_1 < end_addr_lim_2) {
      end_addr = end_addr_lim_1;
    } else {
      end_addr = end_addr_lim_2;
    }

    // How many elements in this burst
    uint64_t elm_per_burst = (end_addr - start_addr_misaligned) >> enc_ew;
    vl_eff -= elm_per_burst;
    // Log burst info
    axi_log->burst_vec_elm[axi_log->bursts]    = elm_per_burst;
    axi_log->burst_start_addr[axi_log->bursts++] = start_addr_misaligned;

    // Find next start address
    start_addr = end_addr;
    // After the first burst, the address is always aligned with the bus width
    start_addr_misaligned = start_addr;
  }

  return axi_log;
}

// Get the number of bursts per vector unit-stride AXI memory operation and the number of elements per burst.
// This function calculates the effective vl and address from vl, addr, and vstart, some other helpers,
// and then fall through the real function.
void get_unit_stride_bursts_wrap(axi_burst_log_t *axi_log, uint64_t addr, uint64_t vl, uint64_t ew, uint64_t mem_bus_byte, uint64_t vstart, uint8_t is_store) {
  // Encode ew [bits] in a [byte] exponent
  uint64_t enc_ew = (31 - __builtin_clz(ew)) - 3;
  // Is this memory operation misaligned?
  uint64_t is_misaligned = addr & (mem_bus_byte - 1);
  // Calculate the effective memory bus width. Misaligned or vstart>0 stores get a reduced BW.
  uint64_t eff_mem_bus_byte = (is_store && (is_misaligned || (vstart > 0))) ? (ew >> 3) : mem_bus_byte;
  // Find log2 byte alignment
  uint64_t log2_balign = (31 - __builtin_clz(eff_mem_bus_byte));
  // Effective starting address
  uint64_t eff_addr = addr + (vstart << enc_ew);
  uint64_t eff_vl   = vl - vstart;

  return get_unit_stride_bursts(axi_log, eff_addr, eff_vl, enc_ew, log2_balign);
}

// Quick pseudo-rand from 0 to max
uint64_t pseudo_rand(uint64_t max) {
  static uint64_t x = 0;
  return (x = (x + 7) % (max + 1));
}

#endif // __RVV_RVV_TEST_H__
