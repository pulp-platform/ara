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
	test -d $(CVA6_SDK_ROOT)/rootfs/input$* && rm -r $(CVA6_SDK_ROOT)/rootfs/input$* || true
	test -d $(ARA_APPS)/$*/input && cp -Lr $(ARA_APPS)/$*/input $(CVA6_SDK_ROOT)/rootfs/input$* || true

# Make all the rivec apps
rivec-all:
	@$(foreach app,$(RIVEC_APPS),$(MAKE) rivec-bmark-$(app) && ) true

# Prune large input datasets
rivec-all-small: rivec-all
	cd $(CVA6_SDK_ROOT)/rootfs/input_blackscholes && rm in_64K.input in_16K.input in_4K.input in_1024.input
	cd $(CVA6_SDK_ROOT)/rootfs/input_canneal      && rm 2500000.nets 400000.nets 200000.nets 100000.nets
	cd $(CVA6_SDK_ROOT)/rootfs/input_matmul       && rm data_512.in data_256.in gendata.pl
	cd $(CVA6_SDK_ROOT)/rootfs/input_pathfinder   && rm data_large.in data_medium.in data_small.in
	cd $(CVA6_SDK_ROOT)/rootfs/input_spmv         && rm lhr07.* Na5.* poisson3Db.* venkat25.*
