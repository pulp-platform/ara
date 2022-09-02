// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Perfect dispatcher to Ara: load instructions from an external file
//
// Note: the module does not support answers from Ara,
// it is just a blind dispatcher

`define STRINGIFY(x) `"x`"
`ifndef VTRACE
`define VTRACE ./
`endif

module accel_dispatcher_ideal import axi_pkg::*; import ara_pkg::*; (
  input logic                     clk_i,
  inout logic                     rst_ni,
  // Accelerator interaface
  output accelerator_req_t  acc_req_o,
  output logic              acc_req_valid_o,
  input  logic              acc_req_ready_i,
  input  accelerator_resp_t acc_resp_i,
  input  logic              acc_resp_valid_i,
  output logic              acc_resp_ready_o
);

  localparam string vtrace = `STRINGIFY(`VTRACE);

  // Reading process
  initial begin
    int fd;
    int status;

    riscv::instruction_t insn;
    riscv::xlen_t        rs1, rs2;

    acc_req_o = '0;
    acc_req_valid_o = 1'b0;

    // Flush the answer
	acc_resp_ready_o = 1'b1;

    acc_req_o     = '0;
    acc_req_o.frm = fpnew_pkg::RNE;

    fd = $fopen(vtrace, "r");
    if (!fd) $display("Error: vector instructions list did not open correctly.");

    @(posedge rst_ni);
    @(negedge clk_i);

    while ($fscanf(fd, "%h %h", insn, rs1) == 2) begin
      // Always valid
      acc_req_valid_o = 1'b1;
      acc_req_o.insn  = insn;
      acc_req_o.rs1   = rs1;
      //acc_req_o.rs2   = rs2;
      // Wait for the handshake
      wait(acc_req_ready_i);
      @(posedge clk_i);
      @(negedge clk_i);
    end

    // Stop dispatching
    acc_req_valid_o = 1'b0;

    $fclose(fd);
  end

endmodule
