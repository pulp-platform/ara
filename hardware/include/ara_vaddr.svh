// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
// Description:
// Ara's functions to calculate VRF addresses. Not in the package
// since the functions depend on `NrLanes`

// All the functions to support a Barber-Pole VRF layout

// Find the starting VRF address of a vector register vid
function automatic vaddr_t vaddr(logic [4:0] vid, int NrLanes);
  // This is not an adder, it's only wires.
  // (this holds if VLENB / NrLanes >= NrVRFBanksPerLane^2)
  vaddr = vid * (VLENB / NrLanes / NrVRFBanksPerLane) + vid[VaddrBankWidth-1:0];
endfunction: vaddr

// Return the physical address of the next element of a certain vector
function automatic vaddr_t next_vaddr(vaddr_t vaddr, logic [4:0] vid);
  // vaddr msbs -> byte index in a bank
  logic [VaddrIdxWidth-1:VaddrBankWidth] index, old_index;
  // vaddr lsbs -> bank index
  logic [VaddrBankWidth-1:0] bank;

  index = vaddr[VaddrIdxWidth-1:VaddrBankWidth];
  bank  = vaddr[VaddrBankWidth-1:0];

  old_index = index;

  // Increment bank counter
  bank += 1;
  if (bank == vid[VaddrBankWidth-1:0])
    // Wrap around
    index += 1;

  // If we change vreg, the start element position is +1 (LMUL > 1)
  // This is important for B layout consistency among different LMUL
  // or when inactive element policy is "undistrubed"
  if (index[VaddrVregWidth] != old_index[VaddrVregWidth])
    bank += 1;

  return {index, bank};
endfunction

// Initialize with an offset (necessary with vslideup)
function automatic vaddr_t vaddr_offset(vaddr_t vaddr, vaddr_t off, logic [4:0] vid);
  // vaddr msbs -> byte index in a bank
  logic [VaddrIdxWidth-1:VaddrBankWidth] index, old_index;
  // vaddr lsbs -> bank index
  logic [VaddrBankWidth-1:0] bank, old_bank;

  index = vaddr[VaddrIdxWidth-1:VaddrBankWidth];
  bank  = vaddr[VaddrBankWidth-1:0];

  old_index = index;
  old_bank  = bank;

  // Increment bank counter
  index += off[VaddrIdxWidth-1:VaddrBankWidth];
  bank  += off[VaddrBankWidth-1:0];
  // Support vstart != 0: don't hypothesize that old_bank == vid[VaddrBankWidth-1:0]
  // Wrap around if we meet vid[VaddrBankWidth-1:0] during the addition
  if (old_bank > vid[VaddrBankWidth-1:0]) begin
    if (bank >= vid[VaddrBankWidth-1:0] && bank < old_bank)
      // Wrap around
      index += 1;
  end else if (old_bank < vid[VaddrBankWidth-1:0]) begin
    if (bank >= vid[VaddrBankWidth-1:0] || bank < old_bank)
      // Wrap around
      index += 1;
  end

  // If we change vreg, the start element position is +1
  // for every reg passed (LMUL > 1). The max reg id delta is 7
  // with LMUL == 8.
  bank += index[VaddrVregWidth +: 3] - old_index[VaddrVregWidth +: 3];

  return {index, bank};
endfunction
