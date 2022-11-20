// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's functions to calculate VRF addresses. Not in the package
// since the functions depend on `NrLanes`

// All the functions support a Barber-Pole layout

// Find the starting VRF address of a vector register vid
function automatic vaddr_t vaddr(logic [4:0] vid, int NrLanes);
  // This is not an adder, it's only wires.
  // (this holds if VLENB / NrLanes >= NrVRFBanksPerLane^2)
  vaddr = vid * (VLENB / NrLanes / NrVRFBanksPerLane) + vid[VaddrBankWidth-1:0];
endfunction: vaddr

// Return the physical address of the next element of a certain vector
function automatic vaddr_t increment_vaddr(vaddr_t vaddr, logic [4:0] vid);
  // vaddr msbs -> byte index in a bank
  logic [VaddrIdxWidth-1:VaddrBankWidth] index;
  // vaddr lsbs -> bank index
  logic [VaddrBankWidth-1:0] bank;

  index = vaddr[VaddrIdxWidth-1:VaddrBankWidth];
  bank  = vaddr[VaddrBankWidth-1:0];

  // Increment bank counter
  bank += 1;
  if (bank == vid[VaddrBankWidth-1:0])
    // Wrap around
    index += 1;

  return {index, bank};
endfunction : increment_vaddr
