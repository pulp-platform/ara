# Copyright 2020 ETH Zurich and University of Bologna.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Matheus Cavalcante, ETH Zurich

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$MEMPOOL_DIR)

INSTALL_PREFIX          ?= install
INSTALL_DIR             ?= ${ROOT_DIR}/${INSTALL_PREFIX}
GCC_INSTALL_DIR         ?= ${INSTALL_DIR}/riscv-gcc
LLVM_INSTALL_DIR        ?= ${INSTALL_DIR}/riscv-llvm
ISA_SIM_INSTALL_DIR     ?= ${INSTALL_DIR}/riscv-isa-sim
ISA_SIM_MOD_INSTALL_DIR ?= ${INSTALL_DIR}/riscv-isa-sim-mod
VERIL_INSTALL_DIR       ?= ${INSTALL_DIR}/verilator
VERIL_VERSION           ?= v5.012
DTC_COMMIT              ?= b6910bec11614980a21e46fbccc35934b671bd81

CMAKE ?= cmake

# CC and CXX are Makefile default variables that are always defined in a Makefile. Hence, overwrite
# the variable if it is only defined by the Makefile (its origin in the Makefile's default).
ifeq ($(origin CC),default)
CC     = gcc
endif
ifeq ($(origin CXX),default)
CXX    = g++
endif

# We need a recent LLVM to compile Verilator
CLANG_CC  ?= clang
CLANG_CXX ?= clang++
ifneq (${CLANG_PATH},)
	CLANG_CXXFLAGS := "-nostdinc++ -isystem $(CLANG_PATH)/include/c++/v1"
	CLANG_LDFLAGS  := "-L $(CLANG_PATH)/lib -Wl,-rpath,$(CLANG_PATH)/lib -lc++ -nostdlib++"
else
	CLANG_CXXFLAGS := ""
	CLANG_LDFLAGS  := ""
endif

# Default target
all: toolchains riscv-isa-sim verilator

# GCC and LLVM Toolchains
.PHONY: toolchain-gcc

toolchain-gcc: Makefile
	mkdir -p $(GCC_INSTALL_DIR)
	cd $(CURDIR)/toolchain/riscv-gnu-toolchain && rm -rf build && mkdir -p build && cd build && \
	CC=$(CC) CXX=$(CXX) ../configure --prefix=$(GCC_INSTALL_DIR) --with-arch=rv64gcv --with-cmodel=medlow --enable-multilib && \
	$(MAKE) MAKEINFO=true -j4

# Spike
.PHONY: riscv-isa-sim riscv-isa-sim-mod
riscv-isa-sim: ${ISA_SIM_INSTALL_DIR} ${ISA_SIM_MOD_INSTALL_DIR}
riscv-isa-sim-mod: ${ISA_SIM_MOD_INSTALL_DIR}

${ISA_SIM_MOD_INSTALL_DIR}: Makefile patches/0003-riscv-isa-sim-patch ${ISA_SIM_INSTALL_DIR}
	# There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike.
	# Therefore, here we resort to older versions of the compilers.
	# If there are problems with dynamic linking, use:
	# make riscv-isa-sim LDFLAGS="-static-libstdc++"
	# Spike was compiled successfully using gcc and g++ version 7.2.0.
	cd toolchain/riscv-isa-sim && git stash && git apply ../../patches/0003-riscv-isa-sim-patch && \
	rm -rf build && mkdir -p build && cd build; \
	[ -d dtc ] || git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git && cd dtc && git checkout $(DTC_COMMIT); \
	make install SETUP_PREFIX=$(ISA_SIM_MOD_INSTALL_DIR) PREFIX=$(ISA_SIM_MOD_INSTALL_DIR) && \
	PATH=$(ISA_SIM_MOD_INSTALL_DIR)/bin:$$PATH; cd ..; \
	../configure --prefix=$(ISA_SIM_MOD_INSTALL_DIR) \
	--without-boost --without-boost-asio --without-boost-regex && \
	make -j32 && make install; \
	git stash

${ISA_SIM_INSTALL_DIR}: Makefile
	# There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike.
	# Therefore, here we resort to older versions of the compilers.
	# If there are problems with dynamic linking, use:
	# make riscv-isa-sim LDFLAGS="-static-libstdc++"
	# Spike was compiled successfully using gcc and g++ version 7.2.0.
	cd toolchain/riscv-isa-sim && rm -rf build && mkdir -p build && cd build; \
	[ -d dtc ] || git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git && cd dtc && git checkout $(DTC_COMMIT); \
	make install SETUP_PREFIX=$(ISA_SIM_INSTALL_DIR) PREFIX=$(ISA_SIM_INSTALL_DIR) && \
	PATH=$(ISA_SIM_INSTALL_DIR)/bin:$$PATH; cd ..; \
	../configure --prefix=$(ISA_SIM_INSTALL_DIR) \
	--without-boost --without-boost-asio --without-boost-regex && \
	make -j32 && make install

# Verilator
.PHONY: verilator
verilator: ${VERIL_INSTALL_DIR}

${VERIL_INSTALL_DIR}: Makefile
	# Checkout the right version
	cd $(CURDIR)/toolchain/verilator && git reset --hard && git fetch && git checkout ${VERIL_VERSION}
	# Compile verilator
	cd $(CURDIR)/toolchain/verilator && git clean -xfdf && autoconf && \
	CC=$(CLANG_CC) CXX=$(CLANG_CXX) CXXFLAGS=$(CLANG_CXXFLAGS) LDFLAGS=$(CLANG_LDFLAGS) \
		./configure --prefix=$(VERIL_INSTALL_DIR) && make -j8 && make install

# RISC-V Tests
riscv_tests:
	make -C apps -j4 riscv_tests && \
	make -C hardware riscv_tests_simc

# Helper targets
.PHONY: clean

clean:
	rm -rf $(INSTALL_DIR)
