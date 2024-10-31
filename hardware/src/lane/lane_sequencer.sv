// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is the sequencer of one lane. It controls the execution of one vector
// instruction within one lane, interfacing with the internal functional units
// and with the main sequencer.

module lane_sequencer import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter int unsigned NrLanes               = 0,
    parameter type         pe_req_t              = logic,
    parameter type         pe_resp_t             = logic,
    parameter type         operand_request_cmd_t = logic,
    parameter type         vfu_operation_t       = logic
  ) (
    input  logic                                          clk_i,
    input  logic                                          rst_ni,
    // Lane ID
    input  logic                 [idx_width(NrLanes)-1:0] lane_id_i,
    // Interface with the main sequencer
    input  pe_req_t                                       pe_req_i,
    input  logic                                          pe_req_valid_i,
    input  logic                 [NrVInsn-1:0]            pe_vinsn_running_i,
    output logic                                          pe_req_ready_o,
    output pe_resp_t                                      pe_resp_o,
    // Interface with the operand requester
    output operand_request_cmd_t [NrOperandQueues-1:0]    operand_request_o,
    output logic                 [NrOperandQueues-1:0]    operand_request_valid_o,
    input  logic                 [NrOperandQueues-1:0]    operand_request_ready_i,
    output logic                                          alu_vinsn_done_o,
    output logic                                          mfpu_vinsn_done_o,
    // Interface with the lane's VFUs
    output vfu_operation_t                                vfu_operation_o,
    output logic                                          vfu_operation_valid_o,
    input  logic                                          alu_ready_i,
    input  logic                 [NrVInsn-1:0]            alu_vinsn_done_i,
    input  logic                                          mfpu_ready_i,
    input  logic                 [NrVInsn-1:0]            mfpu_vinsn_done_i
  );

  ////////////////////////////
  //  Register the request  //
  ////////////////////////////

  // Don't accept the same request more than once!
  // The main sequencer keeps the valid high and broadcast
  // a certain instruction with ID == X to all the lanes
  // until every lane has sampled it.

  // Every time a lane handshakes the main sequencer, it also
  // saves the insn ID, not to re-sample the same instruction.
  vid_t last_id_d, last_id_q;
  logic pe_req_valid_i_msk;
  logic en_sync_mask_d, en_sync_mask_q;

  pe_req_t pe_req;
  logic    pe_req_valid;
  logic    pe_req_ready;

  fall_through_register #(
    .T(pe_req_t)
  ) i_pe_req_register (
    .clk_i     (clk_i             ),
    .rst_ni    (rst_ni            ),
    .clr_i     (1'b0              ),
    .testmode_i(1'b0              ),
    .data_i    (pe_req_i          ),
    .valid_i   (pe_req_valid_i_msk),
    .ready_o   (pe_req_ready_o    ),
    .data_o    (pe_req            ),
    .valid_o   (pe_req_valid      ),
    .ready_i   (pe_req_ready      )
  );

  always_comb begin
    // Default assignment
    last_id_d      = last_id_q;
    en_sync_mask_d = en_sync_mask_q;

    // If the sync mask is enabled and the ID is the same
    // as before, avoid to re-sample the same instruction
    // more than once.
    if (en_sync_mask_q && (pe_req_i.id == last_id_q))
      pe_req_valid_i_msk = 1'b0;
    else
      pe_req_valid_i_msk = pe_req_valid_i;

    // Enable the sync mask when a handshake happens,
    // and save the insn ID
    if (pe_req_valid_i_msk && pe_req_ready_o) begin
      last_id_d      = pe_req_i.id;
      en_sync_mask_d = 1'b1;
    end

    // Disable the block if the sequencer valid goes down
    if (!pe_req_valid_i && en_sync_mask_q)
      en_sync_mask_d = 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      last_id_q      <= '0;
      en_sync_mask_q <= 1'b0;
    end else begin
      last_id_q      <= last_id_d;
      en_sync_mask_q <= en_sync_mask_d;
    end
  end

  //////////////////////////////////////
  //  Operand Request Command Queues  //
  //////////////////////////////////////

  // We cannot use a simple FIFO because the operand request commands include
  // bits that indicate whether there is a hazard between different vector
  // instructions. Such hazards must be continuously cleared based on the
  // value of the currently running loops from the main sequencer.
  operand_request_cmd_t [NrOperandQueues-1:0] operand_request;
  logic                 [NrOperandQueues-1:0] operand_request_push;

  operand_request_cmd_t [NrOperandQueues-1:0] operand_request_d;
  logic                 [NrOperandQueues-1:0] operand_request_valid_d;

  always_comb begin: p_operand_request
    for (int queue = 0; queue < NrOperandQueues; queue++) begin
      // Maintain state
      operand_request_d[queue]       = operand_request_o[queue];
      operand_request_valid_d[queue] = operand_request_valid_o[queue];

      // Clear the request
      if (operand_request_ready_i[queue]) begin
        operand_request_d[queue]       = '0;
        operand_request_valid_d[queue] = 1'b0;
      end

      // Got a new request
      if (operand_request_push[queue]) begin
        operand_request_d[queue]       = operand_request[queue];
        operand_request_valid_d[queue] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_operand_request_ff
    if (!rst_ni) begin
      operand_request_o       <= '0;
      operand_request_valid_o <= '0;
    end else begin
      operand_request_o       <= operand_request_d;
      operand_request_valid_o <= operand_request_valid_d;
    end
  end

  /////////////////////////////
  //  VFU Operation control  //
  /////////////////////////////

  // Running instructions
  logic [NrVInsn-1:0] vinsn_done_d, vinsn_done_q;
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  // VFU operation
  vfu_operation_t vfu_operation_d;
  logic           vfu_operation_valid_d;

  // Cut the path
  logic alu_vinsn_done_d, mfpu_vinsn_done_d;

  // Returns true if the corresponding lane VFU is ready.
  function automatic logic vfu_ready(vfu_e vfu, logic alu_ready_i, logic mfpu_ready_i);
    vfu_ready = 1'b1;
    unique case (vfu)
      VFU_Alu,
      VFU_MaskUnit: vfu_ready = alu_ready_i;
      VFU_MFpu    : vfu_ready = mfpu_ready_i;
      default:;
    endcase
  endfunction : vfu_ready

  always_comb begin: sequencer
    // Running loops
    vinsn_running_d = vinsn_running_q & pe_vinsn_running_i;

    // Ready to accept a new request, by default
    pe_req_ready = 1'b1;

    // Loops that finished execution
    vinsn_done_d         = alu_vinsn_done_i | mfpu_vinsn_done_i;
    alu_vinsn_done_d     = |alu_vinsn_done_i;
    mfpu_vinsn_done_d    = |mfpu_vinsn_done_i;
    pe_resp_o.vinsn_done = vinsn_done_q;

    // Make no requests to the operand requester
    operand_request    = '0;
    operand_request_push = '0;

    // Make no requests to the lane's VFUs
    vfu_operation_d       = '0;
    vfu_operation_valid_d = 1'b0;

    // If the operand requesters are busy, abort the request and wait for another cycle.
    if (pe_req_valid) begin
      unique case (pe_req.vfu)
        VFU_Alu : begin
          pe_req_ready = !(operand_request_valid_o[AluA] ||
            operand_request_valid_o[AluB ] ||
            operand_request_valid_o[MaskM]);
        end
        VFU_MFpu : begin
          pe_req_ready = !(operand_request_valid_o[MulFPUA] ||
            operand_request_valid_o[MulFPUB] ||
            operand_request_valid_o[MulFPUC] ||
            operand_request_valid_o[MaskM]);
        end
        VFU_LoadUnit : pe_req_ready = !(operand_request_valid_o[MaskM] ||
            (pe_req_i.op == VLXE && operand_request_valid_o[SlideAddrGenA]));
        VFU_SlideUnit: pe_req_ready = !(operand_request_valid_o[SlideAddrGenA]);
        VFU_StoreUnit: begin
          pe_req_ready = !(operand_request_valid_o[StA] ||
            operand_request_valid_o[MaskM] ||
            (pe_req_i.op == VSXE && operand_request_valid_o[SlideAddrGenA]));
        end
        VFU_MaskUnit : begin
          pe_req_ready = !(operand_request_valid_o[AluA] ||
            operand_request_valid_o [AluB] ||
            operand_request_valid_o [MulFPUA] ||
            operand_request_valid_o [MulFPUB] ||
            operand_request_valid_o[MaskB] ||
            operand_request_valid_o[MaskM]);
        end
        VFU_None : begin
          pe_req_ready = !(operand_request_valid_o[MaskB]);
        end
        default:;
      endcase
    end

    // We received a new vector instruction
    if (pe_req_valid && pe_req_ready && !vinsn_running_d[pe_req.id]) begin
      // Populate the VFU request
      vfu_operation_d = '{
        id             : pe_req.id,
        op             : pe_req.op,
        vm             : pe_req.vm,
        vfu            : pe_req.vfu,
        use_vs1        : pe_req.use_vs1,
        use_vs2        : pe_req.use_vs2,
        use_vd_op      : pe_req.use_vd_op,
        scalar_op      : pe_req.scalar_op,
        use_scalar_op  : pe_req.use_scalar_op,
        vd             : pe_req.vd,
        use_vd         : pe_req.use_vd,
        swap_vs2_vd_op : pe_req.swap_vs2_vd_op,
        fp_rm          : pe_req.fp_rm,
        wide_fp_imm    : pe_req.wide_fp_imm,
        cvt_resize     : pe_req.cvt_resize,
        vtype          : pe_req.vtype,
        default        : '0
      };
      vfu_operation_valid_d = (vfu_operation_d.vfu != VFU_None) ? 1'b1 : 1'b0;

      // Vector length calculation
      vfu_operation_d.vl = pe_req.vl / NrLanes;
      // If lane_id_i < vl % NrLanes, this lane has to execute one extra micro-operation.
      if (lane_id_i < pe_req.vl[idx_width(NrLanes)-1:0]) vfu_operation_d.vl += 1;

      // Calculate the start element for Lane[i]. This will be forwarded to both opqueues
      // and operand requesters, with some light modification in the case of a vslide.
      // Regardless of the EW, the start element of Lane[i] is "vstart / NrLanes".
      // If vstart deos not divide NrLanes perfectly, some low-index lanes will send
      // mock data to balance the payload.
      vfu_operation_d.vstart = pe_req.vstart / NrLanes;

      // Mark the vector instruction as running
      vinsn_running_d[pe_req.id] = (vfu_operation_d.vfu != VFU_None) ? 1'b1 : 1'b0;

      // Mute request if the instruction runs in the lane and the vl is zero.
      // Exception 1: insn on mask vectors, as MASKU has to receive something from all lanes
      // and the partial results come from VALU and VMFPU.
      // Exception 2: during a reduction, all the lanes must cooperate anyway.
      if (vfu_operation_d.vl == '0 && (vfu_operation_d.vfu inside {VFU_Alu, VFU_MFpu}) && !(vfu_operation_d.op inside {[VREDSUM:VWREDSUM], [VFREDUSUM:VFWREDOSUM]})) begin
        vfu_operation_valid_d = 1'b0;
        // We are already done with this instruction
        vinsn_done_d[pe_req.id] |= 1'b1;
        vinsn_running_d[pe_req.id] = 1'b0;
      end

      ////////////////////////
      //  Operand requests  //
      ////////////////////////

      unique case (pe_req.vfu)
        VFU_Alu: begin
          operand_request[AluA] = '{
            id         : pe_req.id,
            vs         : pe_req.vs1,
            eew        : pe_req.eew_vs1,
            // If reductions and vl == 0, we must replace with neutral values
            conv       : (vfu_operation_d.vl == '0) ? OpQueueReductionZExt : pe_req.conversion_vs1,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            vtype      : pe_req.vtype,
            // In case of reduction, AluA opqueue will keep the scalar element
            vl         : (pe_req.op inside {[VREDSUM:VWREDSUM]}) ? 1 : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            hazard     : pe_req.hazard_vs1 | pe_req.hazard_vd,
            is_reduct  : pe_req.op inside {[VREDSUM:VWREDSUM]} ? 1'b1 : 0,
            target_fu  : ALU_SLDU,
            default    : '0
          };
          operand_request_push[AluA] = pe_req.use_vs1;

          operand_request[AluB] = '{
            id         : pe_req.id,
            vs         : pe_req.vs2,
            eew        : pe_req.eew_vs2,
            // If reductions and vl == 0, we must replace with neutral values
            conv       : (vfu_operation_d.vl == '0) ? OpQueueReductionZExt : pe_req.conversion_vs2,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            vtype      : pe_req.vtype,
            // If reductions and vl == 0, we must replace the operands with neutral
            // values in the opqueues. So, vl must be 1 at least
            vl         : (pe_req.op inside {[VREDSUM:VWREDSUM]} && vfu_operation_d.vl == '0)
                         ? 1 : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            hazard     : pe_req.hazard_vs2 | pe_req.hazard_vd,
            is_reduct  : pe_req.op inside {[VREDSUM:VWREDSUM]} ? 1'b1 : 0,
            target_fu  : ALU_SLDU,
            default    : '0
          };
          operand_request_push[AluB] = pe_req.use_vs2;

          // This vector instruction uses masks
          operand_request[MaskM] = '{
            id     : pe_req.id,
            vs     : VMASK,
            eew    : pe_req.vtype.vsew,
            vtype  : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl     : (pe_req.vl / NrLanes / 8) >> unsigned'(pe_req.vtype.vsew),
            vstart : vfu_operation_d.vstart,
            hazard : pe_req.hazard_vm | pe_req.hazard_vd,
            default: '0
          };
          if ((operand_request[MaskM].vl << unsigned'(pe_req.vtype.vsew)) *
              NrLanes * 8 != pe_req.vl) operand_request[MaskM].vl += 1;
          operand_request_push[MaskM] = !pe_req.vm;
        end
        VFU_MFpu: begin
          operand_request[MulFPUA] = '{
            id         : pe_req.id,
            vs         : pe_req.vs1,
            eew        : pe_req.eew_vs1,
            // If reductions and vl == 0, we must replace with neutral values
            conv       : pe_req.conversion_vs1,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            vtype      : pe_req.vtype,
            // If reductions and vl == 0, we must replace the operands with neutral
            // values in the opqueues. So, vl must be 1 at least
            vl         : (pe_req.op inside {[VFREDUSUM:VFWREDOSUM]}) ? 1 : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            hazard     : pe_req.hazard_vs1 | pe_req.hazard_vd,
            is_reduct  : pe_req.op inside {[VFREDUSUM:VFWREDOSUM]} ? 1'b1 : 0,
            target_fu  : MFPU_ADDRGEN,
            default    : '0
          };
          operand_request_push[MulFPUA] = pe_req.use_vs1;

          operand_request[MulFPUB] = '{
            id         : pe_req.id,
            vs         : pe_req.swap_vs2_vd_op ? pe_req.vd        : pe_req.vs2,
            eew        : pe_req.swap_vs2_vd_op ? pe_req.eew_vd_op : pe_req.eew_vs2,
            // If reductions and vl == 0, we must replace with neutral values
            conv       : pe_req.conversion_vs2,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            vtype      : pe_req.vtype,
            // If reductions and vl == 0, we must replace the operands with neutral
            // values in the opqueues. So, vl must be 1 at least
            vl         : (pe_req.op inside {[VFREDUSUM:VFWREDOSUM]} && vfu_operation_d.vl == '0)
                        ? 1 : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            hazard     : (pe_req.swap_vs2_vd_op ?
            pe_req.hazard_vd : (pe_req.hazard_vs2 | pe_req.hazard_vd)),
            is_reduct  : pe_req.op inside {[VFREDUSUM:VFWREDOSUM]} ? 1'b1 : 0,
            target_fu  : MFPU_ADDRGEN,
            default: '0
          };
          operand_request_push[MulFPUB] = pe_req.swap_vs2_vd_op ?
          pe_req.use_vd_op : pe_req.use_vs2;

          operand_request[MulFPUC] = '{
            id         : pe_req.id,
            vs         : pe_req.swap_vs2_vd_op ? pe_req.vs2            : pe_req.vd,
            eew        : pe_req.swap_vs2_vd_op ? pe_req.eew_vs2        : pe_req.eew_vd_op,
            conv       : pe_req.swap_vs2_vd_op ? pe_req.conversion_vs2 : OpQueueConversionNone,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            // If reductions and vl == 0, we must replace the operands with neutral
            // values in the opqueues. So, vl must be 1 at least
            vl         : (pe_req.op inside {[VFREDUSUM:VFWREDOSUM]} && vfu_operation_d.vl == '0)
                        ? 1 : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            vtype      : pe_req.vtype,
            hazard     : pe_req.swap_vs2_vd_op ?
            (pe_req.hazard_vs2 | pe_req.hazard_vd) : pe_req.hazard_vd,
            is_reduct  : pe_req.op inside {[VFREDUSUM:VFWREDOSUM]} ? 1'b1 : 0,
            target_fu  : MFPU_ADDRGEN,
            default : '0
          };
          operand_request_push[MulFPUC] = pe_req.swap_vs2_vd_op ?
          pe_req.use_vs2 : pe_req.use_vd_op;

          // This vector instruction uses masks
          operand_request[MaskM] = '{
            id     : pe_req.id,
            vs     : VMASK,
            eew    : pe_req.vtype.vsew,
            vtype  : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl     : (pe_req.vl / NrLanes / 8) >> unsigned'(pe_req.vtype.vsew),
            vstart : vfu_operation_d.vstart,
            hazard : pe_req.hazard_vm | pe_req.hazard_vd,
            default: '0
          };
          if ((operand_request[MaskM].vl << unsigned'(pe_req.vtype.vsew)) *
              NrLanes * 8 != pe_req.vl) operand_request[MaskM].vl += 1;
          operand_request_push[MaskM] = !pe_req.vm;
        end
        VFU_LoadUnit : begin
          // This vector instruction uses masks
          operand_request[MaskM] = '{
            id     : pe_req.id,
            vs     : VMASK,
            eew    : pe_req.vtype.vsew,
            vtype  : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl     : (pe_req.vl / NrLanes / 8) >> unsigned'(pe_req.vtype.vsew),
            vstart : vfu_operation_d.vstart,
            hazard : pe_req.hazard_vm | pe_req.hazard_vd,
            default: '0
          };
          if ((operand_request[MaskM].vl << unsigned'(pe_req.vtype.vsew)) *
              NrLanes * 8 != pe_req.vl) operand_request[MaskM].vl += 1;
          operand_request_push[MaskM] = !pe_req.vm;

          // Load indexed
          operand_request[SlideAddrGenA] = '{
            id       : pe_req_i.id,
            vs       : pe_req_i.vs2,
            eew      : pe_req_i.eew_vs2,
            conv     : pe_req_i.conversion_vs2,
            target_fu: MFPU_ADDRGEN,
            vl       : pe_req_i.vl / NrLanes,
            scale_vl : pe_req_i.scale_vl,
            vstart   : vfu_operation_d.vstart,
            vtype    : pe_req_i.vtype,
            hazard   : pe_req_i.hazard_vs2 | pe_req_i.hazard_vd,
            default  : '0
          };
          // Since this request goes outside of the lane, we might need to request an
          // extra operand regardless of whether it is valid in this lane or not.
          if (operand_request[SlideAddrGenA].vl * NrLanes != pe_req_i.vl)
            operand_request[SlideAddrGenA].vl += 1;
          operand_request_push[SlideAddrGenA] = pe_req_i.op == VLXE;
        end

        VFU_StoreUnit : begin
          // vstart is supported here
          operand_request[StA] = '{
            id      : pe_req.id,
            vs      : pe_req.vs1,
            eew     : pe_req.old_eew_vs1,
            conv    : pe_req.conversion_vs1,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            vl      : vfu_operation_d.vl,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vs1 | pe_req.hazard_vd,
            default : '0
          };
          // Since this request goes outside of the lane, we might need to request an
          // extra operand regardless of whether it is valid in this lane or not.
          // This is done to balance the data received by the store unit, which expects
          // L*64-bits packets only.
          if (lane_id_i > pe_req.end_lane) begin
            operand_request[StA].vl += 1;
          end
          operand_request_push[StA] = pe_req.use_vs1;

          // This vector instruction uses masks
          operand_request[MaskM] = '{
            id     : pe_req.id,
            vs     : VMASK,
            eew    : pe_req.vtype.vsew,
            vtype  : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl     : (pe_req.vl / NrLanes / 8) >> unsigned'(pe_req.vtype.vsew),
            vstart : vfu_operation_d.vstart,
            hazard : pe_req.hazard_vm | pe_req.hazard_vd,
            default: '0
          };
          if ((operand_request[MaskM].vl << unsigned'(pe_req.vtype.vsew)) *
              NrLanes * 8 != pe_req.vl) operand_request[MaskM].vl += 1;
          operand_request_push[MaskM] = !pe_req.vm;

          // Store indexed
          // TODO: add vstart support here
          operand_request[SlideAddrGenA] = '{
            id       : pe_req_i.id,
            vs       : pe_req_i.vs2,
            eew      : pe_req_i.eew_vs2,
            conv     : pe_req_i.conversion_vs2,
            target_fu: MFPU_ADDRGEN,
            vl       : pe_req_i.vl / NrLanes,
            scale_vl : pe_req_i.scale_vl,
            vstart   : vfu_operation_d.vstart,
            vtype    : pe_req_i.vtype,
            hazard   : pe_req_i.hazard_vs2 | pe_req_i.hazard_vd,
            default  : '0
          };
          // Since this request goes outside of the lane, we might need to request an
          // extra operand regardless of whether it is valid in this lane or not.
          if (operand_request[SlideAddrGenA].vl * NrLanes != pe_req_i.vl) begin
            operand_request[SlideAddrGenA].vl += 1;
          end
          operand_request_push[SlideAddrGenA] = pe_req_i.op == VSXE;
        end

        VFU_SlideUnit: begin
          operand_request[SlideAddrGenA] = '{
            id       : pe_req.id,
            vs       : pe_req.vs2,
            eew      : pe_req.eew_vs2,
            conv     : pe_req.conversion_vs2,
            target_fu: ALU_SLDU,
            is_slide : 1'b1,
            scale_vl : pe_req.scale_vl,
            vtype    : pe_req.vtype,
            vstart   : vfu_operation_d.vstart,
            hazard   : pe_req.hazard_vs2 | pe_req.hazard_vd,
            default  : '0
          };
          operand_request_push[SlideAddrGenA] = pe_req.use_vs2;

          unique case (pe_req.op)
            VSLIDEUP: begin
              // We need to trim full words from the end of the vector that are not used
              // as operands by the slide unit.
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              operand_request[SlideAddrGenA].vl =
              (pe_req.vl - pe_req.stride + NrLanes - 1) / NrLanes;
            end
            VSLIDEDOWN: begin
              // Extra elements to ask, because of the stride
              logic [$clog2(8*NrLanes)-1:0] extra_stride;
              // Need one bit more than vl, since we will also add the stride contribution
              logic [$bits(pe_req.vl):0] vl_tot;

              // We need to trim full words from the start of the vector that are not used
              // as operands by the slide unit.
              operand_request[SlideAddrGenA].vstart = pe_req.stride / NrLanes;

              // The stride move the initial address in boundaries of 8*NrLanes Byte.
              // If the stride is not multiple of a full VRF word (8*NrLanes Byte),
              // we must request it as well from the VRF

              // Find the number of extra elements to ask, related to the stride
              unique case (pe_req.eew_vs2)
                EW8 : extra_stride = pe_req.stride[$clog2(8*NrLanes)-1:0];
                EW16: extra_stride = {1'b0, pe_req.stride[$clog2(4*NrLanes)-1:0]};
                EW32: extra_stride = {2'b0, pe_req.stride[$clog2(2*NrLanes)-1:0]};
                EW64: extra_stride = {3'b0, pe_req.stride[$clog2(1*NrLanes)-1:0]};
                default:
                  extra_stride = {3'b0, pe_req.stride[$clog2(1*NrLanes)-1:0]};
              endcase

              // Find the total number of elements to be asked
              vl_tot = pe_req.vl;
              if (!pe_req.use_scalar_op)
                vl_tot += extra_stride;

              // Ask the elements, and ask one more if we do not perfectly divide NrLanes
              operand_request[SlideAddrGenA].vl = vl_tot / NrLanes;
              if (operand_request[SlideAddrGenA].vl * NrLanes != vl_tot)
                operand_request[SlideAddrGenA].vl += 1;
            end
            default:;
          endcase

          // This vector instruction uses masks
          operand_request[MaskM] = '{
            id      : pe_req.id,
            vs      : VMASK,
            eew     : pe_req.vtype.vsew,
            is_slide: 1'b1,
            vtype   : pe_req.vtype,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vm | pe_req.hazard_vd,
            default : '0
          };
          operand_request_push[MaskM] = !pe_req.vm;

          case (pe_req.op)
            VSLIDEUP: begin
              // We need to trim full words from the end of the vector that are not used
              // as operands by the slide unit.
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              operand_request[MaskM].vl =
              ((pe_req.vl - pe_req.stride + NrLanes - 1) / 8 / NrLanes)
              >> unsigned'(pe_req.vtype.vsew);

              if (((operand_request[MaskM].vl + pe_req.stride) <<
                    unsigned'(pe_req.vtype.vsew) * NrLanes * 8 != pe_req.vl))
                operand_request[MaskM].vl += 1;

              // SLIDEUP only uses mask bits whose indices are > stride
              // Don't send the previous (unused) ones to the MASKU
              if (pe_req.stride >= NrLanes * 64)
                operand_request[MaskM].vstart += ((pe_req.stride >> NrLanes * 64) << NrLanes * 64) / 8;
            end
            VSLIDEDOWN: begin
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              operand_request[MaskM].vl = ((pe_req.vl / NrLanes / 8) >> unsigned'(
                    pe_req.vtype.vsew));
              if ((operand_request[MaskM].vl << unsigned'(pe_req.vtype.vsew)) *
                  NrLanes * 8 != pe_req.vl)
                operand_request[MaskM].vl += 1;
            end
          endcase
        end
        VFU_MaskUnit: begin
          operand_request[AluA] = '{
            id      : pe_req.id,
            vs      : pe_req.vs1,
            eew     : pe_req.eew_vs1,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vs1 | pe_req.hazard_vd,
            default : '0
          };

          // This is an operation that runs normally on the ALU, and then gets *condensed* and
          // reshuffled at the Mask Unit.
          if (pe_req.op inside {[VMSEQ:VMSBC]}) begin
            operand_request[AluA].vl = vfu_operation_d.vl;
          end
          // This is an operation that runs normally on the ALU, and then gets reshuffled at the
          // Mask Unit.
          else begin
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            operand_request[AluA].vl = (pe_req.vl / NrLanes) >>
            (unsigned'(EW64) - unsigned'(pe_req.eew_vs1));
            if ((operand_request[AluA].vl << (unsigned'(EW64) - unsigned'(pe_req.eew_vs1))) * NrLanes !=
                pe_req.vl) operand_request[AluA].vl += 1;
          end
          operand_request_push[AluA] = pe_req.use_vs1 && !(pe_req.op inside {[VMFEQ:VMFGE], VCPOP, VMSIF, VMSOF, VMSBF});

          operand_request[AluB] = '{
            id      : pe_req.id,
            vs      : pe_req.vs2,
            eew     : pe_req.eew_vs2,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vs2 | pe_req.hazard_vd,
            default : '0
          };
          // This is an operation that runs normally on the ALU, and then gets *condensed* and
          // reshuffled at the Mask Unit.
          if (pe_req.op inside {[VMSEQ:VMSBC]}) begin
            operand_request[AluB].vl = vfu_operation_d.vl;
          end
          // This is an operation that runs normally on the ALU, and then gets reshuffled at the
          // Mask Unit.
          else begin
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            operand_request[AluB].vl = (pe_req.vl / NrLanes) >>
            (unsigned'(EW64) - unsigned'(pe_req.eew_vs2));
            if ((operand_request[AluB].vl << (unsigned'(EW64) - unsigned'(pe_req.eew_vs2))) * NrLanes !=
                pe_req.vl) operand_request[AluB].vl += 1;
          end
          operand_request_push[AluB] = pe_req.use_vs2 && !(pe_req.op inside {[VMFEQ:VMFGE], VCPOP, VMSIF, VMSOF, VMSBF, VFIRST});

          operand_request[MulFPUA] = '{
            id      : pe_req.id,
            vs      : pe_req.vs1,
            eew     : pe_req.eew_vs1,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vs1 | pe_req.hazard_vd,
            default : '0
          };

          // This is an operation that runs normally on the ALU, and then gets *condensed* and
          // reshuffled at the Mask Unit.
          operand_request[MulFPUA].vl = vfu_operation_d.vl;
          operand_request_push[MulFPUA] = pe_req.use_vs1 && pe_req.op inside {[VMFEQ:VMFGE]} && !(pe_req.op inside {VCPOP, VMSIF, VMSOF, VMSBF});

          operand_request[MulFPUB] = '{
            id      : pe_req.id,
            vs      : pe_req.vs2,
            eew     : pe_req.eew_vs2,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            vstart  : vfu_operation_d.vstart,
            hazard  : pe_req.hazard_vs2 | pe_req.hazard_vd,
            default : '0
          };
          // This is an operation that runs normally on the ALU, and then gets *condensed* and
          // reshuffled at the Mask Unit.
          operand_request[MulFPUB].vl = vfu_operation_d.vl;
          operand_request_push[MulFPUB] = pe_req.use_vs2 && pe_req.op inside {[VMFEQ:VMFGE]} && !(pe_req.op inside {VCPOP, VMSIF, VMSOF, VMSBF, VFIRST});

          operand_request[MaskB] = '{
            id      : pe_req.id,
            vs      : pe_req.vs2,
            eew     : pe_req.eew_vs2,
            scale_vl: pe_req.scale_vl,
            vtype   : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl      : (pe_req.vl / NrLanes / ELEN) << (unsigned'(EW64) - unsigned'(pe_req.vtype.vsew)),
            vstart  : vfu_operation_d.vstart,
            hazard  : (pe_req.op inside {VMSBF, VMSOF, VMSIF}) ? pe_req.hazard_vs2 : pe_req.hazard_vs2 | pe_req.hazard_vd,
            default : '0
          };
          operand_request[MaskB].vl = pe_req.vl / (NrLanes * (8 << pe_req.vtype.vsew));
          if ((pe_req.vl % (NrLanes*ELEN)) != 0) begin
            operand_request[MaskB].vl += 1'b1;
          end
          operand_request_push[MaskB] = pe_req.use_vs2 && pe_req.op inside {VCPOP, VFIRST, VMSIF, VMSOF, VMSBF};

          operand_request[MaskM] = '{
            id     : pe_req.id,
            vs     : VMASK,
            eew    : pe_req.vtype.vsew,
            vtype  : pe_req.vtype,
            // Since this request goes outside of the lane, we might need to request an
            // extra operand regardless of whether it is valid in this lane or not.
            vl     : (pe_req.vl / NrLanes / ELEN),
            vstart : vfu_operation_d.vstart,
            hazard : pe_req.hazard_vm,
            default: '0
          };
          if ((operand_request[MaskM].vl * NrLanes * ELEN) != pe_req.vl) begin
            operand_request[MaskM].vl += 1;
          end
          operand_request_push[MaskM] = !pe_req.vm;
        end
        VFU_None: begin
          operand_request[MaskB] = '{
            id         : pe_req.id,
            vs         : pe_req.vs2,
            eew        : pe_req.eew_vs2,
            conv       : pe_req.conversion_vs2,
            scale_vl   : pe_req.scale_vl,
            cvt_resize : pe_req.cvt_resize,
            vtype      : pe_req.vtype,
            vl         : vfu_operation_d.vl,
            vstart     : vfu_operation_d.vstart,
            hazard     : pe_req.hazard_vs2,
            default    : '0
          };
          operand_request_push[MaskB] = 1'b1;
        end
        default:;
      endcase
    end
  end: sequencer

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_sequencer_ff
    if (!rst_ni) begin
      vinsn_done_q    <= '0;
      vinsn_running_q <= '0;

      vfu_operation_o       <= '0;
      vfu_operation_valid_o <= 1'b0;

      alu_vinsn_done_o  <= 1'b0;
      mfpu_vinsn_done_o <= 1'b0;
    end else begin
      vinsn_done_q    <= vinsn_done_d;
      vinsn_running_q <= vinsn_running_d;

      vfu_operation_o       <= vfu_operation_d;
      vfu_operation_valid_o <= vfu_operation_valid_d;

      alu_vinsn_done_o  <= alu_vinsn_done_d;
      mfpu_vinsn_done_o <= mfpu_vinsn_done_d;
    end
  end

endmodule : lane_sequencer
