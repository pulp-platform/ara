// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File:   ara_pkg.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's main package, containing most of the definitions for its usage.

package ara_pkg;

  /****************
   *  Parameters  *
   ****************/

  // Maximum size of a single vector element, in bits.
  // Ara only supports vector elements up to 64 bits.
  localparam int unsigned ELEN  = 64;
  // Maximum size of a single vector element, in bytes.
  localparam int unsigned ELENB = ELEN / 8;
  // Number of bits in a vector register.
  localparam int unsigned VLEN  = `ifdef VLEN `VLEN `else 0 `endif;
  // Number of bytes in a vector register.
  localparam int unsigned VLENB = VLEN / 8;
  // Maximum vector length (in elements).
  localparam int unsigned MAXVL = VLEN; // SEW = EW8, LMUL = 8. VL = 8 * VLEN / 8 = VLEN.

  // Number of vector instructions that can run in parallel.
  localparam int unsigned NrVInsn = 8;

  /*****************
   *  Definitions  *
   *****************/

  typedef logic [$clog2(MAXVL)-1:0] vlen_t;
  typedef logic [$clog2(NrVInsn)-1:0] vid_t;

  typedef logic [ELEN-1:0] elen_t;

  /****************
   *  Operations  *
   ****************/

  typedef enum logic [3:0] {
    // Arithmetic instructions
    VADD, VSUB, VAND, VOR, VXOR,
    // Load instructions
    VLE, VLSE, VLXE,
    // Store instructions
    VSE, VSSE, VSXE
  } ara_op_e;

  // Return true if op is a load operation
  function automatic is_load(ara_op_e op);
    is_load = op inside {[VLE:VLXE]};
  endfunction: is_load

  // Return true if op is a store operation
  function automatic is_store(ara_op_e op);
    is_store = op inside {[VSE:VSXE]};
  endfunction: is_store

  /***************************
   *  Accelerator interface  *
   ***************************/

  // Use Ariane's accelerator interface.
  typedef ariane_pkg::accelerator_req_t accelerator_req_t;
  typedef ariane_pkg::accelerator_resp_t accelerator_resp_t;

  /***********************
   *  Backend interface  *
   ***********************/

  // Interfaces between Ara's dispatcher and Ara's backend

  typedef struct packed {
    ara_op_e op; // Operation
    logic vm;    // Masked instruction

    logic [4:0] vs1; // 1st vector register operand
    logic use_vs1;
    logic [4:0] vs2; // 2nd vector register operand
    logic use_vs2;
    elen_t scalar_op; // Scalar operand
    logic use_scalar_op;
    elen_t stride; // 2nd scalar operand: stride for constant-strided vector load/stores

    logic [4:0] vd; // Destination vector register
    logic use_vd;   // Instruction writes to vd

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;
  } ara_req_t;

  typedef struct packed {
    // Scalar response
    elen_t resp;

    // Instruction triggered an error
    logic error;
  } ara_resp_t;

  /******************
   *  PE interface  *
   ******************/

  // Those are Ara's VFUs.
  //
  // It is important that all the VFUs that can write back to the VRF
  // are grouped towards the beginning of the enumeration. The store unit
  // cannot do so, therefore it is at the end of the enumeration.
  localparam int unsigned NrVFUs = 5;
  typedef enum logic [$clog2(NrVFUs)-1:0] {
    VFU_Alu, VFU_MFpu, VFU_SlideUnit, VFU_LoadUnit, VFU_StoreUnit
  } vfu_e;

  typedef struct packed {
    vid_t id; // ID of the vector instruction

    ara_op_e op; // Operation
    logic vm;    // Masked instruction

    vfu_e vfu; // VFU responsible for handling this instruction

    logic [4:0] vs1; // 1st vector register operand
    logic use_vs1;
    logic [4:0] vs2; // 2nd vector register operand
    logic use_vs2;
    elen_t scalar_op; // Scalar operand
    logic use_scalar_op;
    elen_t stride; // 2nd scalar operand: stride for constant-strided vector load/stores

    logic [4:0] vd; // Destination vector register
    logic use_vd;   // Instruction writes to vd

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;

    // Running vector instructions
    logic [NrVInsn-1:0] vinsn_running;

    // Hazards
    logic [NrVInsn-1:0] hazard_vs1;
    logic [NrVInsn-1:0] hazard_vs2;
    logic [NrVInsn-1:0] hazard_vm;
    logic [NrVInsn-1:0] hazard_vd;
  } pe_req_t;

  typedef struct packed {
    // Each set bit indicates that the corresponding vector loop has finished execution
    logic [NrVInsn-1:0] vinsn_done;
  } pe_resp_t;

  /**********************
   *  Lane definitions  *
   **********************/

  // There are seven operand queues, serving operands to the different functional units of each lane
  localparam int unsigned NrOperandQueues = 7;
  typedef enum logic [$clog2(NrOperandQueues)-1:0] {
    AluA, AluB, MulFPUA, MulFPUB, MulFPUC, StA, AddrGenA
  } opqueue_e;

  // Each lane has eight VRF banks
  localparam int unsigned NrVRFBanksPerLane = 8;

  // Find the starting address of a vector register vid
  function automatic logic [63:0] vaddr(logic [4:0] vid, int NrLanes);
    vaddr = vid * (VLENB >> NrLanes);
  endfunction: vaddr

  // This is the interface between the lane's sequencer and the operand request stage, which
  // makes consecutive requests to the vector elements inside the VRF.
  typedef struct packed {
    vid_t id; // ID of the vector instruction

    logic [4:0] vs; // Vector register operand
    logic use_vs;

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;

    // Hazards
    logic [NrVInsn-1:0] hazard;
  } operand_request_cmd_t;

  // This is the interface between the lane's sequencer and the lane's VFUs.
  typedef struct packed {
    vid_t id; // ID of the vector instruction

    ara_op_e op; // Operation
    logic vm;    // Masked instruction

    elen_t scalar_op; // Scalar operand
    logic use_scalar_op;

    vfu_e vfu; // VFU responsible for this instruction

    logic [4:0] vd; // Vector destination register
    logic use_vd;

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;
  } vfu_operation_t;

  /***************************************
   *  Vector Load/Store Unit definition  *
   ***************************************/

  // The address generation unit makes requests on the AR/AW buses, while the load and
  // store unit handle the R, W, and B buses. The latter need some information about the
  // original request, namely the fields below.
  typedef struct packed {
    axi_pkg::largest_addr_t addr;
    axi_pkg::size_t size;
    axi_pkg::len_t len;
    logic is_load;
  } addrgen_axi_req_t;

endpackage : ara_pkg
