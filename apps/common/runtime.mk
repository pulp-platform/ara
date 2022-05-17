# Copyright 2020 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
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

# Author: Samuel Riedel, ETH Zurich
#         Matheus Cavalcante, ETH Zurich
SHELL = /usr/bin/env bash

ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$ARA_DIR)

# Choose Ara's configuration
ifndef config
	ifdef ARA_CONFIGURATION
		config := $(ARA_CONFIGURATION)
	else
		config := default
	endif
endif

# Include configuration
include $(ARA_DIR)/config/$(config).mk

INSTALL_DIR         ?= $(ARA_DIR)/install
GCC_INSTALL_DIR     ?= $(INSTALL_DIR)/riscv-gcc
LLVM_INSTALL_DIR    ?= $(INSTALL_DIR)/riscv-llvm
ISA_SIM_INSTALL_DIR ?= $(INSTALL_DIR)/riscv-isa-sim

RISCV_XLEN    ?= 64
RISCV_ARCH    ?= rv$(RISCV_XLEN)gcv
RISCV_ABI     ?= lp64d
RISCV_TARGET  ?= riscv$(RISCV_XLEN)-unknown-elf

# Use LLVM
RISCV_PREFIX  ?= $(LLVM_INSTALL_DIR)/bin/
RISCV_CC      ?= $(RISCV_PREFIX)clang
RISCV_CXX     ?= $(RISCV_PREFIX)clang++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)llvm-objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)llvm-objcopy
RISCV_AS      ?= $(RISCV_PREFIX)llvm-as
RISCV_AR      ?= $(RISCV_PREFIX)llvm-ar
RISCV_LD      ?= $(RISCV_PREFIX)ld.lld
RISCV_STRIP   ?= $(RISCV_PREFIX)llvm-strip

# Use gcc to compile scalar riscv-tests
RISCV_CC_GCC  ?= $(GCC_INSTALL_DIR)/bin/$(RISCV_TARGET)-gcc

# Defines
ENV_DEFINES ?=
MAKE_DEFINES = -DNR_LANES=$(nr_lanes) -DVLEN=$(vlen)
DEFINES += $(ENV_DEFINES) $(MAKE_DEFINES)

# Common flags
RISCV_WARNINGS += -Wunused-variable -Wall -Wextra -Wno-unused-command-line-argument # -Werror

# LLVM Flags
LLVM_FLAGS     ?= -march=rv64gcv0p10 -mabi=$(RISCV_ABI) -menable-experimental-extensions -mno-relax -fuse-ld=lld
RISCV_FLAGS    ?= $(LLVM_FLAGS) -mcmodel=medany -I$(CURDIR)/common -std=gnu99 -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)
RISCV_CCFLAGS  ?= $(RISCV_FLAGS)
RISCV_CXXFLAGS ?= $(RISCV_FLAGS)
RISCV_LDFLAGS  ?= -static -nostartfiles -lm

# GCC Flags
RISCV_FLAGS_GCC    ?= -mcmodel=medany -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -I$(CURDIR)/common -static -std=gnu99 -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)
RISCV_CCFLAGS_GCC  ?= $(RISCV_FLAGS_GCC)
RISCV_CXXFLAGS_GCC ?= $(RISCV_FLAGS_GCC)
RISCV_LDFLAGS_GCC  ?= -static -nostartfiles -lm -lgcc $(RISCV_FLAGS_GCC)

ifeq ($(COMPILER),gcc)
	RISCV_OBJDUMP_FLAGS ?=
else
	RISCV_OBJDUMP_FLAGS ?= --mattr=+experimental-v
endif

# Compile two different versions of the runtime, since we cannot link code compiled with two different toolchains
RUNTIME_GCC  ?= common/crt0-gcc.S.o common/printf-gcc.c.o common/string-gcc.c.o common/serial-gcc.c.o
RUNTIME_LLVM ?= common/crt0-llvm.S.o common/printf-llvm.c.o common/string-llvm.c.o common/serial-llvm.c.o

.INTERMEDIATE: $(RUNTIME_GCC) $(RUNTIME_LLVM)

%-gcc.S.o: %.S
	$(RISCV_CC_GCC) $(RISCV_CCFLAGS_GCC) -c $< -o $@

%-gcc.c.o: %.c
	$(RISCV_CC_GCC) $(RISCV_CCFLAGS_GCC) -c $< -o $@

%-llvm.S.o: %.S
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%-llvm.c.o: %.c
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%.S.o: %.S
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%.c.o: %.c
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%.cpp.o: %.cpp
	$(RISCV_CXX) $(RISCV_CXXFLAGS) -c $< -o $@

%.ld: %.ld.c
	$(RISCV_CC) -P -E $(DEFINES) $< -o $@
