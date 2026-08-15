# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Minimal run script for gate-level simulations.
#
# scripts/run.tcl is deliberately NOT used here:
#   * `log -r /*` would log every net of the netlist for the whole run, which
#     is prohibitively slow and fills the disk with an enormous WLF;
#   * scripts/wave.tcl adds waves at RTL paths (e.g. .../i_ara/i_dispatcher/*)
#     that synthesis has ungrouped, so most of its `add wave` commands fail.

run -a
