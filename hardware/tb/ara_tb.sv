// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// Top level testbench module.

import "DPI-C" function void read_elf (input string filename);
import "DPI-C" function byte get_section (output longint address, output longint len);
import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);

module ara_tb;

  /*****************
   *  Definitions  *
   *****************/

  `ifndef VERILATOR
  timeunit      1ns;
  timeprecision 1ps;
  `endif

  `ifdef NR_LANES
  localparam NrLanes = `NR_LANES;
  `else
  localparam NrLanes = 0;
  `endif

  localparam ClockPeriod = 1ns;

  localparam AxiAddrWidth      = 64;
  localparam AxiWideDataWidth  = 64 * NrLanes / 2;
  localparam AxiWideBeWidth    = AxiWideDataWidth / 8;
  localparam AxiWideByteOffset = $clog2(AxiWideBeWidth);

  localparam DRAMAddrBase = 64'h8000_0000;
  localparam DRAMLength   = 64'h4000_0000; // 1GByte of DDR (split between two chips on Genesys2)

  /********************************
   *  Clock and Reset Generation  *
   ********************************/

  logic clk;
  logic rst_n;

  // Toggling the clock
  always #(ClockPeriod/2) clk = !clk;

  // Controlling the reset
  initial begin
    clk   = 1'b0;
    rst_n = 1'b0;

    repeat (5)
      #(ClockPeriod);

    rst_n = 1'b1;
  end

  /*********
   *  DUT  *
   *********/

  logic [63:0] exit;

  // This TB must be implemented in C for integration with Verilator.
  // In order to Verilator to understand that the ara_testharness module is the top-level,
  // we do not instantiate it when Verilating this module.
  `ifndef VERILATOR
  ara_testharness #(
    .NrLanes     (NrLanes         ),
    .AxiAddrWidth(AxiAddrWidth    ),
    .AxiDataWidth(AxiWideDataWidth)
  ) dut (
    .clk_i (clk  ),
    .rst_ni(rst_n),
    .exit_o(exit )
  );
  `endif

  /*************************
   *  DRAM Initialization  *
   *************************/

  typedef logic [AxiAddrWidth-1:0] addr_t;
  typedef logic [AxiWideDataWidth-1:0] data_t;

  initial begin : dram_init
    automatic data_t mem_row;
    byte buffer [];
    addr_t address;
    addr_t length;
    string binary;

    // tc_sram is initialized with zeros. We need to overwrite this value.
    repeat (2)
      #ClockPeriod;

    // Initialize memories
    void'($value$plusargs("PRELOAD=%s", binary));
    if (binary != "") begin
      // Read ELF
      read_elf(binary);
      $display("Loading ELF file %s", binary);
      while (get_section(address, length)) begin
        // Read sections
        automatic int nwords = (length + AxiWideBeWidth - 1)/AxiWideBeWidth;
        $display("Loading section %x of length %x", address, length);
        buffer = new[nwords * AxiWideBeWidth];
        void'(read_section(address, buffer));
        // Initializing memories
        for (int w = 0; w < nwords; w++) begin
          mem_row = '0;
          for (int b = 0; b < AxiWideBeWidth; b++) begin
            mem_row[8 * b +: 8] = buffer[w * AxiWideBeWidth + b];
          end
          if (address >= DRAMAddrBase && address < DRAMAddrBase + DRAMLength)
            // This requires the sections to be aligned to AxiWideByteOffset,
            // otherwise, they can be over-written.
            dut.i_ara_soc.i_dram.init_val[(address - DRAMAddrBase + (w << AxiWideByteOffset)) >> AxiWideByteOffset] = mem_row;
          else
            $display("Cannot initialize address %x, which doesn't fall into the L2 region.", address);
        end
      end
    end else begin
        $error("Expecting a firmware to run, non was provided!");
        $finish;
    end
  end : dram_init

  /*********
   *  EOC  *
   *********/

  always @(posedge clk) begin
    if (exit[0]) begin
      if (exit >> 1) begin
        $warning("Core Test ", $sformatf("*** FAILED *** (tohost = %0d)", (exit >> 1)));
      end else begin
        $info("Core Test ", $sformatf("*** SUCCESS *** (tohost = %0d)", (exit >> 1)));
      end

      $finish(exit >> 1);
    end
  end

endmodule : ara_tb
