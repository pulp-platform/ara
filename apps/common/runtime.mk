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

# Defines
DEFINES := -DNR_LANES=$(nr_lanes)

LLVM_FLAGS ?= -march=rv64gcv0p10 -mabi=$(RISCV_ABI) -menable-experimental-extensions -mno-relax -fuse-ld=lld

RISCV_WARNINGS += -Wunused-variable -Wall -Wextra -Wno-unused-command-line-argument # -Werror
RISCV_FLAGS    ?= $(LLVM_FLAGS) -mcmodel=medany -I$(CURDIR)/common -std=gnu99 -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)

RISCV_CCFLAGS  ?= $(RISCV_FLAGS)
RISCV_CXXFLAGS ?= $(RISCV_FLAGS)
RISCV_LDFLAGS  ?= -static -nostartfiles -lm
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
