# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Moritz Imfeld  <moimfeld@student.ethz.ch>
# Author: Matteo Perotti <mperotti@ethz.ch>
# Modifier : Mojtaba Rostami <m.rostami1989@gmail.com>

# Cheshire root repository
MAKEFILE_DIR            := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ARA_ROOT                := $(MAKEFILE_DIR)/..
BACKREF_CHS_ROOT        ?= $(realpath ../../../../..)
BACKREF_CHS_XIL_SCRIPTS := $(BACKREF_CHS_ROOT)/target/xilinx/scripts
BACKREF_CHS_SIM_SCRIPTS := $(BACKREF_CHS_ROOT)/target/sim/vsim/

# Tools
VIVADO ?= 'vitis-2020.2 vivado'

# Set up Bender targets and defines
# default configuration for Cheshire + Ara is 2_lanes
ARA_CONFIGURATION         ?= 2_lanes
include $(ARA_ROOT)/config/$(ARA_CONFIGURATION).mk

# Default to VCU128 if no BOARD is specified, but allow overriding.
BOARD                     ?= vcu128
VLOG_ARGS                 ?= -suppress 2583 -suppress 13314
COMMON_CUSTOM_TARGETS     := -t cv64a6_imafdcv_sv39 -t cva6 --define ARA --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen)
CUSTOM_SIM_BENDER_TARGETS := $(COMMON_CUSTOM_TARGETS) -t sim -t test -t rtl --vlog-arg="$(VLOG_ARGS)"
CUSTOM_XIL_BENDER_TARGETS := $(COMMON_CUSTOM_TARGETS) -t fpga -t $(BOARD)

.PHONY: ara-chs-xilinx ara-chs-flash apply-patches update_xilinx_src clean

# Combine the xilinx and flash targets to be flexible for different boards.
ara-chs-xilinx: update_xilinx_src
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-$(BOARD)

ara-chs-flash:
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-flash-$(BOARD) VIVADO=$(VIVADO)

apply-patches:
	cd $(BACKREF_CHS_ROOT) && \
	git apply $(ARA_ROOT)/cheshire/patches/device_tree.patch

update_xilinx_src:
	cd $(BACKREF_CHS_ROOT) && \
	bender script vivado $(CUSTOM_XIL_BENDER_TARGETS) > $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.$(BOARD).tcl

update_vsim_src:
	cd $(BACKREF_CHS_ROOT) && \
	bender script vsim $(CUSTOM_SIM_BENDER_TARGETS) > $(BACKREF_CHS_SIM_SCRIPTS)/compile.cheshire_soc.tcl
	echo 'vlog "$(realpath $(BACKREF_CHS_ROOT))/target/sim/src/elfloader.cpp" -ccflags "-std=c++11"' >> $(BACKREF_CHS_SIM_SCRIPTS)/compile.cheshire_soc.tcl

clean:
	rm -f $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.$(BOARD).tcl
	rm -f $(MAKEFILE_DIR)/add_sources.$(BOARD).tcl

