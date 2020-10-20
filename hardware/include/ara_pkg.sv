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
// File          : ara_pkg.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 14.03.2018
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara main package.

package ara_pkg;

  import ariane_pkg::*      ;
  import ara_frontend_pkg::*;

  /****************
   *  CONTROLLER  *
   ****************/

  // Parallel vector loops
  localparam VLOOP_ID = 8;
  typedef logic [$clog2(VLOOP_ID)-1:0] vloop_id_t;

  typedef struct packed {
    logic [63:0] word ;
    logic valid       ;
  } word_t;

  /***********************
   *  ADDRESS GENERATOR  *
   ***********************/

  typedef struct packed {
    logic [63:0] addr        ;
    vsize_full_t burst_length;
    logic is_load            ;
  } addr_t;

  /*********************
   *  OPERAND REQUEST  *
   *********************/

  // We have ten arbiter channels. They are organized as follows.

  // | -- 0 -- | -- 1 -- | -- 2 -- | -- 3 -- | -- 4 -- | -- 5 -- | -- 6 -- | -- 7 -- | -- 8 -- | -- 9 -- |
  // | MFPU MFPU MFPU MFPU MFPU MFPU MFPU    | ALU ALU ALU ALU ALU ALU ALU | ST ST ST ST ST ST | ADDRGEN |
  //                                         | SLD SLD SLD SLD   |         | LD LD   |

  function automatic int get_initial_channel(vfu_t fu);
    unique case (fu)
      VFU_MFPU : return 0;
      VFU_ALU  : return 4;
      VFU_SLD  : return 4;
      VFU_LD   : return 7;
      VFU_ST   : return 7;
    endcase // unique case (fu)
  endfunction : get_initial_channel

  localparam NR_OPQUEUE = 10;
  typedef enum logic [$clog2(NR_OPQUEUE)-1:0] {
    MFPU_MASK   ,
    MFPU_A      ,
    MFPU_B      ,
    MFPU_C      ,
    ALU_SLD_MASK,
    ALU_SLD_A   ,
    ALU_B       ,
    LD_ST_MASK  ,
    ST_A        ,
    ADDRGEN_A
  } op_dest_t;

  typedef struct packed {
    vfu_op op                ;
    vfu_t fu                 ;
    riscv::vrepr_t repr      ;
    logic [ 1:0] mask        ;
    vdesc_t vs               ;
    vsize_t length           ;
    logic [VLOOP_ID-1:0] hzd ;
  } opreq_cmd_t;

  typedef struct packed {
    logic req         ;
    logic prio        ;
    logic we          ;
    vloop_id_t id     ;
    vaddr_t addr      ;
    op_dest_t dest    ;
    logic [63:0] wdata;
    logic [ 7:0] be   ;
  } arb_request_t;

  typedef struct packed {
    logic req;
    logic we ;

    vaddr_t addr  ;
    op_dest_t dest;

    logic [63:0] wdata;
    logic [7:0] be    ;
  } vrf_request_t;

  /********************
   *  OPERAND QUEUES  *
   ********************/

  typedef enum logic [1:0] {
    MASK_CONV,
    INT_CONV ,
    FLOAT_CONV
  } conv_type_t;

  typedef struct packed {
    // Select which fu is using the queues
    logic slave_select   ;
    // How many times this word can be reused
    vsize_t cnt          ;
    conv_type_t conv_type;
    riscv::vtype_t srct  ;
    riscv::vtype_t dstt  ;
    logic [1:0] mask     ;
  } opqueue_cmd_t;

  typedef struct packed {
    logic sign          ;
    logic [4:0] exponent;
    logic [9:0] mantissa;
  } fp16_t;

  typedef struct packed {
    logic sign           ;
    logic [ 7:0] exponent;
    logic [22:0] mantissa;
  } fp32_t;

  typedef struct packed {
    logic sign           ;
    logic [10:0] exponent;
    logic [51:0] mantissa;
  } fp64_t;

  /*********************
   *  EXECUTION UNITS  *
   *********************/

  typedef struct packed {
    logic valid      ;
    // Operation control
    vloop_id_t id    ;
    vfu_t fu         ;
    vfu_op op        ;
    riscv::vtype_t vd;
    logic [ 4:0] vid ;
    vaddr_t addr     ;
    vsize_t length   ;
    voffset_t offset ;
    logic reduction  ;
    logic [ 1:0] mask;
    logic use_imm    ;
    logic [63:0] rs1 ;
    logic [63:0] rs2 ;
    logic [63:0] imm ;
  } operation_t;

  // Multiplier's latency
  localparam int unsigned LAT_MULTIPLIER = 2;

  // Parallel instructions per functional unit
  localparam int unsigned OPQUEUE_DEPTH = 4;
  typedef logic [$clog2(OPQUEUE_DEPTH):0] opqueue_cnt_t;

  // Returns the physical address of the next element of a certain vector.
  function automatic vaddr_t increment_addr(vaddr_t addr, logic [4:0] id);
    vaddr_t retval = addr;

    retval.bank += 1; // Increment bank counter
    if (retval.bank == id[VRF_BANK_TAG-1:0]) // Wrap around
      retval.index += 1;

    return retval;
  endfunction : increment_addr

  /***********
   *  LANES  *
   ***********/

  typedef struct packed {
    logic ready                   ;
    logic [VLOOP_ID-1:0] loop_done;
  } vfu_status_t;

  typedef struct packed {
    vloop_id_t id ;
    logic valid   ;
  } reg_access_t;

  typedef struct packed {
    logic valid                      ;
    vloop_id_t id                    ;
    vfu_t fu                         ;
    vfu_op op                        ;
    vdesc_t vd                       ;
    vdesc_t [ 3:0] vs                ;
    logic [ 1:0] mask                ;
    voffset_t offset                 ;
    logic reduction                  ;
    logic use_imm                    ;
    logic [ 63:0] rs1                ;
    logic [ 63:0] rs2                ;
    logic [ 63:0] imm                ;
    logic [VLOOP_ID-1:0] loop_running;
    logic [ 3:0][VLOOP_ID-1:0] hzd   ;
  } lane_req_t;

  typedef struct packed {
    logic ready                   ;
    logic [VLOOP_ID-1:0] loop_done;
    word_t scalar_result          ;
  } lane_resp_t;

  /*************************
   *  SHUFFLER/DESHUFFLER  *
   *************************/

  typedef union packed {
    logic [ 1*NR_LANES-1:0][63:0] w64;
    logic [ 2*NR_LANES-1:0][31:0] w32;
    logic [ 4*NR_LANES-1:0][15:0] w16;
    logic [ 8*NR_LANES-1:0][ 7:0] w8 ;
    logic [64*NR_LANES-1:0] w        ;
  } union_word_t;

  typedef struct packed {
    union_word_t word;
    logic valid      ;
  } word_full_t;

  // Shuffles sequential data into the lanes
  function automatic word_t [NR_LANES-1:0] shuffle(union_word_t word_i, riscv::vwidth_t width_i);
    word_t [NR_LANES-1:0] retval = '0;

    // Generate shuffling indexes
    automatic int unsigned i64 [1*NR_LANES-1:0];
    automatic int unsigned i32 [2*NR_LANES-1:0];
    automatic int unsigned i16 [4*NR_LANES-1:0];
    automatic int unsigned i8 [8*NR_LANES-1:0];

    automatic union_word_t w = '0;

    for (int unsigned l = 0; l < 1*NR_LANES; l++)
      i64[l] = (l >> 0);
    for (int unsigned l = 0; l < 2*NR_LANES; l++)
      i32[l] = (l >> 1) + l[0] * 1 * NR_LANES;
    for (int unsigned l = 0; l < 4*NR_LANES; l++)
      i16[l] = (l >> 2) + l[0] * 2 * NR_LANES + l[1] * 1 * NR_LANES;
    for (int unsigned l = 0; l < 8*NR_LANES; l++)
      i8[l] = (l >> 3) + l[0] * 4 * NR_LANES + l[1] * 2 * NR_LANES + l[2] * NR_LANES;

    // Shuffle
    case (width_i)
      riscv::WD_V64B: for (int l = 0; l < 1*NR_LANES; l++) w.w64[l] = word_i.w64[i64[l]];
      riscv::WD_V32B: for (int l = 0; l < 2*NR_LANES; l++) w.w32[l] = word_i.w32[i32[l]];
      riscv::WD_V16B: for (int l = 0; l < 4*NR_LANES; l++) w.w16[l] = word_i.w16[i16[l]];
      riscv::WD_V8B : for (int l = 0; l < 8*NR_LANES; l++) w.w8[l] = word_i.w8[i8[l]];
    endcase // case (width_i)

    for (int l = 0; l < NR_LANES; l++)
      retval[l] = {w.w64[l], 1'b1};

    return retval;
  endfunction : shuffle

  // Deshuffles lanes data into sequential data
  function automatic word_full_t deshuffle(word_t [NR_LANES-1:0] word_i, riscv::vwidth_t width_i);
    word_full_t retval = '0;

    // Generate deshuffling indexes
    automatic int unsigned i64 [1*NR_LANES-1:0];
    automatic int unsigned i32 [2*NR_LANES-1:0];
    automatic int unsigned i16 [4*NR_LANES-1:0];
    automatic int unsigned i8 [8*NR_LANES-1:0];

    automatic union_word_t                w_input;
    automatic logic        [NR_LANES-1:0] w_input_valid;

    for (int l = 0; l < 1*NR_LANES; l++)
      i64[l] = (l >> 0);
    for (int l = 0; l < 2*NR_LANES; l++)
      i32[l] = (l >> 1) + l[0] * 1 * NR_LANES;
    for (int l = 0; l < 4*NR_LANES; l++)
      i16[l] = (l >> 2) + l[0] * 2 * NR_LANES + l[1] * 1 * NR_LANES;
    for (int l = 0; l < 8*NR_LANES; l++)
      i8[l] = (l >> 3) + l[0] * 4 * NR_LANES + l[1] * 2 * NR_LANES + l[2] * NR_LANES;

    // Deshuffle
    for (int l = 0; l < NR_LANES; l++) begin
      w_input.w64[l]   = word_i[l].word ;
      w_input_valid[l] = word_i[l].valid;
    end

    case (width_i)
      riscv::WD_V64B: for (int unsigned l = 0; l < 1*NR_LANES; l++) retval.word.w64[i64[l]] = w_input.w64[l];
      riscv::WD_V32B: for (int unsigned l = 0; l < 2*NR_LANES; l++) retval.word.w32[i32[l]] = w_input.w32[l];
      riscv::WD_V16B: for (int unsigned l = 0; l < 4*NR_LANES; l++) retval.word.w16[i16[l]] = w_input.w16[l];
      riscv::WD_V8B : for (int unsigned l = 0; l < 8*NR_LANES; l++) retval.word.w8[ i8[l]] = w_input.w8[l];
    endcase // case (width_i)
    retval.valid = &w_input_valid;

    return retval;
  endfunction : deshuffle

endpackage : ara_pkg
