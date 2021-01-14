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
// File:   operand_requester.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   02.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This stage is responsible for requesting individual elements from the vector
// register file, in order, and sending them to the corresponding operand
// queues. This stage also includes the VRF arbiter.

module operand_requester import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes = 0,
    parameter int  unsigned NrBanks = 0,                         // Number of banks in the vector register file
    parameter type          vaddr_t = logic,                     // Type used to address vector register file elements
    // Dependant parameters. DO NOT CHANGE!
    parameter type          strb_t  = logic[$bits(elen_t)/8-1:0]
  ) (
    input  logic                                       clk_i,
    input  logic                                       rst_ni,
    // Interface with the lane sequencer
    input  operand_request_cmd_t [NrOperandQueues-1:0] operand_request_i,
    input  logic                 [NrOperandQueues-1:0] operand_request_valid_i,
    output logic                 [NrOperandQueues-1:0] operand_request_ready_o,
    input  logic                 [ NrVInsn-1:0]        vinsn_running_i,
    // Interface with the VRF
    output logic                 [NrBanks-1:0]         vrf_req_o,
    output vaddr_t               [NrBanks-1:0]         vrf_addr_o,
    output logic                 [NrBanks-1:0]         vrf_wen_o,
    output elen_t                [NrBanks-1:0]         vrf_wdata_o,
    output strb_t                [NrBanks-1:0]         vrf_be_o,
    output opqueue_e             [NrBanks-1:0]         vrf_tgt_opqueue_o,
    // Interface with the operand queues
    input  logic                 [NrOperandQueues-1:0] operand_queue_ready_i,
    output logic                 [NrOperandQueues-1:0] operand_issued_o,
    // Interface with the VFUs
    // ALU
    input  logic                                       alu_result_req_i,
    input  vid_t                                       alu_result_id_i,
    input  vaddr_t                                     alu_result_addr_i,
    input  elen_t                                      alu_result_wdata_i,
    input  strb_t                                      alu_result_be_i,
    output logic                                       alu_result_gnt_o,
    // Multiplier/FPU
    input  logic                                       mfpu_result_req_i,
    input  vid_t                                       mfpu_result_id_i,
    input  vaddr_t                                     mfpu_result_addr_i,
    input  elen_t                                      mfpu_result_wdata_i,
    input  strb_t                                      mfpu_result_be_i,
    output logic                                       mfpu_result_gnt_o,
    // Mask unit
    input  logic                                       masku_result_req_i,
    input  vid_t                                       masku_result_id_i,
    input  vaddr_t                                     masku_result_addr_i,
    input  elen_t                                      masku_result_wdata_i,
    input  strb_t                                      masku_result_be_i,
    output logic                                       masku_result_gnt_o,
    // Slide unit
    input  logic                                       sldu_result_req_i,
    input  vid_t                                       sldu_result_id_i,
    input  vaddr_t                                     sldu_result_addr_i,
    input  elen_t                                      sldu_result_wdata_i,
    input  strb_t                                      sldu_result_be_i,
    output logic                                       sldu_result_gnt_o,
    // Load unit
    input  logic                                       ldu_result_req_i,
    input  vid_t                                       ldu_result_id_i,
    input  vaddr_t                                     ldu_result_addr_i,
    input  elen_t                                      ldu_result_wdata_i,
    input  strb_t                                      ldu_result_be_i,
    output logic                                       ldu_result_gnt_o
  );

  import cf_math_pkg::idx_width;

  /*********************
   *  Stall mechanism  *
   *********************/

  // To handle any type of stall between vector instructions, we ensure
  // that operands of a second instruction that has a hazard on a first
  // instruction are read at the same rate the results of the second
  // instruction are written. Therefore, the second instruction can never
  // overtake the first one.

  // Instruction wrote a result
  logic [NrVInsn-1:0] vinsn_result_written_d, vinsn_result_written_q;

  always_comb begin
    vinsn_result_written_d = '0;

    // Which vector instructions are writing something?
    vinsn_result_written_d[alu_result_id_i] |= alu_result_gnt_o;
    vinsn_result_written_d[mfpu_result_id_i] |= mfpu_result_gnt_o;
    vinsn_result_written_d[masku_result_id_i] |= masku_result_gnt_o;
    vinsn_result_written_d[ldu_result_id_i] |= ldu_result_gnt_o;
    vinsn_result_written_d[sldu_result_id_i] |= sldu_result_gnt_o;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin: p_vinsn_result_written_ff
    if (!rst_ni) begin
      vinsn_result_written_q <= '0;
    end else begin
      vinsn_result_written_q <= vinsn_result_written_d;
    end
  end

  /*********************
   *  Operand request  *
   *********************/

  // There is an operand requester for each operand queue. Each one
  // can be in one of the following two states.
  typedef enum logic {
    IDLE,
    REQUESTING
  } state_t;

  // A set bit indicates that the the master q is requesting access to the bank b
  // Masters 0 to NrOperandQueues-1 correspond to the operand queues.
  // The remaining four masters correspond to the ALU, the MFPU, the MASKU, the VLDU, and the SLDU.
  localparam NrMasters = NrOperandQueues + 5;

  typedef struct packed {
    vaddr_t addr;
    logic wen;
    elen_t wdata;
    strb_t be;
    opqueue_e opqueue;
  } payload_t;

  logic     [NrBanks-1:0][NrMasters-1:0] operand_req;
  logic     [NrBanks-1:0][NrMasters-1:0] operand_gnt;
  payload_t [NrMasters-1:0]              operand_payload;

  for (genvar requester = 0; requester < NrOperandQueues; requester++) begin: gen_operand_requester
    // State of this operand requester
    state_t state_d, state_q;

    // Metadata required to request all elements of this vector operand
    struct packed {
      // Address of the next element to be read
      vaddr_t addr;
      // How many elements remain to be read
      vlen_t len;
      // Element width
      vew_e vew;

      // Hazards between vector instructions
      logic [NrVInsn-1:0] hazard;
    } requester_d, requester_q;

    // Is there a hazard during this cycle?
    logic stall;
    assign stall = |(requester_q.hazard & ~vinsn_result_written_q);

    // Did we get a grant?
    logic [NrBanks-1:0] operand_requester_gnt;
    for (genvar bank = 0; bank < NrBanks; bank++) begin: gen_operand_requester_gnt
      assign operand_requester_gnt[bank] = operand_gnt[bank][requester];
    end

    // Did we issue a word to this operand queue?
    assign operand_issued_o[requester] = |(operand_requester_gnt);

    always_comb begin: operand_requester
      // Maintain state
      state_d     = state_q;
      requester_d = requester_q;

      // Make no requests to the VRF
      operand_payload[requester] = '0;
      for (int bank = 0; bank < NrBanks; bank++)
        operand_req[bank][requester] = 1'b0;

      // Do not acknowledge any operand requester commands
      operand_request_ready_o[requester] = 1'b0;

      case (state_q)
        IDLE: begin
          // Accept a new instruction
          if (operand_request_valid_i[requester]) begin
            state_d                            = REQUESTING;
            // Acknowledge the request
            operand_request_ready_o[requester] = 1'b1;

            // Store the request
            requester_d = '{
              addr   : vaddr(operand_request_i[requester].vs, NrLanes) + (operand_request_i[requester].vstart >> (int'(EW64) - int'(operand_request_i[requester].eew))),
              len    : operand_request_i[requester].vl,
              vew    : operand_request_i[requester].eew,
              hazard : operand_request_i[requester].hazard,
              default: '0
            };
          end
        end

        REQUESTING: begin
          if (operand_queue_ready_i[requester]) begin
            // Bank we are currently requesting
            automatic int bank = requester_q.addr[idx_width(NrBanks)-1:0];

            // Operand request
            operand_req[bank][requester] = !stall;
            operand_payload[requester]   = '{
              addr   : requester_q.addr >> $clog2(NrBanks),
              opqueue: opqueue_e'(requester),
              default: '0
            };

            // Received a grant.
            if (|operand_requester_gnt) begin
              // Bump the address pointer
              requester_d.addr = requester_q.addr + 1'b1;

              // We read less than 64 bits worth of elements
              if (requester_q.len < (1 << (int'(EW64) - int'(requester_q.vew))))
                requester_d.len = 0;
              else
                requester_d.len = requester_q.len - (1 << (int'(EW64) - int'(requester_q.vew)));
            end

            // Update hazards
            requester_d.hazard = requester_q.hazard & vinsn_running_i;

            // Finished requesting all the elements
            if (requester_d.len == '0)
              state_d = IDLE;
          end
        end
      endcase
    end: operand_requester

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        state_q     <= IDLE;
        requester_q <= '0;
      end else begin
        state_q     <= state_d;
        requester_q <= requester_d;
      end
    end
  end: gen_operand_requester

  /**************
   *  Arbiters  *
   **************/

  // Remember whether the VFUs are trying to write something to the VRF
  always_comb begin
    // Default assignment
    for (int bank = 0; bank < NrBanks; bank++) begin
      operand_req[bank][NrOperandQueues + VFU_Alu]       = 1'b0;
      operand_req[bank][NrOperandQueues + VFU_MFpu]      = 1'b0;
      operand_req[bank][NrOperandQueues + VFU_MaskUnit]  = 1'b0;
      operand_req[bank][NrOperandQueues + VFU_SlideUnit] = 1'b0;
      operand_req[bank][NrOperandQueues + VFU_LoadUnit]  = 1'b0;
    end

    // Generate the payload
    operand_payload[NrOperandQueues + VFU_Alu] = '{
      addr   : alu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : alu_result_wdata_i,
      be     : alu_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MFpu] = '{
      addr   : mfpu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : mfpu_result_wdata_i,
      be     : mfpu_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_MaskUnit] = '{
      addr   : masku_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : masku_result_wdata_i,
      be     : masku_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_SlideUnit] = '{
      addr   : sldu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : sldu_result_wdata_i,
      be     : sldu_result_be_i,
      default: '0
    };
    operand_payload[NrOperandQueues + VFU_LoadUnit] = '{
      addr   : ldu_result_addr_i >> $clog2(NrBanks),
      wen    : 1'b1,
      wdata  : ldu_result_wdata_i,
      be     : ldu_result_be_i,
      default: '0
    };

    // Store their request value
    operand_req[alu_result_addr_i[idx_width(NrBanks)-1:0]][NrOperandQueues + VFU_Alu]        = alu_result_req_i;
    operand_req[mfpu_result_addr_i[idx_width(NrBanks)-1:0]][NrOperandQueues + VFU_MFpu]      = mfpu_result_req_i;
    operand_req[masku_result_addr_i[idx_width(NrBanks)-1:0]][NrOperandQueues + VFU_MaskUnit] = masku_result_req_i;
    operand_req[sldu_result_addr_i[idx_width(NrBanks)-1:0]][NrOperandQueues + VFU_SlideUnit] = sldu_result_req_i;
    operand_req[ldu_result_addr_i[idx_width(NrBanks)-1:0]][NrOperandQueues + VFU_LoadUnit]   = ldu_result_req_i;

    // Generate the grant signals
    alu_result_gnt_o   = 1'b0;
    mfpu_result_gnt_o  = 1'b0;
    masku_result_gnt_o = 1'b0;
    sldu_result_gnt_o  = 1'b0;
    ldu_result_gnt_o   = 1'b0;
    for (int bank = 0; bank < NrBanks; bank++) begin
      alu_result_gnt_o   = alu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_Alu];
      mfpu_result_gnt_o  = mfpu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_MFpu];
      masku_result_gnt_o = masku_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_MaskUnit];
      sldu_result_gnt_o  = sldu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_SlideUnit];
      ldu_result_gnt_o   = ldu_result_gnt_o | operand_gnt[bank][NrOperandQueues + VFU_LoadUnit];
    end
  end

  // Instantiate a RR arbiter per bank
  for (genvar bank = 0; bank < NrBanks; bank++) begin: gen_vrf_arbiters
    rr_arb_tree #(
      .NumIn    (NrMasters       ),
      .DataWidth($bits(payload_t)),
      .AxiVldRdy(1'b0            )
    ) i_vrf_arbiter (
      .clk_i  (clk_i                                                                                          ),
      .rst_ni (rst_ni                                                                                         ),
      .flush_i(1'b0                                                                                           ),
      .rr_i   ('0                                                                                             ),
      .data_i (operand_payload                                                                                ),
      .req_i  (operand_req[bank]                                                                              ),
      .gnt_o  (operand_gnt[bank]                                                                              ),
      .data_o ({vrf_addr_o[bank], vrf_wen_o[bank], vrf_wdata_o[bank], vrf_be_o[bank], vrf_tgt_opqueue_o[bank]}),
      .idx_o  (/* Unused */                                                                                   ),
      .req_o  (vrf_req_o[bank]                                                                                ),
      .gnt_i  (vrf_req_o[bank]                                                                                ) // Acknowledge it directly
    );
  end: gen_vrf_arbiters

endmodule : operand_requester
