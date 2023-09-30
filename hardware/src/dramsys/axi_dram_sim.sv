// Copyright 2023 ETH Zurich and 
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 07.June.2023

// An axi wrapped dram model

`include "axi/assign.svh"
`include "axi/typedef.svh"

module axi_dram_sim #(
    // AXI Parameter
    parameter int unsigned AxiAddrWidth     = 32,
    parameter int unsigned AxiDataWidth     = 256,
    parameter int unsigned AxiIdWidth       = 5,
    parameter int unsigned AxiUserWidth     = 1,
    //DRAM Base Addr
    parameter longint unsigned BASE         = 64'h80000000,
    //DRAM type
    parameter              DRAMType         = "DDR4",   
    parameter              CustomerDRAM     = "none",   
    // AXI interface 
    parameter type         axi_req_t        = logic,
    parameter type         axi_resp_t       = logic,
    parameter type         axi_ar_t         = logic,
    parameter type         axi_r_t          = logic,
    parameter type         axi_aw_t         = logic,
    parameter type         axi_w_t          = logic,
    parameter type         axi_b_t          = logic
    )(
    /// Clock, positive edge triggered.
    input   logic                           clk_i,
    /// Reset, active low.
    input   logic                           rst_ni,
    /// Axi
    input   axi_req_t                       axi_req_i,
    output  axi_resp_t                      axi_resp_o
 );
 
    //define port to DRAM
    localparam int unsigned DramAddrWidth   = AxiAddrWidth;
    localparam int unsigned DramDataWidth   = 512;
    localparam int unsigned DramIdWidth     = AxiIdWidth;
    localparam int unsigned DramUserWidth   = AxiUserWidth;
    typedef logic [DramAddrWidth-1:0]       addr_t;
    typedef logic [DramDataWidth-1:0]       data_t;
    typedef logic [DramDataWidth/8-1:0]     strb_t;
    typedef logic [DramIdWidth-1:0]         id_t;
    typedef logic [DramUserWidth-1:0]       user_t;
    `AXI_TYPEDEF_ALL(dram_axi, addr_t, id_t, data_t, strb_t, user_t)

    dram_axi_req_t                          dram_axi_req;
    dram_axi_resp_t                         dram_axi_resp;


    axi_dw_converter #(
        .AxiMaxReads        (64),
        .AxiSlvPortDataWidth(AxiDataWidth),
        .AxiMstPortDataWidth(DramDataWidth),
        .AxiAddrWidth       (AxiAddrWidth),
        .AxiIdWidth         (AxiIdWidth),
        .aw_chan_t          (axi_aw_t),
        .mst_w_chan_t       (dram_axi_w_chan_t),
        .slv_w_chan_t       (axi_w_t),
        .b_chan_t           (axi_b_t),
        .ar_chan_t          (axi_ar_t),
        .mst_r_chan_t       (dram_axi_r_chan_t),
        .slv_r_chan_t       (axi_r_t),
        .axi_mst_req_t      (dram_axi_req_t),
        .axi_mst_resp_t     (dram_axi_resp_t),
        .axi_slv_req_t      (axi_req_t),
        .axi_slv_resp_t     (axi_resp_t)
    ) i_axi_dw_converter (
        .clk_i,
        .rst_ni,
        .slv_req_i (axi_req_i ),
        .slv_resp_o(axi_resp_o),
        .mst_req_o (dram_axi_req ),
        .mst_resp_i(dram_axi_resp)
    );


    `AXI_LITE_TYPEDEF_ALL(dram_axi_lite, addr_t, data_t, strb_t)

    dram_axi_lite_req_t dram_axi_lite_req;
    dram_axi_lite_resp_t dram_axi_lite_resp;


    axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth),
    .AxiDataWidth   (DramDataWidth),
    .AxiIdWidth     (AxiIdWidth),
    .AxiUserWidth   (AxiUserWidth),
    .AxiMaxWriteTxns(64),
    .AxiMaxReadTxns (64),
    .FallThrough    (0),
    .full_req_t     (dram_axi_req_t),
    .full_resp_t    (dram_axi_resp_t),
    .lite_req_t     (dram_axi_lite_req_t),
    .lite_resp_t    (dram_axi_lite_resp_t)
    ) i_axi_to_axi_lite (
    .clk_i,
    .rst_ni,
    .test_i    ('0        ),
    .slv_req_i (dram_axi_req ),
    .slv_resp_o(dram_axi_resp),
    .mst_req_o (dram_axi_lite_req ),
    .mst_resp_i(dram_axi_lite_resp )
    );


    //============================//
    // AXI Lite to DRAM interface //
    //============================//

    logic                      dramsys_req;
    logic                      dramsys_rsp;
    logic                      dramsys_we;
    logic [DramAddrWidth-1:0]  dramsys_addr;
    logic [DramDataWidth-1:0]  dramsys_wdata;
    logic [DramDataWidth-1:0]  dramsys_rdata;
    logic                      dramsys_rvalid;
    logic                      dramsys_rready;

    typedef struct packed {
        logic  we;
        addr_t addr;
        data_t wdata;
    } dram_req_t;

    dram_req_t dramsys_payload;
    assign dramsys_we = dramsys_payload.we;
    assign dramsys_addr = dramsys_payload.addr;
    assign dramsys_wdata = dramsys_payload.wdata;

    //AR
    dram_req_t read_req;
    logic read_valid;
    logic read_ready;

    assign read_req = '{
        we: 1'b0,
        addr: (((dram_axi_lite_req.ar.addr)>>$clog2(DramDataWidth/8))<<$clog2(DramDataWidth/8)) - BASE,
        wdata: '0
    };
    assign read_valid = dram_axi_lite_req.ar_valid;
    assign dram_axi_lite_resp.ar_ready = read_ready;

    //R
    assign dram_axi_lite_resp.r.resp = '0;
    assign dram_axi_lite_resp.r.data = dramsys_rdata;
    assign dram_axi_lite_resp.r_valid = dramsys_rvalid;
    assign dramsys_rready = dram_axi_lite_req.r_ready;

    //AW + W
    dram_req_t merge_write_req;
    logic merge_write_valid;
    logic merge_write_ready;

    assign merge_write_req = '{
        we: 1'b1,
        addr: (((dram_axi_lite_req.aw.addr)>>$clog2(DramDataWidth/8))<<$clog2(DramDataWidth/8)) - BASE,
        wdata: dram_axi_lite_req.w.data
    };
    assign merge_write_valid = dram_axi_lite_req.aw_valid & dram_axi_lite_req.w_valid;
    assign dram_axi_lite_resp.aw_ready = merge_write_ready & merge_write_valid;
    assign dram_axi_lite_resp.w_ready = merge_write_ready & merge_write_valid;

    dram_req_t write_req;
    logic write_valid;
    logic write_ready;
    assign write_req = merge_write_req;
    assign write_valid = merge_write_valid;
    assign merge_write_ready =  write_ready;

    assign dram_axi_lite_resp.b.resp = '0;



    //arbit W/R
    stream_arbiter #(.DATA_T(dram_req_t), .N_INP(2)) i_stream_arbiter (
        .clk_i,
        .rst_ni,
        .inp_data_i ({write_req, read_req} ),
        .inp_valid_i({write_valid, read_valid}),
        .inp_ready_o({write_ready, read_ready}),
        .oup_data_o (dramsys_payload ),
        .oup_valid_o(dramsys_req),
        .oup_ready_i(dramsys_rsp)
    );


    sim_dram #(.DataWidth(DramDataWidth), .AddrWidth(DramAddrWidth), .DRAMType(DRAMType), .CustomerDRAM(CustomerDRAM), .BASE(BASE)) i_sim_dram (
    .clk_i,
    .rst_ni,
    .req_valid_i(dramsys_req),
    .req_ready_o(dramsys_rsp),
    .we_i       (dramsys_we       ),
    .addr_i     (dramsys_addr     ),
    .wdata_i    (dramsys_wdata    ),
    .rsp_valid_o(dramsys_rvalid),
    .rsp_ready_i(dramsys_rready),
    .rdata_o    (dramsys_rdata    ),
    .b_valid_o  (dram_axi_lite_resp.b_valid),
    .b_ready_i  (dram_axi_lite_req.b_ready)
  );



endmodule : axi_dram_sim 
