// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Hierarchical modules cannot have parametrized data types during Verilator's
// hierarchical verilation.

typedef struct packed {
  vid_t id; // ID of the vector instruction

  ara_op_e op; // Operation

  // Mask vector register operand
  logic vm;
  rvv_pkg::vew_e eew_vmask;

  vfu_e vfu; // VFU responsible for handling this instruction

  // Rescale vl taking into account the new and old EEW
  logic scale_vl;

  // The lane that provides the first element of the computation
  logic [$clog2(MaxNrLanes)-1:0] start_lane;
  // The lane that provides the last element of the computation
  logic [$clog2(MaxNrLanes)-1:0] end_lane;

  // 1st vector register operand
  logic [4:0] vs1;
  logic use_vs1;
  opqueue_conversion_e conversion_vs1;
  rvv_pkg::vew_e eew_vs1;
  rvv_pkg::vew_e old_eew_vs1;

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
  logic is_stride_np2;

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
