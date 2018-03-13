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
// File          : ara_system.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 14.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara system, containing an Ariane instance.

import ariane_pkg::*          ;
import ara_frontend_pkg::*    ;
import ara_pkg::*             ;
import ara_axi_pkg::axi_req_t ;
import ara_axi_pkg::axi_resp_t;

// default to AXI64 cache ports if not using the
// serpent PULP extension
`ifndef PITON_ARIANE
`ifndef AXI64_CACHE_PORTS
`define AXI64_CACHE_PORTS
`endif
`endif

module ara_system #(
    `ifdef PITON_ARIANE
    parameter bit SwapEndianess          = 0               , // swap endianess in l15 adapter
    parameter logic [63:0] CachedAddrEnd = 64'h80_0000_0000, // end of cached region
    `endif
    parameter logic [63:0] CachedAddrBeg = 64'h00_8000_0000 // begin of cached region
  ) (
    input logic        clk_i,
    input logic        rst_ni,
    input  logic       testmode_i,
    input  logic       scan_enable_i,
    input  logic       scan_data_i,
    output logic       scan_data_o,
    // Core ID, Cluster ID and boot address are considered more or less static
    input logic [63:0] boot_addr_i, // reset boot address
    input logic [63:0] hart_id_i,   // hart id in a multicore environment (reflected in a CSR)
    // Interrupt inputs
    input logic [ 1:0] irq_i,       // level sensitive IR lines, mip & sip (async)
    input logic        ipi_i,       // inter-processor interrupts (async)
    // Timer facilities
    input logic        time_irq_i,  // timer interrupt in (async)
    input logic        debug_req_i, // debug request (async)
    `ifdef AXI64_CACHE_PORTS
    // memory side, AXI Master
    output ariane_axi::req_t axi_req_o ,
    input ariane_axi::resp_t axi_resp_i,
    `else
    // L15 (memory side)
    output serpent_cache_pkg::l15_req_t l15_req_o ,
    input serpent_cache_pkg::l15_rtrn_t l15_rtrn_i,
    `endif
    output axi_req_t  ara_axi_req_o ,
    input  axi_resp_t ara_axi_resp_i
  );

  ara_req_t      ara_req;
  ara_resp_t     ara_resp;
  ara_mem_req_t  ara_mem_req;
  ara_mem_resp_t ara_mem_resp;

  ariane #(
    `ifdef PITON_ARIANE
    .SwapEndianess(SwapEndianess),
    .CachedAddrEnd(CachedAddrEnd),
    `endif
    .CachedAddrBeg(CachedAddrBeg)
  ) i_ariane (
    .clk_i       (clk_i      ),
    .rst_ni      (rst_ni     ),
    .boot_addr_i (boot_addr_i),
    .hart_id_i   (hart_id_i  ),
    .irq_i       (irq_i      ),
    .ipi_i       (ipi_i      ),
    .time_irq_i  (time_irq_i ),
    .debug_req_i (debug_req_i),
    .ara_req_o   (ara_req    ),
    .ara_resp_i  (ara_resp   ),
    `ifdef AXI64_CACHE_PORTS
    .axi_req_o  (axi_req_o ),
    .axi_resp_i (axi_resp_i)
    `else
    .l15_req_o  (l15_req_o ),
    .l15_rtrn_i (l15_rtrn_i)
    `endif
  );

  ara i_ara (
    .clk_i         (clk_i         ),
    .rst_ni        (rst_ni        ),
    .ara_req_i     (ara_req       ),
    .ara_resp_o    (ara_resp      ),
    .ara_mem_req_o (ara_mem_req   ),
    .ara_mem_resp_i('0            ),
    .ara_axi_req_o (ara_axi_req_o ),
    .ara_axi_resp_i(ara_axi_resp_i)
  );

endmodule : ara_system
