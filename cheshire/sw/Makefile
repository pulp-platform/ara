# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Matteo Perotti <mperotti@ethz.ch>
#
# Copy and compile vector software on Cheshire

CHS_ROOT ?= $(realpath ../../../../../..)
ARA_SW   := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
CHS_SW   := $(CHS_ROOT)/sw
SRC      := $(wildcard $(ARA_SW)/*.c) $(wildcard $(ARA_SW)/*.h)

# Get the original compiler options and add the support for vector extension
CHS_SW_FLAGS ?= $(shell grep "^CHS_SW_FLAGS\s\+?=\s\+" -- $(CHS_SW)/sw.mk | sed 's/^.*?= //' | sed s/rv64gc/rv64gcv/)

.PHONY: chs-sw-all copy_vector_sw

# Forward build command to the main Cheshire makefile and attach the correct -march
# Rename the .c vector files not to break the cheshire vanilla flow
chs-sw-all: copy-vector-sw
	make -C $(CHS_ROOT) $@ CHS_SW_FLAGS="$(CHS_SW_FLAGS)"
	for f in $(filter %.c, $(SRC)); do mv $(CHS_SW)/tests/$f $(CHS_SW)/tests/$f.bkp; done

# Copy the vector programs to cheshire
copy-vector-sw:
	cp $(SRC) $(CHS_SW)/tests
