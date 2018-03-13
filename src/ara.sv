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
// File          : ara.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 28.05.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara backend top-level.

import ariane_pkg::*          ;
import ara_frontend_pkg::*    ;
import ara_pkg::*             ;
import ara_axi_pkg::axi_req_t ;
import ara_axi_pkg::axi_resp_t;

module ara (
    input  logic          clk_i,
    input  logic          rst_ni,
    // Interface with Ariane
    input  ara_req_t      ara_req_i,
    output ara_resp_t     ara_resp_o,
    // Address translation interface
    output ara_mem_req_t  ara_mem_req_o,
    input  ara_mem_resp_t ara_mem_resp_i,
    // Memory interface
    output axi_req_t      ara_axi_req_o,
    input  axi_resp_t     ara_axi_resp_i
  );

  /*************
   *  SIGNALS  *
   *************/

  // Sequencer
  lane_req_t                        operation_sequencer_lane;
  lane_resp_t   [NR_LANES-1:0]      resp_lane_sequencer;
  // SLDU
  word_t        [NR_LANES-1:0][1:0] sld_operand_lane_sldu;
  logic                             sld_operand_ready_sldu_lane;
  lane_resp_t                       resp_sldu_sequencer;
  arb_request_t [NR_LANES-1:0]      sld_result_sldu_lane;
  logic         [NR_LANES-1:0]      sld_result_gnt_lane_sldu;
  // VLSU
  word_t        [NR_LANES-1:0]      ld_operand_lane_vlsu;
  word_t        [NR_LANES-1:0][1:0] st_operand_lane_vlsu;
  word_t        [NR_LANES-1:0]      addrgen_operand_lane_vlsu;
  logic                             ld_operand_ready_vlsu_lane;
  logic                             st_operand_ready_vlsu_lane;
  logic                             addrgen_operand_ready_vlsu_lane;
  arb_request_t [NR_LANES-1:0]      ld_result_vlsu_lane;
  logic         [NR_LANES-1:0]      ld_result_gnt_lane_vlsu;
  logic                             ack_addrgen_sequencer;
  lane_resp_t   [1:0]               resp_vlsu_sequencer;

  /***************
   *  SEQUENCER  *
   ***************/

  ara_sequencer i_sequencer (
    .clk_i           (clk_i                                                          ),
    .rst_ni          (rst_ni                                                         ),
    .req_i           (ara_req_i                                                      ),
    .resp_o          (ara_resp_o                                                     ),
    .lane_operation_o(operation_sequencer_lane                                       ),
    .lane_resp_i     ({resp_sldu_sequencer, resp_vlsu_sequencer, resp_lane_sequencer}),
    .addrgen_ack_i   (ack_addrgen_sequencer                                          )
  );

  /****************
   *  SLIDE UNIT  *
   ****************/

  slide_unit i_sldu (
    .clk_i              (clk_i                      ),
    .rst_ni             (rst_ni                     ),
    .operation_i        (operation_sequencer_lane   ),
    .resp_o             (resp_sldu_sequencer        ),
    .sld_operand_i      (sld_operand_lane_sldu      ),
    .sld_operand_ready_o(sld_operand_ready_sldu_lane),
    .sld_result_o       (sld_result_sldu_lane       ),
    .sld_result_gnt_i   (sld_result_gnt_lane_sldu   )
  );

  /****************************
   *  VECTOR LOAD/STORE UNIT  *
   ****************************/

  vlsu i_vlsu (
    .clk_i                  (clk_i                          ),
    .rst_ni                 (rst_ni                         ),
    .ara_mem_req_o          (ara_mem_req_o                  ) ,
    .ara_mem_resp_i         (ara_mem_resp_i                 ),
    .addrgen_ack_o          (ack_addrgen_sequencer          ),
    .ara_axi_req_o          (ara_axi_req_o                  ) ,
    .ara_axi_resp_i         (ara_axi_resp_i                 ),
    .operation_i            (operation_sequencer_lane       ),
    .resp_o                 (resp_vlsu_sequencer            ),
    .ld_operand_i           (ld_operand_lane_vlsu           ),
    .st_operand_i           (st_operand_lane_vlsu           ),
    .addrgen_operand_i      (addrgen_operand_lane_vlsu      ),
    .ld_operand_ready_o     (ld_operand_ready_vlsu_lane     ),
    .st_operand_ready_o     (st_operand_ready_vlsu_lane     ),
    .addrgen_operand_ready_o(addrgen_operand_ready_vlsu_lane),
    .ld_result_o            (ld_result_vlsu_lane            ),
    .ld_result_gnt_i        (ld_result_gnt_lane_vlsu        )
  );

  /******************
   *  VECTOR LANES  *
   ******************/

  for (genvar l = 0; l < NR_LANES; l++) begin: gen_lanes
    lane i_lane (
      .clk_i                  (clk_i                           ) ,
      .rst_ni                 (rst_ni                          ),
      .operation_i            (operation_sequencer_lane        ),
      .resp_o                 (resp_lane_sequencer[l]          ),
      .sld_operand_o          (sld_operand_lane_sldu[l]        ),
      .sld_operand_ready_i    (sld_operand_ready_sldu_lane     ),
      .sld_result_i           (sld_result_sldu_lane[l]         ),
      .sld_result_gnt_o       (sld_result_gnt_lane_sldu[l]     ),
      .ld_operand_o           (ld_operand_lane_vlsu[l]         ),
      .st_operand_o           (st_operand_lane_vlsu[l]         ),
      .addrgen_operand_o      (addrgen_operand_lane_vlsu[l]    ),
      .ld_operand_ready_i     (ld_operand_ready_vlsu_lane      ),
      .st_operand_ready_i     (st_operand_ready_vlsu_lane      ),
      .addrgen_operand_ready_i(addrgen_operand_ready_vlsu_lane ),
      .ld_result_i            (ld_result_vlsu_lane[l]          ),
      .ld_result_gnt_o        (ld_result_gnt_lane_vlsu[l]      )
    );
  end

endmodule : ara
