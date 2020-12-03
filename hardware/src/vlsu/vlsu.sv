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
// File:   vlsu.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   03.12.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// This is Ara's vector load/store unit. It is used exclusively for vector
// loads and vector stores. There are no guarantees regarding concurrency
// and coherence with Ariane's own load/store unit.

module vlsu import ara_pkg::*; import rvv_pkg::*; #(
    parameter int  unsigned NrLanes      = 0,
    parameter type          vaddr_t      = logic,                  // Type used to address vector register file elements
    // AXI Interface parameters
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
    parameter int  unsigned DataWidth    = $bits(elen_t),
    parameter type          strb_t       = logic [DataWidth/8-1:0]
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    // AXI Memory Interface
    output axi_req_t                axi_req_o,
    input  axi_resp_t               axi_resp_i,
    // Interface with the sequencer
    input  pe_req_t                 pe_req_i,
    input  logic                    pe_req_valid_i,
    output logic      [1:0]         pe_req_ready_o,         // Load (0) and Store (1) units
    output pe_resp_t  [1:0]         pe_resp_o,              // Load (0) and Store (1) units
    output logic                    addrgen_ack_o,
    output logic                    addrgen_error_o,
    // Interface with the lanes
    // Store unit operands
    input  elen_t     [NrLanes-1:0] stu_operand_i,
    input  logic      [NrLanes-1:0] stu_operand_valid_i,
    output logic                    stu_operand_ready_o,
    // Address generation operands
    input  elen_t     [NrLanes-1:0] addrgen_operand_i,
    input  logic      [NrLanes-1:0] addrgen_operand_valid_i,
    output logic                    addrgen_operand_ready_o,
    // Results
    output logic      [NrLanes-1:0] ldu_result_req_o,
    output vid_t      [NrLanes-1:0] ldu_result_id_o,
    output vaddr_t    [NrLanes-1:0] ldu_result_addr_o,
    output elen_t     [NrLanes-1:0] ldu_result_wdata_o,
    output strb_t     [NrLanes-1:0] ldu_result_be_o,
    input  logic      [NrLanes-1:0] ldu_result_gnt_i
  );

  /*****************
   *  Definitions  *
   *****************/

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;

  /*************
   *  AXI Cut  *
   *************/

  // Internal AXI request signals
  axi_req_t  axi_req;
  axi_resp_t axi_resp;

  axi_cut #(
    .ar_chan_t(axi_ar_t  ),
    .r_chan_t (axi_r_t   ),
    .aw_chan_t(axi_aw_t  ),
    .w_chan_t (axi_w_t   ),
    .b_chan_t (axi_b_t   ),
    .req_t    (axi_req_t ),
    .resp_t   (axi_resp_t)
  ) i_axi_cut (
    .clk_i     (clk_i     ),
    .rst_ni    (rst_ni    ),
    .mst_req_o (axi_req_o ),
    .mst_resp_i(axi_resp_i),
    .slv_req_i (axi_req   ),
    .slv_resp_o(axi_resp  )
  );

  /************************
   *  Address Generation  *
   ************************/

  // Interface with the load/store units
  addrgen_axi_req_t axi_addrgen_req;
  logic             axi_addrgen_req_valid;
  logic             ldu_axi_addrgen_req_ready;
  logic             stu_axi_addrgen_req_ready;

  assign stu_axi_addrgen_req_ready = 1'b0;
  assign pe_req_ready_o[1]         = '1;
  assign pe_resp_o[1]              = '0;

  addrgen #(
    .NrLanes     (NrLanes     ),
    .AxiDataWidth(AxiDataWidth),
    .AxiAddrWidth(AxiAddrWidth),
    .axi_ar_t    (axi_ar_t    ),
    .axi_aw_t    (axi_aw_t    )
  ) i_addrgen (
    .clk_i                      (clk_i                    ),
    .rst_ni                     (rst_ni                   ),
    // AXI Memory Interface
    .axi_aw_o                   (axi_req.aw               ),
    .axi_aw_valid_o             (axi_req.aw_valid         ),
    .axi_aw_ready_i             (axi_resp.aw_ready        ),
    .axi_ar_o                   (axi_req.ar               ),
    .axi_ar_valid_o             (axi_req.ar_valid         ),
    .axi_ar_ready_i             (axi_resp.ar_ready        ),
    // Interface with the sequencer
    .pe_req_i                   (pe_req_i                 ),
    .pe_req_valid_i             (pe_req_valid_i           ),
    .addrgen_ack_o              (addrgen_ack_o            ),
    .addrgen_error_o            (addrgen_error_o          ),
    // Interface with the lanes
    .addrgen_operand_i          (addrgen_operand_i        ),
    .addrgen_operand_valid_i    (addrgen_operand_valid_i  ),
    .addrgen_operand_ready_o    (addrgen_operand_ready_o  ),
    // Interface with the load/store units
    .axi_addrgen_req_o          (axi_addrgen_req          ),
    .axi_addrgen_req_valid_o    (axi_addrgen_req_valid    ),
    .ldu_axi_addrgen_req_ready_i(ldu_axi_addrgen_req_ready),
    .stu_axi_addrgen_req_ready_i(stu_axi_addrgen_req_ready)
  );

  assign axi_req.w       = '0;
  assign axi_req.w_valid = 1'b0;
  assign axi_req.b_ready = 1'b1;

  /**********************
   *  Vector Load Unit  *
   **********************/

  vldu #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .axi_r_t     (axi_r_t     ),
    .NrLanes     (NrLanes     ),
    .vaddr_t     (vaddr_t     )
  ) i_vldu (
    .clk_i                  (clk_i                    ),
    .rst_ni                 (rst_ni                   ),
    // AXI Memory Interface
    .axi_r_i                (axi_resp.r               ),
    .axi_r_valid_i          (axi_resp.r_valid         ),
    .axi_r_ready_o          (axi_req.r_ready          ),
    // Interface with the main sequencer
    .pe_req_i               (pe_req_i                 ),
    .pe_req_valid_i         (pe_req_valid_i           ),
    .pe_req_ready_o         (pe_req_ready_o[0]        ),
    .pe_resp_o              (pe_resp_o[0]             ),
    // Interface with the address generator
    .axi_addrgen_req_i      (axi_addrgen_req          ),
    .axi_addrgen_req_valid_i(axi_addrgen_req_valid    ),
    .axi_addrgen_req_ready_o(ldu_axi_addrgen_req_ready),
    // Interface with the lanes
    .ldu_result_req_o       (ldu_result_req_o         ),
    .ldu_result_addr_o      (ldu_result_addr_o        ),
    .ldu_result_id_o        (ldu_result_id_o          ),
    .ldu_result_wdata_o     (ldu_result_wdata_o       ),
    .ldu_result_be_o        (ldu_result_be_o          ),
    .ldu_result_gnt_i       (ldu_result_gnt_i         )
  );

/**********************
 *  INTERNAL SIGNALS  *
 **********************/
/*
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

 assign ara_axi_req_o.w       = ara_axi_req_vstu.w ;
 assign ara_axi_req_o.w_valid = ara_axi_req_vstu.w_valid;
 assign ara_axi_req_o.b_ready = ara_axi_req_vstu.b_ready;

 */
endmodule : vlsu
