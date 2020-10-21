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
// Author: Matheus Cavalcante, ETH Zurich
// Date: 21/10/2020
// Description: Top level testbench module.

import "DPI-C" function void read_elf (input string filename)                                ;
import "DPI-C" function byte get_section (output longint address, output longint len)        ;
import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);

module ara_tb;

  /*****************
   *  Definitions  *
   *****************/

  timeunit      1ns;
  timeprecision 1ps;

  `ifdef NR_LANES
  localparam NrLanes = `NR_LANES;
  `else
  localparam NrLanes = 0;
  `endif

  `ifdef VLEN
  localparam VectorLength = `VLEN;
  `else
  localparam VectorLength = 0;
  `endif

  localparam ClockPeriod = 1ns;

  localparam AxiAddrWidth       = 64;
  localparam AxiNarrowDataWidth = 64;
  localparam AxiWideDataWidth   = 64 * NrLanes / 2;
  localparam AxiWideBeWidth     = AxiWideDataWidth / 8;
  localparam AxiWideByteOffset  = $clog2(AxiWideBeWidth);

  localparam DRAMAddrBase = 64'h8000_0000;

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

  logic [31:0] exit;

  ara_testharness #(
    .NrLanes           (NrLanes           ),
    .VectorLength      (VectorLength      ),
    .AxiAddrWidth      (AxiAddrWidth      ),
    .AxiWideDataWidth  (AxiWideDataWidth  ),
    .AxiNarrowDataWidth(AxiNarrowDataWidth)
  ) dut (
    .clk_i (clk  ),
    .rst_ni(rst_n),
    .exit_o(exit )
  );

  /*************************
   *  DRAM Initialization  *
   *************************/

  typedef logic [AxiAddrWidth-1:0] addr_t    ;
  typedef logic [AxiWideDataWidth-1:0] data_t;

  initial begin : dram_init
    automatic data_t mem_row;
    byte buffer []          ;
    addr_t address          ;
    addr_t length           ;
    string binary           ;

    // tc_sram is initialized with zeros. We need to overwrite this value.
    repeat (2)
      #ClockPeriod;

    // Initialize memories
    void'($value$plusargs("PRELOAD=%s", binary));
    if (binary != "") begin
      // Read ELF
      void'(read_elf(binary))       ;
      $display("Loading %s", binary);
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
          if (address >= DRAMAddrBase && address < DRAMAddrBase)
            dut.i_sram.sram[(address - DRAMAddrBase + (w << AxiWideByteOffset)) >> AxiWideByteOffset] = mem_row;
          else
            $display("Cannot initialize address %x, which doesn't fall into the L2 region.", address);
        end
      end
    end
  end : dram_init

  /*********
   *  EOC  *
   *********/

  initial begin
    forever begin
      wait (exit[0]);

      if (exit >> 1) begin
        $warning("Core Test", $sformatf("*** FAILED *** (tohost = %0d)", (exit >> 1)));
      end else begin
        $info("Core Test", $sformatf("*** SUCCESS *** (tohost = %0d)", (exit >> 1)));
      end

      $finish(exit >> 1);
    end
  end

endmodule : ara_tb
