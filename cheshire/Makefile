# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Moritz Imfeld   <moimfeld@student.ethz.ch>
# Author: Matteo Perotti  <mperotti@ethz.ch>
# Author: Mojtaba Rostami <m.rostami1989@gmail.com>

# Chshire root reposiotry
MAKEFILE_DIR            := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ARA_ROOT                := $(MAKEFILE_DIR)/..
BACKREF_CHS_ROOT        ?= $(realpath ../../../../..)
BACKREF_CHS_XIL_SCRIPTS := $(BACKREF_CHS_ROOT)/target/xilinx/scripts
BACKREF_CHS_VSIM        := $(BACKREF_CHS_ROOT)/target/sim/vsim/
BACKREF_CHS_VCS         := $(BACKREF_CHS_ROOT)/target/sim/vcs/

# Tools
BENDER := bender
VIVADO ?= 'vitis-2020.2 vivado'

# Caution: Questasim requires this to point to the *actual* compiler install path
CXX_PATH := $(shell which $(CXX))

# Set up Bender targets and defines
# default configuration for Cheshire + Ara is 2_lanes
ARA_CONFIGURATION         ?= 2_lanes
include $(ARA_ROOT)/config/$(ARA_CONFIGURATION).mk
BOARD                     ?= vcu128
COMMON_CUSTOM_TARGETS     := -t cv64a6_imafdcv_sv39 -t cva6 -t rtl -t exclude_first_pass_decoder --define ARA --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen)
CUSTOM_SIM_BENDER_TARGETS := $(COMMON_CUSTOM_TARGETS)
CUSTOM_XIL_BENDER_TARGETS := $(COMMON_CUSTOM_TARGETS) -t fpga -t $(BOARD)

# Define XILINX FPGA URL and PATH for programming
CHS_XILINX_HWS_URL  ?=
CHS_XILINX_HWS_PATH ?=

.PHONY: ara-chs-all ara-chs-xilinx ara-chs-flash ara-chs-xilinx-program update_xilinx_src update_vsim_src clean

# Make all cheshire HW/SW and get ready for simulation
ara-chs-all:
	$(MAKE) -C $(BACKREF_CHS_ROOT) all
	$(MAKE) update_vsim_src

ara-chs-xilinx: update_xilinx_src
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-$(BOARD)

ara-chs-image:
	make -C $(BACKREF_CHS_ROOT) $(BACKREF_CHS_ROOT)/sw/boot/linux.$(BOARD).gpt.bin -B

ara-chs-xilinx-flash:
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-flash-$(BOARD) VIVADO="$(VIVADO)" CHS_XILINX_HWS_URL="$(CHS_XILINX_HWS_URL)" CHS_XILINX_HWS_PATH_$(BOARD)="$(CHS_XILINX_HWS_PATH)"

ara-chs-xilinx-program:
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-program-$(BOARD) VIVADO="$(VIVADO)" CHS_XILINX_HWS_URL="$(CHS_XILINX_HWS_URL)" CHS_XILINX_HWS_PATH_$(BOARD)="$(CHS_XILINX_HWS_PATH)"

update_xilinx_src:
	cd $(BACKREF_CHS_ROOT) && \
	$(BENDER) script vivado $(CUSTOM_XIL_BENDER_TARGETS) > $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.$(BOARD).tcl

update_vsim_src:
	$(MAKE) -C $(BACKREF_CHS_ROOT) $(BACKREF_CHS_ROOT)/target/sim/vsim/compile.cheshire_soc.tcl CHS_BENDER_RTL_FLAGS="$(CUSTOM_SIM_BENDER_TARGETS)"
	$(MAKE) -C $(BACKREF_CHS_ROOT) $(BACKREF_CHS_ROOT)/target/sim/vcs/compile.cheshire_soc.sh CHS_BENDER_RTL_FLAGS="$(CUSTOM_SIM_BENDER_TARGETS)"

clean:
	rm $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.$(BOARD).tcl
	rm $(MAKEFILE_DIR)/add_sources.$(BOARD).tcl
