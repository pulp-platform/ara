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
// File          : vlsu.sv
// Author        : Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Created       : 15.01.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Vector Load/Store unit

import ariane_pkg::*          ;
import ara_frontend_pkg::*    ;
import ara_pkg::*             ;
import std_cache_pkg::*       ;
import ara_axi_pkg::axi_req_t ;
import ara_axi_pkg::axi_resp_t;

module vlsu (
    input  logic                              clk_i ,
    input  logic                              rst_ni ,
    // Address translation
    output ara_mem_req_t                      ara_mem_req_o ,
    input  ara_mem_resp_t                     ara_mem_resp_i ,
    output logic                              addrgen_ack_o ,
    // Memory interface
    output axi_req_t                          ara_axi_req_o ,
    input  axi_resp_t                         ara_axi_resp_i ,
    // Operation
    input  lane_req_t                         operation_i ,
    output lane_resp_t    [ 1:0]              resp_o ,
    // Operands
    input  word_t         [NR_LANES-1:0]      ld_operand_i ,
    input  word_t         [NR_LANES-1:0][1:0] st_operand_i ,
    input  word_t         [NR_LANES-1:0]      addrgen_operand_i ,
    output logic                              ld_operand_ready_o ,
    output logic                              st_operand_ready_o ,
    output logic                              addrgen_operand_ready_o,
    // Result
    output arb_request_t  [NR_LANES-1:0]      ld_result_o ,
    input  logic          [NR_LANES-1:0]      ld_result_gnt_i
  );

  /**********************
   *  INTERNAL SIGNALS  *
   **********************/

  axi_req_t ara_axi_req_vldu ;
  axi_req_t ara_axi_req_vstu ;
  axi_req_t ara_axi_req_addrgen;

  addr_t addr_addrgen ;
  logic  addr_valid_addrgen ;
  logic  addr_ready_vldu_addrgen;
  logic  addr_ready_vstu_addrgen;

  logic ld_addr_valid_addrgen;
  logic st_addr_valid_addrgen;

  assign ld_addr_valid_addrgen = addr_valid_addrgen & addr_addrgen.is_load ;
  assign st_addr_valid_addrgen = addr_valid_addrgen & !addr_addrgen.is_load;

  /***************
   *  LOAD UNIT  *
   ***************/

  vldu i_vldu (
    .clk_i              (clk_i                  ) ,
    .rst_ni             (rst_ni                 ),
    .ara_axi_req_o      (ara_axi_req_vldu       ),
    .ara_axi_resp_i     (ara_axi_resp_i         ) ,
    .operation_i        (operation_i            ) ,
    .resp_o             (resp_o[VFU_LD]         ),
    .ld_operand_i       (ld_operand_i           ) ,
    .ld_operand_ready_o (ld_operand_ready_o     ),
    .addr_i             (addr_addrgen           ),
    .addr_valid_i       (ld_addr_valid_addrgen  ),
    .addr_ready_o       (addr_ready_vldu_addrgen),
    .ld_result_o        (ld_result_o            ) ,
    .ld_result_gnt_i    (ld_result_gnt_i        )
  );

  assign ara_axi_req_o.r_ready = ara_axi_req_vldu.r_ready;

  /****************
   *  STORE UNIT  *
   ****************/

  vstu i_vstu (
    .clk_i              (clk_i                  ),
    .rst_ni             (rst_ni                 ) ,
    .ara_axi_req_o      (ara_axi_req_vstu       ),
    .ara_axi_resp_i     (ara_axi_resp_i         ),
    .operation_i        (operation_i            ) ,
    .resp_o             (resp_o[VFU_ST]         ),
    .st_operand_i       (st_operand_i           ) ,
    .st_operand_ready_o (st_operand_ready_o     ),
    .addr_i             (addr_addrgen           ),
    .addr_valid_i       (st_addr_valid_addrgen  ),
    .addr_ready_o       (addr_ready_vstu_addrgen)
  );

  assign ara_axi_req_o.w       = ara_axi_req_vstu.w      ;
  assign ara_axi_req_o.w_valid = ara_axi_req_vstu.w_valid;
  assign ara_axi_req_o.b_ready = ara_axi_req_vstu.b_ready;

  /***********************
   *  ADDRESS GENERATOR  *
   ***********************/

  addrgen i_addrgen (
    .clk_i                   (clk_i                  ),
    .rst_ni                  (rst_ni                 ),
    .ara_axi_req_o           (ara_axi_req_addrgen    ),
    .ara_axi_resp_i          (ara_axi_resp_i         ) ,
    .ara_mem_req_o           (ara_mem_req_o          ) ,
    .ara_mem_resp_i          (ara_mem_resp_i         ),
    .addrgen_ack_o           (addrgen_ack_o          ),
    .operation_i             (operation_i            ) ,
    .addr_o                  (addr_addrgen           ),
    .addr_valid_o            (addr_valid_addrgen     ),
    .ld_addr_ready_i         (addr_ready_vldu_addrgen),
    .st_addr_ready_i         (addr_ready_vstu_addrgen),
    .addrgen_operand_i       (addrgen_operand_i      ) ,
    .addrgen_operand_ready_o (addrgen_operand_ready_o)
  );

  assign ara_axi_req_o.ar       = ara_axi_req_addrgen.ar      ;
  assign ara_axi_req_o.ar_valid = ara_axi_req_addrgen.ar_valid;
  assign ara_axi_req_o.aw       = ara_axi_req_addrgen.aw      ;
  assign ara_axi_req_o.aw_valid = ara_axi_req_addrgen.aw_valid;

endmodule : vlsu
