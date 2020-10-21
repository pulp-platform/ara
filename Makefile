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

INSTALL_PREFIX      ?= install
INSTALL_DIR         ?= ${ROOT_DIR}/${INSTALL_PREFIX}
GCC_INSTALL_DIR     ?= ${INSTALL_DIR}/riscv-gcc
ISA_SIM_INSTALL_DIR ?= ${INSTALL_DIR}/riscv-isa-sim

# CC and CXX are Makefile default variables that are always defined in a Makefile. Hence, overwrite
# the variable if it is only defined by the Makefile (its origin in the Makefile's default).
ifeq ($(origin CC),default)
CC     = gcc-8.2.0
endif
ifeq ($(origin CXX),default)
CXX    = g++-8.2.0
endif

# Default target
all: toolchain riscv-isa-sim

# Toolchain
.PHONY: toolchain
toolchain: ${GCC_INSTALL_DIR}

${GCC_INSTALL_DIR}:
	mkdir -p $(GCC_INSTALL_DIR)
	# Apply patch on riscv-binutils
	cd $(CURDIR)/toolchain/riscv-gnu-toolchain/riscv-binutils && git reset --hard && git apply $(CURDIR)/patches/0001-riscv-binutils-patch
	cd $(CURDIR)/toolchain/riscv-gnu-toolchain && rm -rf build && mkdir -p build && cd build && \
	../configure --prefix=$(GCC_INSTALL_DIR) --with-arch=rv64gcv --with-cmodel=medlow --enable-multilib && \
	$(MAKE) MAKEINFO=true -j4

# Spike
.PHONY: riscv-isa-sim
riscv-isa-sim: ${ISA_SIM_INSTALL_DIR}

${ISA_SIM_INSTALL_DIR}:
	cd toolchain/riscv-isa-sim && mkdir -p build && cd build; \
	[ -d dtc ] || git clone git://git.kernel.org/pub/scm/utils/dtc/dtc.git && cd dtc; \
	make install SETUP_PREFIX=$$(pwd)/install PREFIX=$$(pwd)/install && \
	PATH=$$(pwd)/install/bin:$$PATH; cd ..; \
	../configure --prefix=$(ISA_SIM_INSTALL_DIR) && make && make install

# Helper targets
.PHONY: clean

clean:
	rm -rf $(INSTALL_DIR)
