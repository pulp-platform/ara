/*
 Copyright 2024 OpenhW Group
 Copyright 2021 TU Wien
 Copyright 2021 ETH Zurich and University of Bologna

 This file, and derivatives thereof are licensed under the
 Solderpad License, Version 2.0 (the "License");
 Use of this file means you agree to the terms and conditions
 of the license and are in full compliance with the License.
 You may obtain a copy of the License at

 https://solderpad.org/licenses/SHL-2.0/

 Unless required by applicable law or agreed to in writing, software
 and hardware implementations thereof
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESSED OR IMPLIED.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

// CV-X-IF Package
// Contributor: Moritz Imfeld <moimfeld@student.ethz.ch>
// Contributor: Michael Platzer <michael.platzer@hotmail.com>
// Contributor: Davide Schiavone <davide@openhwgroup.org>

// interface core_v_xif
// #(
//   parameter int unsigned X_NUM_RS               = 2,  // Number of register file read ports that can be used by the eXtension interface
//   parameter int unsigned X_ID_WIDTH             = 4,  // Width of ID field.
//   parameter int unsigned X_RFR_WIDTH            = 32, // Register file read access width for the eXtension interface
//   parameter int unsigned X_RFW_WIDTH            = 32, // Register file write access width for the eXtension interface
//   parameter int unsigned X_NUM_HARTS            = 1,  // Number of harts (hardware threads) associated with the interface
//   parameter int unsigned X_HARTID_WIDTH         = 1,  // Width of ``hartid`` signals.
//   parameter logic [25:0] X_MISA                 = '0, // MISA extensions implemented on the eXtension interface
//   parameter int unsigned X_DUALREAD             = 0,  // Is dual read supported? 0: No, 1: Yes, for ``rs1``, 2: Yes, for ``rs1`` - ``rs2``, 3: Yes, for ``rs1`` - ``rs3``
//   parameter int unsigned X_DUALWRITE            = 0,  // Is dual write supported? 0: No, 1: Yes.
//   parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,  // Does the interface pipeline register interface? 0: No, 1: Yes.
//   parameter int unsigned X_MEM_WIDTH            = 32  // Memory access width for loads/stores via the eXtension interface
// );


//   // Compressed interface
//   logic               compressed_valid;
//   logic               compressed_ready;
//   x_compressed_req_t  compressed_req;
//   x_compressed_resp_t compressed_resp;

//   // Issue interface
//   logic               issue_valid;
//   logic               issue_ready;
//   x_issue_req_t       issue_req;
//   x_issue_resp_t      issue_resp;

//   // Register interface
//   logic               register_valid;
//   logic               register_ready;
//   x_register_t        register;

//   // Commit interface
//   logic               commit_valid;
//   x_commit_t          commit;

//   // Memory (request/response) interface
//   logic               mem_valid;
//   logic               mem_ready;
//   x_mem_req_t         mem_req;
//   x_mem_resp_t        mem_resp;

//   // Memory result interface
//   logic               mem_result_valid;
//   x_mem_result_t      mem_result;

//   // Result interface
//   logic               result_valid;
//   logic               result_ready;
//   x_result_t          result;

//   // Port directions for host CPU
//   modport core_v_xif_cpu_compressed (
//     output compressed_valid,
//     input  compressed_ready,
//     output compressed_req,
//     input  compressed_resp
//   );

//   modport core_v_xif_cpu_issue (
//     output issue_valid,
//     input  issue_ready,
//     output issue_req,
//     input  issue_resp
//   );

//   modport core_v_xif_cpu_register (
//     output register_valid,
//     input  register_ready,
//     output register
//   );

//   modport core_v_xif_cpu_commit (
//     output commit_valid,
//     output commit
//   );

//   modport core_v_xif_cpu_mem (
//     input  mem_valid,
//     output mem_ready,
//     input  mem_req,
//     output mem_resp
//   );

//   modport core_v_xif_cpu_mem_result (
//     output mem_result_valid,
//     output mem_result
//   );

//   modport core_v_xif_cpu_result (
//     input  result_valid,
//     output result_ready,
//     input  result
//   );

//   // Port directions for CO-PROCESSOR
//   modport core_v_xif_coprocessor_compressed (
//     input   compressed_valid,
//     output  compressed_ready,
//     input   compressed_req,
//     output  compressed_resp
//   );

//   modport core_v_xif_coprocessor_issue (
//     input   issue_valid,
//     output  issue_ready,
//     input   issue_req,
//     output  issue_resp
//   );

//   modport core_v_xif_coprocessor_register (
//     input   register_valid,
//     output  register_ready,
//     input   register
//   );

//   modport core_v_xif_coprocessor_commit (
//     input   commit_valid,
//     input   commit
//   );

//   modport core_v_xif_coprocessor_mem (
//     output  mem_valid,
//     input   mem_ready,
//     output  mem_req,
//     input   mem_resp
//   );

//   modport core_v_xif_coprocessor_mem_result (
//     input   mem_result_valid,
//     input   mem_result
//   );

//   modport core_v_xif_coprocessor_result (
//     output  result_valid,
//     input   result_ready,
//     output  result
//   );


// endinterface : core_v_xif

//   parameter int unsigned X_NUM_RS               = 2,  // Number of register file read ports that can be used by the eXtension interface
//   parameter int unsigned X_ID_WIDTH             = 4,  // Width of ID field.
//   parameter int unsigned X_RFR_WIDTH            = 32, // Register file read access width for the eXtension interface
//   parameter int unsigned X_RFW_WIDTH            = 32, // Register file write access width for the eXtension interface
//   parameter int unsigned X_NUM_HARTS            = 1,  // Number of harts (hardware threads) associated with the interface
//   parameter int unsigned X_HARTID_WIDTH         = 1,  // Width of ``hartid`` signals.
//   parameter logic [25:0] X_MISA                 = '0, // MISA extensions implemented on the eXtension interface
//   parameter int unsigned X_DUALREAD             = 0,  // Is dual read supported? 0: No, 1: Yes, for ``rs1``, 2: Yes, for ``rs1`` - ``rs2``, 3: Yes, for ``rs1`` - ``rs3``
//   parameter int unsigned X_DUALWRITE            = 0,  // Is dual write supported? 0: No, 1: Yes.
//   parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,  // Does the interface pipeline register interface? 0: No, 1: Yes.
//   parameter int unsigned X_MEM_WIDTH            = 32  // Memory access width for loads/stores via the eXtension interface

`ifndef CORE_V_XIF_SVH_
`define CORE_V_XIF_SVH_

`define CORE_V_XIF_BASE_T(X_NUM_RS, X_ID_WIDTH, X_HARTID_WIDTH, X_DUALREAD, X_DUALWRITE)     \
  typedef logic [X_NUM_RS+X_DUALREAD-1:0] readregflags_t; \
  typedef logic [X_DUALWRITE:0] writeregflags_t;          \
  typedef logic [1:0] mode_t;                             \
  typedef logic [X_ID_WIDTH-1:0] id_t;                    \
  typedef logic [X_HARTID_WIDTH-1:0] hartid_t;            \

`define CORE_V_XIF_ISSUE_REQ_T    \
  typedef struct packed {         \
    logic [31:0] instr;           \
    mode_t mode;                  \
    hartid_t hartid;              \
    id_t id;                      \
  } x_issue_req_t;

`define CORE_V_XIF_ISSUE_RESP_T       \
  typedef struct packed {             \
    logic accept;                     \
    writeregflags_t writeback;        \
    readregflags_t register_read;     \
    logic loadstore;                  \
  } x_issue_resp_t;

`define CORE_V_XIF_REGISTER_T(X_RFR_WIDTH)          \
  typedef struct {                                  \
    hartid_t hartid;                                \
    id_t id;                                        \
    logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];       \
    readregflags_t rs_valid;                        \
  } x_register_t;

`define CORE_V_XIF_COMMIT_T     \
  typedef struct packed {       \
    hartid_t hartid;            \
    id_t id;                    \
    logic commit_kill;          \
  } x_commit_t;

`define CORE_V_XIF_RESULT_T(X_RFW_WIDTH)    \
  typedef struct packed {                   \
    hartid_t hartid;                        \
    id_t id;                                \
    logic [X_RFW_WIDTH     -1:0] data;      \
    logic [4:0] rd;                         \
    writeregflags_t we;                     \
    logic exc;                              \
    logic [5:0] exccode;                    \
    logic dbg;                              \
    logic err;                              \
  } x_result_t;

`define CORE_V_XIF_ACC_REQ_T      \
  typedef struct packed {         \
    fpnew_pkg::roundmode_e frm;   \
    logic store_pending;          \
    logic acc_cons_en;            \
    logic inval_ready;            \
  } x_acc_req_t;

`define CORE_V_XIF_ACC_RESP_T(AxiAddrWidth) \
  typedef struct packed {                   \
    logic error;                            \
    logic store_pending;                    \
    logic store_complete;                   \
    logic load_complete;                    \
    logic [4:0] fflags;                     \
    logic fflags_valid;                     \
    logic inavl_valid;                      \
    logic [63:0] inval_addr;                \
  } x_acc_resp_t;

`endif