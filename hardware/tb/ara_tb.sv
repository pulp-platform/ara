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

`define STRINGIFY(x) `"x`"

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

  localparam ClockPeriod  = 1ns;
  // Axi response delay [ps]
  localparam int unsigned AxiRespDelay = 200;

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

  // Controlling the reset
  initial begin
    clk   = 1'b0;
    rst_n = 1'b0;

    // Synch reset for TB memories
    repeat (10) #(ClockPeriod/2) clk = ~clk;
    clk = 1'b0;

    // Asynch reset for main system
    repeat (5) #(ClockPeriod);
    rst_n = 1'b1;
    repeat (5) #(ClockPeriod);

    // Start the clock
    forever #(ClockPeriod/2) clk = ~clk;
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
    .AxiDataWidth(AxiWideDataWidth),
    .AxiRespDelay(AxiRespDelay    )
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
      $error("Expecting a firmware to run, none was provided!");
      $finish;
    end
  end : dram_init

`ifndef TARGET_GATESIM

  /*************************
   *  PRINT STORED VALUES  *
   *************************/

  // This is useful to check that the ideal dispatcher simulation was correct

`ifndef IDEAL_DISPATCHER
  localparam OutResultFile = "../gold_results.txt";
`else
  localparam OutResultFile = "../id_results.txt";
`endif

  int fd;

  data_t                     ara_w;
  logic [AxiWideBeWidth-1:0] ara_w_strb;
  logic                      ara_w_valid;
  logic                      ara_w_ready;

  // Avoid dumping what it's not measured, e.g. cache warming
  logic dump_en_mask;

  initial begin
    fd = $fopen(OutResultFile, "w");
    $display("Dump results on %s", OutResultFile);
  end

  assign ara_w       = dut.i_ara_soc.i_system.i_ara.i_vlsu.axi_req.w.data;
  assign ara_w_strb  = dut.i_ara_soc.i_system.i_ara.i_vlsu.axi_req.w.strb;
  assign ara_w_valid = dut.i_ara_soc.i_system.i_ara.i_vlsu.axi_req.w_valid;
  assign ara_w_ready = dut.i_ara_soc.i_system.i_ara.i_vlsu.axi_resp.w_ready;

`ifndef IDEAL_DISPATCHER
  assign dump_en_mask = dut.i_ara_soc.hw_cnt_en_o[0];
`else
  // Ideal-Dispatcher system does not warm the scalar cache
  assign dump_en_mask = 1'b1;
`endif
  always_ff @(posedge clk)
    if (dump_en_mask)
      if (ara_w_valid && ara_w_ready)
        for (int b = 0; b < AxiWideBeWidth; b++)
          if (ara_w_strb[b])
            $fdisplay(fd, "%0x", ara_w[b*8 +: 8]);

`endif

  /*********
   *  EOC  *
   *********/

  always @(posedge clk) begin
    if (exit[0]) begin
      if (exit >> 1) begin
        $warning("Core Test ", $sformatf("*** FAILED *** (tohost = %0d)", (exit >> 1)));
      end else begin
        // Print vector HW runtime
`ifndef TARGET_GATESIM
        $display("[hw-cycles]: %d", int'(dut.runtime_buf_q));
`endif
        $info("Core Test ", $sformatf("*** SUCCESS *** (tohost = %0d)", (exit >> 1)));
      end

`ifndef TARGET_GATESIM
      $fclose(fd);
`endif
      $finish(exit >> 1);
    end
  end

// Dump VCD with a SW trigger
`ifdef VCD_DUMP

  /****************
  *  VCD DUMPING  *
  ****************/

`ifdef VCD_PATH
  string vcd_path = `STRINGIFY(`VCD_PATH);
`else
  string vcd_path = "../vcd/last_sim.vcd";
`endif

  localparam logic [63:0] VCD_TRIGGER_ON  = 64'h0000_0000_0000_0001;
  localparam logic [63:0] VCD_TRIGGER_OFF = 64'hFFFF_FFFF_FFFF_FFFF;

  event start_dump_event;
  event stop_dump_event;

  logic [63:0] event_trigger_reg;
  logic        dumping = 1'b0;

  assign event_trigger_reg =
           dut.i_ara_soc.i_ctrl_registers.event_trigger_o;

  initial begin
    $display("VCD_DUMP successfully defined\n");
  end

  always_ff @(posedge clk) begin
    if(event_trigger_reg == VCD_TRIGGER_ON && !dumping) begin
       $display("[TB - VCD] START DUMPING\n");
       -> start_dump_event;
       dumping = 1'b1;
    end
    if(event_trigger_reg == VCD_TRIGGER_OFF) begin
       -> stop_dump_event;
       $display("[TB - VCD] STOP DUMPING\n");
    end
  end

  initial begin
    @(start_dump_event);
    $dumpfile(vcd_path);
    $dumpvars(0, dut.i_ara_soc.i_system);
    $dumpon;

    #1 $display("[TB - VCD] DUMPING...\n");

    @(stop_dump_event)
    $dumpoff;
    $dumpflush;
    $finish;
  end

`endif

endmodule : ara_tb
