// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Ara's sequencer controls the ordering and the dependencies between the
// parallel vector instructions in execution.

module ara_sequencer import ara_pkg::*; import rvv_pkg::*; #(
    // RVV Parameters
    parameter int unsigned NrLanes = 1,          // Number of parallel vector lanes
    // Dependant parameters. DO NOT CHANGE!
    // Ara has NrLanes + 3 processing elements: each one of the lanes, the vector load unit, the vector store unit, the slide unit, and the mask unit.
    parameter int unsigned NrPEs   = NrLanes + 4
  ) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    // Interface with Ara's dispatcher
    input  ara_req_t              ara_req_i,
    input  logic                  ara_req_valid_i,
    output logic                  ara_req_ready_o,
    output ara_resp_t             ara_resp_o,
    output logic                  ara_resp_valid_o,
    output logic                  ara_idle_o,
    // Interface with the processing elements
    output pe_req_t               pe_req_o,
    output logic                  pe_req_valid_o,
    input  logic      [NrPEs-1:0] pe_req_ready_i,
    input  pe_resp_t  [NrPEs-1:0] pe_resp_i,
    input  elen_t                 pe_scalar_resp_i,      // Only the slide unit can answer with a scalar response
    input  logic                  pe_scalar_resp_valid_i,
    // Interface with the Address Generation
    input  logic                  addrgen_ack_i,
    input  logic                  addrgen_error_i
  );

  /*********************************
   *  Running vector instructions  *
   *********************************/

  // A set bit indicates that the corresponding vector instruction is running at that PE.
  logic [NrPEs-1:0][NrVInsn-1:0] pe_vinsn_running_d, pe_vinsn_running_q;

  // A set bit indicates that the corresponding vector instruction in running somewhere in Ara.
  logic [NrVInsn-1:0] vinsn_running_d, vinsn_running_q;
  vid_t               vinsn_next_id;
  logic               vinsn_running_full;

  // Ara is idle if no instruction is currently running on it.
  assign ara_idle_o = !(|vinsn_running_q);

  lzc #(
    .WIDTH(NrVInsn)
  ) i_next_id (
    .in_i   (~vinsn_running_q  ),
    .cnt_o  (vinsn_next_id     ),
    .empty_o(vinsn_running_full)
  );

  always_comb begin: p_vinsn_running
    vinsn_running_d = '0;
    for (int unsigned pe = 0; pe < NrPEs; pe++)
      vinsn_running_d |= pe_vinsn_running_d[pe];
  end: p_vinsn_running

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_vinsn_running_ff
    if (!rst_ni) begin
      vinsn_running_q    <= '0;
      pe_vinsn_running_q <= '0;
    end else begin
      vinsn_running_q    <= vinsn_running_d;
      pe_vinsn_running_q <= pe_vinsn_running_d;
    end
  end

  /***************
   *  Sequencer  *
   ***************/

  // If the instruction requires an answer to Ariane, the sequencer needs to wait.
  enum logic { IDLE, WAIT } state_d, state_q;

  // For hazard detection, we need to know which vector instruction is reading/writing to each vector register
  typedef struct packed {
    vid_t vid;
    logic valid;
  } vreg_access_t;
  vreg_access_t [31:0] read_list_d, read_list_q;
  vreg_access_t [31:0] write_list_d, write_list_q;

  pe_req_t pe_req_d;
  logic    pe_req_valid_d;

  // This function determines the VFU responsible for handling this operation.
  function automatic vfu_e vfu(ara_op_e op);
    unique case (op) inside
      [VADD:VMERGE]   : vfu = VFU_Alu;
      [VMUL:VFSGNJX]  : vfu = VFU_MFpu;
      [VMANDNOT:VMSBC]: vfu = VFU_MaskUnit;
      [VLE:VLXE]      : vfu = VFU_LoadUnit;
      [VSE:VSXE]      : vfu = VFU_StoreUnit;
    endcase
  endfunction: vfu

  always_comb begin: p_sequencer
    // Default assignments
    state_d            = state_q;
    pe_vinsn_running_d = pe_vinsn_running_q;
    read_list_d        = read_list_q;
    write_list_d       = write_list_q;

    // Maintain request
    pe_req_d = '{
      vinsn_running: vinsn_running_d,
      default      : '0
    };
    pe_req_valid_d = 1'b0;

    // No response
    ara_resp_o       = '0;
    ara_resp_valid_o = 1'b0;

    // Always ready to receive a new request
    ara_req_ready_o = 1'b1;

    // Update vector register's access list
    for (int unsigned v = 0; v < 32; v++) begin
      read_list_d[v].valid &= vinsn_running_q[read_list_q[v].vid] ;
      write_list_d[v].valid &= vinsn_running_q[write_list_q[v].vid];
    end

    // Update the running vector instructions
    for (int pe = 0; pe < NrPEs; pe++)
      pe_vinsn_running_d[pe] &= ~pe_resp_i[pe].vinsn_done;

    case (state_q)
      IDLE: begin
        // Sent a request, but the VFUs are not ready
        if (pe_req_valid_o && !(&pe_req_ready_i)) begin
          // Maintain output
          pe_req_d               = pe_req_o;
          pe_req_d.vinsn_running = vinsn_running_d;
          pe_req_valid_d         = pe_req_valid_o;

          // Recalculate the hazard bits
          pe_req_d.hazard_vs1 &= vinsn_running_d;
          pe_req_d.hazard_vs2 &= vinsn_running_d;
          pe_req_d.hazard_vd &= vinsn_running_d;
          pe_req_d.hazard_vm &= vinsn_running_d;

          // We are not ready
          ara_req_ready_o = 1'b0;
        // Received a new request
        end else if (ara_req_valid_i) begin
          // PEs are ready, and we can handle another running vector instruction
          if (&pe_req_ready_i && !vinsn_running_full) begin
            /*************
             *  Hazards  *
             *************/

            // RAW
            if (ara_req_i.use_vs1)
              pe_req_d.hazard_vs1[write_list_d[ara_req_i.vs1].vid] |= write_list_d[ara_req_i.vs1].valid;
            if (ara_req_i.use_vs2)
              pe_req_d.hazard_vs2[write_list_d[ara_req_i.vs2].vid] |= write_list_d[ara_req_i.vs2].valid;
            if (!ara_req_i.vm)
              pe_req_d.hazard_vm[write_list_d[VMASK].vid] |= write_list_d[VMASK].valid;

            // WAR
            if (ara_req_i.use_vd) begin
              pe_req_d.hazard_vs1[read_list_d[ara_req_i.vd].vid] |= read_list_d[ara_req_i.vd].valid;
              pe_req_d.hazard_vs2[read_list_d[ara_req_i.vd].vid] |= read_list_d[ara_req_i.vd].valid;
              pe_req_d.hazard_vm[read_list_d[ara_req_i.vd].vid] |= read_list_d[ara_req_i.vd].valid;
            end

            // WAW
            if (ara_req_i.use_vd)
              pe_req_d.hazard_vd[write_list_d[ara_req_i.vd].vid] |= write_list_d[ara_req_i.vd].valid;

            /***********
             *  Issue  *
             ***********/

            // Populate the PE request
            pe_req_d = '{
              id            : vinsn_next_id,
              op            : ara_req_i.op,
              vm            : ara_req_i.vm,
              eew_vmask     : ara_req_i.eew_vmask,
              vfu           : vfu(ara_req_i.op),
              vs1           : ara_req_i.vs1,
              use_vs1       : ara_req_i.use_vs1,
              conversion_vs1: ara_req_i.conversion_vs1,
              eew_vs1       : ara_req_i.eew_vs1,
              vs2           : ara_req_i.vs2,
              use_vs2       : ara_req_i.use_vs2,
              conversion_vs2: ara_req_i.conversion_vs2,
              eew_vs2       : ara_req_i.eew_vs2,
              use_vd_op     : ara_req_i.use_vd_op,
              eew_vd_op     : ara_req_i.eew_vd_op,
              scalar_op     : ara_req_i.scalar_op,
              use_scalar_op : ara_req_i.use_scalar_op,
              swap_vs2_vd_op: ara_req_i.swap_vs2_vd_op,
              stride        : ara_req_i.stride,
              vd            : ara_req_i.vd,
              use_vd        : ara_req_i.use_vd,
              emul          : ara_req_i.emul,
              fp_rm         : ara_req_i.fp_rm,
              vl            : ara_req_i.vl,
              vstart        : ara_req_i.vstart,
              vtype         : ara_req_i.vtype,
              vinsn_running : vinsn_running_d,
              hazard_vd     : pe_req_d.hazard_vd,
              hazard_vm     : pe_req_d.hazard_vm,
              hazard_vs1    : pe_req_d.hazard_vs1,
              hazard_vs2    : pe_req_d.hazard_vs2,
              default       : '0
            };

            // We only issue instructions that take no operands if they have no hazards.
            if (!(|{ara_req_i.use_vs1, ara_req_i.use_vs2, ara_req_i.use_vd_op, !ara_req_i.vm}) &&
                |{pe_req_d.hazard_vs1, pe_req_d.hazard_vs2, pe_req_d.hazard_vm, pe_req_d.hazard_vd}) begin
              ara_req_ready_o = 1'b0;
              pe_req_valid_d  = 1'b0;
            end else begin
              // Acknowledge instruction
              ara_req_ready_o = 1'b1;

              // Remember that the vector instruction is running
              unique case (vfu(ara_req_i.op))
                VFU_LoadUnit : pe_vinsn_running_d[NrLanes + OffsetLoad][vinsn_next_id]  = 1'b1;
                VFU_StoreUnit: pe_vinsn_running_d[NrLanes + OffsetStore][vinsn_next_id] = 1'b1;
                VFU_SlideUnit: pe_vinsn_running_d[NrLanes + OffsetSlide][vinsn_next_id] = 1'b1;
                VFU_MaskUnit : pe_vinsn_running_d[NrLanes + OffsetMask][vinsn_next_id]  = 1'b1;
                default : // Instruction is running on the lanes
                  for (int l = 0; l < NrLanes; l++)
                    pe_vinsn_running_d[l][vinsn_next_id] = 1'b1;
              endcase

              // Masked vector instructions also run on the mask unit
              pe_vinsn_running_d[NrLanes + OffsetMask][vinsn_next_id] = !ara_req_i.vm;

              // Some instructions need to wait for an acknowledgment
              // before being committed with Ariane
              if (is_load(ara_req_i.op) || is_store(ara_req_i.op) || !ara_req_i.use_vd) begin
                ara_req_ready_o = 1'b0;
                state_d         = WAIT;
              end

              // Issue the instruction
              pe_req_valid_d = 1'b1;

              // Mark that this vector instruction is writing to vector vd
              if (ara_req_i.use_vd)
                write_list_d[ara_req_i.vd] = '{vid: vinsn_next_id, valid: 1'b1};

              // Mark that this loop is reading vs
              if (ara_req_i.use_vs1)
                read_list_d[ara_req_i.vs1] = '{vid: vinsn_next_id, valid: 1'b1};
              if (ara_req_i.use_vs2)
                read_list_d[ara_req_i.vs2] = '{vid: vinsn_next_id, valid: 1'b1};
              if (!ara_req_i.vm)
                read_list_d[VMASK] = '{vid: vinsn_next_id, valid: 1'b1};
            end
          end else begin
            // Wait until the PEs are ready
            ara_req_ready_o = 1'b0;
          end
        end
      end

      WAIT: begin
        // Wait until we got an answer from lane 0
        ara_req_ready_o = 1'b0;

        // Maintain output
        pe_req_d               = pe_req_o;
        pe_req_d.vinsn_running = vinsn_running_d;
        pe_req_valid_d         = pe_req_valid_o;

        // Recalculate the hazard bits
        pe_req_d.hazard_vs1 &= vinsn_running_d;
        pe_req_d.hazard_vs2 &= vinsn_running_d;
        pe_req_d.hazard_vd &= vinsn_running_d;
        pe_req_d.hazard_vm &= vinsn_running_d;

        if (is_load(pe_req_d.op) || is_store(pe_req_d.op))
          // Wait for the address translation
          if (addrgen_ack_i) begin
            state_d          = IDLE;
            ara_req_ready_o  = 1'b1;
            ara_resp_valid_o = 1'b1;
            ara_resp_o.error = addrgen_error_i;
          end

        if (!ara_req_i.use_vd)
          // Wait for the scalar result
          if (pe_scalar_resp_valid_i) begin
            // Acknowledge the request
            state_d          = IDLE;
            ara_req_ready_o  = 1'b1;
            ara_resp_o.resp  = pe_scalar_resp_i;
            ara_resp_valid_o = 1'b1;
          end
      end
    endcase
  end : p_sequencer

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_sequencer_ff
    if (!rst_ni) begin
      state_q <= IDLE;

      read_list_q  <= '0;
      write_list_q <= '0;

      pe_req_o       <= '0;
      pe_req_valid_o <= 1'b0;
    end else begin
      state_q <= state_d;

      read_list_q  <= read_list_d;
      write_list_q <= write_list_d;

      pe_req_o       <= pe_req_d;
      pe_req_valid_o <= pe_req_valid_d;
    end
  end

endmodule : ara_sequencer
