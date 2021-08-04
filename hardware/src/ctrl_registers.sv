// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description: AXI-LITE accessible control registers, holding
// static information about Ara's SoC.

module ctrl_registers #(
    parameter int   unsigned                 DataWidth       = 32,
    parameter int   unsigned                 AddrWidth       = 32,
    // Parameters
    parameter logic          [DataWidth-1:0] DRAMBaseAddr    = 0,
    parameter logic          [DataWidth-1:0] DRAMLength      = 0,
    // AXI Structs
    parameter type                           axi_lite_req_t  = logic,
    parameter type                           axi_lite_resp_t = logic
  ) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    // AXI Bus
    input  axi_lite_req_t                  axi_lite_slave_req_i,
    output axi_lite_resp_t                 axi_lite_slave_resp_o,
    // Control registers
    output logic           [DataWidth-1:0] exit_o,
    output logic           [DataWidth-1:0] dram_base_addr_o,
    output logic           [DataWidth-1:0] dram_end_addr_o
  );

  `include "common_cells/registers.svh"

  ///////////////////
  //  Definitions  //
  ///////////////////

  localparam int unsigned NumRegs          = 3;
  localparam int unsigned DataWidthInBytes = (DataWidth + 7) / 8;
  localparam int unsigned RegNumBytes      = NumRegs * DataWidthInBytes;

  localparam logic [DataWidthInBytes-1:0] ReadOnlyReg  = {DataWidthInBytes{1'b1}};
  localparam logic [DataWidthInBytes-1:0] ReadWriteReg = {DataWidthInBytes{1'b0}};

  // Memory map
  // [23:24]: dram_end_addr  (ro)
  // [15:8]:  dram_base_addr (ro)
  // [7:0]:   exit           (rw)
  localparam logic [NumRegs-1:0][DataWidth-1:0] RegRstVal = '{
    DRAMBaseAddr + DRAMLength,
    DRAMBaseAddr,
    0
  };
  localparam logic [NumRegs-1:0][DataWidthInBytes-1:0] AxiReadOnly = '{
    ReadOnlyReg,
    ReadOnlyReg,
    ReadWriteReg
  };

  /////////////////
  //  Registers  //
  /////////////////

  logic [RegNumBytes-1:0] wr_active_d, wr_active_q;

  logic [DataWidth-1:0] dram_base_address;
  logic [DataWidth-1:0] dram_end_address;
  logic [DataWidth-1:0] exit;

  axi_lite_regs #(
    .RegNumBytes (RegNumBytes    ),
    .AxiAddrWidth(AddrWidth      ),
    .AxiDataWidth(DataWidth      ),
    .AxiReadOnly (AxiReadOnly    ),
    .RegRstVal   (RegRstVal      ),
    .req_lite_t  (axi_lite_req_t ),
    .resp_lite_t (axi_lite_resp_t)
  ) i_axi_lite_regs (
    .clk_i      (clk_i                                      ),
    .rst_ni     (rst_ni                                     ),
    .axi_req_i  (axi_lite_slave_req_i                       ),
    .axi_resp_o (axi_lite_slave_resp_o                      ),
    .wr_active_o(wr_active_d                                ),
    .rd_active_o(/* Unused */                               ),
    .reg_d_i    ('0                                         ),
    .reg_load_i ('0                                         ),
    .reg_q_o    ({dram_end_address, dram_base_address, exit})
  );

  `FF(wr_active_q, wr_active_d, '0);

  /////////////////
  //   Signals   //
  /////////////////

  assign dram_base_addr_o = dram_base_address;
  assign dram_end_addr_o  = dram_end_address;
  assign exit_o           = {exit, logic'(|wr_active_q[7:0])};

endmodule : ctrl_registers
