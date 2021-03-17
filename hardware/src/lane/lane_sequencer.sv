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
    parameter int unsigned NrLanes = 0
  ) (
    input  logic                                          clk_i,
    input  logic                                          rst_ni,
    // Lane ID
    input  logic                 [idx_width(NrLanes)-1:0] lane_id_i,
    // Interface with the main sequencer
    input  pe_req_t                                       pe_req_i,
    input  logic                                          pe_req_valid_i,
    output logic                                          pe_req_ready_o,
    output pe_resp_t                                      pe_resp_o,
    // Interface with the operand requester
    output operand_request_cmd_t [NrOperandQueues-1:0]    operand_request_o,
    output logic                 [NrOperandQueues-1:0]    operand_request_valid_o,
    input  logic                 [NrOperandQueues-1:0]    operand_request_ready_i,
    output logic                 [NrVInsn-1:0]            vinsn_running_o,
    // Interface with the lane's VFUs
    output vfu_operation_t                                vfu_operation_o,
    output logic                                          vfu_operation_valid_o,
    input  logic                                          alu_ready_i,
    input  logic                 [NrVInsn-1:0]            alu_vinsn_done_i,
    input  logic                                          mfpu_ready_i,
    input  logic                 [NrVInsn-1:0]            mfpu_vinsn_done_i
  );

  /************************************
   *  Operand Request Command Queues  *
   ************************************/

  // We cannot use a simple FIFO because the operand request commands include
  // bits that indicate whether there is a hazard between different vector
  // instructions. Such hazards must be continuously cleared based on the
  // value of the currently running loops from the main sequencer.
  operand_request_cmd_t [NrOperandQueues-1:0] operand_request_i;
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
        operand_request_d[queue]       = operand_request_i[queue];
        operand_request_valid_d[queue] = 1'b1;
      end

      // Re-evaluate the hazards
      operand_request_d[queue].hazard &= pe_req_i.vinsn_running;
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

  /***************************
   *  VFU Operation control  *
   ***************************/

  // Running instructions
  logic [NrVInsn-1:0] vinsn_done_d, vinsn_done_q;
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;

  assign vinsn_running_o = vinsn_running_q;

  // VFU operation
  vfu_operation_t vfu_operation_d;
  logic           vfu_operation_valid_d;

  // Returns true if the corresponding lane VFU is ready.
  function automatic logic vfu_ready(vfu_e vfu, logic alu_ready_i, logic mfpu_ready_i);
    vfu_ready = 1'b1;
    unique case (vfu)
      VFU_Alu,
      VFU_MaskUnit: vfu_ready = alu_ready_i;
      VFU_MFpu    : vfu_ready = mfpu_ready_i;
      default:;
    endcase
  endfunction

  always_comb begin: sequencer
    // Running loops
    vinsn_running_d = vinsn_running_q & pe_req_i.vinsn_running;

    // Ready to accept a new request, by default
    pe_req_ready_o = 1'b1;

    // Loops that finished execution
    vinsn_done_d         = alu_vinsn_done_i | mfpu_vinsn_done_i;
    pe_resp_o.vinsn_done = vinsn_done_q;

    // Make no requests to the operand requester
    operand_request_i    = '0;
    operand_request_push = '0;

    // Make no requests to the lane's VFUs
    vfu_operation_d       = '0;
    vfu_operation_valid_d = 1'b0;

    // Maintain the output until the functional unit acknowledges the operation
    if (vfu_operation_valid_o && !vfu_ready(vfu_operation_o.vfu, alu_ready_i, mfpu_ready_i)) begin
      vfu_operation_d       = vfu_operation_o;
      vfu_operation_valid_d = 1'b1;
      // We are not ready for another request.
      pe_req_ready_o        = 1'b0;
    end else begin
      // If the operand requesters are busy, abort the request and wait for another cycle.
      if (pe_req_valid_i)
        unique case (pe_req_i.vfu)
          VFU_Alu      : pe_req_ready_o = !(operand_request_valid_o[AluA] || operand_request_valid_o[AluB] || operand_request_valid_o[MaskM]);
          VFU_MFpu     : pe_req_ready_o = !(operand_request_valid_o[MulFPUA] || operand_request_valid_o[MulFPUB] || operand_request_valid_o[MulFPUC] || operand_request_valid_o[MaskM]);
          VFU_LoadUnit : pe_req_ready_o = !(operand_request_valid_o[MaskM]);
          VFU_StoreUnit: pe_req_ready_o = !(operand_request_valid_o[StA] || operand_request_valid_o[MaskM]);
          VFU_MaskUnit : pe_req_ready_o = !(operand_request_valid_o[AluA] || operand_request_valid_o[AluB] || operand_request_valid_o[MaskB] || operand_request_valid_o[MaskM]);
          default:;
        endcase

      // We received a new vector instruction
      if (pe_req_valid_i && pe_req_ready_o && !vinsn_running_d[pe_req_i.id]) begin
        // Populate the VFU request
        vfu_operation_d = '{
          id             : pe_req_i.id,
          op             : pe_req_i.op,
          vm             : pe_req_i.vm,
          vfu            : pe_req_i.vfu,
          use_vs1        : pe_req_i.use_vs1,
          use_vs2        : pe_req_i.use_vs2,
          use_vd_op      : pe_req_i.use_vd_op,
          scalar_op      : pe_req_i.scalar_op,
          use_scalar_op  : pe_req_i.use_scalar_op,
          vd             : pe_req_i.vd,
          use_vd         : pe_req_i.use_vd,
          swap_vs2_vd_op : pe_req_i.swap_vs2_vd_op,
          fp_rm          : pe_req_i.fp_rm,
          wide_fp_imm    : pe_req_i.wide_fp_imm,
          vtype          : pe_req_i.vtype,
          default        : '0
        };
        vfu_operation_valid_d = 1'b1;

        // Vector length calculation
        vfu_operation_d.vl = pe_req_i.vl / NrLanes;
        // If lane_id_i < vl % NrLanes, this lane has to execute one extra micro-operation.
        if (lane_id_i < pe_req_i.vl[idx_width(NrLanes)-1:0])
          vfu_operation_d.vl += 1;

        // Vector start calculation
        vfu_operation_d.vstart = pe_req_i.vstart / NrLanes;
        // If lane_id_i < vstart % NrLanes, this lane needs to execute one micro-operation less.
        if (lane_id_i < pe_req_i.vstart[idx_width(NrLanes)-1:0])
          vfu_operation_d.vstart -= 1;

        // Mark the vector instruction as running
        vinsn_running_d[pe_req_i.id] = 1'b1;

        /**********************
         *  Operand requests  *
         **********************/

        unique case (pe_req_i.vfu)
          VFU_Alu: begin
            operand_request_i[AluA] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs1,
              eew    : pe_req_i.eew_vs1,
              conv   : pe_req_i.conversion_vs1,
              vtype  : pe_req_i.vtype,
              vl     : vfu_operation_d.vl,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs1 | pe_req_i.hazard_vd,
              default: '0
            };
            operand_request_push[AluA] = pe_req_i.use_vs1;

            operand_request_i[AluB] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs2,
              eew    : pe_req_i.eew_vs2,
              conv   : pe_req_i.conversion_vs2,
              vtype  : pe_req_i.vtype,
              vl     : vfu_operation_d.vl,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs2 | pe_req_i.hazard_vd,
              default: '0
            };
            operand_request_push[AluB] = pe_req_i.use_vs2;

            // This vector instruction uses masks
            operand_request_i[MaskM] = '{
              id     : pe_req_i.id,
              vs     : VMASK,
              eew    : pe_req_i.vtype.vsew,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / 8) >> (int'(EW64) - int'(pe_req_i.vtype.vsew)),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vm | pe_req_i.hazard_vd,
              default: '0
            };
            if ((operand_request_i[MaskM].vl << (int'(EW64) - int'(pe_req_i.vtype.vsew))) * NrLanes * 8 != pe_req_i.vl)
              operand_request_i[MaskM].vl += 1;
            operand_request_push[MaskM] = !pe_req_i.vm;
          end
          VFU_MFpu: begin
            operand_request_i[MulFPUA] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs1,
              eew    : pe_req_i.eew_vs1,
              conv   : pe_req_i.conversion_vs1,
              vtype  : pe_req_i.vtype,
              vl     : vfu_operation_d.vl,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs1 | pe_req_i.hazard_vd,
              default: '0
            };
            operand_request_push[MulFPUA] = pe_req_i.use_vs1;

            operand_request_i[MulFPUB] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.swap_vs2_vd_op ? pe_req_i.vd        : pe_req_i.vs2,
              eew    : pe_req_i.swap_vs2_vd_op ? pe_req_i.eew_vd_op : pe_req_i.eew_vs2,
              conv   : pe_req_i.conversion_vs2,
              vtype  : pe_req_i.vtype,
              vl     : vfu_operation_d.vl,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.swap_vs2_vd_op ? pe_req_i.hazard_vd : (pe_req_i.hazard_vs2 | pe_req_i.hazard_vd),
              default: '0
            };
            operand_request_push[MulFPUB] = pe_req_i.swap_vs2_vd_op ? pe_req_i.use_vd_op : pe_req_i.use_vs2;

            operand_request_i[MulFPUC] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.swap_vs2_vd_op ? pe_req_i.vs2     : pe_req_i.vd,
              eew    : pe_req_i.swap_vs2_vd_op ? pe_req_i.eew_vs2 : pe_req_i.eew_vd_op,
              conv   : pe_req_i.swap_vs2_vd_op ? pe_req_i.conversion_vs2 : OpQueueConversionNone,
              vl     : vfu_operation_d.vl,
              vstart : vfu_operation_d.vstart,
              vtype  : pe_req_i.vtype,
              hazard : pe_req_i.swap_vs2_vd_op ? (pe_req_i.hazard_vs2 | pe_req_i.hazard_vd) : pe_req_i.hazard_vd,
              default: '0
            };
            operand_request_push[MulFPUC] = pe_req_i.swap_vs2_vd_op ? pe_req_i.use_vs2 : pe_req_i.use_vd_op;

            // This vector instruction uses masks
            operand_request_i[MaskM] = '{
              id     : pe_req_i.id,
              vs     : VMASK,
              eew    : pe_req_i.vtype.vsew,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / 8) >> (int'(EW64) - int'(pe_req_i.vtype.vsew)),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vm | pe_req_i.hazard_vd,
              default: '0
            };
            if ((operand_request_i[MaskM].vl << (int'(EW64) - int'(pe_req_i.vtype.vsew))) * NrLanes * 8 != pe_req_i.vl)
              operand_request_i[MaskM].vl += 1;
            operand_request_push[MaskM] = !pe_req_i.vm;
          end
          VFU_LoadUnit : begin
            // This vector instruction uses masks
            operand_request_i[MaskM] = '{
              id     : pe_req_i.id,
              vs     : VMASK,
              eew    : pe_req_i.vtype.vsew,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / 8) >> (int'(EW64) - int'(pe_req_i.vtype.vsew)),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vm | pe_req_i.hazard_vd,
              default: '0
            };
            if ((operand_request_i[MaskM].vl << (int'(EW64) - int'(pe_req_i.vtype.vsew))) * NrLanes * 8 != pe_req_i.vl)
              operand_request_i[MaskM].vl += 1;
            operand_request_push[MaskM] = !pe_req_i.vm;
          end
          VFU_StoreUnit : begin
            operand_request_i[StA] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs1,
              eew    : pe_req_i.eew_vs1,
              conv   : pe_req_i.conversion_vs1,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : pe_req_i.vl / NrLanes,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs1 | pe_req_i.hazard_vd,
              default: '0
            };
            if (operand_request_i[StA].vl * NrLanes != pe_req_i.vl)
              operand_request_i[StA].vl += 1;
            operand_request_push[StA] = pe_req_i.use_vs1;

            // This vector instruction uses masks
            operand_request_i[MaskM] = '{
              id     : pe_req_i.id,
              vs     : VMASK,
              eew    : pe_req_i.vtype.vsew,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / 8) >> (int'(EW64) - int'(pe_req_i.vtype.vsew)),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vm | pe_req_i.hazard_vd,
              default: '0
            };
            if ((operand_request_i[MaskM].vl << (int'(EW64) - int'(pe_req_i.vtype.vsew))) * NrLanes * 8 != pe_req_i.vl)
              operand_request_i[MaskM].vl += 1;
            operand_request_push[MaskM] = !pe_req_i.vm;
          end
          VFU_MaskUnit: begin
            operand_request_i[AluA] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs1,
              eew    : pe_req_i.eew_vs1,
              vtype  : pe_req_i.vtype,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs1 | pe_req_i.hazard_vd,
              default: '0
            };

            // This is an operation that runs normally on the ALU, and then gets *condensed* and reshuffled at the Mask Unit.
            if (pe_req_i.op inside {[VMSEQ:VMSBC]}) begin
              operand_request_i[AluA].vl = (pe_req_i.vl + NrLanes - 1) / NrLanes;
            end
            // This is an operation that runs normally on the ALU, and then gets reshuffled at the Mask Unit.
            else begin
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              operand_request_i[AluA].vl = (pe_req_i.vl / NrLanes) >> (int'(EW64) - int'(pe_req_i.eew_vs1));
              if ((operand_request_i[AluA].vl << (int'(EW64) - int'(pe_req_i.eew_vs1))) * NrLanes != pe_req_i.vl)
                operand_request_i[AluA].vl += 1;
            end
            operand_request_push[AluA] = pe_req_i.use_vs1;

            operand_request_i[AluB] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vs2,
              eew    : pe_req_i.eew_vs2,
              vtype  : pe_req_i.vtype,
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vs2 | pe_req_i.hazard_vd,
              default: '0
            };
            // This is an operation that runs normally on the ALU, and then gets *condensed* and reshuffled at the Mask Unit.
            if (pe_req_i.op inside {[VMSEQ:VMSBC]}) begin
              operand_request_i[AluB].vl = (pe_req_i.vl + NrLanes - 1) / NrLanes;
            end
            // This is an operation that runs normally on the ALU, and then gets reshuffled at the Mask Unit.
            else begin
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              operand_request_i[AluB].vl = (pe_req_i.vl / NrLanes) >> (int'(EW64) - int'(pe_req_i.eew_vs2));
              if ((operand_request_i[AluB].vl << (int'(EW64) - int'(pe_req_i.eew_vs2))) * NrLanes != pe_req_i.vl)
                operand_request_i[AluB].vl += 1;
            end
            operand_request_push[AluB] = pe_req_i.use_vs2;

            operand_request_i[MaskB] = '{
              id     : pe_req_i.id,
              vs     : pe_req_i.vd,
              eew    : pe_req_i.eew_vd_op,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / ELEN),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vd,
              default: '0
            };
            if ((operand_request_i[MaskB].vl * NrLanes * ELEN) != pe_req_i.vl)
              operand_request_i[MaskB].vl += 1;
            operand_request_push[MaskB] = pe_req_i.use_vd_op;

            operand_request_i[MaskM] = '{
              id     : pe_req_i.id,
              vs     : VMASK,
              eew    : pe_req_i.vtype.vsew,
              vtype  : pe_req_i.vtype,
              // Since this request goes outside of the lane, we might need to request an
              // extra operand regardless of whether it is valid in this lane or not.
              vl     : (pe_req_i.vl / NrLanes / ELEN),
              vstart : vfu_operation_d.vstart,
              hazard : pe_req_i.hazard_vm,
              default: '0
            };
            if ((operand_request_i[MaskM].vl * NrLanes * ELEN) != pe_req_i.vl)
              operand_request_i[MaskM].vl += 1;
            operand_request_push[MaskM] = !pe_req_i.vm;
          end
          default:;
        endcase
      end
    end
  end: sequencer

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_sequencer_ff
    if (!rst_ni) begin
      vinsn_done_q    <= '0;
      vinsn_running_q <= '0;

      vfu_operation_o       <= '0;
      vfu_operation_valid_o <= 1'b0;
    end else begin
      vinsn_done_q    <= vinsn_done_d;
      vinsn_running_q <= vinsn_running_d;

      vfu_operation_o       <= vfu_operation_d;
      vfu_operation_valid_o <= vfu_operation_valid_d;
    end
  end

endmodule : lane_sequencer
