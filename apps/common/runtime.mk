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
# Include configuration
include $(ARA_DIR)/config/config.mk

INSTALL_DIR         ?= $(ARA_DIR)/install
GCC_INSTALL_DIR     ?= $(INSTALL_DIR)/riscv-gcc
LLVM_INSTALL_DIR    ?= $(INSTALL_DIR)/riscv-llvm
ISA_SIM_INSTALL_DIR ?= $(INSTALL_DIR)/riscv-isa-sim

RISCV_XLEN    ?= 64
RISCV_ARCH    ?= rv$(RISCV_XLEN)gcv
RISCV_ABI     ?= lp64
RISCV_TARGET  ?= riscv$(RISCV_XLEN)-unknown-elf

# Use GCC
RISCV_PREFIX_GCC  ?= $(GCC_INSTALL_DIR)/bin/$(RISCV_TARGET)-
RISCV_PREFIX_LLVM ?= $(LLVM_INSTALL_DIR)/bin/
RISCV_CC          ?= $(RISCV_PREFIX_LLVM)clang
RISCV_CXX         ?= $(RISCV_PREFIX_LLVM)clang++
RISCV_GCC_CC      ?= $(RISCV_PREFIX_GCC)gcc
RISCV_GCC_CXX     ?= $(RISCV_PREFIX_GCC)g++
RISCV_OBJDUMP     ?= $(RISCV_PREFIX_LLVM)llvm-objdump
RISCV_OBJCOPY     ?= $(RISCV_PREFIX_LLVM)llvm-objcopy
RISCV_AS          ?= $(RISCV_PREFIX_LLVM)llvm-as
RISCV_AR          ?= $(RISCV_PREFIX_LLVM)llvm-ar
RISCV_LD          ?= $(RISCV_PREFIX_LLVM)ld.lld
RISCV_STRIP       ?= $(RISCV_PREFIX_LLVM)llvm-strip

# Defines
DEFINES := -DNR_LANES=$(nr_lanes)

GCC_FLAGS  ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI)
LLVM_FLAGS ?= -march=rv64gcv0p10 -mabi=$(RISCV_ABI) -menable-experimental-extensions --sysroot=/scratch/mperotti/processor/ara/install/riscv-gcc/riscv64-unknown-elf/

RISCV_WARNINGS += -Wunused-variable -Wall -Wextra # -Werror
RISCV_FLAGS    ?= -mcmodel=medany  -mno-relax -I$(CURDIR)/common -static -std=gnu99 -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)

RISCV_CCFLAGS      ?= $(RISCV_FLAGS) $(LLVM_FLAGS)
RISCV_CXXFLAGS     ?= $(RISCV_FLAGS) $(LLVM_FLAGS)
RISCV_GCC_CCFLAGS  ?= $(RISCV_FLAGS) $(GCC_FLAGS)
RISCV_GCC_CXXFLAGS ?= $(RISCV_FLAGS) $(GCC_FLAGS)
RISCV_LDFLAGS      ?= -L$(RISCV_PREFIX_LLVM)../lib/linux
ifeq ($(COMPILER),gcc)
	RISCV_OBJDUMP_FLAGS ?=
else
	RISCV_OBJDUMP_FLAGS ?=
endif

RUNTIME ?= common/crt0.S.o common/printf.c.o common/string.c.o common/serial.c.o

.INTERMEDIATE: $(RUNTIME)

%.S.o: %.S
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%.c.o: %.c
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

%.cpp.o: %.cpp
	$(RISCV_CXX) $(RISCV_CXXFLAGS) -c $< -o $@

%.ld: %.ld.c
	$(RISCV_CC) -P -E $(DEFINES) $< -o $@
