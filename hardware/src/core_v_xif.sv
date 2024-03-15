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

interface core_v_xif
#(
  parameter int unsigned X_NUM_RS               = 2,  // Number of register file read ports that can be used by the eXtension interface
  parameter int unsigned X_ID_WIDTH             = 4,  // Width of ID field.
  parameter int unsigned X_RFR_WIDTH            = 32, // Register file read access width for the eXtension interface
  parameter int unsigned X_RFW_WIDTH            = 32, // Register file write access width for the eXtension interface
  parameter int unsigned X_NUM_HARTS            = 1,  // Number of harts (hardware threads) associated with the interface
  parameter int unsigned X_HARTID_WIDTH         = 1,  // Width of ``hartid`` signals.
  parameter logic [31:0] X_MISA                 = '0, // MISA extensions implemented on the eXtension interface
  parameter logic [ 1:0] X_ECS_XS               = '0, // Initial value for mstatus.XS
  parameter int unsigned X_DUALREAD             = 0,  // Is dual read supported? 0: No, 1: Yes, for ``rs1``, 2: Yes, for ``rs1`` - ``rs2``, 3: Yes, for ``rs1`` - ``rs3``
  parameter int unsigned X_DUALWRITE            = 0,  // Is dual write supported? 0: No, 1: Yes.
  parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,  // Does the interface pipeline register interface? 0: No, 1: Yes.
  parameter int unsigned X_MEM_WIDTH            = 32  // Memory access width for loads/stores via the eXtension interface
);

  typedef logic [X_NUM_RS+X_DUALREAD-1:0] readregflags_t;
  typedef logic [X_DUALWRITE:0] writeregflags_t;
  typedef logic [X_NUM_RS-1:0][X_RFR_WIDTH-1:0] mode_t;
  typedef logic [X_ID_WIDTH-1:0] id_t;
  typedef logic [X_HARTID_WIDTH-1:0] hartid_t;

  typedef struct packed {
    logic [15:0] instr;  // Offloaded compressed instruction
    hartid_t hartid;  // Identification of the hart offloading the instruction
  } x_compressed_req_t;

  typedef struct packed {
    logic [31:0] instr;  // Uncompressed instruction
    logic accept;  // Is the offloaded compressed instruction (id) accepted by the coprocessor?
  } x_compressed_resp_t;

  typedef struct packed {
    logic [31:0] instr;  // Offloaded instruction
    mode_t mode;  // Effective Privilege level, as used for load and store instructions.
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
  } x_issue_req_t;

  typedef struct packed {
    logic accept;  // Is the offloaded instruction (id) accepted by the coprocessor?
    writeregflags_t writeback;  // Will the coprocessor perform a writeback in the core to rd?
    readregflags_t register_read;   // Will the coprocessor perform require specific registers to be read?
    logic ecswrite;  // Will the coprocessor perform a writeback in the core to mstatus.xs, mstatus.fs, mstatus.vs
    logic loadstore;  // Is the offloaded instruction a load/store instruction?
  } x_issue_resp_t;

  typedef struct {
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
    /* verilator lint_off UNPACKED */
    logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];  // Register file source operands for the offloaded instruction.
    readregflags_t rs_valid; // Validity of the register file source operand(s).
    logic [5:0] ecs; // Extension Context Status ({mstatus.xs, mstatus.fs, mstatus.vs})
    logic ecs_valid; // Validity of the Extension Context Status.
  } x_register_t;

  typedef struct packed {
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
    logic commit_kill;  // Shall an offloaded instruction be killed?
  } x_commit_t;

  typedef struct packed {
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
    logic [31:0] addr;  // Virtual address of the memory transaction
    mode_t mode;  // Privilege level
    logic we;  // Write enable of the memory transaction
    logic [2:0] size;  // Size of the memory transaction
    logic [X_MEM_WIDTH/8-1:0] be;  // Byte enables for memory transaction
    logic [1:0] attr;  // Memory transaction attributes
    logic [X_MEM_WIDTH  -1:0] wdata;  // Write data of a store memory transaction
    logic last;  // Is this the last memory transaction for the offloaded instruction?
    logic spec;  // Is the memory transaction speculative?
  } x_mem_req_t;

  typedef struct packed {
    logic exc;  // Did the memory request cause a synchronous exception?
    logic [5:0] exccode;  // Exception code
    logic dbg;  // Did the memory request cause a debug trigger match with ``mcontrol.timing`` = 0?
  } x_mem_resp_t;

  typedef struct packed {
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
    logic [X_MEM_WIDTH-1:0] rdata;  // Read data of a read memory transaction
    logic err;  // Did the instruction cause a bus error?
    logic dbg;  // Did the read data cause a debug trigger match with ``mcontrol.timing`` = 0?
  } x_mem_result_t;

  typedef struct packed {
    hartid_t hartid;  // Identification of the hart offloading the instruction
    id_t id;  // Identification of the offloaded instruction
    logic [X_RFW_WIDTH     -1:0] data;  // Register file write data value(s)
    logic [4:0] rd;  // Register file destination address(es)
    writeregflags_t we;  // Register file write enable(s)
    logic [2:0] ecswe;  // Write enables for {mstatus.xs, mstatus.fs, mstatus.vs}
    logic [5:0] ecsdata;  // Write data value for {mstatus.xs, mstatus.fs, mstatus.vs}
    logic exc;  // Did the instruction cause a synchronous exception?
    logic [5:0] exccode;  // Exception code
    logic dbg;  // Did the instruction cause a debug trigger match with ``mcontrol.timing`` = 0?
    logic err;  // Did the instruction cause a bus error?
  } x_result_t;

  typedef struct packed {
    fpnew_pkg::roundmode_e  frm;
    logic                   store_pending_req;
    logic                   acc_cons_en;
    logic                   inval_ready;
  } x_mod_req_t;

  typedef struct packed {
    logic                   error;
    logic                   store_pending_resp;
    logic                   store_complete;
    logic                   load_complete;
    logic [4:0]             fflags;
    logic                   fflags_valid;
    logic                   inval_valid;
    logic [63:0]            inval_addr;
  } x_mod_resp_t;

  // Compressed interface
  logic               compressed_valid;
  logic               compressed_ready;
  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;

  // Issue interface
  logic               issue_valid;
  logic               issue_ready;
  x_issue_req_t       issue_req;
  x_issue_resp_t      issue_resp;

  // Register interface
  logic               register_valid;
  logic               register_ready;
  x_register_t        register;

  // Commit interface
  logic               commit_valid;
  x_commit_t          commit;

  // Memory (request/response) interface
  logic               mem_valid;
  logic               mem_ready;
  x_mem_req_t         mem_req;
  x_mem_resp_t        mem_resp;

  // Memory result interface
  logic               mem_result_valid;
  x_mem_result_t      mem_result;

  // Result interface
  logic               result_valid;
  logic               result_ready;
  x_result_t          result;

  // Modified interface for ara and cva6 
  x_mod_req_t         mod_req;
  x_mod_resp_t        mod_resp;             

  // Port directions for host CPU
  modport core_v_xif_cpu_compressed (
    output compressed_valid,
    input  compressed_ready,
    output compressed_req,
    input  compressed_resp
  );

  modport core_v_xif_cpu_issue (
    output issue_valid,
    input  issue_ready,
    output issue_req,
    input  issue_resp
  );

  modport core_v_xif_cpu_register (
    output register_valid,
    input  register_ready,
    output register
  );

  modport core_v_xif_cpu_commit (
    output commit_valid,
    output commit
  );

  modport core_v_xif_cpu_mem (
    input  mem_valid,
    output mem_ready,
    input  mem_req,
    output mem_resp
  );

  modport core_v_xif_cpu_mem_result (
    output mem_result_valid,
    output mem_result
  );

  modport core_v_xif_cpu_result (
    input  result_valid,
    output result_ready,
    input  result
  );

  modport core_v_xif_cpu_mod (
    output mod_req,
    input  mod_resp
  );

  // Port directions for CO-PROCESSOR
  modport core_v_xif_coprocessor_compressed (
    input   compressed_valid,
    output  compressed_ready,
    input   compressed_req,
    output  compressed_resp
  );

  modport core_v_xif_coprocessor_issue (
    input   issue_valid,
    output  issue_ready,
    input   issue_req,
    output  issue_resp
  );

  modport core_v_xif_coprocessor_register (
    input   register_valid,
    output  register_ready,
    input   register
  );

  modport core_v_xif_coprocessor_commit (
    input   commit_valid,
    input   commit
  );

  modport core_v_xif_coprocessor_mem (
    output  mem_valid,
    input   mem_ready,
    output  mem_req,
    input   mem_resp
  );

  modport core_v_xif_coprocessor_mem_result (
    input   mem_result_valid,
    input   mem_result
  );

  modport core_v_xif_coprocessor_result (
    output  result_valid,
    input   result_ready,
    output  result
  );

  modport core_v_xif_coprocessor_mod (
    input   mod_req,
    output  mod_resp
  );


endinterface : core_v_xif

