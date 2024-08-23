# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$ARA_DIR)
INSTALL_DIR := $(abspath $(ROOT_DIR)/../install)
VERILATOR_INCLUDE := $(INSTALL_DIR)/verilator/share/verilator/include/vltstd

BENDER         := $(ROOT_DIR)/../hardware/bender
BENDER_VERSION := 0.27.3

# Choose Ara's configuration
ifndef config
	ifdef ARA_CONFIGURATION
		config := $(ARA_CONFIGURATION)
	else
		config := default
	endif
endif

# Include configuration
config_file := $(ROOT_DIR)/../config/$(config).mk
include $(abspath $(ROOT_DIR)/../config/$(config).mk)

# Clang flags for Verilator command
ifneq (${CLANG_PATH},)
	CLANG_CXXFLAGS := -CFLAGS "-nostdinc++ -isystem $(CLANG_PATH)/include/c++/v1"
	CLANG_LDFLAGS  := -LDFLAGS "-L $(CLANG_PATH)/lib -Wl,-rpath,$(CLANG_PATH)/lib -lc++ -nostdlib++"
else
	CLANG_CXXFLAGS := ""
	CLANG_LDFLAGS  := ""
endif

# build path
buildpath      ?= build
resultpath     ?= results
# questa library
library        ?= work
# dpi library
dpi_library    ?= work-dpi
# verilator library
veril_library  ?= $(buildpath)/verilator
# verilator path
veril_path     ?= $(abspath $(INSTALL_DIR)/verilator/bin)
# verilator top-level
veril_top      ?= ara_tb_verilator
# Top level module to compile
top_level      ?= ara_tb
# Questa version
ifeq ($(vcd_dump), 1)
  questa_version ?= 2019.3
else
  questa_version ?= 2021.2
endif
# QuestaSim command
questa_cmd     ?= questa-$(questa_version)
# QuestaSim arguments
questa_args    ?=
# Path to the binaries
app_path       ?= $(abspath $(ROOT_DIR)/../apps/bin)
# Path to ideal dispatcher vtraces
vtrace_path    ?= $(abspath $(ROOT_DIR)/../apps/ideal_dispatcher/vtrace)

ideal          ?=
ifeq ($(ideal_dispatcher), 1)
  vtrace       = $(vtrace_path)/$(app).vtrace
  bender_defs += --define IDEAL_DISPATCHER=1 --define VTRACE="$(vtrace)" --define N_VINSN=$(shell wc -l $(vtrace) | cut -d " " -f 1)
  ideal        = "_ideal"
endif

ifeq ($(vcd_dump), 1)
  vcd_path    ?= ../vcd/$(app).vcd
  bender_defs += --define VCD_DUMP=1 --define VCD_PATH=$(vcd_path)
endif

# Check if the specified QuestaSim version exists
ifeq (, $(shell which $(questa_cmd)))
  # Spaces are needed for indentation here!
  $(warning "Specified QuestaSim version ($(questa_cmd)) not found in PATH $(PATH)")
  questa_cmd =
endif

questa_args += +UVM_NO_RELNOTES
ifdef app
ifeq ($(ideal_dispatcher), 1)
	preload ?= "$(app_path)/$(app).ideal"
else
	preload ?= "$(app_path)/$(app)"
endif
endif
ifdef preload
	questa_args += +PRELOAD=$(preload)
endif
questa_args += -sv_lib $(dpi_library)/ara_dpi -work $(library) -voptargs=+acc
questa_args += -suppress vsim-3009 -suppress vopt-7033

# DPI source files
dpi   := $(patsubst tb/dpi/%.cc,$(buildpath)/$(dpi_library)/%.o,$(wildcard tb/dpi/*.cc))

vlog_args += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233
vlog_args += -work $(library)

# Bender
# Defines
bender_defs += --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen) --define ARIANE_ACCELERATOR_PORT=1
bender_defs_veril := $(bender_defs) --define COMMON_CELLS_ASSERTS_OFF
# Targets
bender_common_targs := -t rtl -t cv64a6_imafdcv_sv39 -t tech_cells_generic_include_tc_sram -t tech_cells_generic_include_tc_clk
bender_targs_simc     := $(bender_common_targs) -t ara_test -t cva6_test
bender_targs_veril    := $(bender_common_targs) -t ara_test -t cva6_test -t verilator
bender_targs_spyglass := $(bender_common_targs) -t spyglass

# Default target
all: compile

# Build path
$(buildpath):
	mkdir -p $(buildpath)

.PHONY: bender update
# Bender
bender: $(BENDER)
$(BENDER):
	@[ -x $(BENDER) ] && echo "Bender already exists." || \
	curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh	-s -- $(BENDER_VERSION)
	@echo "$$(./bender --version) available."

update: $(BENDER) $(ROOT_DIR)/../Bender.yml
	rm -rf $(ROOT_DIR)/../hardware/deps/*
	$(BENDER) update -f
	$(BENDER) checkout

checkout: $(BENDER)
	$(BENDER) checkout

# Patches
.PHONY: apply-patches
apply-patches: patches
	cd deps/tech_cells_generic && git apply ../../patches/0001-tech-cells-generic-sram.patch

# Library
.PHONY: lib
lib: $(buildpath) $(buildpath)/$(library)
$(buildpath)/$(library):
	cd $(buildpath) && $(questa_cmd) vlib $(library) && $(questa_cmd) vmap $(library) $(library)

# Compilation
.PHONY: compile
compile: dpi lib $(buildpath) bender $(buildpath)/compile_$(config).tcl
$(buildpath)/compile_$(config).tcl: $(config_file) Makefile ../Bender.yml $(shell find src -type f) $(shell find ../config -type f) $(shell find include -type f) $(shell find tb -type f) $(shell find deps -type f)
	$(BENDER) script vsim --vlog-arg="$(vlog_args)" $(bender_targs_simc) $(bender_defs) > $(buildpath)/compile_$(config).tcl
	echo "exit" >> $(buildpath)/compile_$(config).tcl
	cd $(buildpath) && $(questa_cmd) vsim -work $(library) -c -do compile_$(config).tcl
	# Rename the file if compilation did not succeed
	if [ `cat $(buildpath)/transcript | grep "\*\* Error" | wc -l` -ne 0 ]; then mv $(buildpath)/compile_$(config).tcl $(buildpath)/compile_$(config).tcl.ERROR; fi

# Simulation
.PHONY: sim
sim: compile
	cd $(buildpath) && \
	$(questa_cmd) vsim $(questa_args) $(library).$(top_level) -do ../scripts/run$(ideal).tcl
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

tests := $(ara_tests) $(cva6_tests)

# Verilator
.PHONY: verilate
verilate: $(buildpath) bender $(veril_library)/V$(veril_top)

$(veril_library)/V$(veril_top): $(config_file) Makefile ../Bender.yml $(shell find src -type f) $(shell find ../config -type f) $(shell find include -type f) $(shell find tb -type f) $(shell find deps -type f)
	rm -rf $(veril_library); mkdir -p $(veril_library)
	$(BENDER) script verilator $(bender_targs_veril) $(bender_defs_veril) > $(veril_library)/bender_script_$(config)
# Verilate the design
	$(veril_path)/verilator -f $(veril_library)/bender_script_$(config)           \
  -GNrLanes=$(nr_lanes)                                                         \
  -GVLEN=$(vlen)                                                                \
  -O3                                                                           \
  --hierarchical \
  -Wno-fatal                                                                    \
  -Wno-PINCONNECTEMPTY                                                          \
  -Wno-BLKANDNBLK                                                               \
  -Wno-CASEINCOMPLETE                                                           \
  -Wno-CMPCONST                                                                 \
  -Wno-LATCH                                                                    \
  -Wno-LITENDIAN                                                                \
  -Wno-UNOPTFLAT                                                                \
  -Wno-UNPACKED                                                                 \
  -Wno-UNSIGNED                                                                 \
  -Wno-WIDTH                                                                    \
  -Wno-WIDTHCONCAT                                                              \
  -Wno-ENUMVALUE                                                                \
  -Wno-COMBDLY                                                                  \
  tb/verilator/waiver.vlt                                                       \
  --Mdir $(veril_library)                                                       \
  -Itb/dpi                                                                      \
  --compiler clang                                                              \
  -CFLAGS "-DTOPLEVEL_NAME=$(veril_top)"                                        \
  -CFLAGS "-DNR_LANES=$(nr_lanes)"                                              \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_dpi/cpp       \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_verilator/cpp \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_simutil_verilator/cpp \
  $(CLANG_CXXFLAGS)                                                             \
  -LDFLAGS "-lelf"                                                              \
  $(CLANG_LDFLAGS)                                                              \
  --exe                                                                         \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_dpi/cpp/*.cc            \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_verilator/cpp/*.cc      \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_simutil_verilator/cpp/*.cc      \
  $(ROOT_DIR)/tb/verilator/ara_tb.cpp                                           \
  --cc                                                                          \
  $(if $(trace),--trace-fst -Wno-INSECURE,)                                     \
  --top-module $(veril_top) &&                                                  \
	cd $(veril_library) && OBJCACHE='' make -j4 -f V$(veril_top).mk

# Simulation
.PHONY: simv
simv:
	$(veril_library)/V$(veril_top) $(if $(trace),-t,) -l ram,$(app_path)/$(app),elf

.PHONY: riscv_tests_simv
riscv_tests_simv: $(tests)

$(tests): rv%: $(app_path)/rv%
	$(veril_library)/V$(veril_top) $(if $(trace),-t,) -l ram,$<,elf &> $(buildpath)/$@.trace

# Lint
.PHONY: lint spyglass/tmp/files

SNPS_SG ?= spyglass-2022.06
lint: spyglass/tmp/files spyglass/sdc/func.sdc spyglass/scripts/run_lint.tcl
	cd spyglass; $(SNPS_SG) sg_shell -tcl scripts/run_lint.tcl

spyglass/tmp/files: $(bender)
	mkdir -p spyglass/tmp
	$(BENDER) script verilator $(bender_targs_spyglass) $(bender_defs) --define SPYGLASS > spyglass/tmp/files

# DPIs
.PHONY: dpi
dpi: $(buildpath)/$(dpi_library)/ara_dpi.so

$(buildpath)/$(dpi_library)/%.o: tb/dpi/%.cc
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -fPIC -std=c++11 -Bsymbolic -c $< -I$(VERILATOR_INCLUDE) -I$(INSTALL_DIR)/riscv-isa-sim/include -o $@

$(buildpath)/$(dpi_library)/ara_dpi.so: $(dpi)
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -m64 -o $(buildpath)/$(dpi_library)/ara_dpi.so $?

# Clean targets
.PHONY: clean
clean:
	rm -rf $(buildpath)
	rm -f  $(BENDER)
