# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Moritz Imfeld <moimfeld@student.ethz.ch>
#


# Chshire root reposiotry
MAKEFILE_DIR            := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ARA_ROOT								:= $(MAKEFILE_DIR)/..
BACKREF_CHS_ROOT        ?= ../../cheshire
BACKREF_CHS_XIL_SCRIPTS := $(BACKREF_CHS_ROOT)/target/xilinx/scripts
BOARD                   := vcu128
CUSTOM_BENDER_TARGETS   := -t fpga -t cv64a6_imafdcv_sv39 -t cva6 -t $(BOARD) --define ARA

.PHONY: ara-chs-xilinx-all clean

ara-chs-xilinx-all: $(MAKEFILE_DIR)/add_sources.vcu128.tcl
	make -C $(BACKREF_CHS_ROOT) chs-xilinx-$(BOARD)

$(MAKEFILE_DIR)/add_sources.vcu128.tcl:
	cd $(BACKREF_CHS_ROOT) && \
	bender script vivado $(CUSTOM_BENDER_TARGETS) > $@ && \
	cp $(MAKEFILE_DIR)/add_sources.vcu128.tcl $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl

clean:
	rm $(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl
	rm $(MAKEFILE_DIR)/add_sources.vcu128.tcl
