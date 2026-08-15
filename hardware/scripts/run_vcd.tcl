# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Time-windowed VCD dump, used to feed PrimeTime's VCD-based power analysis.
#
# Expected variables (set by the caller, see the `sim-vcd` target):
#   VCD_START : simulation time at which the dump starts            [ns]
#   VCD_END   : simulation time at which the dump stops             [ns]
#               -1 means "dump until the end of the simulation"
#   VCD_FILE  : output VCD file (absolute, or relative to $buildpath)
#   VCD_SCOPE : scope to dump. Must be the scope PrimeTime strips away with
#               `read_vcd -strip_path`, i.e. the placed&routed system.

if {![info exists VCD_START]} {set VCD_START                                 0}
if {![info exists VCD_END  ]} {set VCD_END                                  -1}
if {![info exists VCD_FILE ]} {set VCD_FILE             "../vcd/last_sim.vcd"}
if {![info exists VCD_SCOPE]} {set VCD_SCOPE "/ara_tb/dut/i_ara_soc/i_system"}

if {$VCD_END >= 0 && $VCD_END <= $VCD_START} {
  error "VCD_END ($VCD_END) must be larger than VCD_START ($VCD_START)"
}

# Keep control of the simulation when the testbench calls $finish, otherwise
# vsim tears down before we get the chance to flush and close the VCD file.
onfinish stop

file mkdir [file dirname $VCD_FILE]

########################################
# Fast-forward to the start of the window
########################################

# Nothing is recorded yet, so this costs no disk space.
if {$VCD_START > 0} {
  echo "\[TB - VCD\] running up to $VCD_START ns without dumping"
  # `catch` protects us against a testbench that calls $finish before we get
  # to the window: we still want to close the (empty) VCD file cleanly.
  catch {run $VCD_START ns}
}

########################################
# Open the VCD and start recording
########################################

echo "\[TB - VCD\] opening $VCD_FILE at time $now"
vcd file $VCD_FILE
vcd add -r ${VCD_SCOPE}/*
vcd on

########################################
# Run the dump window
########################################

if {$VCD_END < 0} {
  echo "\[TB - VCD\] dumping until the end of the simulation"
  catch {run -all}
} else {
  set window [expr {$VCD_END - $VCD_START}]
  echo "\[TB - VCD\] dumping for $window ns (up to $VCD_END ns)"
  catch {run $window ns}
}

########################################
# Close the VCD
########################################

vcd off
vcd flush

echo "\[TB - VCD\] dump closed at time $now"
echo "\[TB - VCD\] VCD written to $VCD_FILE"

quit -f
