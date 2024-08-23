// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Macros used throughout the Ara project

`ifndef ARA_SVH_
`define ARA_SVH_

  // Structs in ports of hierarchical modules are not supported in Verilator
  // --> Flatten them for Verilator
  `define STRUCT_PORT(struct_t)  \
  `ifndef VERILATOR              \
    struct_t                     \
  `else                          \
    logic[$bits(struct_t)-1:0]   \
  `endif

  // Structs in ports of hierarchical modules are not supported in Verilator
  // --> Flatten them for Verilator
  `define STRUCT_PORT_BITS(bits) \
  `ifndef VERILATOR              \
    struct_t                     \
  `else                          \
    logic[bits-1:0]              \
  `endif

  // Create a flattened vector of a struct. Make sure the first dimension is
  // the dimension into the vector of struct types and not the struct itself.
  `define STRUCT_VECT(struct_t, dim)  \
  `ifndef VERILATOR                   \
    struct_t dim                      \
  `else                               \
    logic dim [$bits(struct_t)-1:0]   \
  `endif

`endif
