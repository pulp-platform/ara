# Copyright (c) 2020 ETH Zurich, University of Bologna
#
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Wolfgang Roenninger <wroennin@ethz.ch>


####################################################################################################
# This script runs xsim in vivado
####################################################################################################

# set script root to location where this script is located
set SCRIPT_ROOT [file normalize [file dirname [info script]]]

# check if the enviroment variables are set, if not, set default to genesys2
if {![info exists ::env(XILINX_PART)]} {
	puts "Set default XILINX_PART"
	set env(XILINX_PART) "xc7k325tffg900-2"
}
if {![info exists ::env(XILINX_BOARD)]} {
	puts "Set default XILINX_BOARD"
	set env(XILINX_BOARD) "digilentinc.com:genesys2:part0:1.1"
}

####################################################################################################
# Create project
####################################################################################################

set project tc_generic_sim

create_project $project . -force -part $::env(XILINX_PART)
set_property board_part $::env(XILINX_BOARD) [current_project]

# set number of threads
set_param general.maxThreads 8

####################################################################################################
# add design sources
####################################################################################################

source $SCRIPT_ROOT/add_sources.tcl
set_property top tb_tc_sram [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

####################################################################################################
# Simulate tc_sram_xilinx with one port
####################################################################################################

set_property generic NumPorts=32'd1 [get_fileset sim_1]
update_ip_catalog

update_compile_order -fileset sources_1

launch_simulation

run -all

close_sim

####################################################################################################
# Simulate tc_sram_xilinx with two ports
####################################################################################################

set_property generic NumPorts=32'd2 [get_fileset sim_1]
update_ip_catalog

update_compile_order -fileset sources_1

launch_simulation

run -all

close_sim
