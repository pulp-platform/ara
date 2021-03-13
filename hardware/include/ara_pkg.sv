// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
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

  // Maximum number of lanes that Ara can support.
  localparam int unsigned MaxNrLanes = 16;

  // Multiplier latencies.
  localparam int unsigned LatMultiplierEW64 = 1;
  localparam int unsigned LatMultiplierEW32 = 1;
  localparam int unsigned LatMultiplierEW16 = 0;
  localparam int unsigned LatMultiplierEW8  = 0;

  // FPU latencies.
  localparam int unsigned LatFCompEW64    = 'd5;
  localparam int unsigned LatFCompEW32    = 'd4;
  localparam int unsigned LatFCompEW16    = 'd3;
  localparam int unsigned LatFCompEW8     = 'd2;
  localparam int unsigned LatFCompEW16Alt = 'd3;
  localparam int unsigned LatFDivSqrt     = 'd3;
  localparam int unsigned LatFNonComp     = 'd1;
  localparam int unsigned LatFConv        = 'd2;

  /*****************
   *  Definitions  *
   *****************/

  typedef logic [$clog2(MAXVL)-1:0] vlen_t;
  typedef logic [$clog2(NrVInsn)-1:0] vid_t;

  typedef logic [ELEN-1:0] elen_t;

  /****************
   *  Operations  *
   ****************/

  typedef enum logic [6:0] {
    // Arithmetic and logic instructions
    VADD, VSUB, VADC, VSBC, VRSUB, VMINU, VMIN, VMAXU, VMAX, VAND, VOR, VXOR,
    // Shifts,
    VSLL, VSRL, VSRA, VNSRL, VNSRA,
    // Merge
    VMERGE,
    // Mul/Mul-Add
    VMUL, VMULH, VMULHU, VMULHSU, VMACC, VNMSAC, VMADD, VNMSUB,
    // Div
    VDIVU, VDIV, VREMU, VREM,
    // FPU
    VFADD, VFSUB, VFRSUB, VFMUL, VFMACC, VFNMACC, VFMSAC, VFNMSAC, VFMADD, VFNMADD, VFMSUB, VFNMSUB, VFMIN, VFMAX,
    // Mask operations
    VMANDNOT, VMAND, VMOR, VMXOR, VMORNOT, VMNAND, VMNOR, VMXNOR,
    // Integer comparison instructions
    VMSEQ, VMSNE, VMSLTU, VMSLT, VMSLEU, VMSLE, VMSGTU, VMSGT,
    // Integer add-with-carry and subtract-with-borrow carry-out instructions
    VMADC, VMSBC,
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

  /**********************
   *  Width conversion  *
   **********************/

  // Some instructions mix vector element widths. For example, widening integers, vwadd.vv,
  // operate on 2*SEW = SEW + SEW. In Ara, we would out the whole instruction on 2*SEW.
  //
  // The operand queues are responsible for taking an element of width EEW and converting it on
  // an element of width SEW for the functional units. The operand queues support the following
  // type conversions:

  localparam int unsigned NumConversions = 7;

  typedef enum logic [$clog2(NumConversions)-1:0] {
    OpQueueConversionNone,
    OpQueueConversionZExt2,
    OpQueueConversionSExt2,
    OpQueueConversionZExt4,
    OpQueueConversionSExt4,
    OpQueueConversionZExt8,
    OpQueueConversionSExt8
  } opqueue_conversion_e;

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

    // Mask vector register operand
    logic vm;
    rvv_pkg::vew_e eew_vmask;

    // 1st vector register operand
    logic [4:0] vs1;
    logic use_vs1;
    opqueue_conversion_e conversion_vs1;
    rvv_pkg::vew_e eew_vs1;

    // 2nd vector register operand
    logic [4:0] vs2;
    logic use_vs2;
    opqueue_conversion_e conversion_vs2;
    rvv_pkg::vew_e eew_vs2;

    // Use vd as an operand as well (e.g., vmacc)
    logic use_vd_op;
    rvv_pkg::vew_e eew_vd_op;

    // Scalar operand
    elen_t scalar_op;
    logic use_scalar_op;

    // 2nd scalar operand: stride for constant-strided vector load/stores
    elen_t stride;

    // Destination vector register
    logic [4:0] vd;
    logic use_vd;

    // If asserted: vs2 is kept in MulFPU opqueue C, and vd_op in MulFPU A
    logic swap_vs2_vd_op;

    // Effective length multiplier
    rvv_pkg::vlmul_e emul;

    // Rounding-Mode for FP operations
    fpnew_pkg::roundmode_e fp_rm;

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
  localparam int unsigned NrVFUs = 6;
  typedef enum logic [$clog2(NrVFUs)-1:0] {
    VFU_Alu, VFU_MFpu, VFU_SlideUnit, VFU_MaskUnit, VFU_LoadUnit, VFU_StoreUnit
  } vfu_e;

  // Internally, each lane is treated as a processing element, between indexes
  // 0 and NrLanes-1. Besides such PEs, functional units that act at a global
  // scale also are with index given by NrLanes plus the following offset.
  //
  // The load and the store unit must be at the beginning of this enumeration.
  typedef enum {
    OffsetLoad, OffsetStore, OffsetMask, OffsetSlide
  } vfu_offset_e;

  typedef struct packed {
    vid_t id; // ID of the vector instruction

    ara_op_e op; // Operation

    // Mask vector register operand
    logic vm;
    rvv_pkg::vew_e eew_vmask;

    vfu_e vfu; // VFU responsible for handling this instruction

    // 1st vector register operand
    logic [4:0] vs1;
    logic use_vs1;
    opqueue_conversion_e conversion_vs1;
    rvv_pkg::vew_e eew_vs1;

    // 2nd vector register operand
    logic [4:0] vs2;
    logic use_vs2;
    opqueue_conversion_e conversion_vs2;
    rvv_pkg::vew_e eew_vs2;

    // Use vd as an operand as well (e.g., vmacc)
    logic use_vd_op;
    rvv_pkg::vew_e eew_vd_op;

    // Scalar operand
    elen_t scalar_op;
    logic use_scalar_op;

    // If asserted: vs2 is kept in MulFPU opqueue C, and vd_op in MulFPU A
    logic swap_vs2_vd_op;

    // 2nd scalar operand: stride for constant-strided vector load/stores
    elen_t stride;

    // Destination vector register
    logic [4:0] vd;
    logic use_vd;

    // Effective length multiplier
    rvv_pkg::vlmul_e emul;

    // Rounding-Mode for FP operations
    fpnew_pkg::roundmode_e fp_rm;

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

  // The VRF data is stored into the lanes in a shuffled way, similar to how it was done
  // in version 0.9 of the RISC-V Vector Specification, when SLEN < VLEN. In fact, VRF
  // data is organized in lanes as in section 4.3 of the RVV Specification v0.9, with
  // the striping distance set to SLEN = 64, the lane width.
  //
  // As an example, with four lanes, the elements of a vector register are organized
  // as follows.
  //
  // Byte:      1F 1E 1D 1C 1B 1A 19 18 | 17 16 15 14 13 12 11 10 | 0F 0E 0D 0C 0B 0A 09 08 | 07 06 05 04 03 02 01 00 |
  //                                    |                         |                         |                         |
  // SEW = 64:                        3 |                       2 |                       1 |                       0 |
  // SEW = 32:            7           3 |           6           2 |           5           1 |           4           0 |
  // SEW = 16:      F     7     B     3 |     E     6     A     2 |     D     5     9     1 |     C     4     8     0 |
  // SEW = 8:   1F  F 17  7 1B  B 13  3 | 1E  E 16  6 1A  A 12  2 | 1D  D 15  5 19  9 11  1 | 1C  C 14  4 18  8 10  0 |
  //
  // Data coming from/going to the lanes must be reshuffled, in order to be organized
  // in a natural way (i.e., with the bits packed simply from the least-significant
  // to the most-significant). This operation is done by the shuffle (natural packing
  // to the lane's organization) and deshuffle (lane's organization to the natural
  // packing) functions.

  function automatic vlen_t shuffle_index(vlen_t byte_idx, int NrLanes, rvv_pkg::vew_e ew);
    // Generate the shuffling of the table above
    unique case (NrLanes)
      1: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 5; idx[4] = 4; idx[3] = 3; idx[2] = 2; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 5; idx[4] = 4; idx[3] = 3; idx[2] = 2; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 3; idx[4] = 2; idx[3] = 5; idx[2] = 4; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 3; idx[5] = 5; idx[4] = 1; idx[3] = 6; idx[2] = 2; idx[1] = 4; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
        endcase
      4: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 29; idx[28] = 28; idx[27] = 27; idx[26] = 26; idx[25] = 25; idx[24] = 24;
            idx[23] = 23; idx[22] = 22; idx[21] = 21; idx[20] = 20; idx[19] = 19; idx[18] = 18; idx[17] = 17; idx[16] = 16;
            idx[15] = 15; idx[14] = 14; idx[13] = 13; idx[12] = 12; idx[11] = 11; idx[10] = 10; idx[09] = 09; idx[08] = 08;
            idx[07] = 07; idx[06] = 06; idx[05] = 05; idx[04] = 04; idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 29; idx[28] = 28; idx[27] = 23; idx[26] = 22; idx[25] = 21; idx[24] = 20;
            idx[23] = 15; idx[22] = 14; idx[21] = 13; idx[20] = 12; idx[19] = 07; idx[18] = 06; idx[17] = 05; idx[16] = 04;
            idx[15] = 27; idx[14] = 26; idx[13] = 25; idx[12] = 24; idx[11] = 19; idx[10] = 18; idx[09] = 17; idx[08] = 16;
            idx[07] = 11; idx[06] = 10; idx[05] = 09; idx[04] = 08; idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 23; idx[28] = 22; idx[27] = 15; idx[26] = 14; idx[25] = 07; idx[24] = 06;
            idx[23] = 27; idx[22] = 26; idx[21] = 19; idx[20] = 18; idx[19] = 11; idx[18] = 10; idx[17] = 03; idx[16] = 02;
            idx[15] = 29; idx[14] = 28; idx[13] = 21; idx[12] = 20; idx[11] = 13; idx[10] = 12; idx[09] = 05; idx[08] = 04;
            idx[07] = 25; idx[06] = 24; idx[05] = 17; idx[04] = 16; idx[03] = 09; idx[02] = 08; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 23; idx[29] = 15; idx[28] = 07; idx[27] = 27; idx[26] = 19; idx[25] = 11; idx[24] = 03;
            idx[23] = 29; idx[22] = 21; idx[21] = 13; idx[20] = 05; idx[19] = 25; idx[18] = 17; idx[17] = 09; idx[16] = 01;
            idx[15] = 30; idx[14] = 22; idx[13] = 14; idx[12] = 06; idx[11] = 26; idx[10] = 18; idx[09] = 10; idx[08] = 02;
            idx[07] = 28; idx[06] = 20; idx[05] = 12; idx[04] = 04; idx[03] = 24; idx[02] = 16; idx[01] = 08; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
        endcase
    // TODO: Remaining NrLanes. Generalize this case accordingly to the function below.
    endcase

  /*automatic vlen_t [8*MaxNrLanes-1:0] element_shuffle_index;

   unique case (ew)
   rvv_pkg::EW64:
   for (vlen_t element = 0; element < NrLanes; element++)
   for (int b = 0; b < 8; b++)
   element_shuffle_index[8*(element >> 0) + b] = 8*element + b;
   rvv_pkg::EW32:
   for (vlen_t element = 0; element < 2*NrLanes; element++)
   for (int b = 0; b < 4; b++)
   element_shuffle_index[4*((element >> 1) + int'(element[0]) * NrLanes*1) + b] = 4*element + b;
   rvv_pkg::EW16:
   for (vlen_t element = 0; element < 4*NrLanes; element++)
   for (int b = 0; b < 2; b++)
   element_shuffle_index[2*((element >> 2) + int'(element[1]) * NrLanes*1 + int'(element[0]) * NrLanes*2) + b] = 2*element + b;
   rvv_pkg::EW8:
   for (vlen_t element = 0; element < 8*NrLanes; element++)
   for (int b = 0; b < 1; b++)
   element_shuffle_index[1*((element >> 3) + int'(element[2]) * NrLanes*1 + int'(element[1]) * NrLanes*2 + int'(element[0]) * NrLanes*4) + b] = 1*element + b;
   default:;
   endcase

   return element_shuffle_index[byte_index];*/
  endfunction: shuffle_index

  function automatic vlen_t deshuffle_index(vlen_t byte_index, int NrLanes, rvv_pkg::vew_e ew);
    // Generate the deshuffling of the table above
    unique case (NrLanes)
      1: begin
        automatic vlen_t [7:0] index;
        for (int b = 0; b < 8; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[2:0]];
      end
      4: begin
        automatic vlen_t [31:0] index;
        for (int b = 0; b < 32; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[4:0]];
      end
    // TODO: Remaining NrLanes. Generalize this case accordingly to the function below.
    endcase

  /*automatic vlen_t [8*MaxNrLanes-1:0] element_deshuffle_index;

   // Generate the deshuffling table above
   unique case (ew)
   rvv_pkg::EW64:
   for (vlen_t element = 0; element < NrLanes; element++)
   for (int b = 0; b < 8; b++)
   element_deshuffle_index[8*element + b] = 8*(element >> 0) + b;
   rvv_pkg::EW32:
   for (vlen_t element = 0; element < 2*NrLanes; element++)
   for (int b = 0; b < 4; b++)
   element_deshuffle_index[4*element + b] = 4*((element >> 1) + int'(element[0]) * NrLanes*1) + b;
   rvv_pkg::EW16:
   for (vlen_t element = 0; element < 4*NrLanes; element++)
   for (int b = 0; b < 2; b++)
   element_deshuffle_index[2*element + b] = 2*((element >> 2) + int'(element[1]) * NrLanes*1 + int'(element[0]) * NrLanes*2) + b;
   rvv_pkg::EW8:
   for (vlen_t element = 0; element < 8*NrLanes; element++)
   for (int b = 0; b < 1; b++)
   element_deshuffle_index[1*element + b] = 1*((element >> 3) + int'(element[2]) * NrLanes*1 + int'(element[1]) * NrLanes*2 + int'(element[0]) * NrLanes*4) + b;
   default:;
   endcase

   return element_deshuffle_index[byte_index];*/
  endfunction: deshuffle_index

  /**********************
   *  Lane definitions  *
   **********************/

  // There are seven operand queues, serving operands to the different functional units of each lane
  localparam int unsigned NrOperandQueues = 9;
  typedef enum logic [$clog2(NrOperandQueues)-1:0] {
    AluA, AluB, MulFPUA, MulFPUB, MulFPUC, MaskB, MaskM, StA, AddrGenA
  } opqueue_e;

  // Each lane has eight VRF banks
  localparam int unsigned NrVRFBanksPerLane = 8;

  // Find the starting address of a vector register vid
  function automatic logic [63:0] vaddr(logic [4:0] vid, int NrLanes);
    vaddr = vid * (VLENB / NrLanes / 8);
  endfunction: vaddr

  // This is the interface between the lane's sequencer and the operand request stage, which
  // makes consecutive requests to the vector elements inside the VRF.
  typedef struct packed {
    vid_t id; // ID of the vector instruction

    logic [4:0] vs; // Vector register operand

    rvv_pkg::vew_e eew;        // Effective element width
    opqueue_conversion_e conv; // Type conversion

    // Vector machine metadata
    rvv_pkg::vtype_t vtype;
    vlen_t vl;
    vlen_t vstart;

    // Hazards
    logic [NrVInsn-1:0] hazard;
  } operand_request_cmd_t;

  typedef struct packed {
    rvv_pkg::vew_e eew;        // Effective element width
    vlen_t vl;                 // Vector length
    opqueue_conversion_e conv; // Type conversion
  } operand_queue_cmd_t;

  // This is the interface between the lane's sequencer and the lane's VFUs.
  typedef struct packed {
    vid_t id; // ID of the vector instruction

    ara_op_e op; // Operation
    logic vm;    // Masked instruction

    logic use_vs1;   // This operation uses vs1
    logic use_vs2;   // This operation uses vs1
    logic use_vd_op; // This operation uses vd as an operand as well

    elen_t scalar_op;    // Scalar operand
    logic use_scalar_op; // This operation uses the scalar operand

    vfu_e vfu; // VFU responsible for this instruction

    logic [4:0] vd; // Vector destination register
    logic use_vd;

    logic swap_vs2_vd_op; // If asserted: vs2 is kept in MulFPU opqueue C, and vd_op in MulFPU A

    fpnew_pkg::roundmode_e fp_rm; // Rounding-Mode for FP operations

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;
  } vfu_operation_t;

  // Due to the shuffled nature of the vector elements inside one lane, the byte enable
  // signal must be generated differently depending on how many valid elements are there.
  // Considering the lane 0 of the previous example, and vector elements of width 8 bits,
  //
  // Byte:      07 06 05 04 03 02 01 00
  // SEW = 8:   1C  C 14  4 18  8 10  0
  //
  // If there are only three valid vector elements (0, 4, and 8), then the byte enable of
  // that word should be 8'b00010101. The position of the i-th vector element inside one
  // lane is is generated using the same shuffle function as shuffle_index, but considering
  // NrLanes = 1.

  // The following function generates a 8-bit wide byte enable signal, based on how many
  // valid elements are there in that lane word, and the element width.

  function automatic logic [ELEN/8-1:0] be(logic [3:0] cnt, rvv_pkg::vew_e ew);
    unique case (ew)
      rvv_pkg::EW8:
        for (int el = 0; el < 8; el++)
          for (int b = 0; b < 1; b++)
            be[shuffle_index(1*el + b, 1, ew)] = el < cnt;
      rvv_pkg::EW16:
        for (int el = 0; el < 4; el++)
          for (int b = 0; b < 2; b++)
            be[shuffle_index(2*el + b, 1, ew)] = el < cnt;
      rvv_pkg::EW32:
        for (int el = 0; el < 2; el++)
          for (int b = 0; b < 4; b++)
            be[shuffle_index(4*el + b, 1, ew)] = el < cnt;
      rvv_pkg::EW64:
        for (int el = 0; el < 1; el++)
          for (int b = 0; b < 8; b++)
            be[shuffle_index(8*el + b, 1, ew)] = el < cnt;
      default:;
    endcase
  endfunction: be

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
