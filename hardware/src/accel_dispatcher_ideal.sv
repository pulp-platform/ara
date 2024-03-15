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

// Dummy definition not to throw errors during compilation
// If N_VINSN is not defined, this file will not be used anyway
`ifndef N_VINSN
`define N_VINSN 1
`endif

module accel_dispatcher_ideal import axi_pkg::*; import ara_pkg::*; (
  input logic                     clk_i,
  input logic                     rst_ni,
  // Accelerator interaface
  output accelerator_req_t  acc_req_o,
  input  accelerator_resp_t acc_resp_i,
  // XIF
  core_v_xif                xif_compressed_p,
  core_v_xif                xif_issue_p,
  core_v_xif                xif_register_p,
  core_v_xif                xif_commit_p,
  core_v_xif                xif_mem_p,
  core_v_xif                xif_mem_result_p,
  core_v_xif                xif_result_p,
  core_v_xif                xif_mod_p
);

  localparam string vtrace = `STRINGIFY(`VTRACE);

  ///////////
  //  XIF  //
  ///////////


  // Compressed interface:
  // Handshake
  // assign xif_compressed_p.compressed_valid = ;
  // assign = xif_compressed_p.compressed_ready;
  // Outputs
  // assign xif_compressed_p.compressed_req.instr = ;
  // assign xif_compressed_p.compressed_req.hartid = ;
  // Inputs
  // assign = xif_compressed_p.compressed_resp.isntr;
  // assign = xif_compressed_p.compressed_resp.accept;

  // Issue interface:
  // Handshake
  assign xif_issue_p.issue_valid = acc_req_o.req_valid;
  assign acc_resp_i.req_ready = xif_issue_p.issue_ready;
  // Outputs
  assign xif_issue_p.issue_req.instr = acc_req_o.insn;
  // assign xif_issue_p.instr_req.hartid = ;
  assign xif_issue_p.issue_req.id = acc_req_o.trans_id;
  // Inputs
  // assign = xif_issue_p.issue_resp.accept;
  // assign = xif_issue_p.issue_resp.writeback;
  // assign = xif_issue_p.issue_resp.register_read;
  // assign = xif_issue_p.issue_resp.ecswrite;

  // Register interface:
  // Handshake
  assign xif_register_p.register_valid = acc_req_o.req_valid;
  // assign acc_resp_i.req_ready = xif_register_p.register_ready;
  // Outputs
  // assign xif_register_p.register.hartid = ;
  assign xif_register_p.register.id = acc_req_o.trans_id;
  assign xif_register_p.register.rs[0] = acc_req_o.rs1;
  assign xif_register_p.register.rs[1] = acc_req_o.rs2;
  // assign xif_register_p.register.rs_valid = ;
  // assign xif_register_p.register.ecs = ;
  // assign xif_register_p.register.ecs_valid = ;

  // Commit interface:
  // Handshake
  // assign xif_commit_p.commit_valid = ;
  // Outputs
  // assign xif_commit_p.commit.hartid = ;
  assign xif_commit_p.commit.id = acc_req_o.trans_id;
  // assign xif_commit_p.commit.commit_kill = ;

  // Result interface:
  // Handshake
  assign acc_resp_i.resp_valid = xif_result_p.result_valid;
  assign xif_result_p.result_ready = acc_req_o.resp_ready;
  // Inputs
  // assign = xif_result_p.result.hartid;
  assign acc_resp_i.trans_id = xif_result_p.result.id;
  assign acc_resp_i.result = xif_result_p.result.data;
  // assign = xif_result_p.result.rd;
  // assign = xif_result_p.result.we;
  // assign = xif_result_p.result.ecswe;
  // assign = xif_result_p.result.ecsdata;

  // Modified interface for ara/cva6:
  assign xif_mod_p.mod_req.frm = acc_req_o.frm;
  assign xif_mod_p.mod_req.store_pending_req = acc_req_o.store_pending;
  // assign xif_mod_p.acc_cons_en = acc_req_o.acc_cons_en;
  // assign xif_mod_p.inval_ready = acc_req_o.inval_ready;
  assign acc_resp_i.error = xif_mod_p.mod_resp.error;
  assign acc_resp_i.store_pending = xif_mod_p.mod_resp.store_pending_resp;
  assign acc_resp_i.store_complete = xif_mod_p.mod_resp.store_complete;
  assign acc_resp_i.load_complete = xif_mod_p.mod_resp.load_complete;
  assign acc_resp_i.fflags = xif_mod_p.mod_resp.fflags;
  assign acc_resp_i.fflags_valid = xif_mod_p.mod_resp.fflags_valid;
  // assign acc_resp_i.inval_valid = xif_mod_p.inval_valid;
  // assign acc_resp_i.inval_addr = xif_mod_p.inval_addr;

  //////////
  // Data //
  //////////

  // Width and number of vector instructions in the ideal dispatcher
  localparam integer unsigned DATA_WIDTH  = 32 + 64 + 64; // vinsn + scalar reg + scalar reg
  localparam integer unsigned N_VINSN   = `N_VINSN;

  typedef struct packed {
    riscv::instruction_t insn;
    riscv::xlen_t rs1;
    riscv::xlen_t rs2;
  } fifo_payload_t;

  logic [DATA_WIDTH-1:0] fifo_data_raw;
  fifo_payload_t fifo_data;

  // FIFO-like structure with no reset
  // Instantiated here without hierarchy to please questasim

  // FIFO read pointer
  logic [$clog2(N_VINSN):0] read_pointer_n, read_pointer_q;
  // FIFO counter
  logic [$clog2(N_VINSN):0] status_cnt_n, status_cnt_q;
  // FIFO
  logic [DATA_WIDTH-1:0] fifo_q [N_VINSN];
  logic fifo_empty;

  // read and write queue logic
  always_comb begin : read_write_comb
    // Default assignment
    read_pointer_n = read_pointer_q;
    status_cnt_n   = status_cnt_q;
    fifo_data_raw  = fifo_q[read_pointer_q];

    if (acc_resp_i.req_ready && ~fifo_empty) begin
      // read from the queue is a default assignment
      // but increment the read pointer...
      if (read_pointer_n == N_VINSN - 1)
        read_pointer_n = '0;
      else
        read_pointer_n = read_pointer_q + 1;
      // ... and decrement the overall count
      status_cnt_n = status_cnt_q - 1;
    end
  end

  // sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_pointer_q  <= '0;
      status_cnt_q    <= N_VINSN;
    end else begin
      read_pointer_q  <= read_pointer_n;
      status_cnt_q    <= status_cnt_n;
    end
  end

  assign fifo_empty = (status_cnt_q == 0);

  // Output assignment
  assign fifo_data = fifo_payload_t'(fifo_data_raw);
  assign acc_req_o = '{
    insn    : fifo_data.insn,
    rs1     : fifo_data.rs1,
    rs2     : fifo_data.rs2,
    // Always valid until empty
    req_valid  : ~fifo_empty,
    // Flush the answer
    resp_ready : 1'b1,
    default : '0
  };

  // Initialize the perfect dispatcher
  initial $readmemh(vtrace, fifo_q);

  /////////////
  // Control //
  /////////////

  // Ideal performance counter
  logic [63:0] perf_cnt_d, perf_cnt_q;
  // Useful if the reset is not asserted exactly when the simulation starts
  logic was_reset = 0;

  // Reset the counter and then always count-up until the end
  assign perf_cnt_d = rst_ni ? perf_cnt_q + 1 : '0;
  always_ff @(posedge clk_i, negedge rst_ni) begin : p_perf_cnt_ideal
    if (!rst_ni) begin
      perf_cnt_q  <= '0;
      was_reset   <= 1'b1;
	end else begin
      perf_cnt_q  <= perf_cnt_d;
    end
  end

  // Stop the computation when the instructions are over and ara has returned idle
  // Just check that we are after reset
  always_ff @(posedge clk_i) begin
    if (rst_ni && was_reset && !acc_req_o.req_valid && i_system.i_ara.ara_idle) begin
      $display("[hw-cycles]: %d", int'(perf_cnt_q));
      $display("[cva6-d$-stalls]: %d", int'(dut.dcache_stall_buf_q));
      $display("[cva6-i$-stalls]: %d", int'(dut.icache_stall_buf_q));
      $display("[cva6-sb-full]: %d", int'(dut.sb_full_buf_q));
      $info("Core Test ", $sformatf("*** SUCCESS *** (tohost = %0d)", 0));
      $finish(0);
    end
  end
endmodule

// The following is another definition of the module, possibly more flexible
// but not compatible with Verilator
/*
  //////////
  // Data //
  //////////

    // Reading process
    initial begin
    int fd;
    int status;

    typedef struct packed {
      riscv::instruction_t insn;
      riscv::xlen_t rs1;
    } fifo_payload_t;
    fifo_payload_t payload;

    acc_req_o = '0;
    acc_req_o.req_valid = 1'b0;

    // Flush the answer
	acc_req_o.resp_ready = 1'b1;

    acc_req_o     = '0;
    acc_req_o.frm = fpnew_pkg::RNE;

    fd = $fopen(vtrace, "r");
    if (!fd) $display("Error: vector instructions list did not open correctly.");

    @(posedge rst_ni);
    @(negedge clk_i);

    while ($fscanf(fd, "%h", payload) == 1) begin
      // Always valid
      acc_req_o.req_valid = 1'b1;
      acc_req_o.insn  = payload.insn;
      acc_req_o.rs1   = payload.rs1;
      // Wait for the handshake
      wait(acc_resp_i.req_ready);
      @(posedge clk_i);
      @(negedge clk_i);
    end

    // Stop dispatching
    acc_req_o.req_valid = 1'b0;

    $fclose(fd);
  end

  /////////////
  // Control //
  /////////////

  // Ideal performance counter
  logic [63:0] perf_cnt_d, perf_cnt_q;

  initial begin
    $display("Ideal performance counter is initialized.");
    perf_cnt_d = '0;
    // Start the counter when the first instruction is dispatched
    @(posedge i_system.acc_req_valid);
    $display("Start counting...");
    // Loop until the last instruction is dispatched and until ara is idle again
    while (i_system.acc_req_valid || !i_system.i_ara.ara_idle) begin
	  perf_cnt_d = perf_cnt_q + 1;
      @(negedge clk_i);
	end
    $display("Stop counting.");
    perf_cnt_d = perf_cnt_q;
    $display("[cycles]: %d", int'(perf_cnt_q));
    $info("Core Test ", $sformatf("*** SUCCESS *** (tohost = %0d)", 0));
    $finish(0);
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin : p_perf_cnt_ideal
    if (!rst_ni) begin
      perf_cnt_q <= '0;
	end else begin
      perf_cnt_q <= perf_cnt_d;
    end
  end
 */
