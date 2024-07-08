// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Description:
// This is Ara's vector load/store unit. It is used exclusively for vector
// loads and vector stores. There are no guarantees regarding concurrency
// and coherence with Ariane's own load/store unit.

module vlsu import ara_pkg::*; import rvv_pkg::*; #(
    parameter  int  unsigned NrLanes   = 0,
    parameter  int  unsigned VLEN      = 0,
    parameter  type          vaddr_t   = logic,  // Type used to address vector register file elements
    parameter  type          pe_req_t  = logic,
    parameter  type          pe_resp_t = logic,
    // AXI Interface parameters
    parameter  int  unsigned AxiDataWidth = 0,
    parameter  int  unsigned AxiAddrWidth = 0,
    parameter  type          axi_ar_t     = logic,
    parameter  type          axi_r_t      = logic,
    parameter  type          axi_aw_t     = logic,
    parameter  type          axi_w_t      = logic,
    parameter  type          axi_b_t      = logic,
    parameter  type          axi_req_t    = logic,
    parameter  type          axi_resp_t   = logic,
    // Dependant parameters. DO NOT CHANGE!
    localparam int  unsigned DataWidth    = $bits(elen_t),
    localparam type          strb_t       = logic [DataWidth/8-1:0],
    localparam type          vlen_t       = logic[$clog2(VLEN+1)-1:0]
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    // AXI Memory Interface
    output axi_req_t                axi_req_o,
    input  axi_resp_t               axi_resp_i,
    // Interface with the dispatcher
    input  logic                    core_st_pending_i,
    output logic                    load_complete_o,
    output logic                    store_complete_o,
    output logic                    store_pending_o,
    // Interface with the sequencer
    input  pe_req_t                 pe_req_i,
    input  logic                    pe_req_valid_i,
    input  logic      [NrVInsn-1:0] pe_vinsn_running_i,
    output logic      [1:0]         pe_req_ready_o,         // Load (0) and Store (1) units
    output pe_resp_t  [1:0]         pe_resp_o,              // Load (0) and Store (1) units
    output logic                    addrgen_ack_o,
    output ariane_pkg::exception_t  addrgen_exception_o,
    output vlen_t                   addrgen_exception_vstart_o,
    // Interface with the lanes
    // Store unit operands
    input  elen_t     [NrLanes-1:0] stu_operand_i,
    input  logic      [NrLanes-1:0] stu_operand_valid_i,
    output logic      [NrLanes-1:0] stu_operand_ready_o,
    output logic                    stu_exception_flush_o,
    // Address generation operands
    input  elen_t     [NrLanes-1:0] addrgen_operand_i,
    input  target_fu_e[NrLanes-1:0] addrgen_operand_target_fu_i,
    input  logic      [NrLanes-1:0] addrgen_operand_valid_i,
    output logic                    addrgen_operand_ready_o,
    // Interface with the Mask unit
    input  strb_t     [NrLanes-1:0] mask_i,
    input  logic      [NrLanes-1:0] mask_valid_i,
    output logic                    vldu_mask_ready_o,
    output logic                    vstu_mask_ready_o,

    // CSR input
    input  logic                    en_ld_st_translation_i,

    // Interface with CVA6's sv39 MMU
    // This is everything the MMU can provide, it might be overcomplete for Ara and some signals be useless
    output  logic                          mmu_misaligned_ex_o,
    output  logic                          mmu_req_o,        // request address translation
    output  logic [riscv::VLEN-1:0]        mmu_vaddr_o,      // virtual address out
    output  logic                          mmu_is_store_o,   // the translation is requested by a store
    // if we need to walk the page table we can't grant in the same cycle
    // Cycle 0
    input logic                            mmu_dtlb_hit_i,   // sent in the same cycle as the request if translation hits in the DTLB
    input logic [riscv::PPNW-1:0]          mmu_dtlb_ppn_i,   // ppn (send same cycle as hit)
    // Cycle 1
    input logic                            mmu_valid_i,      // translation is valid
    input logic [riscv::PLEN-1:0]          mmu_paddr_i,      // translated address
    input ariane_pkg::exception_t          mmu_exception_i,  // address translation threw an exception

    // Results
    output logic      [NrLanes-1:0] ldu_result_req_o,
    output vid_t      [NrLanes-1:0] ldu_result_id_o,
    output vaddr_t    [NrLanes-1:0] ldu_result_addr_o,
    output elen_t     [NrLanes-1:0] ldu_result_wdata_o,
    output strb_t     [NrLanes-1:0] ldu_result_be_o,
    input  logic      [NrLanes-1:0] ldu_result_gnt_i,
    input  logic      [NrLanes-1:0] ldu_result_final_gnt_i
  );

  logic load_complete, store_complete;
  logic addrgen_illegal_load, addrgen_illegal_store;
  assign load_complete_o  = load_complete;
  assign store_complete_o = store_complete;

  ///////////////////
  //  Definitions  //
  ///////////////////

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;

  ///////////////
  //  AXI Cut  //
  ///////////////

  // Internal AXI request signals
  axi_req_t  axi_req;
  axi_resp_t axi_resp;

  axi_cut #(
    .ar_chan_t (axi_ar_t  ),
    .r_chan_t  (axi_r_t   ),
    .aw_chan_t (axi_aw_t  ),
    .w_chan_t  (axi_w_t   ),
    .b_chan_t  (axi_b_t   ),
    .axi_req_t (axi_req_t ),
    .axi_resp_t(axi_resp_t)
  ) i_axi_cut (
    .clk_i     (clk_i     ),
    .rst_ni    (rst_ni    ),
    .mst_req_o (axi_req_o ),
    .mst_resp_i(axi_resp_i),
    .slv_req_i (axi_req   ),
    .slv_resp_o(axi_resp  )
  );

  //////////////////////////
  //  Address Generation  //
  //////////////////////////

  // Interface with the load/store units
  addrgen_axi_req_t axi_addrgen_req;
  logic             axi_addrgen_req_valid;
  logic             ldu_axi_addrgen_req_ready;
  logic             stu_axi_addrgen_req_ready;

  addrgen #(
    .NrLanes     (NrLanes     ),
    .VLEN        (VLEN        ),
    .AxiDataWidth(AxiDataWidth),
    .AxiAddrWidth(AxiAddrWidth),
    .axi_ar_t    (axi_ar_t    ),
    .axi_aw_t    (axi_aw_t    ),
    .pe_req_t    (pe_req_t    ),
    .pe_resp_t   (pe_resp_t   )
  ) i_addrgen (
    .clk_i                      (clk_i                      ),
    .rst_ni                     (rst_ni                     ),
    // AXI Memory Interface
    .axi_aw_o                   (axi_req.aw                 ),
    .axi_aw_valid_o             (axi_req.aw_valid           ),
    .axi_aw_ready_i             (axi_resp.aw_ready          ),
    .axi_ar_o                   (axi_req.ar                 ),
    .axi_ar_valid_o             (axi_req.ar_valid           ),
    .axi_ar_ready_i             (axi_resp.ar_ready          ),
    // Interface with dispatcher
    .core_st_pending_i          (core_st_pending_i          ),
    // Interface with the sequencer
    .pe_req_i                   (pe_req_i                   ),
    .pe_req_valid_i             (pe_req_valid_i             ),
    .pe_vinsn_running_i         (pe_vinsn_running_i         ),
    .addrgen_ack_o              (addrgen_ack_o              ),
    .addrgen_exception_o        ( addrgen_exception_o       ),
    .addrgen_exception_vstart_o ( addrgen_exception_vstart_o),
    .addrgen_illegal_load_o     (addrgen_illegal_load       ),
    .addrgen_illegal_store_o    (addrgen_illegal_store      ),
    // Interface with the lanes
    .addrgen_operand_i          (addrgen_operand_i          ),
    .addrgen_operand_target_fu_i(addrgen_operand_target_fu_i),
    .addrgen_operand_valid_i    (addrgen_operand_valid_i    ),
    .addrgen_operand_ready_o    (addrgen_operand_ready_o    ),
    // Interface with the load/store units
    .axi_addrgen_req_o          (axi_addrgen_req            ),
    .axi_addrgen_req_valid_o    (axi_addrgen_req_valid      ),
    .ldu_axi_addrgen_req_ready_i(ldu_axi_addrgen_req_ready  ),
    .stu_axi_addrgen_req_ready_i(stu_axi_addrgen_req_ready  ),

    // CSR input
    .en_ld_st_translation_i,
    .mmu_misaligned_ex_o,
    .mmu_req_o,
    .mmu_vaddr_o,
    .mmu_is_store_o,
    .mmu_dtlb_hit_i,
    .mmu_dtlb_ppn_i,
    .mmu_valid_i,
    .mmu_paddr_i,
    .mmu_exception_i
  );

  ////////////////////////
  //  Vector Load Unit  //
  ////////////////////////

  vldu #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .axi_r_t     (axi_r_t     ),
    .NrLanes     (NrLanes     ),
    .VLEN        (VLEN        ),
    .vaddr_t     (vaddr_t     ),
    .pe_req_t    (pe_req_t    ),
    .pe_resp_t   (pe_resp_t   )
  ) i_vldu (
    .clk_i                  (clk_i                     ),
    .rst_ni                 (rst_ni                    ),
    // AXI Memory Interface
    .axi_r_i                (axi_resp.r                ),
    .axi_r_valid_i          (axi_resp.r_valid          ),
    .axi_r_ready_o          (axi_req.r_ready           ),
    // Interface with the dispatcher
    .load_complete_o        (load_complete             ),
    // Interface with the main sequencer
    .pe_req_i               (pe_req_i                  ),
    .pe_req_valid_i         (pe_req_valid_i            ),
    .pe_vinsn_running_i     (pe_vinsn_running_i        ),
    .pe_req_ready_o         (pe_req_ready_o[OffsetLoad]),
    .pe_resp_o              (pe_resp_o[OffsetLoad]     ),
    // Interface with the address generator
    .axi_addrgen_req_i      (axi_addrgen_req           ),
    .axi_addrgen_req_valid_i(axi_addrgen_req_valid     ),
    .axi_addrgen_req_ready_o(ldu_axi_addrgen_req_ready ),
    .addrgen_illegal_load_i (addrgen_illegal_load      ),
    // Interface with the Mask unit
    .mask_i                 (mask_i                    ),
    .mask_valid_i           (mask_valid_i              ),
    .mask_ready_o           (vldu_mask_ready_o         ),
    // Interface with the lanes
    .ldu_result_req_o       (ldu_result_req_o          ),
    .ldu_result_addr_o      (ldu_result_addr_o         ),
    .ldu_result_id_o        (ldu_result_id_o           ),
    .ldu_result_wdata_o     (ldu_result_wdata_o        ),
    .ldu_result_be_o        (ldu_result_be_o           ),
    .ldu_result_gnt_i       (ldu_result_gnt_i          ),
    .ldu_result_final_gnt_i (ldu_result_final_gnt_i    )
  );

  /////////////////////////
  //  Vector Store Unit  //
  /////////////////////////

  vstu #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .axi_w_t     (axi_w_t     ),
    .axi_b_t     (axi_b_t     ),
    .NrLanes     (NrLanes     ),
    .VLEN        (VLEN        ),
    .vaddr_t     (vaddr_t     ),
    .pe_req_t    (pe_req_t    ),
    .pe_resp_t   (pe_resp_t   )
  ) i_vstu (
    .clk_i                  (clk_i                      ),
    .rst_ni                 (rst_ni                     ),
    // AXI Memory Interface
    .axi_w_o                (axi_req.w                  ),
    .axi_w_valid_o          (axi_req.w_valid            ),
    .axi_w_ready_i          (axi_resp.w_ready           ),
    .axi_b_i                (axi_resp.b                 ),
    .axi_b_valid_i          (axi_resp.b_valid           ),
    .axi_b_ready_o          (axi_req.b_ready            ),
    // Interface with the dispatcher
    .store_pending_o        (store_pending_o            ),
    .store_complete_o       (store_complete             ),
    // Interface with the main sequencer
    .pe_req_i               (pe_req_i                   ),
    .pe_req_valid_i         (pe_req_valid_i             ),
    .pe_vinsn_running_i     (pe_vinsn_running_i         ),
    .pe_req_ready_o         (pe_req_ready_o[OffsetStore]),
    .pe_resp_o              (pe_resp_o[OffsetStore]     ),
    // Interface with the address generator
    .axi_addrgen_req_i      (axi_addrgen_req            ),
    .axi_addrgen_req_valid_i(axi_addrgen_req_valid      ),
    .axi_addrgen_req_ready_o(stu_axi_addrgen_req_ready  ),
    .addrgen_illegal_store_i(addrgen_illegal_store      ),
    // Interface with the Mask unit
    .mask_i                 (mask_i                     ),
    .mask_valid_i           (mask_valid_i               ),
    .mask_ready_o           (vstu_mask_ready_o          ),
    // Interface with the lanes
    .stu_operand_i          (stu_operand_i              ),
    .stu_operand_valid_i    (stu_operand_valid_i        ),
    .stu_operand_ready_o    (stu_operand_ready_o        ),
    .stu_exception_flush_o  (stu_exception_flush_o      )
  );

  //////////////////
  //  Assertions  //
  //////////////////

  if (AxiDataWidth == 0)
    $error("[vlsu] The data width of the AXI bus cannot be zero.");

  if (AxiAddrWidth == 0)
    $error("[vlsu] The address width of the AXI bus cannot be zero.");

  if (NrLanes == 0)
    $error("[vlsu] Ara needs to have at least one lane.");

endmodule : vlsu
