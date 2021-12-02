// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's main package, containing most of the definitions for its usage.

package ara_pkg;

  //////////////////
  //  Parameters  //
  //////////////////

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

  // Ara Features.

  // The three bits correspond to {RVVD, RVVF, RVVH}
  typedef enum logic [2:0] {
    FPUSupportNone             = 3'b000,
    FPUSupportHalf             = 3'b001,
    FPUSupportSingle           = 3'b010,
    FPUSupportHalfSingle       = 3'b011,
    FPUSupportDouble           = 3'b100,
    FPUSupportSingleDouble     = 3'b110,
    FPUSupportHalfSingleDouble = 3'b111
  } fpu_support_e;

  function automatic logic RVVD(fpu_support_e e);
    return e[2];
  endfunction : RVVD

  function automatic logic RVVF(fpu_support_e e);
    return e[1];
  endfunction : RVVF

  function automatic logic RVVH(fpu_support_e e);
    return e[0];
  endfunction : RVVH

  // Multiplier latencies.
  localparam int unsigned LatMultiplierEW64 = 1;
  localparam int unsigned LatMultiplierEW32 = 1;
  localparam int unsigned LatMultiplierEW16 = 1;
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
  // Define the maximum FPU latency
  localparam int unsigned LatFMax = LatFCompEW64;

  // Define the maximum instruction queue depth
  localparam MaxVInsnQueueDepth = 4;
  // FUs instruction queue depth.
  localparam int unsigned MfpuInsnQueueDepth = 4;
  localparam int unsigned ValuInsnQueueDepth = 4;
  localparam int unsigned VlduInsnQueueDepth = 4;
  localparam int unsigned VstuInsnQueueDepth = 4;
  localparam int unsigned SlduInsnQueueDepth = 2;
  localparam int unsigned NoneInsnQueueDepth = 1;
  // Ara supports MaskuInsnQueueDepth = 1 only.
  localparam int unsigned MaskuInsnQueueDepth = 1;

  ///////////////////
  //  Definitions  //
  ///////////////////

  typedef logic [$clog2(MAXVL+1)-1:0] vlen_t;
  typedef logic [$clog2(NrVInsn)-1:0] vid_t;
  typedef logic [ELEN-1:0] elen_t;

  //////////////////
  //  Operations  //
  //////////////////

  typedef enum logic [6:0] {
    // Arithmetic and logic instructions
    VADD, VSUB, VADC, VSBC, VRSUB, VMINU, VMIN, VMAXU, VMAX, VAND, VOR, VXOR,
    // Fixed point
    VSADDU, VSADD, VSSUBU, VSSUB, VAADDU, VAADD, VASUBU, VASUB,
    // Shifts,
    VSLL, VSRL, VSRA, VNSRL, VNSRA,
    // Merge
    VMERGE,
    // Scalar moves to VRF
    VMVSX, VFMVSF,
    // Integer Reductions
    VREDSUM, VREDAND, VREDOR, VREDXOR, VREDMINU, VREDMIN, VREDMAXU, VREDMAX, VWREDSUMU, VWREDSUM,
    // Mul/Mul-Add
    VMUL, VMULH, VMULHU, VMULHSU, VMACC, VNMSAC, VMADD, VNMSUB,
    // Div
    VDIVU, VDIV, VREMU, VREM,
    // FPU
    VFADD, VFSUB, VFRSUB, VFMUL, VFDIV, VFRDIV, VFMACC, VFNMACC, VFMSAC, VFNMSAC, VFMADD, VFNMADD, VFMSUB,
    VFNMSUB, VFSQRT, VFMIN, VFMAX, VFCLASS, VFSGNJ, VFSGNJN, VFSGNJX, VFCVTXUF, VFCVTXF, VFCVTFXU, VFCVTFX,
    VFCVTRTZXUF, VFCVTRTZXF, VFCVTFF,
    // Floating-point reductions
    VFREDUSUM, VFREDOSUM, VFREDMIN, VFREDMAX, VFWREDUSUM, VFWREDOSUM,
    // Floating-point comparison instructions
    VMFEQ, VMFLE, VMFLT, VMFNE, VMFGT, VMFGE,
    // Integer comparison instructions
    VMSEQ, VMSNE, VMSLTU, VMSLT, VMSLEU, VMSLE, VMSGTU, VMSGT,
    // Integer add-with-carry and subtract-with-borrow carry-out instructions
    VMADC, VMSBC,
    // Mask operations
    VMANDNOT, VMAND, VMOR, VMXOR, VMORNOT, VMNAND, VMNOR, VMXNOR,
    // Scalar moves from VRF
    VMVXS, VFMVFS,
    // Slide instructions
    VSLIDEUP, VSLIDEDOWN,
    // Load instructions
    VLE, VLSE, VLXE,
    // Store instructions
    VSE, VSSE, VSXE
  } ara_op_e;

  // Return true if op is a load operation
  function automatic is_load(ara_op_e op);
    is_load = op inside {[VLE:VLXE]};
  endfunction : is_load

  // Return true if op is a store operation
  function automatic is_store(ara_op_e op);
    is_store = op inside {[VSE:VSXE]};
  endfunction : is_store

  typedef enum logic [1:0] {
    NO_RED,
    ALU_RED,
    MFPU_RED
  } sldu_mux_e;

  ////////////////////////
  //  Width conversion  //
  ////////////////////////

  // Some instructions mix vector element widths. For example, widening integers, vwadd.vv,
  // operate on 2*SEW = SEW + SEW. In Ara, we would out the whole instruction on 2*SEW.
  //
  // The operand queues are responsible for taking an element of width EEW and converting it on
  // an element of width SEW for the functional units. The operand queues support the following
  // type conversions:

  localparam int unsigned NumConversions = 10;

  typedef enum logic [$clog2(NumConversions)-1:0] {
    OpQueueConversionNone,
    OpQueueConversionZExt2,
    OpQueueConversionSExt2,
    OpQueueConversionZExt4,
    OpQueueConversionSExt4,
    OpQueueConversionZExt8,
    OpQueueConversionSExt8,
    OpQueueConversionWideFP2,
    OpQueueIntReductionZExt,
    OpQueueFloatReductionZExt,
    OpQueueFloatReductionWideZExt,
    OpQueueAdjustFPCvt
  } opqueue_conversion_e;
  // OpQueueAdjustFPCvt is introduced to support widening FP conversions, to comply with the
  // required SIMD input format of the FPU module (fpnew)

  // The FPU needs to know if, during the conversion, there is also a width change
  // Moreover, the operand requester treats widening instructions differently for handling WAW
  // CVT_WIDE is equal to 2'b00 since these bits are reused with reductions
  // (this is a hack to save wires)
  // Also for floating-point reduction, it is reused as neutral value
  // 00: zero, 01: positive infinity, 10: negative infinity
  typedef enum logic [1:0] {
    CVT_WIDE   = 2'b00,
    CVT_SAME   = 2'b01,
    CVT_NARROW = 2'b10
  } resize_e;

  // Floating-Point structs for re-encoding during widening FP operations
  typedef struct packed {
    logic s;
    logic [4:0] e;
    logic [9:0] m;
  } fp16_t;

  typedef struct packed {
    logic s;
    logic [7:0] e;
    logic [22:0] m;
  } fp32_t;

  typedef struct packed {
    logic s;
    logic [10:0] e;
    logic [51:0] m;
  } fp64_t;

  /////////////////////////////
  //  Accelerator interface  //
  /////////////////////////////

  // Use Ariane's accelerator interface.
  typedef ariane_pkg::accelerator_req_t accelerator_req_t;
  typedef ariane_pkg::accelerator_resp_t accelerator_resp_t;

  /////////////////////////
  //  Backend interface  //
  /////////////////////////

  // Interfaces between Ara's dispatcher and Ara's backend

  typedef struct packed {
    ara_op_e op; // Operation

    // Rescale vl taking into account the new and old EEW
    logic scale_vl;

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

    // 2nd scalar operand: stride for constant-strided vector load/stores, slide offset for vector
    // slides
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
    // Widen FP immediate (re-encoding)
    logic wide_fp_imm;
    // Resizing of FP conversions
    resize_e cvt_resize;

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;

    // Request token, for registration in the sequencer
    logic token;
  } ara_req_t;

  typedef struct packed {
    // Scalar response
    elen_t resp;

    // Instruction triggered an error
    logic error;

    // New value for vstart
    vlen_t error_vl;
  } ara_resp_t;

  ////////////////////
  //  PE interface  //
  ////////////////////

  // Those are Ara's VFUs.
  //
  // It is important that all the VFUs that can write back to the VRF
  // are grouped towards the beginning of the enumeration. The store unit
  // cannot do so, therefore it is at the end of the enumeration.
  localparam int unsigned NrVFUs = 7;
  typedef enum logic [$clog2(NrVFUs)-1:0] {
    VFU_Alu, VFU_MFpu, VFU_SlideUnit, VFU_MaskUnit, VFU_LoadUnit, VFU_StoreUnit, VFU_None
  } vfu_e;

  // Internally, each lane is treated as a processing element, between indexes
  // 0 and NrLanes-1. Besides such PEs, functional units that act at a global
  // scale also are with index given by NrLanes plus the following offset.
  //
  // The load and the store unit must be at the beginning of this enumeration.
  typedef enum logic [1:0] {
    OffsetLoad, OffsetStore, OffsetMask, OffsetSlide
  } vfu_offset_e;

  typedef struct packed {
    vid_t id; // ID of the vector instruction

    ara_op_e op; // Operation

    // Mask vector register operand
    logic vm;
    rvv_pkg::vew_e eew_vmask;

    vfu_e vfu; // VFU responsible for handling this instruction

    // Rescale vl taking into account the new and old EEW
    logic scale_vl;

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
    // Widen FP immediate (re-encoding)
    logic wide_fp_imm;
    // Resizing of FP conversions
    resize_e cvt_resize;

    // Vector machine metadata
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;

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

  /* The VRF data is stored into the lanes in a shuffled way, similar to how it was done
   * in version 0.9 of the RISC-V Vector Specification, when SLEN < VLEN. In fact, VRF
   * data is organized in lanes as in section 4.3 of the RVV Specification v0.9, with
   * the striping distance set to SLEN = 64, the lane width.
   *
   * As an example, with four lanes, the elements of a vector register are organized
   * as follows.
   *
   * Byte:      1F 1E 1D 1C 1B 1A 19 18 | 17 16 15 14 13 12 11 10 | 0F 0E 0D 0C 0B 0A 09 08 | 07 06 05 04 03 02 01 00 |
   *                                    |                         |                         |                         |
   * SEW = 64:                        3 |                       2 |                       1 |                       0 |
   * SEW = 32:            7           3 |           6           2 |           5           1 |           4           0 |
   * SEW = 16:      F     7     B     3 |     E     6     A     2 |     D     5     9     1 |     C     4     8     0 |
   * SEW = 8:   1F  F 17  7 1B  B 13  3 | 1E  E 16  6 1A  A 12  2 | 1D  D 15  5 19  9 11  1 | 1C  C 14  4 18  8 10  0 |
   *
   * Data coming from/going to the lanes must be reshuffled, in order to be organized
   * in a natural way (i.e., with the bits packed simply from the least-significant
   * to the most-significant). This operation is done by the shuffle (natural packing
   * to the lane's organization) and deshuffle (lane's organization to the natural
   * packing) functions.
   */

  function automatic vlen_t shuffle_index(vlen_t byte_idx, int NrLanes, rvv_pkg::vew_e ew);
    // Generate the shuffling of the table above
    unique case (NrLanes)
      1: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 5; idx[4] = 4;
            idx[3] = 3; idx[2] = 2; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 5; idx[4] = 4;
            idx[3] = 3; idx[2] = 2; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 6; idx[5] = 3; idx[4] = 2;
            idx[3] = 5; idx[2] = 4; idx[1] = 1; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [7:0] idx;
            idx[7] = 7; idx[6] = 3; idx[5] = 5; idx[4] = 1;
            idx[3] = 6; idx[2] = 2; idx[1] = 4; idx[0] = 0;
            return idx[byte_idx[2:0]];
          end
        endcase
      2: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [15:0] idx;
            idx[15] = 15; idx[14] = 14; idx[13] = 13; idx[12] = 12;
            idx[11] = 11; idx[10] = 10; idx[09] = 09; idx[08] = 08;
            idx[07] = 07; idx[06] = 06; idx[05] = 05; idx[04] = 04;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[3:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [15:0] idx;
            idx[15] = 15; idx[14] = 14; idx[13] = 13; idx[12] = 12;
            idx[11] = 07; idx[10] = 06; idx[09] = 05; idx[08] = 04;
            idx[07] = 11; idx[06] = 10; idx[05] = 09; idx[04] = 08;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[3:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [15:0] idx;
            idx[15] = 15; idx[14] = 14; idx[13] = 07; idx[12] = 06;
            idx[11] = 11; idx[10] = 10; idx[09] = 03; idx[08] = 02;
            idx[07] = 13; idx[06] = 12; idx[05] = 05; idx[04] = 04;
            idx[03] = 09; idx[02] = 08; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[3:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [15:0] idx;
            idx[15] = 15; idx[14] = 07; idx[13] = 11; idx[12] = 03;
            idx[11] = 13; idx[10] = 05; idx[09] = 09; idx[08] = 01;
            idx[07] = 14; idx[06] = 06; idx[05] = 10; idx[04] = 02;
            idx[03] = 12; idx[02] = 04; idx[01] = 08; idx[00] = 00;
            return idx[byte_idx[3:0]];
          end
        endcase
      4: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 29; idx[28] = 28;
            idx[27] = 27; idx[26] = 26; idx[25] = 25; idx[24] = 24;
            idx[23] = 23; idx[22] = 22; idx[21] = 21; idx[20] = 20;
            idx[19] = 19; idx[18] = 18; idx[17] = 17; idx[16] = 16;
            idx[15] = 15; idx[14] = 14; idx[13] = 13; idx[12] = 12;
            idx[11] = 11; idx[10] = 10; idx[09] = 09; idx[08] = 08;
            idx[07] = 07; idx[06] = 06; idx[05] = 05; idx[04] = 04;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 29; idx[28] = 28;
            idx[27] = 23; idx[26] = 22; idx[25] = 21; idx[24] = 20;
            idx[23] = 15; idx[22] = 14; idx[21] = 13; idx[20] = 12;
            idx[19] = 07; idx[18] = 06; idx[17] = 05; idx[16] = 04;
            idx[15] = 27; idx[14] = 26; idx[13] = 25; idx[12] = 24;
            idx[11] = 19; idx[10] = 18; idx[09] = 17; idx[08] = 16;
            idx[07] = 11; idx[06] = 10; idx[05] = 09; idx[04] = 08;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 30; idx[29] = 23; idx[28] = 22;
            idx[27] = 15; idx[26] = 14; idx[25] = 07; idx[24] = 06;
            idx[23] = 27; idx[22] = 26; idx[21] = 19; idx[20] = 18;
            idx[19] = 11; idx[18] = 10; idx[17] = 03; idx[16] = 02;
            idx[15] = 29; idx[14] = 28; idx[13] = 21; idx[12] = 20;
            idx[11] = 13; idx[10] = 12; idx[09] = 05; idx[08] = 04;
            idx[07] = 25; idx[06] = 24; idx[05] = 17; idx[04] = 16;
            idx[03] = 09; idx[02] = 08; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [31:0] idx;
            idx[31] = 31; idx[30] = 23; idx[29] = 15; idx[28] = 07;
            idx[27] = 27; idx[26] = 19; idx[25] = 11; idx[24] = 03;
            idx[23] = 29; idx[22] = 21; idx[21] = 13; idx[20] = 05;
            idx[19] = 25; idx[18] = 17; idx[17] = 09; idx[16] = 01;
            idx[15] = 30; idx[14] = 22; idx[13] = 14; idx[12] = 06;
            idx[11] = 26; idx[10] = 18; idx[09] = 10; idx[08] = 02;
            idx[07] = 28; idx[06] = 20; idx[05] = 12; idx[04] = 04;
            idx[03] = 24; idx[02] = 16; idx[01] = 08; idx[00] = 00;
            return idx[byte_idx[4:0]];
          end
        endcase
      8: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [63:0] idx;
            idx[63] = 63; idx[62] = 62; idx[61] = 61; idx[60] = 60;
            idx[59] = 59; idx[58] = 58; idx[57] = 57; idx[56] = 56;
            idx[55] = 55; idx[54] = 54; idx[53] = 53; idx[52] = 52;
            idx[51] = 51; idx[50] = 50; idx[49] = 49; idx[48] = 48;
            idx[47] = 47; idx[46] = 46; idx[45] = 45; idx[44] = 44;
            idx[43] = 43; idx[42] = 42; idx[41] = 41; idx[40] = 40;
            idx[39] = 39; idx[38] = 38; idx[37] = 37; idx[36] = 36;
            idx[35] = 35; idx[34] = 34; idx[33] = 33; idx[32] = 32;
            idx[31] = 31; idx[30] = 30; idx[29] = 29; idx[28] = 28;
            idx[27] = 27; idx[26] = 26; idx[25] = 25; idx[24] = 24;
            idx[23] = 23; idx[22] = 22; idx[21] = 21; idx[20] = 20;
            idx[19] = 19; idx[18] = 18; idx[17] = 17; idx[16] = 16;
            idx[15] = 15; idx[14] = 14; idx[13] = 13; idx[12] = 12;
            idx[11] = 11; idx[10] = 10; idx[09] = 09; idx[08] = 08;
            idx[07] = 07; idx[06] = 06; idx[05] = 05; idx[04] = 04;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[5:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [63:0] idx;
            idx[63] = 63; idx[62] = 62; idx[61] = 61; idx[60] = 60;
            idx[59] = 55; idx[58] = 54; idx[57] = 53; idx[56] = 52;
            idx[55] = 47; idx[54] = 46; idx[53] = 45; idx[52] = 44;
            idx[51] = 39; idx[50] = 38; idx[49] = 37; idx[48] = 36;
            idx[47] = 31; idx[46] = 30; idx[45] = 29; idx[44] = 28;
            idx[43] = 23; idx[42] = 22; idx[41] = 21; idx[40] = 20;
            idx[39] = 15; idx[38] = 14; idx[37] = 13; idx[36] = 12;
            idx[35] = 07; idx[34] = 06; idx[33] = 05; idx[32] = 04;
            idx[31] = 59; idx[30] = 58; idx[29] = 57; idx[28] = 56;
            idx[27] = 51; idx[26] = 50; idx[25] = 49; idx[24] = 48;
            idx[23] = 43; idx[22] = 42; idx[21] = 41; idx[20] = 40;
            idx[19] = 35; idx[18] = 34; idx[17] = 33; idx[16] = 32;
            idx[15] = 27; idx[14] = 26; idx[13] = 25; idx[12] = 24;
            idx[11] = 19; idx[10] = 18; idx[09] = 17; idx[08] = 16;
            idx[07] = 11; idx[06] = 10; idx[05] = 09; idx[04] = 08;
            idx[03] = 03; idx[02] = 02; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[5:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [63:0] idx;
            idx[63] = 63; idx[62] = 62; idx[61] = 55; idx[60] = 54;
            idx[59] = 47; idx[58] = 46; idx[57] = 39; idx[56] = 38;
            idx[55] = 31; idx[54] = 30; idx[53] = 23; idx[52] = 22;
            idx[51] = 15; idx[50] = 14; idx[49] = 07; idx[48] = 06;
            idx[47] = 59; idx[46] = 58; idx[45] = 51; idx[44] = 50;
            idx[43] = 43; idx[42] = 42; idx[41] = 35; idx[40] = 34;
            idx[39] = 27; idx[38] = 26; idx[37] = 19; idx[36] = 18;
            idx[35] = 11; idx[34] = 10; idx[33] = 03; idx[32] = 02;
            idx[31] = 61; idx[30] = 60; idx[29] = 53; idx[28] = 52;
            idx[27] = 45; idx[26] = 44; idx[25] = 37; idx[24] = 36;
            idx[23] = 29; idx[22] = 28; idx[21] = 21; idx[20] = 20;
            idx[19] = 13; idx[18] = 12; idx[17] = 05; idx[16] = 04;
            idx[15] = 57; idx[14] = 56; idx[13] = 49; idx[12] = 48;
            idx[11] = 41; idx[10] = 40; idx[09] = 33; idx[08] = 32;
            idx[07] = 25; idx[06] = 24; idx[05] = 17; idx[04] = 16;
            idx[03] = 09; idx[02] = 08; idx[01] = 01; idx[00] = 00;
            return idx[byte_idx[5:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [63:0] idx;
            idx[63] = 63; idx[62] = 55; idx[61] = 47; idx[60] = 39;
            idx[59] = 31; idx[58] = 23; idx[57] = 15; idx[56] = 07;
            idx[55] = 59; idx[54] = 51; idx[53] = 43; idx[52] = 35;
            idx[51] = 27; idx[50] = 19; idx[49] = 11; idx[48] = 03;
            idx[47] = 61; idx[46] = 53; idx[45] = 45; idx[44] = 37;
            idx[43] = 29; idx[42] = 21; idx[41] = 13; idx[40] = 05;
            idx[39] = 57; idx[38] = 49; idx[37] = 41; idx[36] = 33;
            idx[35] = 25; idx[34] = 17; idx[33] = 09; idx[32] = 01;
            idx[31] = 62; idx[30] = 54; idx[29] = 46; idx[28] = 38;
            idx[27] = 30; idx[26] = 22; idx[25] = 14; idx[24] = 06;
            idx[23] = 58; idx[22] = 50; idx[21] = 42; idx[20] = 34;
            idx[19] = 26; idx[18] = 18; idx[17] = 10; idx[16] = 02;
            idx[15] = 60; idx[14] = 52; idx[13] = 44; idx[12] = 36;
            idx[11] = 28; idx[10] = 20; idx[09] = 12; idx[08] = 04;
            idx[07] = 56; idx[06] = 48; idx[05] = 40; idx[04] = 32;
            idx[03] = 24; idx[02] = 16; idx[01] = 08; idx[00] = 00;
            return idx[byte_idx[5:0]];
          end
        endcase
      16: unique case (ew)
          rvv_pkg::EW64: begin
            automatic vlen_t [127:0] idx;
            idx[127] = 127; idx[126] = 126; idx[125] = 125; idx[124] = 124;
            idx[123] = 123; idx[122] = 122; idx[121] = 121; idx[120] = 120;
            idx[119] = 119; idx[118] = 118; idx[117] = 117; idx[116] = 116;
            idx[115] = 115; idx[114] = 114; idx[113] = 113; idx[112] = 112;
            idx[111] = 111; idx[110] = 110; idx[109] = 109; idx[108] = 108;
            idx[107] = 107; idx[106] = 106; idx[105] = 105; idx[104] = 104;
            idx[103] = 103; idx[102] = 102; idx[101] = 101; idx[100] = 100;
            idx[099] = 099; idx[098] = 098; idx[097] = 097; idx[096] = 096;
            idx[095] = 095; idx[094] = 094; idx[093] = 093; idx[092] = 092;
            idx[091] = 091; idx[090] = 090; idx[089] = 089; idx[088] = 088;
            idx[087] = 087; idx[086] = 086; idx[085] = 085; idx[084] = 084;
            idx[083] = 083; idx[082] = 082; idx[081] = 081; idx[080] = 080;
            idx[079] = 079; idx[078] = 078; idx[077] = 077; idx[076] = 076;
            idx[075] = 075; idx[074] = 074; idx[073] = 073; idx[072] = 072;
            idx[071] = 071; idx[070] = 070; idx[069] = 069; idx[068] = 068;
            idx[067] = 067; idx[066] = 066; idx[065] = 065; idx[064] = 064;
            idx[063] = 063; idx[062] = 062; idx[061] = 061; idx[060] = 060;
            idx[059] = 059; idx[058] = 058; idx[057] = 057; idx[056] = 056;
            idx[055] = 055; idx[054] = 054; idx[053] = 053; idx[052] = 052;
            idx[051] = 051; idx[050] = 050; idx[049] = 049; idx[048] = 048;
            idx[047] = 047; idx[046] = 046; idx[045] = 045; idx[044] = 044;
            idx[043] = 043; idx[042] = 042; idx[041] = 041; idx[040] = 040;
            idx[039] = 039; idx[038] = 038; idx[037] = 037; idx[036] = 036;
            idx[035] = 035; idx[034] = 034; idx[033] = 033; idx[032] = 032;
            idx[031] = 031; idx[030] = 030; idx[029] = 029; idx[028] = 028;
            idx[027] = 027; idx[026] = 026; idx[025] = 025; idx[024] = 024;
            idx[023] = 023; idx[022] = 022; idx[021] = 021; idx[020] = 020;
            idx[019] = 019; idx[018] = 018; idx[017] = 017; idx[016] = 016;
            idx[015] = 015; idx[014] = 014; idx[013] = 013; idx[012] = 012;
            idx[011] = 011; idx[010] = 010; idx[009] = 009; idx[008] = 008;
            idx[007] = 007; idx[006] = 006; idx[005] = 005; idx[004] = 004;
            idx[003] = 003; idx[002] = 002; idx[001] = 001; idx[000] = 000;
            return idx[byte_idx[6:0]];
          end
          rvv_pkg::EW32: begin
            automatic vlen_t [127:0] idx;
            idx[127] = 127; idx[126] = 126; idx[125] = 125; idx[124] = 124;
            idx[123] = 119; idx[122] = 118; idx[121] = 117; idx[120] = 116;
            idx[119] = 111; idx[118] = 110; idx[117] = 109; idx[116] = 108;
            idx[115] = 103; idx[114] = 102; idx[113] = 101; idx[112] = 100;
            idx[111] = 095; idx[110] = 094; idx[109] = 093; idx[108] = 092;
            idx[107] = 087; idx[106] = 086; idx[105] = 085; idx[104] = 084;
            idx[103] = 079; idx[102] = 078; idx[101] = 077; idx[100] = 076;
            idx[099] = 071; idx[098] = 070; idx[097] = 069; idx[096] = 068;
            idx[095] = 063; idx[094] = 062; idx[093] = 061; idx[092] = 060;
            idx[091] = 055; idx[090] = 054; idx[089] = 053; idx[088] = 052;
            idx[087] = 047; idx[086] = 046; idx[085] = 045; idx[084] = 044;
            idx[083] = 039; idx[082] = 038; idx[081] = 037; idx[080] = 036;
            idx[079] = 031; idx[078] = 030; idx[077] = 029; idx[076] = 028;
            idx[075] = 023; idx[074] = 022; idx[073] = 021; idx[072] = 020;
            idx[071] = 015; idx[070] = 014; idx[069] = 013; idx[068] = 012;
            idx[067] = 007; idx[066] = 006; idx[065] = 005; idx[064] = 004;
            idx[063] = 123; idx[062] = 122; idx[061] = 121; idx[060] = 120;
            idx[059] = 115; idx[058] = 114; idx[057] = 113; idx[056] = 112;
            idx[055] = 107; idx[054] = 106; idx[053] = 105; idx[052] = 104;
            idx[051] = 099; idx[050] = 098; idx[049] = 097; idx[048] = 096;
            idx[047] = 091; idx[046] = 090; idx[045] = 089; idx[044] = 088;
            idx[043] = 083; idx[042] = 082; idx[041] = 081; idx[040] = 080;
            idx[039] = 075; idx[038] = 074; idx[037] = 073; idx[036] = 072;
            idx[035] = 067; idx[034] = 066; idx[033] = 065; idx[032] = 064;
            idx[031] = 059; idx[030] = 058; idx[029] = 057; idx[028] = 056;
            idx[027] = 051; idx[026] = 050; idx[025] = 049; idx[024] = 048;
            idx[023] = 043; idx[022] = 042; idx[021] = 041; idx[020] = 040;
            idx[019] = 035; idx[018] = 034; idx[017] = 033; idx[016] = 032;
            idx[015] = 027; idx[014] = 026; idx[013] = 025; idx[012] = 024;
            idx[011] = 019; idx[010] = 018; idx[009] = 017; idx[008] = 016;
            idx[007] = 011; idx[006] = 010; idx[005] = 009; idx[004] = 008;
            idx[003] = 003; idx[002] = 002; idx[001] = 001; idx[000] = 000;
            return idx[byte_idx[6:0]];
          end
          rvv_pkg::EW16: begin
            automatic vlen_t [127:0] idx;
            idx[127] = 127; idx[126] = 126; idx[125] = 119; idx[124] = 118;
            idx[123] = 111; idx[122] = 110; idx[121] = 103; idx[120] = 102;
            idx[119] = 095; idx[118] = 094; idx[117] = 087; idx[116] = 086;
            idx[115] = 079; idx[114] = 078; idx[113] = 071; idx[112] = 070;
            idx[111] = 063; idx[110] = 062; idx[109] = 055; idx[108] = 054;
            idx[107] = 047; idx[106] = 046; idx[105] = 039; idx[104] = 038;
            idx[103] = 031; idx[102] = 030; idx[101] = 023; idx[100] = 022;
            idx[099] = 015; idx[098] = 014; idx[097] = 007; idx[096] = 006;
            idx[095] = 123; idx[094] = 122; idx[093] = 115; idx[092] = 114;
            idx[091] = 107; idx[090] = 106; idx[089] = 099; idx[088] = 098;
            idx[087] = 091; idx[086] = 090; idx[085] = 083; idx[084] = 082;
            idx[083] = 075; idx[082] = 074; idx[081] = 067; idx[080] = 066;
            idx[079] = 059; idx[078] = 058; idx[077] = 051; idx[076] = 050;
            idx[075] = 043; idx[074] = 042; idx[073] = 035; idx[072] = 034;
            idx[071] = 027; idx[070] = 026; idx[069] = 019; idx[068] = 018;
            idx[067] = 011; idx[066] = 010; idx[065] = 003; idx[064] = 002;
            idx[063] = 125; idx[062] = 124; idx[061] = 117; idx[060] = 116;
            idx[059] = 109; idx[058] = 108; idx[057] = 101; idx[056] = 100;
            idx[055] = 093; idx[054] = 092; idx[053] = 085; idx[052] = 084;
            idx[051] = 077; idx[050] = 076; idx[049] = 069; idx[048] = 068;
            idx[047] = 061; idx[046] = 060; idx[045] = 053; idx[044] = 052;
            idx[043] = 045; idx[042] = 044; idx[041] = 037; idx[040] = 036;
            idx[039] = 029; idx[038] = 028; idx[037] = 021; idx[036] = 020;
            idx[035] = 013; idx[034] = 012; idx[033] = 005; idx[032] = 004;
            idx[031] = 121; idx[030] = 120; idx[029] = 113; idx[028] = 112;
            idx[027] = 105; idx[026] = 104; idx[025] = 097; idx[024] = 096;
            idx[023] = 089; idx[022] = 088; idx[021] = 081; idx[020] = 080;
            idx[019] = 073; idx[018] = 072; idx[017] = 065; idx[016] = 064;
            idx[015] = 057; idx[014] = 056; idx[013] = 049; idx[012] = 048;
            idx[011] = 041; idx[010] = 040; idx[009] = 033; idx[008] = 032;
            idx[007] = 025; idx[006] = 024; idx[005] = 017; idx[004] = 016;
            idx[003] = 009; idx[002] = 008; idx[001] = 001; idx[000] = 000;
            return idx[byte_idx[6:0]];
          end
          rvv_pkg::EW8: begin
            automatic vlen_t [127:0] idx;
            idx[127] = 127; idx[126] = 119; idx[125] = 111; idx[124] = 103;
            idx[123] = 095; idx[122] = 087; idx[121] = 079; idx[120] = 071;
            idx[119] = 063; idx[118] = 055; idx[117] = 047; idx[116] = 039;
            idx[115] = 031; idx[114] = 023; idx[113] = 015; idx[112] = 007;
            idx[111] = 123; idx[110] = 115; idx[109] = 107; idx[108] = 099;
            idx[107] = 091; idx[106] = 083; idx[105] = 075; idx[104] = 067;
            idx[103] = 059; idx[102] = 051; idx[101] = 043; idx[100] = 035;
            idx[099] = 027; idx[098] = 019; idx[097] = 011; idx[096] = 003;
            idx[095] = 125; idx[094] = 117; idx[093] = 109; idx[092] = 101;
            idx[091] = 093; idx[090] = 085; idx[089] = 077; idx[088] = 069;
            idx[087] = 061; idx[086] = 053; idx[085] = 045; idx[084] = 037;
            idx[083] = 029; idx[082] = 021; idx[081] = 013; idx[080] = 005;
            idx[079] = 121; idx[078] = 113; idx[077] = 105; idx[076] = 097;
            idx[075] = 089; idx[074] = 081; idx[073] = 073; idx[072] = 065;
            idx[071] = 057; idx[070] = 049; idx[069] = 041; idx[068] = 033;
            idx[067] = 025; idx[066] = 017; idx[065] = 009; idx[064] = 001;
            idx[063] = 126; idx[062] = 118; idx[061] = 110; idx[060] = 102;
            idx[059] = 094; idx[058] = 086; idx[057] = 078; idx[056] = 070;
            idx[055] = 062; idx[054] = 054; idx[053] = 046; idx[052] = 038;
            idx[051] = 030; idx[050] = 022; idx[049] = 014; idx[048] = 006;
            idx[047] = 122; idx[046] = 114; idx[045] = 106; idx[044] = 098;
            idx[043] = 090; idx[042] = 082; idx[041] = 074; idx[040] = 066;
            idx[039] = 058; idx[038] = 050; idx[037] = 042; idx[036] = 034;
            idx[035] = 026; idx[034] = 018; idx[033] = 010; idx[032] = 002;
            idx[031] = 124; idx[030] = 116; idx[029] = 108; idx[028] = 100;
            idx[027] = 092; idx[026] = 084; idx[025] = 076; idx[024] = 068;
            idx[023] = 060; idx[022] = 052; idx[021] = 044; idx[020] = 036;
            idx[019] = 028; idx[018] = 020; idx[017] = 012; idx[016] = 004;
            idx[015] = 120; idx[014] = 112; idx[013] = 104; idx[012] = 096;
            idx[011] = 088; idx[010] = 080; idx[009] = 072; idx[008] = 064;
            idx[007] = 056; idx[006] = 048; idx[005] = 040; idx[004] = 032;
            idx[003] = 024; idx[002] = 016; idx[001] = 008; idx[000] = 000;
            return idx[byte_idx[6:0]];
          end
        endcase
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
  endfunction : shuffle_index

  function automatic vlen_t deshuffle_index(vlen_t byte_index, int NrLanes, rvv_pkg::vew_e ew);
    // Generate the deshuffling of the table above
    unique case (NrLanes)
      1: begin
        automatic vlen_t [7:0] index;
        for (int b = 0; b < 8; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[2:0]];
      end
      2: begin
        automatic vlen_t [15:0] index;
        for (int b = 0; b < 16; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[3:0]];
      end
      4: begin
        automatic vlen_t [31:0] index;
        for (int b = 0; b < 32; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[4:0]];
      end
      8: begin
        automatic vlen_t [63:0] index;
        for (int b = 0; b < 64; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[5:0]];
      end
      16: begin
        automatic vlen_t [127:0] index;
        for (int b = 0; b < 128; b++)
          index[shuffle_index(b, NrLanes, ew)] = b;
        return index[byte_index[6:0]];
      end
    endcase
  endfunction : deshuffle_index

  /////////////////////////
  //  Fixed-Point        //
  /////////////////////////

  typedef logic                       vxsat_t;
  typedef logic [1:0]                 vxrm_t;

  typedef union packed {
    logic [0:0][7:0] w64;
    logic [1:0][3:0] w32;
    logic [3:0][1:0] w16;
    logic [7:0][0:0] w8;
  } alu_vxsat_t;

  /////////////////////////
  //  MASKU definitions  //
  /////////////////////////

  // Which FU should process the mask unit request?
  localparam int unsigned NrMaskFUnits = 2;
  typedef enum logic [cf_math_pkg::idx_width(NrMaskFUnits)-1:0]{
    MaskFUAlu, MaskFUMFpu
  } masku_fu_e;

  ////////////////////////
  //  Lane definitions  //
  ////////////////////////

  // There are seven operand queues, serving operands to the different functional units of each lane
  localparam int unsigned NrOperandQueues = 9;
  typedef enum logic [$clog2(NrOperandQueues)-1:0] {
    AluA, AluB, MulFPUA, MulFPUB, MulFPUC, MaskB, MaskM, StA, SlideAddrGenA
  } opqueue_e;

  // Each lane has eight VRF banks
  localparam int unsigned NrVRFBanksPerLane = 8;

  // Find the starting address of a vector register vid
  function automatic logic [63:0] vaddr(logic [4:0] vid, int NrLanes);
    vaddr = vid * (VLENB / NrLanes / 8);
  endfunction: vaddr

  // Differenciate between SLDU and ADDRGEN operands from opqueue
  typedef enum logic {
    SLDU    = 1'b0,
    ADDRGEN = 1'b1
  } target_fu_e;

  // This is the interface between the lane's sequencer and the operand request stage, which
  // makes consecutive requests to the vector elements inside the VRF.
  typedef struct packed {
    vid_t id; // ID of the vector instruction

    logic [4:0] vs; // Vector register operand

    logic scale_vl; // Rescale vl taking into account the new and old EEW

    resize_e cvt_resize;    // Resizing of FP conversions

    rvv_pkg::vew_e eew;        // Effective element width
    opqueue_conversion_e conv; // Type conversion

    target_fu_e target_fu;     // Target FU of the opqueue (if it is not clear)

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
    logic [1:0] ntr_red;       // Neutral type for reductions
    target_fu_e target_fu;     // Target FU of the opqueue (if it is not clear)
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
    logic wide_fp_imm;            // Widen FP immediate (re-encoding)
    resize_e cvt_resize;    // Resizing of FP conversions

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
  endfunction : be

  /////////////////////////////////////////
  //  Vector Load/Store Unit definition  //
  /////////////////////////////////////////

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
