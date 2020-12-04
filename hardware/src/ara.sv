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
// File:   ara.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's top-level, interfacing with Ariane.

module ara import ara_pkg::*; #(
    // RVV Parameters
    parameter int  unsigned NrLanes      = 0,          // Number of parallel vector lanes.
    // AXI Interface
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter type          axi_ar_t     = logic,
    parameter type          axi_r_t      = logic,
    parameter type          axi_aw_t     = logic,
    parameter type          axi_w_t      = logic,
    parameter type          axi_b_t      = logic,
    parameter type          axi_req_t    = logic,
    parameter type          axi_resp_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    // Ara has NrLanes + 3 processing elements: each one of the lanes, the vector load unit, the vector store unit, and the slide unit.
    parameter int  unsigned NrPEs        = NrLanes + 3
  ) (
    // Clock and Reset
    input  logic              clk_i,
    input  logic              rst_ni,
    // Interface with Ariane
    input  accelerator_req_t  acc_req_i,
    input  logic              acc_req_valid_i,
    output logic              acc_req_ready_o,
    output accelerator_resp_t acc_resp_o,
    output logic              acc_resp_valid_o,
    input  logic              acc_resp_ready_i,
    // AXI interface
    output axi_req_t          axi_req_o,
    input  axi_resp_t         axi_resp_i
  );

  import cf_math_pkg::idx_width;

  /*****************
   *  Definitions  *
   ****************/

  localparam int unsigned MaxVLenPerLane  = VLEN / NrLanes;       // In bits
  localparam int unsigned MaxVLenBPerLane = VLENB / NrLanes;      // In bytes
  localparam int unsigned VRFSizePerLane  = MaxVLenPerLane * 32;  // In bits
  localparam int unsigned VRFBSizePerLane = MaxVLenBPerLane * 32; // In bytes
  typedef logic [idx_width(VRFBSizePerLane)-1:0] vaddr_t; // Address of an element in each lane's VRF

  localparam int unsigned DataWidth = $bits(elen_t);
  localparam int unsigned StrbWidth = DataWidth / 8;
  typedef logic [StrbWidth-1:0] strb_t;

  /********************************
   *  Ariane interface registers  *
   ********************************/

  // Response
  accelerator_resp_t acc_resp;
  logic              acc_resp_valid;
  logic              acc_resp_ready;
  spill_register #(
    .T(accelerator_resp_t)
  ) i_acc_resp_register (
    .clk_i  (clk_i           ),
    .rst_ni (rst_ni          ),
    .data_i (acc_resp        ),
    .valid_i(acc_resp_valid  ),
    .ready_o(acc_resp_ready  ),
    .data_o (acc_resp_o      ),
    .valid_o(acc_resp_valid_o),
    .ready_i(acc_resp_ready_i)
  );

  /****************
   *  Dispatcher  *
   ****************/

  // Interface with the sequencer
  ara_req_t  ara_req;
  logic      ara_req_valid;
  logic      ara_req_ready;
  ara_resp_t ara_resp;
  logic      ara_resp_valid;

  ara_dispatcher i_dispatcher (
    .clk_i           (clk_i          ),
    .rst_ni          (rst_ni         ),
    // Interface with Ariane
    .acc_req_i       (acc_req_i      ),
    .acc_req_valid_i (acc_req_valid_i),
    .acc_req_ready_o (acc_req_ready_o),
    .acc_resp_o      (acc_resp       ),
    .acc_resp_valid_o(acc_resp_valid ),
    .acc_resp_ready_i(acc_resp_ready ),
    // Interface with the sequencer
    .ara_req_o       (ara_req        ),
    .ara_req_valid_o (ara_req_valid  ),
    .ara_req_ready_i (ara_req_ready  ),
    .ara_resp_i      (ara_resp       ),
    .ara_resp_valid_i(ara_resp_valid )
  );

  /***************
   *  Sequencer  *
   ***************/

  // Interface with the PEs
  pe_req_t              pe_req;
  logic                 pe_req_valid;
  logic     [NrPEs-1:0] pe_req_ready;
  pe_resp_t [NrPEs-1:0] pe_resp;
  // Interface with the address generator
  logic                 addrgen_ack;
  logic                 addrgen_error;

  ara_sequencer #(
    .NrLanes(NrLanes),
    .NrPEs  (NrPEs  )
  ) i_sequencer (
    .clk_i                 (clk_i          ),
    .rst_ni                (rst_ni         ),
    // Interface with the dispatcher
    .ara_req_i             (ara_req        ),
    .ara_req_valid_i       (ara_req_valid  ),
    .ara_req_ready_o       (ara_req_ready  ),
    .ara_resp_o            (ara_resp       ),
    .ara_resp_valid_o      (ara_resp_valid ),
    // Interface with the PEs
    .pe_req_o              (pe_req         ),
    .pe_req_valid_o        (pe_req_valid   ),
    .pe_req_ready_i        (pe_req_ready   ),
    .pe_resp_i             (pe_resp        ),
    // Interface with the slide unit
    .pe_scalar_resp_i      ('0             ),
    .pe_scalar_resp_valid_i(1'b0           ),
    // Interface with the address generator
    .addrgen_ack_i         (addrgen_ack    ),
    .addrgen_error_i       (addrgen_error  )
  );

  /***********
   *  Lanes  *
   ***********/

  // Interface with the vector load/store unit
  // Store unit
  elen_t  [NrLanes-1:0] stu_operand;
  logic   [NrLanes-1:0] stu_operand_valid;
  logic                 stu_operand_ready;
  // Address generation operands
  elen_t  [NrLanes-1:0] addrgen_operand;
  logic   [NrLanes-1:0] addrgen_operand_valid;
  logic                 addrgen_operand_ready;
  // Results
  logic   [NrLanes-1:0] ldu_result_req;
  vid_t   [NrLanes-1:0] ldu_result_id;
  vaddr_t [NrLanes-1:0] ldu_result_addr;
  elen_t  [NrLanes-1:0] ldu_result_wdata;
  strb_t  [NrLanes-1:0] ldu_result_be;
  logic   [NrLanes-1:0] ldu_result_gnt;

  for (genvar lane = 0; lane < NrLanes; lane++) begin: gen_lanes
    lane #(
      .NrLanes(NrLanes)
    ) i_lane (
      .clk_i                  (clk_i                       ),
      .rst_ni                 (rst_ni                      ),
      .lane_id_i              (lane[idx_width(NrLanes)-1:0]),
      // Interface with the sequencer
      .pe_req_i               (pe_req                      ),
      .pe_req_valid_i         (pe_req_valid                ),
      .pe_req_ready_o         (pe_req_ready[lane]          ),
      .pe_resp_o              (pe_resp[lane]               ),
      // Interface with the slide unit
      .sldu_result_req_i      (1'b0                        ),
      .sldu_result_addr_i     ('0                          ),
      .sldu_result_id_i       ('0                          ),
      .sldu_result_wdata_i    ('0                          ),
      .sldu_result_be_i       ('0                          ),
      .sldu_result_gnt_o      (/* Unused */                ),
      // Interface with the load unit
      .ldu_result_req_i       (ldu_result_req[lane]        ),
      .ldu_result_addr_i      (ldu_result_addr[lane]       ),
      .ldu_result_id_i        (ldu_result_id[lane]         ),
      .ldu_result_wdata_i     (ldu_result_wdata[lane]      ),
      .ldu_result_be_i        (ldu_result_be[lane]         ),
      .ldu_result_gnt_o       (ldu_result_gnt[lane]        ),
      // Interface with the store unit
      .stu_operand_o          (stu_operand[lane]           ),
      .stu_operand_valid_o    (stu_operand_valid[lane]     ),
      .stu_operand_ready_i    (stu_operand_ready           ),
      // Interface with the address generation unit
      .addrgen_operand_o      (addrgen_operand[lane]       ),
      .addrgen_operand_valid_o(addrgen_operand_valid[lane] ),
      .addrgen_operand_ready_i(addrgen_operand_ready       )
    );
  end: gen_lanes

  /****************************
   *  Vector Load/Store Unit  *
   ****************************/

  vlsu #(
    .NrLanes     (NrLanes     ),
    .AxiDataWidth(AxiDataWidth),
    .AxiAddrWidth(AxiAddrWidth),
    .axi_ar_t    (axi_ar_t    ),
    .axi_r_t     (axi_r_t     ),
    .axi_aw_t    (axi_aw_t    ),
    .axi_w_t     (axi_w_t     ),
    .axi_b_t     (axi_b_t     ),
    .axi_req_t   (axi_req_t   ),
    .axi_resp_t  (axi_resp_t  ),
    .vaddr_t     (vaddr_t     )
  ) i_vlsu (
    .clk_i                  (clk_i                     ),
    .rst_ni                 (rst_ni                    ),
    // AXI memory interface
    .axi_req_o              (axi_req_o                 ),
    .axi_resp_i             (axi_resp_i                ),
    // Interface with the sequencer
    .pe_req_i               (pe_req                    ),
    .pe_req_valid_i         (pe_req_valid              ),
    .pe_req_ready_o         (pe_req_ready[NrLanes +: 2]),
    .pe_resp_o              (pe_resp[NrLanes +: 2]     ),
    .addrgen_ack_o          (addrgen_ack               ),
    .addrgen_error_o        (addrgen_error             ),
    // Interface with the lanes
    // Store unit
    .stu_operand_i          (stu_operand               ),
    .stu_operand_valid_i    (stu_operand_valid         ),
    .stu_operand_ready_o    (stu_operand_ready         ),
    // Address Generation
    .addrgen_operand_i      (addrgen_operand           ),
    .addrgen_operand_valid_i(addrgen_operand_valid     ),
    .addrgen_operand_ready_o(addrgen_operand_ready     ),
    // Load unit
    .ldu_result_req_o       (ldu_result_req            ),
    .ldu_result_addr_o      (ldu_result_addr           ),
    .ldu_result_id_o        (ldu_result_id             ),
    .ldu_result_wdata_o     (ldu_result_wdata          ),
    .ldu_result_be_o        (ldu_result_be             ),
    .ldu_result_gnt_i       (ldu_result_gnt            )
  );

  /****************
   *  Slide unit  *
   ****************/

  assign pe_req_ready[NrLanes + 2] = 1'b1;
  assign pe_resp[NrLanes + 2]      = '0;

  /****************
   *  Assertions  *
   ****************/

  if (NrLanes == 0)
    $error("[ara] Ara needs to have at least one lane.");

  if (NrLanes > MaxNrLanes)
    $error("[ara] Ara supports at most MaxNrLanes lanes.");

  if (ara_pkg::VLEN == 0)
    $error("[ara] The vector length must be greater than zero.");

  if (ara_pkg::VLEN < ELEN)
    $error("[ara] The vector length must be greater or equal than the maximum size of a single vector element");

  if (ara_pkg::VLEN != 2**$clog2(ara_pkg::VLEN))
    $error("[ara] The vector length must be a power of two.");

endmodule : ara
