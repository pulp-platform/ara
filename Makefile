# Author: Florian Zaruba, ETH Zurich
# Author: Matheus Cavalcante, ETH Zurich
# Date: 03/19/2017
# Description: Makefile for linting and testing Ara/Ariane.

# questa library
library        ?= work
# verilator lib
ver-library    ?= work-ver
# library for DPI
dpi-library    ?= work-dpi
# Top level module to compile
top_level      ?= core_tb
# Maximum amount of cycles for a successful simulation run
max_cycles     ?= 10000000
# Test case to run
test_case      ?= core_test
# QuestaSim Version
questa_version ?= -10.7b
# verilator version
verilator      ?= verilator
# traget option
target-options ?=
# additional definess
defines        ?= +define+WT_DCACHE
# test name for torture runs (binary name)
test-location  ?= deps/ariane/output/test
# set to either nothing or -log
torture-logs   :=
# custom elf bin to run with sim or sim-verilator
elf-bin        ?= deps/ariane/tmp/riscv-tests/build/benchmarks/dhrystone.riscv
# root path
mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
root-dir := $(dir $(mkfile_path))

support_verilator_4 := $(shell (verilator --version | grep '4\.') &> /dev/null; echo $$?)
ifeq ($(support_verilator_4), 0)
	verilator_threads := 2
endif

ifndef RISCV
$(error RISCV not set - please point your RISCV variable to your RISCV installation)
endif

# spike tandem verification
ifdef spike-tandem
    compile_flag += -define SPIKE_TANDEM
    ifndef preload
        $(error Tandem verification requires preloading)
    endif
endif

# Ara parameters
VRF_SIZE       ?= 131072
VRF_NBANKS     ?= 8
OPQ_DEPTH      ?= 4
ADDRQ_DEPTH    ?= 4
NR_LANES       ?= 4

# Sources
# Package files -> compile first
ariane_pkg := deps/ariane/include/riscv_pkg.sv                          \
              deps/ariane/src/riscv-dbg/src/dm_pkg.sv                   \
              deps/ariane/include/ariane_pkg.sv                         \
              deps/ariane/include/std_cache_pkg.sv                      \
              deps/ariane/include/wt_cache_pkg.sv                       \
              deps/ariane/src/axi/src/axi_pkg.sv                        \
              deps/ariane/src/register_interface/src/reg_intf.sv        \
              deps/ariane/src/axi/src/axi_intf.sv                       \
              deps/ariane/tb/ariane_soc_pkg.sv                          \
              deps/ariane/include/ariane_axi_pkg.sv                     \
              deps/ariane/src/fpu/src/pkg/fpnew_pkg.vhd                 \
              deps/ariane/src/fpu/src/pkg/fpnew_fmts_pkg.vhd            \
              deps/ariane/src/fpu/src/pkg/fpnew_comps_pkg.vhd           \
              deps/ariane/src/fpu/src/pkg/fpnew_pkg_constants.vhd       \
              deps/ariane/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv \
              deps/ariane/src/ara_frontend/ara_frontend_pkg.sv          \
              include/ara_pkg.sv                                        \
              include/ara_axi_pkg.sv
ariane_pkg := $(addprefix $(root-dir), $(ariane_pkg))

# utility modules
util := $(wildcard deps/ariane/src/util/*.svh)                            \
        deps/ariane/src/util/instruction_tracer_pkg.sv                    \
        deps/ariane/src/util/instruction_tracer_if.sv                     \
        deps/ariane/src/tech_cells_generic/src/cluster_clock_gating.sv    \
        deps/ariane/tb/common/mock_uart.sv                                \
        deps/ariane/src/util/sram.sv

ifdef spike-tandem
    util += deps/ariane/tb/common/spike.sv
endif

util := $(addprefix $(root-dir), $(util))
# Test packages
test_pkg := $(wildcard deps/ariane/tb/test/*/*sequence_pkg.sv*) \
            $(wildcard deps/ariane/tb/test/*/*_pkg.sv*)
# DPI
dpi_list := $(patsubst deps/ariane/tb/dpi/%.cc,${dpi-library}/%.o,$(wildcard deps/ariane/tb/dpi/*.cc))
# filter spike stuff if tandem is not activated
ifndef spike-tandem
    dpi = $(filter-out ${dpi-library}/spike.o ${dpi-library}/sim_spike.o, $(dpi_list))
else
    dpi = $(dpi_list)
endif
dpi_hdr := $(wildcard deps/ariane/tb/dpi/*.h)
dpi_hdr := $(addprefix $(root-dir), $(dpi_hdr))
CFLAGS := -I$(QUESTASIM_HOME)/include         \
          -I$(RISCV)/include  \
          -I../tb/dpi

ifdef spike-tandem
    CFLAGS += -Itb/riscv-isa-sim/install/include/spike
endif

# this list contains the standalone components
src :=  $(wildcard src/*.sv)                                                       \
        $(wildcard src/lane/*.sv)                                                  \
        $(wildcard src/slide/*.sv)                                                 \
        $(wildcard src/vlsu/*.sv)                                                  \
        $(wildcard src/util/*.sv)                                                  \
        $(filter-out deps/ariane/src/ariane_regfile.sv,                            \
        $(wildcard deps/ariane/src/*.sv))                                          \
        $(wildcard deps/ariane/src/fpu/src/utils/*.vhd)                            \
        $(wildcard deps/ariane/src/fpu/src/ops/*.vhd)                              \
        $(wildcard deps/ariane/src/fpu/src/subunits/*.vhd)                         \
        deps/ariane/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv                  \
        $(wildcard deps/ariane/src/fpu_div_sqrt_mvp/hdl/*.sv)                      \
        $(filter-out deps/ariane/src/ara_frontend/ara_frontend_pkg.sv,             \
        $(wildcard deps/ariane/src/ara_frontend/*.sv))                             \
        $(wildcard deps/ariane/src/frontend/*.sv)                                  \
        $(filter-out deps/ariane/src/cache_subsystem/std_no_dcache.sv,             \
        $(wildcard deps/ariane/src/cache_subsystem/*.sv))                          \
        $(wildcard deps/ariane/bootrom/*.sv)                                       \
        $(wildcard deps/ariane/src/clint/*.sv)                                     \
        $(wildcard deps/ariane/fpga/src/axi2apb/src/*.sv)                          \
        $(wildcard deps/ariane/fpga/src/axi_slice/src/*.sv)                        \
        $(wildcard deps/ariane/src/plic/*.sv)                                      \
        $(wildcard deps/ariane/src/axi_node/src/*.sv)                              \
        $(wildcard deps/ariane/src/axi_riscv_atomics/src/*.sv)                     \
        $(wildcard deps/ariane/src/axi_mem_if/src/*.sv)                            \
        deps/ariane/src/fpu/src/fpnew.vhd                                          \
        deps/ariane/src/fpu/src/fpnew_top.vhd                                      \
        deps/ariane/src/fpu_div_sqrt_mvp/hdl/fpu_ff.sv                             \
        deps/ariane/src/riscv-dbg/src/dmi_cdc.sv                                   \
        deps/ariane/src/riscv-dbg/src/dmi_jtag.sv                                  \
        deps/ariane/src/riscv-dbg/src/dmi_jtag_tap.sv                              \
        deps/ariane/src/riscv-dbg/src/dm_csrs.sv                                   \
        deps/ariane/src/riscv-dbg/src/dm_mem.sv                                    \
        deps/ariane/src/riscv-dbg/src/dm_sba.sv                                    \
        deps/ariane/src/riscv-dbg/src/dm_top.sv                                    \
        deps/ariane/src/riscv-dbg/debug_rom/debug_rom.sv                           \
        deps/ariane/src/register_interface/src/apb_to_reg.sv                       \
        deps/ariane/src/axi/src/axi_multicut.sv                                    \
        deps/ariane/src/common_cells/src/deprecated/generic_fifo.sv                \
        deps/ariane/src/common_cells/src/deprecated/pulp_sync.sv                   \
        deps/ariane/src/common_cells/src/deprecated/find_first_one.sv              \
        deps/ariane/src/common_cells/src/popcount.sv                               \
        deps/ariane/src/common_cells/src/rstgen_bypass.sv                          \
        deps/ariane/src/common_cells/src/rstgen.sv                                 \
        deps/ariane/src/common_cells/src/stream_mux.sv                             \
        deps/ariane/src/common_cells/src/stream_demux.sv                           \
        deps/ariane/src/common_cells/src/stream_arbiter.sv                         \
        deps/ariane/src/common_cells/src/stream_arbiter_flushable.sv               \
        deps/ariane/src/util/axi_master_connect.sv                                 \
        deps/ariane/src/util/axi_slave_connect.sv                                  \
        deps/ariane/src/util/axi_master_connect_rev.sv                             \
        deps/ariane/src/util/axi_slave_connect_rev.sv                              \
        deps/ariane/src/axi/src/axi_cut.sv                                         \
        deps/ariane/src/axi/src/axi_join.sv                                        \
        deps/ariane/src/axi/src/axi_delayer.sv                                     \
        deps/ariane/src/axi/src/axi_to_axi_lite.sv                                 \
        deps/ariane/src/axi/src/axi_data_width_converter.sv                        \
        deps/ariane/src/axi/src/axi_data_upsize.sv                                 \
        deps/ariane/src/axi/src/axi_data_downsize.sv                               \
        deps/ariane/src/fpga-support/rtl/SyncSpRamBeNx64.sv                        \
        deps/ariane/src/common_cells/src/sync.sv                                   \
        deps/ariane/src/common_cells/src/cdc_2phase.sv                             \
        deps/ariane/src/common_cells/src/spill_register.sv                         \
        deps/ariane/src/common_cells/src/sync_wedge.sv                             \
        deps/ariane/src/common_cells/src/edge_detect.sv                            \
        deps/ariane/src/common_cells/src/fifo_v3.sv                                \
        deps/ariane/src/common_cells/src/fifo_v2.sv                                \
        deps/ariane/src/common_cells/src/fifo_v1.sv                                \
        deps/ariane/src/common_cells/src/lzc.sv                                    \
        deps/ariane/src/common_cells/src/rrarbiter.sv                              \
        deps/ariane/src/common_cells/src/stream_delay.sv                           \
        deps/ariane/src/common_cells/src/lfsr_8bit.sv                              \
        deps/ariane/src/common_cells/src/lfsr_16bit.sv                             \
        deps/ariane/src/common_cells/src/counter.sv                                \
        deps/ariane/src/common_cells/src/shift_reg.sv                              \
        deps/ariane/src/common_cells/src/id_queue.sv                               \
        deps/ariane/src/common_cells/src/onehot_to_bin.sv                          \
        deps/ariane/src/tech_cells_generic/src/cluster_clock_inverter.sv           \
        deps/ariane/src/tech_cells_generic/src/pulp_clock_mux2.sv                  \
        deps/ariane/src/tech_cells_generic/src/pulp_clock_gating.sv                \
        deps/ariane/tb/ariane_peripherals.sv                                       \
        deps/ariane/tb/common/uart.sv                                              \
        deps/ariane/tb/common/SimDTM.sv                                            \
        deps/ariane/tb/common/SimJTAG.sv                                           \
        tb/ara_testharness.sv                                                      \
        tb/core_tb.sv

src := $(addprefix $(root-dir), $(src))

uart_src := $(wildcard deps/ariane/fpga/src/apb_uart/src/*.vhd)
uart_src := $(addprefix $(root-dir), $(uart_src))

fpga_src :=  $(wildcard fpga/src/*.sv) $(wildcard fpga/src/bootrom/*.sv) $(wildcard fpga/src/ariane-ethernet/*.sv)
fpga_src := $(addprefix $(root-dir), $(fpga_src))

# look for testbenches
tbs := tb/ara_tb.sv tb/ara_testharness.sv
# RISCV asm tests and benchmark setup (used for CI)
# there is a defined test-list with selected CI tests
riscv-test-dir            := tmp/riscv-tests/isa
riscv-benchmarks-dir      := tmp/riscv-tests/benchmarks
riscv-asm-tests-list      := deps/ariane/ci/riscv-asm-tests.list
riscv-amo-tests-list      := deps/ariane/ci/riscv-amo-tests.list
riscv-mul-tests-list      := deps/ariane/ci/riscv-mul-tests.list
riscv-fp-tests-list       := deps/ariane/ci/riscv-fp-tests.list
riscv-benchmarks-list     := deps/ariane/ci/riscv-benchmarks.list
riscv-asm-tests           := $(shell xargs printf '\n%s' < $(riscv-asm-tests-list)  | cut -b 1-)
riscv-amo-tests           := $(shell xargs printf '\n%s' < $(riscv-amo-tests-list)  | cut -b 1-)
riscv-mul-tests           := $(shell xargs printf '\n%s' < $(riscv-mul-tests-list)  | cut -b 1-)
riscv-fp-tests            := $(shell xargs printf '\n%s' < $(riscv-fp-tests-list)   | cut -b 1-)
riscv-benchmarks          := $(shell xargs printf '\n%s' < $(riscv-benchmarks-list) | cut -b 1-)

# Search here for include files (e.g.: non-standalone components)
incdir := deps/ariane/src/common_cells/include/common_cells
# Compile and sim flags
# Ara's defines
defines          += +define+ARA_VRF_SIZE=$(VRF_SIZE) +define+ARA_VRF_NBANKS=$(VRF_NBANKS) +define+ARA_OPQ_DEPTH=$(OPQ_DEPTH) +define+ARA_ADDRQ_DEPTH=$(ADDRQ_DEPTH) +define+ARA_NR_LANES=$(NR_LANES)
compile_flag     += +cover=bcfst+/dut -incr -64 -nologo -quiet -suppress 13262 -permissive $(defines)
uvm-flags        += +UVM_NO_RELNOTES +UVM_VERBOSITY=LOW
questa-flags     += -t 1ns -64 -coverage -classdebug $(gui-sim) $(QUESTASIM_FLAGS)
compile_flag_vhd += -64 -nologo -quiet -2008

# Iterate over all include directories and write them with +incdir+ prefixed
# +incdir+ works for Verilator and QuestaSim
list_incdir := $(foreach dir, ${incdir}, +incdir+$(dir))

# RISCV torture setup
riscv-torture-dir    := tmp/riscv-torture
# old java flags  -Xmx1G -Xss8M -XX:MaxPermSize=128M
# -XshowSettings -Xdiag
riscv-torture-bin    := java -jar sbt-launch.jar

# if defined, calls the questa targets in batch mode
ifdef batch-mode
  questa-flags += -c
  questa-cmd   := -do "coverage save -onexit tmp/$@.ucdb; run -a; quit -code [coverage attribute -name TESTSTATUS -concise]"
  questa-cmd   += -do " log -r /*; run -all;"
else
  questa-cmd   := -do " do tb/wave/wave_core.do; run -all;"
endif
# we want to preload the memories
ifdef preload
	questa-cmd += +PRELOAD=$(preload)
	elf-bin = none
endif

ifdef spike-tandem
    questa-cmd += -gblso tb/riscv-isa-sim/install/lib/libriscv.so
endif

# remote bitbang is enabled
ifdef rbb
	questa-cmd += +jtag_rbb_enable=1
else
	questa-cmd += +jtag_rbb_enable=0
endif

# Build the TB and module using QuestaSim
build: $(library) $(library)/.build-srcs $(library)/.build-tb $(dpi-library)/ariane_dpi.so
	# Optimize top level
	vopt$(questa_version) $(compile_flag) -work $(library)  $(top_level) -o $(top_level)_optimized +acc -check_synthesis

# src files
$(library)/.build-srcs: $(util) $(library)
	vlog$(questa_version) $(compile_flag) -work $(library) $(filter %.sv,$(ariane_pkg)) $(list_incdir) -suppress 2583
	vcom$(questa_version) $(compile_flag_vhd) -work $(library) -pedanticerrors $(filter %.vhd,$(ariane_pkg))
	vlog$(questa_version) $(compile_flag) -work $(library) $(filter %.sv,$(util)) $(list_incdir) -suppress 2583
	# Suppress message that always_latch may not be checked thoroughly by QuestaSim.
	vcom$(questa_version) $(compile_flag_vhd) -work $(library) -pedanticerrors $(filter %.vhd,$(uart_src))
	vcom$(questa_version) $(compile_flag_vhd) -work $(library) -pedanticerrors $(filter %.vhd,$(src))
	vlog$(questa_version) $(compile_flag) -work $(library) -pedanticerrors $(filter %.sv,$(src)) $(list_incdir) -suppress 2583
	touch $(library)/.build-srcs

# build TBs
$(library)/.build-tb: $(dpi)
	# Compile top level
	vlog$(questa_version) $(compile_flag) -sv $(tbs) -work $(library)
	touch $(library)/.build-tb

$(library):
	vlib${questa_version} $(library)

# compile DPIs
$(dpi-library)/%.o: deps/ariane/tb/dpi/%.cc $(dpi_hdr)
	mkdir -p $(dpi-library)
	$(CXX) -shared -m64 -fPIC -std=c++0x -Bsymbolic $(CFLAGS) -c $< -o $@

$(dpi-library)/ariane_dpi.so: $(dpi)
	mkdir -p $(dpi-library)
	# Compile C-code and generate .so file
	$(CXX) -shared -m64 -o $(dpi-library)/ariane_dpi.so $? -L$(RISCV)/lib -Wl,-rpath,$(RISCV)/lib -lfesvr

# single test runs on Questa can be started by calling make <testname>, e.g. make towers.riscv
# the test names are defined in ci/riscv-asm-tests.list, and in ci/riscv-benchmarks.list
# if you want to run in batch mode, use make <testname> batch-mode=1
# alternatively you can call make sim elf-bin=<path/to/elf-bin> in order to load an arbitrary binary
sim: build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +MAX_CYCLES=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) $(QUESTASIM_FLAGS) -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi  \
	${top_level}_optimized +permissive-off ++$(elf-bin) ++$(target-options) | tee sim.log

simc: build
	vsim${questa_version} +permissive $(questa-flags) -c $(questa-cmd) -lib  $(library) +MAX_CYCLES=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) $(QUESTASIM_FLAGS) -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi  \
	${top_level}_optimized +permissive-off ++$(elf-bin) ++$(target-options) | tee sim.log

$(riscv-asm-tests): build
	vsim${questa_version} +permissive $(questa-flags) -c $(questa-cmd) +PRELOAD=$(riscv-test-dir)/$@ -lib $(library) +max-cycles=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) +jtag_rbb_enable=0  -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi        \
	${top_level}_optimized $(QUESTASIM_FLAGS) +permissive-off ++none ++$(target-options) | tee tmp/riscv-asm-tests-$@.log

$(riscv-amo-tests): build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) +jtag_rbb_enable=0  -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi        \
	${top_level}_optimized $(QUESTASIM_FLAGS) +permissive-off ++$(riscv-test-dir)/$@ ++$(target-options) | tee tmp/riscv-amo-tests-$@.log

$(riscv-mul-tests): build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) +jtag_rbb_enable=0  -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi        \
	${top_level}_optimized $(QUESTASIM_FLAGS) +permissive-off ++$(riscv-test-dir)/$@ ++$(target-options) | tee tmp/riscv-mul-tests-$@.log

$(riscv-fp-tests): build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-test-dir) $(uvm-flags) +jtag_rbb_enable=0  -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi        \
	${top_level}_optimized $(QUESTASIM_FLAGS) +permissive-off ++$(riscv-test-dir)/$@ ++$(target-options) | tee tmp/riscv-fp-tests-$@.log

$(riscv-benchmarks): build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles) +UVM_TESTNAME=$(test_case) \
	+BASEDIR=$(riscv-benchmarks-dir) $(uvm-flags) +jtag_rbb_enable=0 -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi   \
	${top_level}_optimized $(QUESTASIM_FLAGS) +permissive-off ++$(riscv-benchmarks-dir)/$@ ++$(target-options) | tee tmp/riscv-benchmarks-$@.log

# can use -jX to run ci tests in parallel using X processes
run-asm-tests: $(riscv-asm-tests)
	$(MAKE) check-asm-tests

run-amo-tests: $(riscv-amo-tests)
	$(MAKE) check-amo-tests

run-mul-tests: $(riscv-mul-tests)
	$(MAKE) check-mul-tests

run-fp-tests: $(riscv-fp-tests)
	$(MAKE) check-fp-tests

check-asm-tests:
	deps/ariane/ci/check-tests.sh tmp/riscv-asm-tests- $(shell wc -l $(riscv-asm-tests-list) | awk -F " " '{ print $1 }')

check-amo-tests:
	deps/ariane/ci/check-tests.sh tmp/riscv-amo-tests- $(shell wc -l $(riscv-amo-tests-list) | awk -F " " '{ print $1 }')

check-mul-tests:
	deps/ariane/ci/check-tests.sh tmp/riscv-mul-tests- $(shell wc -l $(riscv-mul-tests-list) | awk -F " " '{ print $1 }')

check-fp-tests:
	deps/ariane/ci/check-tests.sh tmp/riscv-fp-tests- $(shell wc -l $(riscv-fp-tests-list) | awk -F " " '{ print $1 }')

# can use -jX to run ci tests in parallel using X processes
run-benchmarks: $(riscv-benchmarks)
	$(MAKE) check-benchmarks

check-benchmarks:
	deps/ariane/ci/check-tests.sh tmp/riscv-benchmarks- $(shell wc -l $(riscv-benchmarks-list) | awk -F " " '{ print $1 }')

# verilator-specific
verilate_command := $(verilator)                                                           \
                    $(filter-out %.vhd, $(ariane_pkg))                                     \
                    $(filter-out src/fpu_wrap.sv, $(filter-out %.vhd, $(src)))             \
                    $(defines)                                                             \
                    deps/ariane/src/util/sram.sv                                           \
                    +incdir+src/axi_node                                                   \
                    --unroll-count 256                                                     \
                    -Werror-PINMISSING                                                     \
                    -Werror-IMPLICIT                                                       \
                    -Wno-fatal                                                             \
                    -Wno-PINCONNECTEMPTY                                                   \
                    -Wno-ASSIGNDLY                                                         \
                    -Wno-DECLFILENAME                                                      \
                    -Wno-UNOPTFLAT                                                         \
                    -Wno-UNUSED                                                            \
                    -Wno-style                                                             \
                    -Wno-lint                                                              \
                    $(if $(DEBUG),--trace-structs --trace,)                                \
                    -LDFLAGS "-L$(RISCV)/lib -Wl,-rpath,$(RISCV)/lib -lfesvr"              \
                    -CFLAGS "$(CFLAGS)" -Wall --cc  --vpi                                  \
                    $(list_incdir) --top-module ariane_testharness                         \
                    --Mdir $(ver-library) -O3                                              \
                    --exe deps/ariane/tb/ariane_tb.cpp deps/ariane/tb/dpi/SimDTM.cc        \
                    deps/ariane/tb/dpi/SimJTAG.cc deps/ariane/tb/dpi/remote_bitbang.cc     \
                    deps/ariane/tb/dpi/msim_helper.cc

# User Verilator, at some point in the future this will be auto-generated
verilate:
	@echo "[Verilator] Building Model$(if $(PROFILE), for Profiling,)"
	$(verilate_command)
	cd $(ver-library) && $(MAKE) -j${NUM_JOBS} -f Variane_testharness.mk

sim-verilator: verilate
	$(ver-library)/Variane_testharness $(elf-bin)

$(addsuffix -verilator,$(riscv-asm-tests)): verilate
	$(ver-library)/Variane_testharness $(riscv-test-dir)/$(subst -verilator,,$@)

$(addsuffix -verilator,$(riscv-amo-tests)): verilate
	$(ver-library)/Variane_testharness $(riscv-test-dir)/$(subst -verilator,,$@)

$(addsuffix -verilator,$(riscv-mul-tests)): verilate
	$(ver-library)/Variane_testharness $(riscv-test-dir)/$(subst -verilator,,$@)

$(addsuffix -verilator,$(riscv-fp-tests)): verilate
	$(ver-library)/Variane_testharness $(riscv-test-dir)/$(subst -verilator,,$@)

$(addsuffix -verilator,$(riscv-benchmarks)): verilate
	$(ver-library)/Variane_testharness $(riscv-benchmarks-dir)/$(subst -verilator,,$@)

run-asm-tests-verilator: $(addsuffix -verilator, $(riscv-asm-tests)) $(addsuffix -verilator, $(riscv-amo-tests)) $(addsuffix -verilator, $(riscv-fp-tests)) $(addsuffix -verilator, $(riscv-fp-tests))

# split into two halfs for travis jobs (otherwise they will time out)
run-asm-tests1-verilator: $(addsuffix -verilator, $(filter rv64ui-v-% ,$(riscv-asm-tests)))

run-asm-tests2-verilator: $(addsuffix -verilator, $(filter-out rv64ui-v-% ,$(riscv-asm-tests)))

run-amo-verilator: $(addsuffix -verilator, $(riscv-amo-tests))

run-mul-verilator: $(addsuffix -verilator, $(riscv-mul-tests))

run-fp-verilator: $(addsuffix -verilator, $(riscv-fp-tests))

run-benchmarks-verilator: $(addsuffix -verilator,$(riscv-benchmarks))

# torture-specific
torture-gen:
	cd $(riscv-torture-dir) && $(riscv-torture-bin) 'generator/run'

torture-itest:
	cd $(riscv-torture-dir) && $(riscv-torture-bin) 'testrun/run -a output/test.S'

torture-rtest: build
	cd $(riscv-torture-dir) && printf "#!/bin/sh\ncd $(root-dir) && $(MAKE) run-torture$(torture-logs) batch-mode=1 defines=$(defines) test-location=$(test-location)" > call.sh && chmod +x call.sh
	cd $(riscv-torture-dir) && $(riscv-torture-bin) 'testrun/run -r ./call.sh -a $(test-location).S' | tee $(test-location).log
	make check-torture test-location=$(test-location)

torture-dummy: build
	cd $(riscv-torture-dir) && printf "#!/bin/sh\ncd $(root-dir) && $(MAKE) run-torture batch-mode=1 defines=$(defines) test-location=\$${@: -1}" > call.sh

torture-rnight: build
	cd $(riscv-torture-dir) && printf "#!/bin/sh\ncd $(root-dir) && $(MAKE) run-torture$(torture-logs) batch-mode=1 defines=$(defines) test-location=\$${@: -1}" > call.sh && chmod +x call.sh
	cd $(riscv-torture-dir) && $(riscv-torture-bin) 'overnight/run -r ./call.sh -g none' | tee output/overnight.log
	$(MAKE) check-torture

torture-rtest-verilator: verilate
	cd $(riscv-torture-dir) && printf "#!/bin/sh\ncd $(root-dir) && $(MAKE) run-torture-verilator batch-mode=1 defines=$(defines)" > call.sh && chmod +x call.sh
	cd $(riscv-torture-dir) && $(riscv-torture-bin) 'testrun/run -r ./call.sh -a output/test.S' | tee output/test.log
	$(MAKE) check-torture

run-torture: build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles)+UVM_TESTNAME=$(test_case)                                  \
	+BASEDIR=$(riscv-torture-dir) $(uvm-flags) +jtag_rbb_enable=0 -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi                                      \
	${top_level}_optimized +permissive-off +signature=$(riscv-torture-dir)/$(test-location).rtlsim.sig ++$(riscv-torture-dir)/$(test-location) ++$(target-options)

run-torture-log: build
	vsim${questa_version} +permissive $(questa-flags) $(questa-cmd) -lib $(library) +max-cycles=$(max_cycles)+UVM_TESTNAME=$(test_case)                                  \
	+BASEDIR=$(riscv-torture-dir) $(uvm-flags) +jtag_rbb_enable=0 -gblso $(RISCV)/lib/libfesvr.so -sv_lib $(dpi-library)/ariane_dpi                                      \
	${top_level}_optimized +permissive-off +signature=$(riscv-torture-dir)/$(test-location).rtlsim.sig ++$(riscv-torture-dir)/$(test-location) ++$(target-options)
	cp vsim.wlf $(riscv-torture-dir)/$(test-location).wlf
	cp trace_hart_0000.log $(riscv-torture-dir)/$(test-location).trace
	cp trace_hart_0000_commit.log $(riscv-torture-dir)/$(test-location).commit
	cp transcript $(riscv-torture-dir)/$(test-location).transcript

run-torture-verilator: verilate
	$(ver-library)/Variane_testharness +max-cycles=$(max_cycles) +signature=$(riscv-torture-dir)/output/test.rtlsim.sig $(riscv-torture-dir)/output/test

check-torture:
	grep 'All signatures match for $(test-location)' $(riscv-torture-dir)/$(test-location).log
	diff -s $(riscv-torture-dir)/$(test-location).spike.sig $(riscv-torture-dir)/$(test-location).rtlsim.sig

build-spike:
	cd tb/riscv-isa-sim && mkdir -p build && cd build && ../configure --prefix=`pwd`/../install --with-fesvr=$(RISCV) --enable-commitlog && make -j8 install

clean:
	rm -rf $(riscv-torture-dir)/output/test*
	rm -rf $(library)/ $(dpi-library)/ $(ver-library)/
	rm -f tmp/*.ucdb tmp/*.log *.wlf *vstf wlft* *.ucdb

.PHONY:
	build sim sim-verilate clean                                              \
	$(riscv-asm-tests) $(addsuffix _verilator,$(riscv-asm-tests))             \
	$(riscv-benchmarks) $(addsuffix _verilator,$(riscv-benchmarks))           \
	check-benchmarks check-asm-tests                                          \
	torture-gen torture-itest torture-rtest                                   \
	run-torture run-torture-verilator check-torture check-torture-verilator
