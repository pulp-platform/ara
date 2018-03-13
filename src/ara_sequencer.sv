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
// File          : ara_sequencer.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 13.05.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Controls the iterations of the parallel hardware loops in execution.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module ara_sequencer (
    input  logic                      clk_i,
    input  logic                      rst_ni,
    // Interface with Ariane
    input  ara_req_t                  req_i,
    output ara_resp_t                 resp_o,
    // Interface with the lanes
    output lane_req_t                 lane_operation_o,
    input  lane_resp_t [NR_LANES+2:0] lane_resp_i,
    // Address Generator
    input  logic                      addrgen_ack_i
  );

  enum logic { IDLE, WAIT_FU } state_d, state_q;

  lane_req_t lane_operation_d;
  vloop_id_t next_id ;

  logic [NR_LANES+2:0][VLOOP_ID-1:0] lane_loop_running_d, lane_loop_running_q;
  logic [VLOOP_ID-1:0]               loop_running_d, loop_running_q, loop_running_qq;
  logic                              loop_running_full;

  lzc #(.WIDTH(VLOOP_ID)) i_next_id_lzc (
    .in_i   (~loop_running_q  ),
    .cnt_o  (next_id          ),
    .empty_o(loop_running_full)
  );

  always_comb begin
    loop_running_d = '0;
    loop_running_q = '0;

    for (int l = 0; l < NR_LANES+3; l++) begin
      loop_running_d |= lane_loop_running_d[l];
      loop_running_q |= lane_loop_running_q[l];
    end
  end

  logic [NR_LANES+2:0] lane_ready;

  // Functional unit being used by every loop

  vfu_t [VLOOP_ID-1:0] vfu_access_d, vfu_access_q;

  // Number of loops touching each functional unit
  opqueue_cnt_t [NR_VFU-1:0] vfu_cnt_d, vfu_cnt_q;

  logic [NR_VFU-1:0] vfu_busy;

  logic [NR_VFU-1:0] struct_hzd;

  // Loops accessing each vector register

  reg_access_t [31:0] read_list_d, read_list_q;
  reg_access_t [31:0] write_list_d, write_list_q;

  always_comb begin
    // Maintain state
    state_d             = state_q            ;
    lane_loop_running_d = lane_loop_running_q;
    vfu_access_d        = vfu_access_q       ;
    vfu_cnt_d           = vfu_cnt_q          ;
    read_list_d         = read_list_q        ;
    write_list_d        = write_list_q       ;

    // No operation request
    lane_operation_d              = '0            ;
    lane_operation_d.loop_running = loop_running_d;

    // Do not acknowledge anything
    resp_o = '0;

    // Update running loops
    for (int l = 0; l < NR_LANES + 3; l++)
      lane_loop_running_d[l] = lane_loop_running_q[l] & ~lane_resp_i[l].loop_done;

    // Ready lanes
    for (int l = 0; l < NR_LANES + 3; l++)
      lane_ready[l] = lane_resp_i[l].ready;

    // Busy VFUs
    vfu_busy = '0;
    for (int v = 0; v < NR_VFU; v++)
      vfu_busy[v] = (vfu_cnt_q[v] != 0);

    for (int l = 0; l < VLOOP_ID; l++)
      if (loop_running_qq[l] && ~loop_running_q[l]) // Loop ended
        vfu_cnt_d[ vfu_access_q[l] ] -= 1;

    // Update vector register's access list
    for (int vreg = 0; vreg < 32; vreg++) begin
      read_list_d[vreg].valid  = read_list_q[vreg].valid & loop_running_q[read_list_q[vreg].id]  ;
      write_list_d[vreg].valid = write_list_q[vreg].valid & loop_running_q[write_list_q[vreg].id];
    end

    // Structural hazards
    struct_hzd = '0;
    if (req_i.valid)
      case (req_i.fu)
        VFU_ALU: struct_hzd[VFU_ALU] = vfu_busy[VFU_SLD];
        VFU_SLD: struct_hzd[VFU_SLD] = vfu_busy[VFU_ALU];

        VFU_LD: struct_hzd[VFU_LD] = vfu_busy[VFU_ST];
        VFU_ST: struct_hzd[VFU_ST] = vfu_busy[VFU_LD];
      endcase

    case (state_q)
      IDLE: begin
        if (&lane_ready && ~(|struct_hzd)) begin
          if (req_i.valid && !loop_running_full) begin
            lane_operation_d.valid     = 1'b1           ;
            lane_operation_d.id        = next_id        ;
            lane_operation_d.fu        = req_i.fu       ;
            lane_operation_d.op        = req_i.op       ;
            lane_operation_d.vd        = req_i.vd       ;
            lane_operation_d.vs        = req_i.vs       ;
            lane_operation_d.mask      = req_i.mask     ;
            lane_operation_d.offset    = req_i.offset   ;
            lane_operation_d.reduction = req_i.reduction;
            lane_operation_d.use_imm   = req_i.use_imm  ;
            lane_operation_d.rs1       = req_i.rs1      ;
            lane_operation_d.rs2       = req_i.rs2      ;
            lane_operation_d.imm       = req_i.imm      ;

            // Acknowledge instruction
            resp_o.ready = 1'b1;

            // Mark loop as running
            case (req_i.fu)
              VFU_LD : lane_loop_running_d[NR_LANES + VFU_LD][next_id]  = 1'b1;
              VFU_ST : lane_loop_running_d[NR_LANES + VFU_ST][next_id]  = 1'b1;
              VFU_SLD: lane_loop_running_d[NR_LANES + VFU_SLD][next_id] = 1'b1;
              default: begin
                for (int l = 0; l < NR_LANES; l++)
                  lane_loop_running_d[l][next_id] = 1'b1;
              end
            endcase

            // Mark functional unit as used
            vfu_access_d[next_id] = req_i.fu;
            vfu_cnt_d[req_i.fu] += 1;

            // Hazards

            for (int vs = 0; vs < 4; vs++) begin
              // RAW
              if (req_i.vs[vs].valid)
                lane_operation_d.hzd[vs][ write_list_d[req_i.vs[vs].id].id ] |= write_list_d[ req_i.vs[vs].id ].valid;

              // WAR
              lane_operation_d.hzd[vs][ read_list_d[req_i.vd.id].id ] |= read_list_d[ req_i.vd.id ].valid;

              // WAW
              lane_operation_d.hzd[vs][ write_list_d[ req_i.vd.id ].id ] |= write_list_d[ req_i.vd.id ].valid;

              // No hazard with itself
              lane_operation_d.hzd[vs][ next_id ] = 1'b0;
            end

            // Mark that this loop is writing to vector vd
            if (req_i.vd.valid)
              write_list_d[ req_i.vd.id ] = {next_id, 1'b1};

            // Mark that this loop is reading vs
            for (int vs = 0; vs < 4; vs++)
              if (req_i.vs[vs].valid)
                read_list_d[ req_i.vs[vs].id ] = {next_id, 1'b1};

            // Some instructions need to wait for an acknowledgment
            // before being committed with Ariane
            if (wait_for_ack(req_i.op)) begin
              resp_o.ready = 1'b0   ;
              state_d      = WAIT_FU;
            end
          end
        end else begin
          lane_operation_d              = lane_operation_o;
          lane_operation_d.loop_running = loop_running_d  ;
        end
      end
      WAIT_FU: begin
        // Maintain output
        lane_operation_d              = lane_operation_o;
        lane_operation_d.loop_running = loop_running_d  ;

        // Mark that this loop is writing to vector vd
        if (req_i.vd.valid)
          write_list_d[ lane_operation_d.vd.id ] = {lane_operation_d.id, 1'b1};

        // Mark that this loop is reading vs
        for (int vs = 0; vs < 4; vs++)
          if (req_i.vs[vs].valid)
            read_list_d[ lane_operation_d.vs[vs].id ] = {lane_operation_d.id, 1'b1};

        for (int vs = 0; vs < 4; vs++)
          lane_operation_d.hzd[vs] = lane_operation_o.hzd[vs] & loop_running_d;

        if (is_load(lane_operation_d.op) || is_store(lane_operation_d.op))
          // Wait for the address translation
          if (addrgen_ack_i) begin
            state_d      = IDLE;
            resp_o.ready = 1'b1;
          end

        if (req_i.wscalar_file)
          // Wait for the scalar result
          if (lane_resp_i[NR_LANES + VFU_SLD].loop_done[lane_operation_d.id]) begin
            state_d       = IDLE                                              ;
            resp_o.ready  = 1'b1                                              ;
            resp_o.wbdata = lane_resp_i[NR_LANES + VFU_SLD].scalar_result.word;
          end
      end
    endcase

    // Operation finished even though one of the functional units wasn't ready
    if (lane_operation_o.valid && !loop_running_d[lane_operation_o.id] && lane_operation_d.id == lane_operation_o.id)
      lane_operation_d.valid = 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;

      lane_loop_running_q <= '0;
      loop_running_qq     <= '0;

      vfu_access_q <= '0;
      vfu_cnt_q    <= '0;
      read_list_q  <= '0;
      write_list_q <= '0;

      lane_operation_o <= '0;
    end else begin
      state_q <= state_d;

      lane_loop_running_q <= lane_loop_running_d;
      loop_running_qq     <= loop_running_q     ;

      vfu_access_q <= vfu_access_d;
      vfu_cnt_q    <= vfu_cnt_d   ;
      read_list_q  <= read_list_d ;
      write_list_q <= write_list_d;

      lane_operation_o <= lane_operation_d;
    end
  end

endmodule : ara_sequencer
