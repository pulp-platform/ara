// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 15/04/2017
// Description: Top level testbench module. Instantiates the top level DUT, configures
//              the virtual interfaces and starts the test passed by +UVM_TEST+


import ariane_pkg::*      ;
import ariane_soc::*      ;
import ara_frontend_pkg::*;
import uvm_pkg::*         ;

`include "uvm_macros.svh"

import "DPI-C" function read_elf(input string filename)                                      ;
import "DPI-C" function byte get_section(output longint address, output longint len)         ;
import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);
import "DPI-C" function longint unsigned get_symbol_address(input string symb)               ;

module core_tb;

  static uvm_cmdline_processor uvcl = uvm_cmdline_processor::get_inst();

  localparam int unsigned CLOCK_PERIOD     = 20ns;
  // toggle with RTC period
  localparam int unsigned RTC_CLOCK_PERIOD = 30.517us;

  localparam int unsigned DATA_WIDTH  = ara_axi_pkg::DataWidth;
  localparam int unsigned DATA_BWIDTH = DATA_WIDTH / 8;
  localparam int unsigned NUM_MEMS    = (DATA_BWIDTH+7)/8;
  localparam int unsigned NUM_WORDS   = 2**21 / NUM_MEMS;

  logic clk_i;
  logic rst_ni;
  logic rtc_i;

  longint unsigned cycles;
  longint unsigned max_cycles;
  longint unsigned tohost;

  logic [31:0] exit_o;

  string binary = "";

  ara_testharness #(
    .AXI_DATA_WIDTH ( DATA_WIDTH ),
    .NUM_WORDS      ( NUM_WORDS  )
  ) dut (
    .clk_i  ( clk_i  ),
    .rst_ni ( rst_ni ),
    .rtc_i  ( 1'b0   ),
    .exit_o ( exit_o )
  );

  `ifdef SPIKE_TANDEM
  spike #(
    .Size ( NUM_WORDS * 8 )
  ) i_spike (
    .clk_i,
    .rst_ni,
    .clint_tick_i   ( rtc_i                               ),
    .commit_instr_i ( dut.i_ariane.commit_instr_id_commit ),
    .commit_ack_i   ( dut.i_ariane.commit_ack             ),
    .exception_i    ( dut.i_ariane.ex_commit              ),
    .waddr_i        ( dut.i_ariane.waddr_commit_id        ),
    .wdata_i        ( dut.i_ariane.wdata_commit_id        ),
    .priv_lvl_i     ( dut.i_ariane.priv_lvl               )
  );
  initial begin
    $display("Running binary in tandem mode");
  end
  `endif

  // Clock process
  initial begin
    clk_i  = 1'b0;
    rst_ni = 1'b0;
    repeat(8)
      #(CLOCK_PERIOD/2) clk_i = ~clk_i;
    rst_ni = 1'b1;
    forever begin
      #(CLOCK_PERIOD/2) clk_i = 1'b1;
      #(CLOCK_PERIOD/2) clk_i = 1'b0;

      //if (cycles > max_cycles)
      //    $fatal(1, "Simulation reached maximum cycle count of %d", max_cycles);

      cycles++;
    end
  end

  initial begin
    forever begin
      rtc_i                       = 1'b0;
      #(RTC_CLOCK_PERIOD/2) rtc_i = 1'b1;
      #(RTC_CLOCK_PERIOD/2) rtc_i = 1'b0;
    end
  end

  initial begin
    forever begin

      wait (exit_o[0]);

      if ((exit_o >> 1)) begin
        `uvm_error( "Core Test", $sformatf("*** FAILED *** (tohost = %0d)", (exit_o >> 1)))
      end else begin
        `uvm_info( "Core Test", $sformatf("*** SUCCESS *** (tohost = %0d)", (exit_o >> 1)), UVM_LOW)
      end

      $finish();
    end
  end

  always @(posedge clk_i) begin
    if (dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].data_req)
      if (({dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].address_tag, dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].address_index} == tohost)) begin
        if ((dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].data_wdata >> 1)) begin
          `uvm_error( "Core Test", $sformatf("*** FAILED *** (tohost = %0d)", (dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].data_wdata >> 1)))
        end else begin
          `uvm_info( "Core Test", $sformatf("*** SUCCESS *** (tohost = %0d)", (dut.i_ara_system.i_ariane.i_cache_subsystem.i_wt_dcache.req_ports_i[2].data_wdata >> 1)), UVM_LOW)
        end

        $finish();
      end
  end

  // Memory Initialization

  logic [NUM_MEMS:0] trigger = 'b1;

  for (genvar m = 0; m < NUM_MEMS; m++)
    // for faster simulation we can directly preload the ELF
    // Note that we are loosing the capabilities to use risc-fesvr though
    initial begin
      automatic logic [7:0][7:0] mem_row;
      automatic longint address, len;
      automatic byte buffer[]                       ;
      void'(uvcl.get_arg_value("+PRELOAD=", binary));

      // Wait for trigger
      wait(trigger[m]);

      if (binary != "") begin
        `uvm_info( "Core Test", $sformatf("Preloading ELF: %s", binary), UVM_LOW)

        void'(read_elf(binary));
        // wait with preloading, otherwise randomization will overwrite the existing value
        wait(rst_ni)           ;

        // while there are more sections to process
        while (get_section(address, len)) begin
          automatic int num_words = (len+DATA_BWIDTH-1)/DATA_BWIDTH;
          `uvm_info( "Core Test", $sformatf("Loading Address: %x, Length: %x", address, len), UVM_LOW)
          buffer = new [num_words*DATA_BWIDTH];
          void'(read_section(address, buffer));
          // preload memories
          for (int i = 0; i < num_words; i++) begin
            mem_row = '0;
            for (int j = 0; j < 8; j++) begin
              mem_row[j] = buffer[i*DATA_BWIDTH + m*8 + j];
            end
            dut.i_sram.genblk1[m].i_ram.Mem_DP[((address[28:0] >> $clog2(DATA_BWIDTH)) + i)] = mem_row;
          end
        end
      end

      // Trigger next preload
      trigger[m+1] = 1'b1;

      if (m == 0) begin
        // Read tohost address
        `uvm_info( "Core Test", $sformatf("tohost Address: %x", get_symbol_address("tohost")), UVM_LOW)
        tohost = get_symbol_address("tohost");
      end
    end

endmodule
