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
// Ara's SoC, containing Ariane, Ara, and a L2 cache.

module ara_soc import axi_pkg::*; #(
    // RVV Parameters
    parameter int  unsigned NrLanes      = 0,                          // Number of parallel vector lanes.
    // AXI Interface
    parameter int  unsigned AxiDataWidth = 0,
    parameter int  unsigned AxiAddrWidth = 0,
    parameter int  unsigned AxiUserWidth = 1,
    parameter int  unsigned AxiIdWidth   = 0,
    // Dependant parameters. DO NOT CHANGE!
    parameter type          axi_data_t   = logic [AxiDataWidth-1:0],
    parameter type          axi_strb_t   = logic [AxiDataWidth/8-1:0],
    parameter type          axi_addr_t   = logic [AxiAddrWidth-1:0],
    parameter type          axi_user_t   = logic [AxiUserWidth-1:0],
    parameter type          axi_id_t     = logic [AxiIdWidth-1:0]
  ) (
    input  logic             clk_i,
    input  logic             rst_ni,
    output logic      [63:0] exit_o,
    // AXI interface
    output logic             axi_aw_valid_o,
    output axi_id_t          axi_aw_id_o,
    output axi_addr_t        axi_aw_addr_o,
    output len_t             axi_aw_len_o,
    output size_t            axi_aw_size_o,
    output burst_t           axi_aw_burst_o,
    output logic             axi_aw_lock_o,
    output cache_t           axi_aw_cache_o,
    output prot_t            axi_aw_prot_o,
    output qos_t             axi_aw_qos_o,
    output region_t          axi_aw_region_o,
    output atop_t            axi_aw_atop_o,
    output axi_user_t        axi_aw_user_o,
    input  logic             axi_aw_ready_i,
    output logic             axi_w_valid_o,
    output axi_data_t        axi_w_data_o,
    output axi_strb_t        axi_w_strb_o,
    output logic             axi_w_last_o,
    output user_t            axi_w_user_o,
    input  logic             axi_w_ready_i,
    input  logic             axi_b_valid_i,
    input  axi_id_t          axi_b_id_i,
    input  resp_t            axi_b_resp_i,
    output logic             axi_b_ready_o,
    output logic             axi_ar_valid_o,
    output axi_id_t          axi_ar_id_o,
    output axi_addr_t        axi_ar_addr_o,
    output len_t             axi_ar_len_o,
    output size_t            axi_ar_size_o,
    output burst_t           axi_ar_burst_o,
    output logic             axi_ar_lock_o,
    output cache_t           axi_ar_cache_o,
    output prot_t            axi_ar_prot_o,
    output qos_t             axi_ar_qos_o,
    output region_t          axi_ar_region_o,
    output axi_user_t        axi_ar_user_o,
    input  logic             axi_ar_ready_i,
    input  logic             axi_r_valid_i,
    input  axi_id_t          axi_r_id_i,
    input  axi_data_t        axi_r_data_i,
    input  resp_t            axi_r_resp_i,
    input  logic             axi_r_last_i,
    input  axi_user_t        axi_r_user_i,
    output logic             axi_r_ready_o
  );

  /********************
   *  Memory Regions  *
   ********************/

  localparam NrAXIMasters = 2; // Actually masters, but slaves on the crossbar

  typedef enum int unsigned {
    L2MEM = 0,
    CTRL  = 1
  } axi_slaves_t;
  localparam NrAXISlaves = CTRL + 1;

  /*********
   *  AXI  *
   *********/

  `include "axi/assign.svh"
  `include "axi/typedef.svh"

  localparam AxiSlvIdWidth = AxiIdWidth + $clog2(NrAXIMasters);
  localparam AxiLlcIdWidth = AxiSlvIdWidth + 1;

  // Ariane's AXI port data width
  localparam AxiNarrowDataWidth = 64;
  // Ara's AXI port data width
  localparam AxiWideDataWidth   = AxiDataWidth;

  // Axi Typedefs
  typedef logic [AxiNarrowDataWidth-1:0] axi_narrow_data_t;
  typedef logic [AxiNarrowDataWidth/8-1:0] axi_narrow_strb_t;
  typedef logic [AxiWideDataWidth-1:0] axi_wide_data_t;
  typedef logic [AxiWideDataWidth/8-1:0] axi_wide_strb_t;
  typedef logic [AxiSlvIdWidth-1:0] axi_slv_id_t;
  typedef logic [AxiLlcIdWidth-1:0] axi_llc_id_t;

  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(llc_ar_chan_t, axi_addr_t, axi_llc_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(narrow_r_chan_t, axi_narrow_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(narrow_slv_r_chan_t, axi_narrow_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(wide_r_chan_t, axi_wide_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(wide_slv_r_chan_t, axi_wide_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(llc_r_chan_t, axi_wide_data_t, axi_llc_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(llc_aw_chan_t, axi_addr_t, axi_llc_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(narrow_w_chan_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(wide_w_chan_t, axi_wide_data_t, axi_wide_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(llc_b_chan_t, axi_llc_id_t, axi_user_t)

  `AXI_TYPEDEF_REQ_T(axi_narrow_req_t, aw_chan_t, narrow_w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_narrow_resp_t, b_chan_t, narrow_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_narrow_slv_req_t, slv_aw_chan_t, narrow_w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_narrow_slv_resp_t, slv_b_chan_t, narrow_slv_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_wide_req_t, aw_chan_t, wide_w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_wide_resp_t, b_chan_t, wide_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_wide_slv_req_t, slv_aw_chan_t, wide_w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_wide_slv_resp_t, slv_b_chan_t, wide_slv_r_chan_t)
  `AXI_TYPEDEF_REQ_T(axi_wide_llc_req_t, llc_aw_chan_t, wide_w_chan_t, llc_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_wide_llc_resp_t, llc_b_chan_t, llc_r_chan_t)

  `AXI_LITE_TYPEDEF_AW_CHAN_T(axi_lite_narrow_slv_aw_t, axi_addr_t)
  `AXI_LITE_TYPEDEF_W_CHAN_T(axi_lite_narrow_slv_w_t, axi_narrow_data_t, axi_narrow_strb_t)
  `AXI_LITE_TYPEDEF_B_CHAN_T(axi_lite_narrow_slv_b_t)
  `AXI_LITE_TYPEDEF_AR_CHAN_T(axi_lite_narrow_slv_ar_t, axi_addr_t)
  `AXI_LITE_TYPEDEF_R_CHAN_T(axi_lite_narrow_slv_r_t, axi_narrow_data_t)
  `AXI_LITE_TYPEDEF_REQ_T(axi_lite_narrow_slv_req_t, axi_lite_narrow_slv_aw_t, axi_lite_narrow_slv_w_t, axi_lite_narrow_slv_ar_t)
  `AXI_LITE_TYPEDEF_RESP_T(axi_lite_narrow_slv_resp_t, axi_lite_narrow_slv_b_t, axi_lite_narrow_slv_r_t)

  // Buses
  axi_narrow_req_t  ariane_narrow_axi_req;
  axi_narrow_resp_t ariane_narrow_axi_resp;
  axi_wide_req_t    ariane_axi_req;
  axi_wide_resp_t   ariane_axi_resp;
  axi_wide_req_t    ara_axi_req;
  axi_wide_resp_t   ara_axi_resp;

  axi_wide_slv_req_t    [NrAXISlaves-1:0] periph_wide_axi_req;
  axi_wide_slv_resp_t   [NrAXISlaves-1:0] periph_wide_axi_resp;
  axi_narrow_slv_req_t  [NrAXISlaves-1:0] periph_narrow_axi_req;
  axi_narrow_slv_resp_t [NrAXISlaves-1:0] periph_narrow_axi_resp;

  // Memory Map
  localparam logic[63:0] CTRLLength = 64'h1000;
  localparam logic[63:0] UARTLength = 64'h1000;
  localparam logic[63:0] DRAMLength = 64'h40000000; // 1GByte of DDR (split between two chips on Genesys2)

  typedef enum logic [63:0] {
    CTRLBase = 64'hD000_0000,
    UARTBase = 64'hC000_0000,
    DRAMBase = 64'h8000_0000
  } soc_bus_start_t;

  /********************
   *  Ara and Ariane  *
   ********************/

  // Accelerator ports
  ariane_pkg::accelerator_req_t acc_req;
  logic acc_req_valid;
  logic acc_req_ready;
  ariane_pkg::accelerator_resp_t acc_resp;
  logic acc_resp_valid;
  logic acc_resp_ready;

  ariane #(
    .ArianeCfg(ariane_pkg::ArianeDefaultConfig)
  ) i_ariane (
    .clk_i           (clk_i                 ),
    .rst_ni          (rst_ni                ),
    .boot_addr_i     (DRAMBase              ), // start fetching from DRAM
    .hart_id_i       ('0                    ),
    .irq_i           ('0                    ),
    .ipi_i           ('0                    ),
    .time_irq_i      ('0                    ),
    .debug_req_i     ('0                    ),
    .axi_req_o       (ariane_narrow_axi_req ),
    .axi_resp_i      (ariane_narrow_axi_resp),
    // Accelerator ports
    .acc_req_o       (acc_req               ),
    .acc_req_valid_o (acc_req_valid         ),
    .acc_req_ready_i (acc_req_ready         ),
    .acc_resp_i      (acc_resp              ),
    .acc_resp_valid_i(acc_resp_valid        ),
    .acc_resp_ready_o(acc_resp_ready        )
  );

  ara #(
    .NrLanes     (NrLanes         ),
    .AxiDataWidth(AxiWideDataWidth),
    .AxiAddrWidth(AxiAddrWidth    ),
    .axi_ar_t    (ar_chan_t       ),
    .axi_r_t     (wide_r_chan_t   ),
    .axi_aw_t    (aw_chan_t       ),
    .axi_w_t     (wide_w_chan_t   ),
    .axi_b_t     (b_chan_t        ),
    .axi_req_t   (axi_wide_req_t  ),
    .axi_resp_t  (axi_wide_resp_t )
  ) i_ara (
    .clk_i           (clk_i         ),
    .rst_ni          (rst_ni        ),
    .acc_req_i       (acc_req       ),
    .acc_req_valid_i (acc_req_valid ),
    .acc_req_ready_o (acc_req_ready ),
    .acc_resp_o      (acc_resp      ),
    .acc_resp_valid_o(acc_resp_valid),
    .acc_resp_ready_i(acc_resp_ready),
    .axi_req_o       (ara_axi_req   ),
    .axi_resp_i      (ara_axi_resp  )
  );

  axi_dw_converter #(
    .AxiSlvPortDataWidth(AxiNarrowDataWidth),
    .AxiMstPortDataWidth(AxiWideDataWidth  ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiIdWidth        ),
    .AxiMaxReads        (4                 ),
    .ar_chan_t          (ar_chan_t         ),
    .mst_r_chan_t       (wide_r_chan_t     ),
    .slv_r_chan_t       (narrow_r_chan_t   ),
    .aw_chan_t          (aw_chan_t         ),
    .b_chan_t           (b_chan_t          ),
    .mst_w_chan_t       (wide_w_chan_t     ),
    .slv_w_chan_t       (narrow_w_chan_t   ),
    .axi_mst_req_t      (axi_wide_req_t    ),
    .axi_mst_resp_t     (axi_wide_resp_t   ),
    .axi_slv_req_t      (axi_narrow_req_t  ),
    .axi_slv_resp_t     (axi_narrow_resp_t )
  ) i_ariane_axi_dwc (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
    .slv_req_i (ariane_narrow_axi_req ),
    .slv_resp_o(ariane_narrow_axi_resp),
    .mst_req_o (ariane_axi_req        ),
    .mst_resp_i(ariane_axi_resp       )
  );

  /****************
   *  Assertions  *
   ****************/

  if (NrLanes == 0)
    $error("[ara_soc] Ara needs to have at least one lane.");

  if (AxiDataWidth == 0)
    $error("[ara_soc] The AXI data width must be greater than zero.");

  if (AxiAddrWidth == 0)
    $error("[ara_soc] The AXI address width must be greater than zero.");

  if (AxiUserWidth == 0)
    $error("[ara_soc] The AXI user width must be greater than zero.");

  if (AxiIdWidth == 0)
    $error("[ara_soc] The AXI ID width must be greater than zero.");

endmodule : ara_soc
