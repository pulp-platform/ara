# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Matteo Perotti <mperotti@ethz.ch>
#
# Build an RVV-ready Linux image

# Linux should be RVV-ready?
RVV_LINUX := 1
# Suffix for host toolchain (to build buildroot toolchain)
TOOLCHAIN_SUFFIX :=

.PHONY: cva6-sdk linux_img

cva6-sdk:
	git submodule update --init --recursive -- $(ARA_SW)/$@

linux_img: cva6-sdk
	echo "Your gcc version is: $(gcc -dumpfullversion). This build worked with gcc and g++ version 11.2.0"
	make -C $(ARA_SW)/cva6-sdk images RVV=$(RVV_LINUX) \
	HOSTCC=gcc$(TOOLCHAIN_SUFFIX) \
	HOSTCXX=g++$(TOOLCHAIN_SUFFIX) \
	HOSTCPP=cpp$(TOOLCHAIN_SUFFIX)
