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
  localparam NR_LANES = 0;
  `endif

  `ifdef VLEN
  localparam VectorLength = `VLEN;
  `else
  localparam VLEN = 0;
  `endif

  localparam ClockPeriod = 1ns;

  /********************************
   *  Clock and Reset Generation  *
   ********************************/

  logic clk;
  logic rst_n;

  // Toggling the clock
  always #(ClockPeriod/2) clk = !clk;

  // Controlling the reset
  initial begin
    clk   = 1'b1;
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
    .NrLanes           (NR_LANES         ),
    .VectorLength      (VLEN             ),
    .AxiWideDataWidth  (64 * NR_LANES / 2),
    .AxiNarrowDataWidth(64               )
  ) dut (
    .clk_i (clk  ),
    .rst_ni(rst_n),
    .exit_o(exit )
  );

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
