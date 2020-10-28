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
// File:   ara_pkg.sv
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
// Date:   28.10.2020
//
// Copyright (C) 2020 ETH Zurich, University of Bologna
// All rights reserved.
//
// Description:
// Ara's main package, containing most of the definitions for its usage.

package ara_pkg;

  /****************
   *  Parameters  *
   ****************/

  // Maximum size of a single vector element, in bits.
  // Ara only supports vector elements up to 64 bits.
  localparam int unsigned ELEN = 64;
  // Number of bits in a vector register.
  // VLEN >= ELEN. Must be a power of two.
  // It must also be divisible by the number of vector lanes.
  localparam int unsigned VLEN = `ifdef VLEN `VLEN `else 64 `endif;
  // Striping distance.
  // For Ara, this corresponds to the lane width, in bits.
  localparam int unsigned SLEN = 64;

  // Number of parallel vector lanes.
  localparam int unsigned NrLanes = `ifdef NR_LANES `NR_LANES `else 0 `endif;

endpackage : ara_pkg
