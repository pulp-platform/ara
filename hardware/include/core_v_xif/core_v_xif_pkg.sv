// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Frederic zur Bonsen <fzurbonsen@sutdent.ethz.ch>
// Description:
// Core-V eXtension Interface implementation.

package core_v_xif_pkg;

    localparam int unsigned X_NUM_RS     		   = ariane_pkg::NR_RGPR_PORTS; //2 or 3
    localparam int unsigned X_ID_WIDTH   		   = ariane_pkg::TRANS_ID_BITS;
    localparam int unsigned X_RFR_WIDTH  		   = riscv::XLEN;
    localparam int unsigned X_RFW_WIDTH  		   = riscv::XLEN;
  	localparam int unsigned X_NUM_HARTS            = 1;
  	localparam int unsigned X_HARTID_WIDTH         = 1;
  	localparam logic [25:0] X_MISA                 = '0;
  	localparam int unsigned X_DUALREAD             = 0;
  	localparam int unsigned X_DUALWRITE            = 0;
  	localparam int unsigned X_ISSUE_REGISTER_SPLIT = 0;
  	localparam int unsigned X_MEM_WIDTH            = 64;

  	localparam X_DATAWIDTH  = riscv::XLEN;

    typedef logic [X_NUM_RS+X_DUALREAD-1:0] readregflags_t;
  	typedef logic [X_DUALWRITE:0] writeregflags_t;
  	typedef logic [1:0] mode_t;
  	typedef logic [X_ID_WIDTH-1:0] id_t;
  	typedef logic [X_HARTID_WIDTH-1:0] hartid_t;

    typedef struct packed {
    logic [15:0] instr;
    hartid_t hartid;
  } x_compressed_req_t;

  typedef struct packed {
    // logic [31:0] instr;
    riscv::instruction_t  instr;
    logic accept;
  } x_compressed_resp_t;

  typedef struct packed {
    // logic [31:0] instr;
    riscv::instruction_t instr;
    mode_t mode;
    hartid_t hartid;
    id_t id;
  } x_issue_req_t;

  typedef struct packed {
    logic accept;
    writeregflags_t writeback;
    readregflags_t register_read;
    logic loadstore;
  } x_issue_resp_t;

  typedef struct {
    hartid_t hartid;
    id_t id;
    /* verilator lint_off UNPACKED */
    logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];
    readregflags_t rs_valid;
  } x_register_t;

  typedef struct packed {
    hartid_t hartid;
    id_t id;
    logic commit_kill;
  } x_commit_t;

  typedef struct packed {
    hartid_t hartid;
    id_t id;
    logic [31:0] addr;
    mode_t mode;
    logic we;
    logic [2:0] size;
    logic [X_MEM_WIDTH/8-1:0] be;
    logic [1:0] attr;
    logic [X_MEM_WIDTH  -1:0] wdata;
    logic last;
    logic spec;
  } x_mem_req_t;

  typedef struct packed {
    logic exc;
    logic [5:0] exccode;
    logic dbg;
  } x_mem_resp_t;

  typedef struct packed {
    hartid_t hartid;
    id_t id;
    logic [X_MEM_WIDTH-1:0] rdata;
    logic err;
    logic dbg;
  } x_mem_result_t;

  typedef struct packed {
    hartid_t hartid;
    id_t id;
    logic [X_RFW_WIDTH     -1:0] data;
    logic [4:0] rd;
    writeregflags_t we;
    logic exc;
    logic [5:0] exccode;
    logic dbg;
    logic err;
  } x_result_t;

  typedef struct packed {
  	fpnew_pkg::roundmode_e frm;
    logic store_pending;
    logic acc_cons_en;
    logic inval_ready;
  } x_acc_req_t;

  typedef struct packed {
  	logic error;
    logic store_pending;
    logic store_complete;
    logic load_complete;
    logic [4:0] fflags;
    logic fflags_valid;
    logic inval_valid;
    logic [63:0] inval_addr;
  } x_acc_resp_t;


// Does not yet contain the full XIF
  typedef struct {
  	// Issue interface 
  	logic                          	issue_valid;
    x_issue_req_t  					issue_req;
    // Register interface
    logic                          	register_valid;
    x_register_t   					register;
    // Commit interface
    logic                          	commit_valid;
    x_commit_t     					commit;
    // Result interface
    logic                         	result_ready;
    // Additional siganls
    x_acc_req_t 					acc_req;
  }	x_req_t;


  typedef struct packed {
  	// Issue interface
    logic                          	issue_ready;
    x_issue_resp_t 					issue_resp;
    // Register interface
    logic                          	register_ready;
    // Result interface
    logic                           result_valid;
    x_result_t      				result;
    // Additional signals
    x_acc_resp_t 					acc_resp;
  } x_resp_t;

endpackage
