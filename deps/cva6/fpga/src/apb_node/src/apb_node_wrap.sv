// Copyright 2016 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Engineer:       Davide Rossi - davide.rossi@unibo.it
//                 Florian Zaruba - zarubaf@iis.ee.ethz.ch
// Design Name:    APB Bus
// Module Name:    apb_node_wrap
// Project Name:   PULP/Kerbin
// Language:       SystemVerilog
//
// Description:    This component implements a wrapper for a configurable APB node

module apb_node_wrap #(
        parameter int unsigned NB_MASTER      = 8,
        parameter int unsigned APB_DATA_WIDTH = 32,
        parameter int unsigned APB_ADDR_WIDTH = 32
)(
        input logic                                      clk_i,
        input logic                                      rst_ni,
        // Slave Port
        APB_BUS.Slave                                    apb_slave,
        // Master Ports
        APB_BUS.Master                                   apb_masters [NB_MASTER-1:0],
        // Configuration Port
        input  logic [NB_MASTER-1:0][APB_ADDR_WIDTH-1:0] start_addr_i,
        input  logic [NB_MASTER-1:0][APB_ADDR_WIDTH-1:0] end_addr_i
    );

    logic [NB_MASTER-1:0]                     penable;
    logic [NB_MASTER-1:0]                     pwrite;
    logic [NB_MASTER-1:0][APB_ADDR_WIDTH-1:0] paddr;
    logic [NB_MASTER-1:0]                     psel;
    logic [NB_MASTER-1:0][APB_DATA_WIDTH-1:0] pwdata;
    logic [NB_MASTER-1:0][APB_DATA_WIDTH-1:0] prdata;
    logic [NB_MASTER-1:0]                     pready;
    logic [NB_MASTER-1:0]                     pslverr;

    for (genvar i = 0; i < NB_MASTER; i++) begin
        assign apb_masters[i].penable = penable[i];
        assign apb_masters[i].pwrite  = pwrite[i];
        assign apb_masters[i].paddr   = paddr[i];
        assign apb_masters[i].psel    = psel[i];
        assign apb_masters[i].pwdata  = pwdata[i];
        assign prdata[i]              = apb_masters[i].prdata;
        assign pready[i]              = apb_masters[i].pready;
        assign pslverr[i]             = apb_masters[i].pslverr;
    end

    apb_node #(
        .NB_MASTER      ( NB_MASTER         ),
        .APB_DATA_WIDTH ( APB_DATA_WIDTH    ),
        .APB_ADDR_WIDTH ( APB_ADDR_WIDTH    )
    ) apb_node_i (
        .penable_i      ( apb_slave.penable ),
        .pwrite_i       ( apb_slave.pwrite  ),
        .paddr_i        ( apb_slave.paddr   ),
	.psel_i         ( apb_slave.psel    ),
        .pwdata_i       ( apb_slave.pwdata  ),
        .prdata_o       ( apb_slave.prdata  ),
        .pready_o       ( apb_slave.pready  ),
        .pslverr_o      ( apb_slave.pslverr ),

        .penable_o      ( penable           ),
        .pwrite_o       ( pwrite            ),
        .paddr_o        ( paddr             ),
        .psel_o         ( psel              ),
        .pwdata_o       ( pwdata            ),
        .prdata_i       ( prdata            ),
        .pready_i       ( pready            ),
        .pslverr_i      ( pslverr           ),

        .START_ADDR_i   ( start_addr_i      ),
        .END_ADDR_i     ( end_addr_i        )
    );
endmodule
