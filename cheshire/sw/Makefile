# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Matteo Perotti <mperotti@ethz.ch>
#
# Copy and compile vector software on Cheshire

CHS_ROOT ?= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/../../../../../..
ARA_ROOT := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/../..
CHS_SW   := $(CHS_ROOT)/sw
ARA_SW   := $(ARA_ROOT)/cheshire/sw
ARA_APPS := $(ARA_ROOT)/apps

APPS    := $(patsubst $(ARA_APPS)/%/main.c,%,$(shell find $(ARA_APPS) -name "main.c"))
SW_C    := $(wildcard $(ARA_SW)/src/*.c)
TESTS_C := $(wildcard $(ARA_SW)/src/tests/*.c) $(wildcard $(ARA_SW)/src/tests/body/*.body)
DEPS_H  := $(wildcard $(ARA_SW)/include/*.h)

# Hardware configuration for the Ara RVV kernels
# Can be chosen in [2|4|8|16]_lanes
ARA_CONFIGURATION ?= 2_lanes
include $(ARA_ROOT)/config/$(ARA_CONFIGURATION).mk

# Get the original compiler options and add the support for vector extension
CHS_SW_FLAGS ?= $(shell grep "^CHS_SW_FLAGS\s\+?=\s\+" -- $(CHS_SW)/sw.mk | sed 's/^.*?= //' | sed s/rv64gc/rv64gcv/)
# Tweak the compilation to include Cheshire-related headers and files
CHS_SW_FLAGS += -DCHESHIRE -DNR_LANES=$(nr_lanes) -DVLEN=$(vlen)
# Include the correct definitions for the RVV tests
CHS_SW_FLAGS += -DARA_NR_LANES=$(nr_lanes) -DEEW=$(eew) -DPRINTF=$(printf)

# Vars and rules to make the Linux image
include cva6-sdk.mk

.PHONY: chs-sw-all copy_vector_sw copy-vector-deps

# Forward build command to the main Cheshire makefile and attach the correct -march
chs-sw-all: copy-vector-sw copy-vector-deps
	make -C $(CHS_ROOT) $@ CHS_SW_FLAGS="$(CHS_SW_FLAGS)"

# Copy the dependencies from this folder to Cheshire
copy-vector-deps: $(DEPS_H)
	cp $^ $(CHS_SW)/tests

# Copy the vector programs from the src folder to cheshire
copy-vector-sw: $(SW_C) $(TESTS_C)
	cp $^ $(CHS_SW)/tests
