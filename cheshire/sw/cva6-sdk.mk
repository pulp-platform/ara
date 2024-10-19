# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Matteo Perotti <mperotti@ethz.ch>
#
# Build an RVV-ready Linux image

# CVA6-SDK subpath
CVA6_SDK_ROOT = $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/cva6-sdk

# Linux should be RVV-ready?
RVV_LINUX := 1
# Suffix for host toolchain (to build buildroot toolchain)
# For IIS users: HOST_TOOLCHAIN_SUFFIX=-11.2.0
HOST_TOOLCHAIN_SUFFIX ?=
# Buildroot toolchain
TARGET_OS_TOOLCHAIN := $(CVA6_SDK_ROOT)/buildroot/output/host/bin/riscv64-buildroot-linux-gnu-gcc
# Github submodule update tokens
CVA6_SDK_UPDATED := $(ARA_ROOT)/cheshire/sw/.cva6-sdk.updated

.PHONY: %-linux linux-img

################
## Build deps ##
################

.PRECIOUS: $(CVA6_SDK_UPDATED)
$(CVA6_SDK_UPDATED):
	git submodule update --init --recursive -- $(CVA6_SDK_ROOT)
	touch $@

$(TARGET_OS_TOOLCHAIN): $(CVA6_SDK_UPDATED)
	@echo "Building the RISC-V CVA6-SDK Linux TOOLCHAIN"
	@echo "Your gcc version is: $$(gcc -dumpfullversion). This build worked with gcc and g++ version 11.2.0. Please adjust this if needed."
	make -C $(CVA6_SDK_ROOT) $@ \
	HOSTCC=gcc$(HOST_TOOLCHAIN_SUFFIX) \
	HOSTCXX=g++$(HOST_TOOLCHAIN_SUFFIX) \
	HOSTCPP=cpp$(HOST_TOOLCHAIN_SUFFIX) \
	RVV=$(RVV_LINUX)
	touch $@

########################
## Build RVV Software ##
########################

$(ARA_APPS)/bin/%-linux: $(shell find $(ARA_APPS)/$* -name "*.c" -o -name "*.S") $(TARGET_OS_TOOLCHAIN)
	make -C $(ARA_APPS) bin/$*-linux LINUX=1 config=${ARA_CONFIGURATION}

.PRECIOUS: $(CVA6_SDK_ROOT)/rootfs/%
$(CVA6_SDK_ROOT)/rootfs/%: $(ARA_APPS)/bin/%-linux
	cp $< $@

%-linux: $(CVA6_SDK_ROOT)/rootfs/%
	@echo "$@ built and copied."

#####################
## Build Linux IMG ##
#####################

$(CVA6_SDK_ROOT)/install64/vmlinux: $(CVA6_SDK_UPDATED) $(TARGET_OS_TOOLCHAIN) $(TARGET_KERNELS)
	make -C $(ARA_SW)/cva6-sdk images RVV=$(RVV_LINUX)

# Softlink the linux image and create a bootable Cheshire image
linux-img: $(CVA6_SDK_ROOT)/install64/vmlinux
	if [ -d "$(CHS_SW)/deps/cva6-sdk/install64" ]; then \
		echo "$(CHS_SW)/deps/cva6-sdk/install64 already exists, creating a backup..."; \
		mv $(CHS_SW)/deps/cva6-sdk/install64 $(CHS_SW)/deps/cva6-sdk/install64.bak_$(shell date +%Y%m%d_%H%M%S); \
	fi
	cp -r $(CVA6_SDK_ROOT)/install64 $(CHS_SW)/deps/cva6-sdk/
