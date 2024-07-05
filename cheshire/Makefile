# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Moritz Imfeld  <moimfeld@student.ethz.ch>
# Author: Matteo Perotti <mperotti@ethz.ch>
#

# Chshire root reposiotry
MAKEFILE_DIR            := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ARA_ROOT                := $(MAKEFILE_DIR)/..
BACKREF_CHS_ROOT        ?= $(realpath ../../../../..)
BACKREF_CHS_XIL_SCRIPTS := $(BACKREF_CHS_ROOT)/target/xilinx/scripts


# Set up Bender targets and defines
# default configuration for Cheshire + Ara is 2_lanes
ARA_CONFIGURATION       ?= 2_lanes
include $(ARA_ROOT)/config/$(ARA_CONFIGURATION).mk
BOARD                   := vcu128
CUSTOM_BENDER_TARGETS   := -t fpga -t cv64a6_imafdcv_sv39 -t cva6 -t $(BOARD) --define ARA --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen)

.PHONY: ara-chs-xilinx-$(BOARD) update_xilinx_src clean

ara-chs-xilinx-$(BOARD): update_xilinx_src
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-$(BOARD)

update_xilinx_src:
	cd $(BACKREF_CHS_ROOT) && \
	bender script vivado $(CUSTOM_BENDER_TARGETS) > $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl

clean:
	rm $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl
	rm $(MAKEFILE_DIR)/add_sources.vcu128.tcl
