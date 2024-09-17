# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

add wave -noupdate -group Ara -group core /ara_tb/dut/i_ara_soc/i_system/i_ara/*


add wave -noupdate -group Ara -group dispatcher /ara_tb/dut/i_ara_soc/i_system/i_ara/i_dispatcher/*
add wave -noupdate -group Ara -group sequencer /ara_tb/dut/i_ara_soc/i_system/i_ara/i_sequencer/*
add wave -noupdate -group Ara -group xif_handler -position insertpoint sim:/ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/*
add wave -noupdate -group Ara -group xif_pre_decoder -position insertpoint sim:/ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/i_xif_issue_pre_decoder/*
add wave -noupdate -group Ara -group xif_buffer -position insertpoint sim:/ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/i_xif_buffer/*

# Add waves from all the lanes
for {set lane 0}  {$lane < [examine -radix dec ara_tb.NrLanes]} {incr lane} {
    do ../scripts/wave_lane.tcl $lane
}

add wave -noupdate -group Ara -group masku /ara_tb/dut/i_ara_soc/i_system/i_ara/i_masku/*

add wave -noupdate -group Ara -group sldu /ara_tb/dut/i_ara_soc/i_system/i_ara/i_sldu/*

add wave -noupdate -group Ara -group vlsu -group addrgen /ara_tb/dut/i_ara_soc/i_system/i_ara/i_vlsu/i_addrgen/*
add wave -noupdate -group Ara -group vlsu -group vldu /ara_tb/dut/i_ara_soc/i_system/i_ara/i_vlsu/i_vldu/*
add wave -noupdate -group Ara -group vlsu -group vstu /ara_tb/dut/i_ara_soc/i_system/i_ara/i_vlsu/i_vstu/*
add wave -noupdate -group Ara -group vlsu /ara_tb/dut/i_ara_soc/i_system/i_ara/i_vlsu/*


add wave -noupdate -group Ara -group xif_handler /ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/*
add wave -noupdate -group Ara -group xif_handler -group ring_buffer /ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/i_ring_buffer/*
add wave -noupdate -group Ara -group xif_handler -group pre_decoder /ara_tb/dut/i_ara_soc/i_system/i_ara/i_xif_handler/i_pre_decoder/*
