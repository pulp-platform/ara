# Copyright 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Matteo Perotti <mperotti@ethz.ch>
#
# Facility to build rivec apps

RIVEC_APPS := _axpy _blackscholes _canneal _jacobi-2d _lavaMD _matmul _particlefilter _pathfinder _somier _spmv _streamcluster _swaptions

.PHONY: rivec-bmark-% rivec-bmark-all

# Make the scalar and vector rivec app and a copy of input data
rivec-bmark-%:
	$(MAKE) $*-linux
	mv $(CVA6_SDK_ROOT)/rootfs/$* $(CVA6_SDK_ROOT)/rootfs/$*-scalar
	make -s -C $(ARA_APPS) clean
	$(MAKE) $*-linux ENV_DEFINES="-DUSE_RISCV_VECTOR"
	mv $(CVA6_SDK_ROOT)/rootfs/$* $(CVA6_SDK_ROOT)/rootfs/$*-vector
	make -s -C $(ARA_APPS) clean
	test -d $(ARA_APPS)/$*/input && cp -Lr $(ARA_APPS)/$*/input $(CVA6_SDK_ROOT)/rootfs/input$* || true

# Make all the rivec apps
rivec-all:
	@$(foreach app,$(RIVEC_APPS),$(MAKE) rivec-bmark-$(app) && ) true
