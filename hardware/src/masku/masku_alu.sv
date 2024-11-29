// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:

module masku_alu import ara_pkg::*; import rvv_pkg::*; #(
    parameter integer unsigned VrgatherParallelism = 0,
    parameter integer unsigned VmLogicalParallelism = 0,
    parameter integer unsigned VmsxfParallelism = 0,
  ) (
    input  logic                                       clk_i,
    input  logic                                       rst_ni,
    input  pe_req_t                                    vinsn_issue_i, // Instruction in the issue phase
    input  logic                                       vinsn_issue_valid_i, // Instruction in the issue phase

    input  logic                                       masku_alu_en_i, // Enable the masku_alu
    input  logic                                       masku_alu_clr_i, // Clear the masku_alu state

    input  logic  [NrLanes*ELEN-1:0]                   masku_operand_m_seq_i,   // Mask (deshuffled)
    input  logic  [NrLanes*ELEN-1:0]                   masku_operand_vd_seq_i,  // vd (deshuffled)
    input  logic  [NrLanes*ELEN-1:0]                   masku_operand_alu_seq_i, // ALU/FPU result (deshuffled, uncompressed)

    output elen_t [NrLanes-1:0]                        alu_result_o,
    logic [NrLanes*DataWidth/8-1:0]                    masku_alu_be_o,
    output logic  [NrLanes*DataWidth-1:0]              background_data_init_o, // Background data

    output logic  [$clog2(VcpopParallelism):0]         masku_alu_popcount_o,
    output logic  [$clog2(VfirstParallelism)-1:0]      masku_alu_vfirst_count_o,
    output logic                                       masku_alu_vfirst_empty_o
  );

  import cf_math_pkg::idx_width;

  logic [NrLanes*DataWidth-1:0] background_data_init_seq;

  // VFIRST, VCPOP
  localparam int N_SLICES_CPOP   = NrLanes * DataWidth / VcpopParallelism;
  localparam int N_SLICES_VFIRST = NrLanes * DataWidth / VfirstParallelism;
  logic [NrLanes*DataWidth-1:0] vcpop_operand;
  logic [VcpopParallelism-1:0]  vcpop_slice; // How many slices of the vcpop_operand have been processed
  logic [VfirstParallelism-1:0] vfirst_slice;
  logic                         found_one, found_one_d, found_one_q;
  logic  [$clog2(VLEN):0]       popcount_d, popcount_q;
  logic  [$clog2(VLEN)-1:0]     vfirst_count_d, vfirst_count_q;
  // VIOTA, VID
  logic [ViotaParallelism-1:0] [idx_width(RISCV_MAX_VLEN)-1:0] viota_res; // VLENMAX can be 64Ki elements at most
  logic [NrLanes*DataWidth/8-1:0] be_viota_seq_d, be_viota_seq_q;
  logic [idx_width(RISCV_MAX_VLEN)-1:0] viota_acc, viota_acc_d, viota_acc_q; // VLENMAX can be 64Ki elements at most
  // VMSIF, VMSBF, VMSOF
  logic [VmsxfParallelism-1:0]  vmsbf_buffer;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsif_vm;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsbf_vm;
  logic [NrLanes*DataWidth-1:0] alu_result_vmsof_vm;
  // VRGATHER, VRGATHEREI16, VCOMPRESS
  logic [NrLanes*DataWidth/8-1:0] be_vrgat_seq_d, be_vrgat_seq_q;
  // Generic
  logic [NrLanes*DataWidth-1:0] alu_result_vm, alu_result_vm_m, alu_result_vm_shuf;
  logic [NrLanes*DataWidth-1:0] alu_result_compressed_seq;
  logic  [NrLanes*DataWidth-1:0] masku_operand_alu_seq_m;


  // assign operand slices to be processed by popcount and lzc
  assign vcpop_slice  = vcpop_operand[(in_ready_cnt_q[idx_width(N_SLICES_CPOP)-1:0] * VcpopParallelism) +: VcpopParallelism];
  assign vfirst_slice = vcpop_operand[(in_ready_cnt_q[idx_width(N_SLICES_VFIRST)-1:0] * VfirstParallelism) +: VfirstParallelism];

  assign masku_alu_popcount_o     = popcount_d;
  assign masku_alu_vfirst_count_o = vfirst_count_d;
  assign masku_alu_vfirst_empty_o = vfirst_empty;

  // Population count for vcpop.m instruction
  popcount #(
    .INPUT_WIDTH (VcpopParallelism)
  ) i_popcount (
    .data_i    (vcpop_slice),
    .popcount_o(popcount   )
  );

  // Trailing zero counter
  lzc #(
    .WIDTH(VfirstParallelism),
    .MODE (0)
  ) i_clz (
    .in_i    (vfirst_slice),
    .cnt_o   (vfirst_count),
    .empty_o (vfirst_empty)
  );

  always_comb begin
    // Tail-agnostic bus
    alu_result_o        = '1;
    alu_result_vm       = '1;
    alu_result_vm_m     = '1;
    alu_result_vm_shuf  = '1;
    alu_result_vmsif_vm = '1;
    alu_result_vmsbf_vm = '1;
    alu_result_vmsof_vm = '1;
    alu_result_vm       = '1;
    alu_result_compressed_seq = '1;

    vcpop_operand = '0;

    vrgat_m_seq_bit = 1'b0;

    // The result mask should be created here since the output is a non-mask vector
    be_viota_seq_d = be_viota_seq_q;

    // Create a bit-masked ALU sequential vector
    masku_operand_alu_seq_m = masku_operand_alu_seq_i
                            & (masku_operand_m_seq_i | {NrLanes*DataWidth{vinsn_issue_i.vm}});


    popcount_d        = popcount_q;
    vfirst_count_d    = vfirst_count_q;

    // VMSBF, VMSIF, VMSOF default assignments
    found_one_d         = found_one_q;
    vmsbf_buffer        = '0;
    // VIOTA default assignments
    viota_acc   = viota_acc_q;
    viota_acc_d = viota_acc_q;
    for (int i = 0; i < ViotaParallelism; i++) viota_res[i] = '0;

    be_vrgat_seq_d = be_vrgat_seq_q;

    // Evaluate the instruction
    unique case (vinsn_issue_i.op) inside
      // Mask logical: pass through the result already computed in the ALU
      // This operation is never masked
      // This operation always writes to multiple of VRF words, and it does not need vd
      // This operation can overwrite the destination register without constraints on tail elements
      [VMANDNOT:VMXNOR]: alu_result_vm_m = masku_operand_alu_seq_i;
      // Compress the alu_result from ALU/FPU format to MASKU format
      [VMFEQ:VMSGT],
      [VMADC:VMSBC]: begin
        unique case (vinsn_issue_i.eew_vs2)
          EW8: begin
            for (int i = 0; i < NrLanes * DataWidth / 8; i++)
              alu_result_compressed_seq[masku_alu_compress_cnt_q[idx_width(NrLanes * DataWidth/8)-1:0] * NrLanes * DataWidth / 8 + i] =
                  masku_operand_alu_seq_i[i * DataWidth / 8];
          end
          EW16: begin
            for (int i = 0; i < NrLanes * DataWidth / 16; i++)
              alu_result_compressed_seq[masku_alu_compress_cnt_q[idx_width(NrLanes * DataWidth/16)-1:0] * NrLanes * DataWidth / 16 + i] =
                  masku_operand_alu_seq_i[i * DataWidth / 4];
          end
          EW32: begin
            for (int i = 0; i < NrLanes * DataWidth / 32; i++)
              alu_result_compressed_seq[masku_alu_compress_cnt_q[idx_width(NrLanes * DataWidth/32)-1:0] * NrLanes * DataWidth / 32 + i] =
                  masku_operand_alu_seq_i[i * DataWidth / 2];
          end
          default: begin // EW64
            for (int i = 0; i < NrLanes * DataWidth / 64; i++)
              alu_result_compressed_seq[masku_alu_compress_cnt_q[idx_width(NrLanes * DataWidth/64)-1:0] * NrLanes * DataWidth / 64 + i] =
                  masku_operand_alu_seq_i[i * DataWidth / 1];
          end
        endcase

        // Comparisons: mask out the masked out bits of this pre-computed slice
        // Add/sub-with-carry/borrow: the masks are all 1 since these operations are NOT masked
        alu_result_vm_m = vinsn_issue_i.op inside {[VMFEQ:VMSGT]}
                        ? alu_result_compressed_seq | ~(masku_operand_m_seq_i | {NrLanes*DataWidth{vinsn_issue_i.vm}})
                        : alu_result_compressed_seq;
      end
      // VMSBF, VMSOF, VMSIF: compute a slice of the output and mask out the masked out bits
      [VMSBF:VMSIF] : begin
        vmsbf_buffer[0] = ~(masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism] | found_one_q);
        for (int i = 1; i < VmsxfParallelism; i++) begin
          vmsbf_buffer[i] = ~((masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism + i]) | ~vmsbf_buffer[i-1]);
        end
        // Have we found a 1 in the current slice?
        found_one = |(masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism]) | found_one_q;

        alu_result_vmsbf_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = vmsbf_buffer;
        alu_result_vmsif_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = {vmsbf_buffer[VmsxfParallelism-2:0], ~found_one_q};
        alu_result_vmsof_vm[out_valid_cnt_q[idx_width(NrLanes*DataWidth/VmsxfParallelism)-1:0] * VmsxfParallelism +: VmsxfParallelism] = ~vmsbf_buffer & {vmsbf_buffer[VmsxfParallelism-2:0], ~found_one_q};

        unique case (vinsn_issue_i.op)
          VMSBF: alu_result_vm = alu_result_vmsbf_vm;
          VMSIF: alu_result_vm = alu_result_vmsif_vm;
          // VMSOF
          default: alu_result_vm = alu_result_vmsof_vm;
        endcase

        // Mask the result
        alu_result_vm_m = (!vinsn_issue_i.vm) || (vinsn_issue_i.op inside {[VMADC:VMSBC]}) ? alu_result_vm | ~masku_operand_m_seq_i : alu_result_vm;
      end
      // VIOTA, VID: compute a slice of the output and mask out the masked elements
      // VID re-uses the VIOTA datapath
      VIOTA, VID: begin
        // Mask the input vector
        // VID uses the same datapath of VIOTA, but with implicit input vector at '1
        masku_operand_alu_seq_m = (vinsn_issue_i.op == VID)
                                ? '1 // VID mask does NOT modify the count
                                : masku_operand_alu_seq_i
                                  & (masku_operand_m_seq_i | {NrLanes*DataWidth{vinsn_issue_i.vm}}); // VIOTA mask DOES modify the count

        // Compute output results on `ViotaParallelism 16-bit adders
        viota_res[0] = viota_acc_q;
        for (int i = 0; i < ViotaParallelism - 1; i++) begin
          viota_res[i+1] = viota_res[i] + masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i];
        end
        viota_acc = viota_res[ViotaParallelism-1] + masku_operand_alu_seq_m[in_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + ViotaParallelism - 1];

        // This datapath should be relativeley simple:
        // `ViotaParallelism bytes connected, in line, to output byte chunks
        // Multiple limited-width counters should help the synthesizer reduce wiring
        unique case (vinsn_issue_i.vtype.vsew)
          EW8: for (int i = 0; i < ViotaParallelism; i++) begin
            alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8/ViotaParallelism)-1:0]  * ViotaParallelism * 8  + i*8  +: 8]  = viota_res[i][7:0];
          end
          EW16: for (int i = 0; i < ViotaParallelism; i++) begin
            alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16/ViotaParallelism)-1:0] * ViotaParallelism * 16 + i*16 +: 16] = viota_res[i];
          end
          EW32: for (int i = 0; i < ViotaParallelism; i++) begin
            alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32/ViotaParallelism)-1:0] * ViotaParallelism * 32 + i*32 +: 32] = {{32{1'b0}}, viota_res[i]};
          end
          default: for (int i = 0; i < ViotaParallelism; i++) begin // EW64
            alu_result_vm_m[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64/ViotaParallelism)-1:0] * ViotaParallelism * 64 + i*64 +: 64] = {{48{1'b0}}, viota_res[i]};
          end
        endcase

        // BE signal for VIOTA,VID
        unique case (vinsn_issue_i.vtype.vsew)
          EW8: for (int i = 0; i < ViotaParallelism; i++) begin
            be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8/ViotaParallelism)-1:0] * ViotaParallelism * 1 + 1*i +: 1] =
              {1{vinsn_issue_i.vm}} | {1{masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
          end
          EW16: for (int i = 0; i < ViotaParallelism; i++) begin
            be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16/ViotaParallelism)-1:0] * ViotaParallelism * 2 + 2*i +: 2] =
              {2{vinsn_issue_i.vm}} | {2{masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
          end
          EW32: for (int i = 0; i < ViotaParallelism; i++) begin
            be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32/ViotaParallelism)-1:0] * ViotaParallelism * 4 + 4*i +: 4] =
              {4{vinsn_issue_i.vm}} | {4{masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
          end
          default: for (int i = 0; i < ViotaParallelism; i++) begin // EW64
            be_viota_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64/ViotaParallelism)-1:0] * ViotaParallelism * 8 + 8*i +: 8] =
              {8{vinsn_issue_i.vm}} | {8{masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth/ViotaParallelism)-1:0] * ViotaParallelism + i]}};
          end
        endcase
      end
      // VRGATHER, VRGATHEREI16, VCOMPRESS get elements from the vd operand queue (not to complicate the ALU control)
      // Then, they just shuffle the operand in the correct place
      // This operation writes vsew-bit elements with vtype.vsew encoding
      // The vd source can have a different encoding (it gets deshuffled in the masku_operand stage)
      [VRGATHER:VCOMPRESS]: begin
        // Buffer for the current element
        logic [NrLanes*DataWidth-1:0] vrgat_res;
        // Buffer for the current element
        logic [DataWidth-1:0] vrgat_buf;

        // Extract the correct elements
        vrgat_res = '1; // Default assignment
        vrgat_buf = masku_operand_vd_seq_i[vrgat_req_idx_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64]; // Default assignment
        unique case (vinsn_issue_i.vtype.vsew)
          EW8: begin
            vrgat_buf[0 +: 8] = masku_operand_vd_seq_i[vrgat_req_idx_q[idx_width(NrLanes*ELENB/1)-1:0] * 8 +: 8];
            vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/1)-1:0] * 8 +: 8] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 8];
          end
          EW16: begin
            vrgat_buf[0 +: 16] = masku_operand_vd_seq_i[vrgat_req_idx_q[idx_width(NrLanes*ELENB/2)-1:0] * 16 +: 16];
            vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/2)-1:0] * 16 +: 16] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 16];
          end
          EW32: begin
            vrgat_buf[0 +: 32] = masku_operand_vd_seq_i[vrgat_req_idx_q[idx_width(NrLanes*ELENB/4)-1:0] * 32 +: 32];
            vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/4)-1:0] * 32 +: 32] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 32];
          end
          default: begin // EW64
            vrgat_buf[0 +: 64] = masku_operand_vd_seq_i[vrgat_req_idx_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64];
            vrgat_res[out_valid_cnt_q[idx_width(NrLanes*ELENB/8)-1:0] * 64 +: 64] = vrgat_idx_oor_q ? '0 : vrgat_buf[0 +: 64];
          end
        endcase

        // BE signal for VRGATHER
		  unique case (vinsn_issue_i.vtype.vsew)
          EW8: begin
            vrgat_m_seq_bit = masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
            be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/8)-1:0] * 1 +: 1] =
              {1{vinsn_issue_i.vm}} | {1{vrgat_m_seq_bit}};
          end
          EW16: begin
            vrgat_m_seq_bit = masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
            be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/16)-1:0] * 2 +: 2] =
              {2{vinsn_issue_i.vm}} | {2{vrgat_m_seq_bit}};
          end
          EW32: begin
            vrgat_m_seq_bit = masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
            be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/32)-1:0] * 4 +: 4] =
              {4{vinsn_issue_i.vm}} | {4{vrgat_m_seq_bit}};
          end
          default: begin // EW64
            vrgat_m_seq_bit = masku_operand_m_seq_i[in_m_ready_cnt_q[idx_width(NrLanes*DataWidth)-1:0]];
            be_vrgat_seq_d[out_valid_cnt_q[idx_width(NrLanes*DataWidth/64)-1:0] * 8 +: 8] =
              {8{vinsn_issue_i.vm}} | {8{vrgat_m_seq_bit}};
          end
        endcase

        alu_result_vm_m = vrgat_res;
      end
      // VCPOP, VFIRST: mask the current slice and feed the popc or lzc unit
      [VCPOP:VFIRST] : begin
        vcpop_operand = (!vinsn_issue_i.vm) ? masku_operand_alu_seq_i & masku_operand_m_seq_i : masku_operand_alu_seq_i;
      end
      default:;
    endcase

    // Shuffle the sequential result with vtype.vsew encoding
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte              = shuffle_index(b, NrLanes, vinsn_issue_i.vtype.vsew);
      alu_result_vm_shuf[8*shuffle_byte +: 8] = alu_result_vm_m[8*b +: 8];
    end
    // Simplify layout handling
    alu_result_o = alu_result_vm_shuf;

    // Shuffle the VIOTA, VID, VRGATHER, VCOMPRESS byte enable signal
    masku_alu_be_o = '0;
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte  = shuffle_index(b, NrLanes, vinsn_issue_i.vtype.vsew);
      masku_alu_be_o[shuffle_byte] = vinsn_issue_i.op inside {VRGATHER,VRGATHEREI16} ? be_vrgat_seq_d[b] : be_viota_seq_d[b];
    end

    // Prepare the background data with vtype.vsew encoding
    result_queue_mask_seq = vinsn_issue_i.op inside {[VIOTA:VID], [VRGATHER:VCOMPRESS]} ? '0 : masku_operand_m_seq_i | {NrLanes*DataWidth{vinsn_issue_i.vm}} | {NrLanes*DataWidth{vinsn_issue_i.op inside {[VMADC:VMSBC]}}};
    background_data_init_seq = masku_operand_vd_seq_i | result_queue_mask_seq;
    background_data_init_o = '0;
    for (int b = 0; b < (NrLanes*StrbWidth); b++) begin
      automatic int shuffle_byte                     = shuffle_index(b, NrLanes, vinsn_issue_i.vtype.vsew);
      background_data_init_o[8*shuffle_byte +: 8] = background_data_init_seq[8*b +: 8];
    end

    if (masku_alu_en_i) begin
      found_one_d    = found_one;
      viota_acc_d    = viota_acc;
      popcount_d     = popcount_q + popcount;
      vfirst_count_d = vfirst_count_q + vfirst_count;
    end

    if (masku_alu_clr_i) begin
      be_viota_seq_d = '1; // Default: write
      be_vrgat_seq_d = '1; // Default: write
      found_one_d    = '0;
      viota_acc_d    = '0;
      popcount_d     = '0;
      vfirst_count_d = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      be_viota_seq_q <= '1; // Default: write
      be_vrgat_seq_q <= '1; // Default: write
      viota_acc_q    <= '0;
      found_one_q    <= '0;
      popcount_q     <= '0;
      vfirst_count_q <= '0;
    end else begin
      be_viota_seq_q <= be_viota_seq_d;
      be_vrgat_seq_q <= be_vrgat_seq_d;
      viota_acc_q    <= viota_acc_d;
      found_one_q    <= found_one_d;
      popcount_q     <= popcount_d;
      vfirst_count_q <= vfirst_count_d;
    end
  end

  // Check if parameters are within range
  if (ViotaParallelism > NrLanes || ViotaParallelism % 2 != 0) begin
    $fatal(1, "Parameter ViotaParallelism cannot be higher than NrLanes and should be a power of 2.");
  end
  // Check if parameters are within range
  if (((VcpopParallelism & (VcpopParallelism - 1)) != 0) || (VcpopParallelism < 8)) begin
    $fatal(1, "Parameter VcpopParallelism must be power of 2.");
  end else if (((VfirstParallelism & (VfirstParallelism - 1)) != 0) || (VfirstParallelism < 8)) begin
    $fatal(1, "Parameter VfirstParallelism must be power of 2.");
  end

endmodule
