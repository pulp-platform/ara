// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Matteo Perotti  <mperotti@iis.ee.ethz.ch>
// Vincenzo Maisto <vincenzo.maisto2@unina.it>

// Tunable parameters
// param_stub_ex_ctrl. 0: no exceptions, 1: always exceptions, 2: random exceptions
#define param_stub_ex_ctrl 1

// param_stub_req_rsp_lat_ctrl. 0: fixed latency (== param_stub_req_rsp_lat), 1: random latency (max == param_stub_req_rsp_lat)
#define param_stub_req_rsp_lat_ctrl 1
#define param_stub_req_rsp_lat      10

#include "rvv_test_mmu_stub_unit_stride_ld_comprehensive.c.body"
