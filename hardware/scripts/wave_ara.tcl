# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

for {set core 0}  {$core < [examine -radix dec ara_tb.NrAraSystems]} {incr core} {
  add wave -noupdate -group Ara_$core -group core /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/*

  add wave -noupdate -group Ara_$core -group dispatcher /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_dispatcher/*
  add wave -noupdate -group Ara_$core -group sequencer /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_sequencer/*

  # Add waves from all the lanes
  for {set lane 0}  {$lane < [examine -radix dec ara_tb.NrLanes]} {incr lane} {
      do ../scripts/wave_lane.tcl $lane $core
  }

  add wave -noupdate -group Ara_$core -group masku /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_masku/*

  add wave -noupdate -group Ara_$core -group sldu /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_sldu/*

  add wave -noupdate -group Ara_$core -group vlsu -group addrgen /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_vlsu/i_addrgen/*
  add wave -noupdate -group Ara_$core -group vlsu -group vldu /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_vlsu/i_vldu/*
  add wave -noupdate -group Ara_$core -group vlsu -group vstu /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_vlsu/i_vstu/*
  add wave -noupdate -group Ara_$core -group vlsu /ara_tb/dut/i_ara_soc/gen_ara_systems[$core]/i_system/i_ara/i_vlsu/*
}
