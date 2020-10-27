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
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$ARA_DIR)
INSTALL_DIR := $(abspath $(ROOT_DIR)/../install)

# Include configuration
include $(abspath $(ROOT_DIR)/../config/config.mk)

# build path
buildpath      ?= build
resultpath     ?= results
# questa library
library        ?= work
# dpi library
dpi_library    ?= work-dpi
# Top level module to compile
top_level      ?= ara_tb
# QuestaSim Version
questa_version ?= 2020.1
# QuestaSim command
questa_cmd     ?= questa-$(questa_version)
# QuestaSim arguments
questa_args    ?=
# Path to the binaries
app_path       ?= $(abspath $(ROOT_DIR)/../apps/bin)

# Check if the specified QuestaSim version exists
ifeq (, $(shell which $(questa_cmd)))
  # Spaces are needed for indentation here!
  $(warning "Specified QuestaSim version ($(questa_cmd)) not found in PATH $(PATH)")
  questa_cmd =
endif

QUESTASIM_HOME ?= /usr/pack/questa-$(questa_version)-kgf/questasim

questa_args += +UVM_NO_RELNOTES
ifdef app
	preload ?= "$(app_path)/$(app)"
endif
ifdef preload
	questa_args += +PRELOAD=$(preload)
endif
questa_args += -sv_lib $(dpi_library)/ara_dpi -work $(library)
questa_args += -suppress vsim-3009

# DPI source files
dpi   := $(patsubst tb/dpi/%.cpp,$(buildpath)/$(dpi_library)/%.o,$(wildcard tb/dpi/*.cpp))

vlog_args += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233
vlog_args += -work $(library)
# Defines
vlog_args += +define+NR_LANES=$(nr_lanes) +define+VLEN=$(vlen) +define+VECTOR_EXTENSION_ARIANE=1

# Default target
all: compile

# Build path
$(buildpath):
	mkdir -p $(buildpath)

# Bender
bender:
	@[ -x ./bender ] && echo "Bender already exists." || \
	(command -v bender >/dev/null 2>&1 && ln -sf $$(command -v bender) ./bender || \
	curl --proto '=https' --tlsv1.2 -sSf https://iis-people.ee.ethz.ch/~andkurt/bender-init \
		| bash -s -- 0.19.0)
	@echo "$$(./bender --version) available."

# Library
.PHONY: lib
lib: $(buildpath) $(buildpath)/$(library)
$(buildpath)/$(library):
	cd $(buildpath) && $(questa_cmd) vlib $(library) && $(questa_cmd) vmap $(library) $(library)

# Compilation
.PHONY: compile
compile: dpi lib $(buildpath) $(buildpath)/compile.tcl | bender
$(buildpath)/compile.tcl: Makefile bender ../Bender.yml $(shell find src -type f) $(shell find tb -type f) $(shell find deps -type f)
	./bender script vsim --vlog-arg="$(vlog_args)" -t rtl -t asic -t ara_test -t test > $(buildpath)/compile.tcl
	echo "exit" >> $(buildpath)/compile.tcl
	cd $(buildpath) && $(questa_cmd) vsim -work $(library) -c -do compile.tcl

# Simulation
.PHONY: sim
sim: compile
	cd $(buildpath) && \
	$(questa_cmd) vsim $(questa_args) -voptargs=+acc $(library).$(top_level) -do ../scripts/run.do
	./scripts/return_status.sh $(buildpath)/transcript

.PHONY: simc
simc: compile
	cd $(buildpath) && \
	$(questa_cmd) vsim -c $(questa_args) $(library).$(top_level) -do "run -a"
	./scripts/return_status.sh $(buildpath)/transcript

# RISC-V Tests simulation
APPS_DIR := $(abspath $(ROOT_DIR)/../apps)
TESTS_DIR := $(APPS_DIR)/riscv-tests/isa
include $(APPS_DIR)/common/riscv_tests.mk

tests := $(cva6_tests) #$(ara_tests)

.PHONY: riscv_tests_simc
riscv_tests_simc: $(tests)

$(tests): rv%: $(app_path)/rv% compile
	cd $(buildpath) && \
	$(questa_cmd) vsim -c $(questa_args) +PRELOAD=$< $(library).$(top_level) -do "run -a"
	./scripts/return_status.sh $(buildpath)/transcript
	cp $(buildpath)/trace_hart_0.log $(buildpath)/$@.trace

# DPIs
.PHONY: dpi
dpi: $(buildpath)/$(dpi_library)/ara_dpi.so

$(buildpath)/$(dpi_library)/%.o: tb/dpi/%.cpp
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -fPIC -std=c++11 -Bsymbolic -c $< -I$(QUESTASIM_HOME)/include -o $@

$(buildpath)/$(dpi_library)/ara_dpi.so: $(dpi)
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -m64 -o $(buildpath)/$(dpi_library)/ara_dpi.so $?

# Clean targets
.PHONY: clean
clean:
	rm -rf $(buildpath)
	rm -f bender
