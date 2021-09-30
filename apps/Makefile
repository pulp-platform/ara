# Copyright 2019 ETH Zurich and University of Bologna.
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
#         Samuel Riedel, ETH Zurich

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
APPS_DIR := $(ROOT_DIR)
COMMON_DIR := $(ROOT_DIR)/common
TESTS_DIR := $(ROOT_DIR)/riscv-tests/isa

# This will overwrite the ROOT_DIR variable from the included makefile
include $(COMMON_DIR)/runtime.mk
include $(COMMON_DIR)/riscv_tests.mk

APPS := $(patsubst $(APPS_DIR)/%/main.c,%,$(shell find $(APPS_DIR) -name "main.c"))
# Don't automatically compile the benchmark app, which is only a wrapper around the other apps
BINARIES := $(filter-out bin/benchmarks, $(addprefix bin/,$(APPS)))

CVA6_EXTENSIONS := rv64ui rv64uc rv64um rv64uf rv64ud rv64si
# Atomics are messy, since there is currently no memory region capable of handling them
# CVA6_EXTENSIONS := rv64ua
CVA6_BINARIES := $(addprefix bin/, $(cva6_tests))
ARA_EXTENSIONS := rv64uv
ARA_BINARIES := $(addprefix bin/, $(ara_tests))

all: $(BINARIES)

# Pre-process the linker-script to correclty align the sections
.PHONY: linker_script
linker_script: $(COMMON_DIR)/script/align_sections.sh $(ROOT_DIR)/../../config/$(config).mk
	chmod +x $(COMMON_DIR)/script/align_sections.sh
	rm -f $(COMMON_DIR)/link.ld && cp $(COMMON_DIR)/arch.link.ld $(COMMON_DIR)/link.ld
	$(COMMON_DIR)/script/align_sections.sh $(nr_lanes) $(COMMON_DIR)/link.ld

# Make all applications
$(APPS): % : bin/% $(APPS_DIR)/Makefile $(shell find common -type f)
.PHONY: $(BINARIES)

define app_compile_template
bin/$1: $(addsuffix .o, $(shell find $(1) -name "*.c" -o -name "*.S")) $(RUNTIME_LLVM) linker_script
	mkdir -p bin/
	$$(RISCV_CC) -Iinclude $(RISCV_CCFLAGS) -o $$@ $(addsuffix .o, $(shell find $(1) -name "*.c" -o -name "*.S")) $(RUNTIME_LLVM) $$(RISCV_LDFLAGS) -T$$(CURDIR)/common/link.ld
	$$(RISCV_OBJDUMP) $$(RISCV_OBJDUMP_FLAGS) -D $$@ > $$@.dump
	$$(RISCV_STRIP) $$@ -S --strip-unneeded
endef
$(foreach app,$(APPS),$(eval $(call app_compile_template,$(app))))

# Make the RISC-V tests
riscv_tests: $(CVA6_BINARIES) $(ARA_BINARIES)

define rvtest_compile_template
TESTS_$(1) := $(addprefix bin/, $($(addsuffix _ara_tests, $1)))

bin/$(1)-ara-%: $(TESTS_DIR)/$(1)/%.$(2) $(RUNTIME_GCC) linker_script
	mkdir -p bin/
	$$(RISCV_CC_GCC) -Iinclude -I$$(TESTS_DIR)/macros/scalar -I$$(TESTS_DIR)/macros/vector $$(RISCV_CCFLAGS_GCC) $$(RISCV_LDFLAGS_GCC) -o $$@ $$< $(RUNTIME_GCC) -T$$(CURDIR)/common/link.ld
	$$(RISCV_OBJDUMP) $$(RISCV_OBJDUMP_FLAGS) -D $$@ > $$@.dump
	$$(RISCV_STRIP) $$@ -S --strip-unneeded
endef

define rvtest_compile_template_c
TESTS_$(1) := $(addprefix bin/, $($(addsuffix _ara_tests, $1)))

bin/$(1)-ara-%: $(TESTS_DIR)/$(1)/%.$(2) $(RUNTIME_LLVM) linker_script
	mkdir -p bin/
	$$(RISCV_CC) -Iinclude -I$$(TESTS_DIR)/macros/scalar -I$$(TESTS_DIR)/macros/vector $$(RISCV_CCFLAGS) $$(RISCV_LDFLAGS) -o $$@ $$< $(RUNTIME_LLVM) -T$$(CURDIR)/common/link.ld
	$$(RISCV_OBJDUMP) $$(RISCV_OBJDUMP_FLAGS) -D $$@ > $$@.dump
	$$(RISCV_STRIP) $$@ -S --strip-unneeded
endef
# CVA6 tests are written in assembly
$(foreach extension, $(CVA6_EXTENSIONS), $(eval $(call rvtest_compile_template,$(extension),S)))
# Ara tests are written in C
$(foreach extension, $(ARA_EXTENSIONS), $(eval $(call rvtest_compile_template_c,$(extension),c)))

# Run Spike tests
.PHONY: riscv_tests_spike
riscv_tests_spike:
	# Compile the tests
	PATH=$(GCC_INSTALL_DIR)/bin:$(LLVM_INSTALL_DIR)/bin:${PATH} ARA_DEFINES="$(DEFINES)" make -j4 -C riscv-tests/isa
	# Run the tests
	PATH=$(ISA_SIM_INSTALL_DIR)/bin:${PATH} make -C riscv-tests/isa run

# Format the sourcecode
.PHONY: format
format:
	$(LLVM_INSTALL_DIR)/bin/clang-format -style=file -i $$(find . | grep -E "\.[h,c,cpp]$$" | grep -v riscv-tests)
	$(LLVM_INSTALL_DIR)/bin/clang-format -style=file -i $$(find riscv-tests/isa/rv64uv | grep -E "\.[h,c,cpp]$$")

# Clean Spike simulation
.PHONY: riscv_tests_spike_clean
riscv_tests_spike_clean:
	make -C riscv-tests/isa clean

.PHONY: clean
clean: riscv_tests_spike_clean
	rm -vf $(BINARIES)
	rm -vf $(CVA6_BINARIES)
	rm -vf $(ARA_BINARIES)
	rm -vf $(addsuffix .dump,$(BINARIES))
	rm -vf $(addsuffix .dump,$(CVA6_BINARIES))
	rm -vf $(addsuffix .dump,$(ARA_BINARIES))
	rm -vf $(addsuffix /main.c.o,$(APPS))
	rm -vf $(RUNTIME_GCC)
	rm -vf $(RUNTIME_LLVM)
	for app in $(APPS); do cd $${app} && rm -f ./*.c.o && rm -f ./*.S.o && cd .. ; done

.INTERMEDIATE: $(addsuffix /main.c.o,$(APPS))
