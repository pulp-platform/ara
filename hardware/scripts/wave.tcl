# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

onerror {resume}
quietly WaveActivateNextPane {} 0

# Add Ariane's waveforms
do ../scripts/wave_core.tcl

# Add Ara's waveforms
do ../scripts/wave_ara.tcl
