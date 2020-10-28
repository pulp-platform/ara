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
// File          : lane.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 14.01.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is a lane of the vector unit. It contains part of the vector register file
// together with the execution units.

import ariane_pkg::*      ;
import ara_frontend_pkg::*;
import ara_pkg::*         ;

module lane (
    input  logic               clk_i,
    input  logic               rst_ni,
    // Interface with the sequencer
    input  lane_req_t          operation_i,
    output lane_resp_t         resp_o,
    // Interface with the slide unit
    output word_t        [1:0] sld_operand_o,
    input  logic               sld_operand_ready_i,
    input  arb_request_t       sld_result_i,
    output logic               sld_result_gnt_o,
    // Interface with memory unit
    output word_t              ld_operand_o,
    output word_t        [1:0] st_operand_o,
    output word_t              addrgen_operand_o,
    input  logic               ld_operand_ready_i,
    input  logic               st_operand_ready_i,
    input  logic               addrgen_operand_ready_i,
    input  arb_request_t       ld_result_i,
    output logic               ld_result_gnt_o
  );

  /**********************
   *  INTERNAL SIGNALS  *
   **********************/

  // Sequencer
  opreq_cmd_t   [NR_OPQUEUE-1:0] cmd_sequencer_opreq;
  logic         [NR_OPQUEUE-1:0] cmd_valid_sequencer_opreq;
  logic         [NR_OPQUEUE-1:0] cmd_ready_opreq_sequencer;
  // Operand request
  vrf_request_t [VRF_NBANKS-1:0] vrf_request_opreq_vaccess;
  opqueue_cmd_t [NR_OPQUEUE-1:0] opqueue_cmd_opreq_vconv;
  logic         [NR_OPQUEUE-1:0] word_issued_opreq_vaccess;
  // Operand access
  word_t        [NR_OPQUEUE-1:0] word_vaccess_vconv;
  // VCONV stage
  logic         [NR_OPQUEUE-1:0] opqueue_ready_vconv_opreq;
  word_t        [2:0]            alu_operand_vconv_vex;
  word_t        [3:0]            mfpu_operand_vconv_vex;
  // VEX stage
  logic                          alu_operand_ready_vex_vconv;
  logic                          mfpu_operand_ready_vex_vconv;
  arb_request_t                  alu_result_vex_vaccess;
  arb_request_t                  mfpu_result_vex_vaccess;
  logic                          alu_result_gnt_vaccess_vex;
  logic                          mfpu_result_gnt_vaccess_vex;
  operation_t                    operation_sequencer_vex;
  vfu_status_t  [NR_VFU-1:0]     vfu_status_vex_sequencer;

  /********************
   *  LANE SEQUENCER  *
   ********************/

  lane_sequencer i_lane_sequencer (
    .clk_i            (clk_i                    ) ,
    .rst_ni           (rst_ni                   ),
    .operation_i      (operation_i              ) ,
    .resp_o           (resp_o                   ),
    .opreq_cmd_o      (cmd_sequencer_opreq      ),
    .opreq_cmd_valid_o(cmd_valid_sequencer_opreq),
    .opreq_cmd_ready_i(cmd_ready_opreq_sequencer),
    .operation_o      (operation_sequencer_vex  ),
    .vfu_status_i     (vfu_status_vex_sequencer )
  );

  /*********************
   *  OPERAND REQUEST  *
   *********************/

  opreq_stage i_opreq_stage (
    .clk_i            (clk_i                      ) ,
    .rst_ni           (rst_ni                     ),
    .opreq_cmd_i      (cmd_sequencer_opreq        ),
    .opreq_cmd_valid_i(cmd_valid_sequencer_opreq  ),
    .opreq_cmd_ready_o(cmd_ready_opreq_sequencer  ),
    .loop_running_i   (operation_i.loop_running   ),
    .vrf_request_o    (vrf_request_opreq_vaccess  ),
    .opqueue_cmd_o    (opqueue_cmd_opreq_vconv    ),
    .opqueue_ready_i  (opqueue_ready_vconv_opreq  ),
    .word_issued_o    (word_issued_opreq_vaccess  ),
    .alu_result_i     (alu_result_vex_vaccess     ),
    .mfpu_result_i    (mfpu_result_vex_vaccess    ),
    .alu_result_gnt_o (alu_result_gnt_vaccess_vex ),
    .mfpu_result_gnt_o(mfpu_result_gnt_vaccess_vex),
    .sld_result_i     (sld_result_i               ) ,
    .sld_result_gnt_o (sld_result_gnt_o           ) ,
    .ld_result_i      (ld_result_i                ) ,
    .ld_result_gnt_o  (ld_result_gnt_o            )
  );

  /********************
   *  OPERAND ACCESS  *
   ********************/

  vaccess_stage i_vaccess_stage (
    .clk_i        (clk_i                    ),
    .rst_ni       (rst_ni                   ),
    .vrf_request_i(vrf_request_opreq_vaccess),
    .word_o       (word_vaccess_vconv       )
  );

  /*********************
   *  TYPE CONVERSION  *
   *********************/

  vconv_stage i_vconv_stage (
    .clk_i                  (clk_i                       ),
    .rst_ni                 (rst_ni                      ),
    .opqueue_cmd_i          (opqueue_cmd_opreq_vconv     ),
    .opqueue_ready_o        (opqueue_ready_vconv_opreq   ),
    .word_i                 (word_vaccess_vconv          ),
    .word_issued_i          (word_issued_opreq_vaccess   ),
    .alu_operand_o          (alu_operand_vconv_vex       ),
    .mfpu_operand_o         (mfpu_operand_vconv_vex      ),
    .sld_operand_o          (sld_operand_o               ) ,
    .ld_operand_o           (ld_operand_o                ) ,
    .st_operand_o           (st_operand_o                ),
    .addrgen_operand_o      (addrgen_operand_o           ),
    .alu_operand_ready_i    (alu_operand_ready_vex_vconv ),
    .mfpu_operand_ready_i   (mfpu_operand_ready_vex_vconv),
    .red_operand_ready_i    (sld_operand_ready_i         ) ,
    .ld_operand_ready_i     (ld_operand_ready_i          ),
    .st_operand_ready_i     (st_operand_ready_i          ),
    .addrgen_operand_ready_i(addrgen_operand_ready_i     )
  );

  /*********************
   *  EXECUTION UNITS  *
   *********************/

  vex_stage i_vex_stage (
    .clk_i               (clk_i                       ),
    .rst_ni              (rst_ni                      ),
    .operation_i         (operation_sequencer_vex     ),
    .vfu_status_o        (vfu_status_vex_sequencer    ),
    .alu_operand_i       (alu_operand_vconv_vex       ),
    .mfpu_operand_i      (mfpu_operand_vconv_vex      ),
    .alu_operand_ready_o (alu_operand_ready_vex_vconv ),
    .mfpu_operand_ready_o(mfpu_operand_ready_vex_vconv),
    .alu_result_o        (alu_result_vex_vaccess      ),
    .mfpu_result_o       (mfpu_result_vex_vaccess     ),
    .alu_result_gnt_i    (alu_result_gnt_vaccess_vex  ),
    .mfpu_result_gnt_i   (mfpu_result_gnt_vaccess_vex )
  );

endmodule : lane
