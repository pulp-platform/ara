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
ISA_SIM_INSTALL_DIR     ?= $(INSTALL_DIR)/riscv-isa-sim
ISA_SIM_MOD_INSTALL_DIR ?= $(INSTALL_DIR)/riscv-isa-sim-mod

RISCV_XLEN    ?= 64
RISCV_ARCH    ?= rv$(RISCV_XLEN)gcv_zfh_zvfh
RISCV_ABI     ?= lp64d

ifeq ($(LINUX),1)
GCC_INSTALL_DIR ?= $(ARA_DIR)/cheshire/sw/cva6-sdk/buildroot/output/host
RISCV_TARGET    ?= riscv$(RISCV_XLEN)-buildroot-linux-gnu
else
GCC_INSTALL_DIR ?= $(INSTALL_DIR)/riscv-gcc
RISCV_TARGET    ?= riscv$(RISCV_XLEN)-unknown-elf
endif

RISCV_PREFIX  ?= $(GCC_INSTALL_DIR)/bin/$(RISCV_TARGET)
RISCV_CC      ?= $(RISCV_PREFIX)-gcc
RISCV_CXX     ?= $(RISCV_PREFIX)-g++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)-objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)-objcopy
RISCV_AS      ?= $(RISCV_PREFIX)-as
RISCV_AR      ?= $(RISCV_PREFIX)-ar
RISCV_LD      ?= $(RISCV_PREFIX)-ld.lld
RISCV_STRIP   ?= $(RISCV_PREFIX)-strip

# Benchmark with spike
spike_env_dir ?= $(ARA_DIR)/apps/riscv-tests
SPIKE_INC     ?= -I$(spike_env_dir)/env -I$(spike_env_dir)/benchmarks/common
SPIKE_CCFLAGS ?= -DPREALLOCATE=1 -DSPIKE=1 $(SPIKE_INC)
SPIKE_LDFLAGS ?= -nostdlib -T$(spike_env_dir)/benchmarks/common/test.ld
RISCV_SIM     ?= $(ISA_SIM_INSTALL_DIR)/bin/spike
RISCV_SIM_MOD ?= $(ISA_SIM_MOD_INSTALL_DIR)/bin/spike
# VLEN should be lower or equal than 4096 because of spike restrictions
vlen_spike := $(shell vlen=$$(grep vlen $(ARA_DIR)/config/$(config).mk | cut -d" " -f3) && echo "$$(( $$vlen < 4096 ? $$vlen : 4096 ))")
RISCV_SIM_OPT ?= --isa=$(RISCV_ARCH) --varch="vlen:$(vlen_spike),elen:64"
RISCV_SIM_MOD_OPT ?= --isa=$(RISCV_ARCH) --varch="vlen:$(vlen_spike),elen:64" -d

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

# Flags
RISCV_CCFLAGS  ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -mcmodel=medany
COMMON_CCFLAGS ?= -O3 -std=gnu99 -ffunction-sections -fdata-sections -ffast-math -fno-common -fno-builtin-printf -I$(CURDIR)/common $(DEFINES) $(RISCV_WARNINGS) -Wunused-variable -Wall -Wextra
COMMON_LDFLAGS ?= -static -nostartfiles -lm -lgcc -Wl,--gc-sections
ifeq ($(LINUX),1)
CCFLAGS ?= $(RISCV_CCFLAGS) -O3 -I$(CURDIR)/common $(DEFINES)
LDFLAGS ?= $(CCFLAGS)
else
CCFLAGS ?= $(RISCV_CCFLAGS) $(COMMON_CCFLAGS)
LDFLAGS ?= $(CCFLAGS) $(COMMON_LDFLAGS) -T$(CURDIR)/common/link.ld
endif
CCFLAGS_SPIKE ?= $(CCFLAGS) $(SPIKE_CCFLAGS)
LDFLAGS_SPIKE ?= $(CCFLAGS) $(COMMON_LDFLAGS)

# Runtime
ifeq ($(LINUX),1)
RUNTIME ?= common/util.c.o
else
RUNTIME ?= common/crt0.S.o common/printf.c.o common/string.c.o common/serial.c.o common/util.c.o
endif
RUNTIME_SPIKE ?= $(spike_env_dir)/benchmarks/common/crt.S.o.spike $(spike_env_dir)/benchmarks/common/syscalls.c.o.spike common/util.c.o.spike

%.S.o: %.S
	$(RISCV_CC) $(CCFLAGS) -c $< -o $@

%.c.o: %.c
	$(RISCV_CC) $(CCFLAGS) -c $< -o $@

%.S.o.spike: %.S patch-spike-crt0
	$(RISCV_CC) $(CCFLAGS_SPIKE) -c $< -o $@

%.c.o.spike: %.c
	$(RISCV_CC) $(CCFLAGS_SPIKE) -c $< -o $@

%.cpp.o: %.cpp
	$(RISCV_CXX) $(CCFLAGS) -c $< -o $@

%.ld: %.ld.c
	$(RISCV_CC) -P -E $(DEFINES) $< -o $@
