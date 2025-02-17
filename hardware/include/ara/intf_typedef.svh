// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

///////////////////////////////////
// CVA6 - Accelerator interfaces //
///////////////////////////////////

// Accelerator - CVA6's
`define CVA6_INTF_TYPEDEF_ACC_REQ(accelerator_req_t, CVA6Cfg, roundmode_e) \
  typedef struct packed {                                                  \
    logic                             req_valid;                           \
    logic                             resp_ready;                          \
    logic [31:0]                      insn;                                \
    logic [CVA6Cfg.XLEN-1:0]          rs1;                                 \
    logic [CVA6Cfg.XLEN-1:0]          rs2;                                 \
    roundmode_e                       frm;                                 \
    logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;                            \
    logic                             store_pending;                       \
    logic                             acc_cons_en;                         \
    logic                             inval_ready;                         \
  } accelerator_req_t;

`define CVA6_INTF_TYPEDEF_ACC_RESP(accelerator_resp_t, CVA6Cfg, exception_t) \
  typedef struct packed {                                                    \
    logic                              req_ready;                            \
    logic                              resp_valid;                           \
    logic [CVA6Cfg.XLEN-1:0]           result;                               \
    logic [CVA6Cfg.TRANS_ID_BITS-1:0]  trans_id;                             \
    exception_t                        exception;                            \
    logic                              store_pending;                        \
    logic                              store_complete;                       \
    logic                              load_complete;                        \
    logic [4:0]                        fflags;                               \
    logic                              fflags_valid;                         \
    logic                              inval_valid;                          \
    logic [63:0]                       inval_addr;                           \
  } accelerator_resp_t;

`define CVA6_INTF_TYPEDEF_MMU_REQ(acc_mmu_req_t, CVA6Cfg) \
  typedef struct packed {                                 \
    logic                    acc_mmu_misaligned_ex;       \
    logic                    acc_mmu_req;                 \
    logic [CVA6Cfg.VLEN-1:0] acc_mmu_vaddr;               \
    logic                    acc_mmu_is_store;            \
  } acc_mmu_req_t;

`define CVA6_INTF_TYPEDEF_MMU_RESP(acc_mmu_resp_t, CVA6Cfg, exception_t) \
  typedef struct packed {                                                \
    logic                    acc_mmu_dtlb_hit;                           \
    logic [CVA6Cfg.PPNW-1:0] acc_mmu_dtlb_ppn;                           \
    logic                    acc_mmu_valid;                              \
    logic [CVA6Cfg.PLEN-1:0] acc_mmu_paddr;                              \
    exception_t              acc_mmu_exception;                          \
  } acc_mmu_resp_t;

`define CVA6_INTF_TYPEDEF_CVA6_TO_ACC(cva6_to_acc_t, accelerator_req_t, acc_mmu_resp_t) \
  typedef struct packed {                                                               \
    accelerator_req_t acc_req;                                                          \
    logic             acc_mmu_en;                                                       \
    acc_mmu_resp_t    acc_mmu_resp;                                                     \
  } cva6_to_acc_t;

`define CVA6_INTF_TYPEDEF_ACC_TO_CVA6(acc_to_cva6_t, accelerator_resp_t, acc_mmu_req_t) \
  typedef struct packed {                                                               \
    accelerator_resp_t acc_resp;                                                        \
    acc_mmu_req_t      acc_mmu_req;                                                     \
  } acc_to_cva6_t;

/////////////////////////
// Exception data type //
/////////////////////////

`define CVA6_TYPEDEF_EXCEPTION(exception_t, CVA6Cfg)           \
  typedef struct packed {                                      \
    // cause of exception                                      \
    logic [CVA6Cfg.XLEN-1:0] cause;                            \
    // additional information of causing exception             \
    // (e.g.: instruction causing it), address of LD/ST fault  \
    logic [CVA6Cfg.XLEN-1:0] tval;                             \
    // additional information when the causing exception in    \
    // a guest exception                                       \
    logic [CVA6Cfg.GPLEN-1:0] tval2;                           \
    // transformed instruction information                     \
    logic [31:0] tinst;                                        \
    // signals when a guest virtual address is written to tval \
    logic gva  ;                                               \
    logic valid;                                               \
  } exception_t;
