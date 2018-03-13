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
// File          : ara_axi_pkg.sv
// Author        : Matheus Cavalcante <matheusd@student.ethz.ch>
// Created       : 12.03.2019
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Structs and definitions related to Ara's AXI interfaces.

package ara_axi_pkg;

  import ara_frontend_pkg::*;
  import axi_pkg::*         ;

  localparam IdWidth   = 4            ;
  localparam UserWidth = 1            ;
  localparam AddrWidth = 64           ;
  localparam DataWidth = 32 * NR_LANES;
  localparam StrbWidth = DataWidth / 8;

  typedef logic [IdWidth-1:0] id_t    ;
  typedef logic [AddrWidth-1:0] addr_t;
  typedef logic [DataWidth-1:0] data_t;
  typedef logic [StrbWidth-1:0] strb_t;
  typedef logic [UserWidth-1:0] user_t;

  // AW Channel
  typedef struct packed {
    id_t id        ;
    addr_t addr    ;
    len_t len      ;
    size_t size    ;
    burst_t burst  ;
    logic lock     ;
    cache_t cache  ;
    prot_t prot    ;
    region_t region;
    qos_t qos      ;
    atop_t atop    ;
  } aw_chan_t;

  // W Channel
  typedef struct packed {
    data_t data;
    strb_t strb;
    logic last ;
  } w_chan_t;

  // B Channel
  typedef struct packed {
    id_t id    ;
    resp_t resp;
  } b_chan_t;

  // AR Channel
  typedef struct packed {
    id_t id        ;
    addr_t addr    ;
    len_t len      ;
    size_t size    ;
    burst_t burst  ;
    logic lock     ;
    cache_t cache  ;
    prot_t prot    ;
    qos_t qos      ;
    region_t region;
  } ar_chan_t;

  // R Channel
  typedef struct packed {
    id_t id    ;
    data_t data;
    resp_t resp;
    logic last ;
  } r_chan_t;

  typedef struct packed {
    aw_chan_t aw  ;
    logic aw_valid;
    w_chan_t w    ;
    logic w_valid ;
    logic b_ready ;
    ar_chan_t ar  ;
    logic ar_valid;
    logic r_ready ;
  } axi_req_t;

  typedef struct packed {
    logic aw_ready;
    logic ar_ready;
    logic w_ready ;
    logic b_valid ;
    b_chan_t b    ;
    logic r_valid ;
    r_chan_t r    ;
  } axi_resp_t;

endpackage : ara_axi_pkg
