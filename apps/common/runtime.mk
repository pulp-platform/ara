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

INSTALL_DIR             ?= $(ARA_DIR)/install
GCC_INSTALL_DIR         ?= $(INSTALL_DIR)/riscv-gcc
LLVM_INSTALL_DIR        ?= $(INSTALL_DIR)/riscv-llvm
ISA_SIM_INSTALL_DIR     ?= $(INSTALL_DIR)/riscv-isa-sim
ISA_SIM_MOD_INSTALL_DIR ?= $(INSTALL_DIR)/riscv-isa-sim-mod

RISCV_XLEN    ?= 64
RISCV_ARCH    ?= rv$(RISCV_XLEN)gcv
RISCV_ABI     ?= lp64d
RISCV_TARGET  ?= riscv$(RISCV_XLEN)-unknown-elf

# Use LLVM for bare-metal RVV and GCC for Linux RVV
ifeq ($(LINUX),1)
RISCV_PREFIX  ?= $(ARA_DIR)/cheshire/sw/cva6-sdk/buildroot/output/host/bin/riscv64-buildroot-linux-gnu-
RISCV_CC      ?= $(RISCV_PREFIX)gcc
RISCV_CXX     ?= $(RISCV_PREFIX)g++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_AS      ?= $(RISCV_PREFIX)as
RISCV_AR      ?= $(RISCV_PREFIX)ar
RISCV_LD      ?= $(RISCV_PREFIX)ld.lld
RISCV_STRIP   ?= $(RISCV_PREFIX)strip
else
RISCV_PREFIX  ?= $(LLVM_INSTALL_DIR)/bin/
RISCV_CC      ?= $(RISCV_PREFIX)clang
RISCV_CXX     ?= $(RISCV_PREFIX)clang++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)llvm-objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)llvm-objcopy
RISCV_AS      ?= $(RISCV_PREFIX)llvm-as
RISCV_AR      ?= $(RISCV_PREFIX)llvm-ar
RISCV_LD      ?= $(RISCV_PREFIX)ld.lld
RISCV_STRIP   ?= $(RISCV_PREFIX)llvm-strip
endif

# Use gcc to compile scalar riscv-tests
RISCV_CC_GCC  ?= $(GCC_INSTALL_DIR)/bin/$(RISCV_TARGET)-gcc

# Benchmark with spike
spike_env_dir ?= $(ARA_DIR)/apps/riscv-tests
SPIKE_INC     ?= -I$(spike_env_dir)/env -I$(spike_env_dir)/benchmarks/common
SPIKE_CCFLAGS ?= -DPREALLOCATE=1 -DSPIKE=1 $(SPIKE_INC)
SPIKE_LDFLAGS ?= -nostdlib -T$(spike_env_dir)/benchmarks/common/test.ld
RISCV_SIM     ?= $(ISA_SIM_INSTALL_DIR)/bin/spike
RISCV_SIM_MOD ?= $(ISA_SIM_MOD_INSTALL_DIR)/bin/spike
# VLEN should be lower or equal than 4096 because of spike restrictions
vlen_spike := $(shell vlen=$$(grep vlen $(ARA_DIR)/config/$(config).mk | cut -d" " -f3) && echo "$$(( $$vlen < 4096 ? $$vlen : 4096 ))")
RISCV_SIM_OPT ?= --isa=rv64gcv_zfh --varch="vlen:$(vlen_spike),elen:64"
RISCV_SIM_MOD_OPT ?= --isa=rv64gcv_zfh --varch="vlen:$(vlen_spike),elen:64" -d

# Python
PYTHON ?= python3

# Defines
ENV_DEFINES ?=
ifeq ($(LINUX),1)
ENV_DEFINES += -DARA_LINUX=1
endif
ifeq ($(vcd_dump),1)
ENV_DEFINES += -DVCD_DUMP=1
endif
MAKE_DEFINES = -DNR_LANES=$(nr_lanes) -DVLEN=$(vlen)
DEFINES += $(ENV_DEFINES) $(MAKE_DEFINES)

# Common flags
RISCV_WARNINGS += -Wunused-variable -Wall -Wextra -Wno-unused-command-line-argument # -Werror

# LLVM Flags
LLVM_FLAGS     ?= -march=rv64gcv_zfh_zvfh -mabi=$(RISCV_ABI) -mno-relax -fuse-ld=lld
LLVM_V_FLAGS   ?= -fno-vectorize -mllvm -scalable-vectorization=off -mllvm -riscv-v-vector-bits-min=0 -mno-implicit-float
RISCV_FLAGS    ?= $(LLVM_FLAGS) $(LLVM_V_FLAGS) -mcmodel=medany -I$(CURDIR)/common -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)
ifeq ($(LINUX),1)
RISCV_CCFLAGS  ?= -march=rv64gcv -mabi=$(RISCV_ABI) -I$(CURDIR)/common -O2 $(DEFINES)
RISCV_LDFLAGS  ?= -lm -lstdc++
RISCV_CXXFLAGS ?= -march=rv64gcv -mabi=$(RISCV_ABI) -I$(CURDIR)/common -O2 $(DEFINES)
else
RISCV_CCFLAGS  ?= $(RISCV_FLAGS) -ffunction-sections -fdata-sections -std=gnu99
RISCV_LDFLAGS  ?= -static -nostartfiles -lm -Wl,--gc-sections -T$(CURDIR)/common/link.ld
endif
RISCV_CCFLAGS_SPIKE  ?= $(RISCV_FLAGS) $(SPIKE_CCFLAGS) -ffunction-sections -fdata-sections -std=gnu99
RISCV_CXXFLAGS ?= $(RISCV_FLAGS) -ffunction-sections -fdata-sections
RISCV_LDFLAGS_SPIKE  ?= -static -nostartfiles -lm $(SPIKE_LDFLAGS) -Wl,--gc-sections

# GCC Flags
RISCV_FLAGS_GCC    ?= -mcmodel=medany -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -I$(CURDIR)/common -static -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)
RISCV_CCFLAGS_GCC  ?= $(RISCV_FLAGS_GCC) -std=gnu99
RISCV_CXXFLAGS_GCC ?= $(RISCV_FLAGS_GCC)
RISCV_LDFLAGS_GCC  ?= -static -nostartfiles -lm -lgcc $(RISCV_FLAGS_GCC) -std=gnu99 -T$(CURDIR)/common/link.ld

ifeq ($(COMPILER),gcc)
	RISCV_OBJDUMP_FLAGS ?=
else
ifneq ($(LINUX),1)
	RISCV_OBJDUMP_FLAGS ?= --mattr=v
endif
endif

# Compile two different versions of the runtime, since we cannot link code compiled with two different toolchains
RUNTIME_GCC   ?= common/crt0-gcc.S.o common/printf-gcc.c.o common/string-gcc.c.o common/serial-gcc.c.o common/util-gcc.c.o
ifeq ($(LINUX),1)
RUNTIME_LLVM  ?= common/util-llvm.c.o
else
RUNTIME_LLVM  ?= common/crt0-llvm.S.o common/printf-llvm.c.o common/string-llvm.c.o common/serial-llvm.c.o common/util-llvm.c.o
endif
RUNTIME_SPIKE ?= $(spike_env_dir)/benchmarks/common/crt.S.o.spike $(spike_env_dir)/benchmarks/common/syscalls.c.o.spike common/util.c.o.spike

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

%.S.o.spike: %.S patch-spike-crt0
	$(RISCV_CC) $(RISCV_CCFLAGS_SPIKE) -c $< -o $@

%.c.o.spike: %.c
	$(RISCV_CC) $(RISCV_CCFLAGS_SPIKE) -c $< -o $@

%.cpp.o: %.cpp
	$(RISCV_CXX) $(RISCV_CXXFLAGS) -c $< -o $@

%.ld: %.ld.c
	$(RISCV_CC) -P -E $(DEFINES) $< -o $@
