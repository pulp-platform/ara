#=======================================================================
# UCB VLSI FLOW: Makefile for riscv-bmarks
#-----------------------------------------------------------------------
# Yunsup Lee (yunsup@cs.berkeley.edu)
#

XLEN ?= 64

default: all

src_dir = .

instname = riscv-bmarks
instbasedir = $(UCB_VLSI_HOME)/install

#--------------------------------------------------------------------
# Sources
#--------------------------------------------------------------------

bmarks =  \
	dropout \
	conv2d

#--------------------------------------------------------------------
# Build rules
#--------------------------------------------------------------------

RISCV_PREFIX ?= riscv$(XLEN)-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
# From -O2 we get a very weird error in SPIKE RVV 0.10 when executing memcpy. SPIKE reads an instruction differently from what I see in the disassembly and get an illegal instruction exception. Give "r" to "spike -d" to reproduce the issue.
GCC_OPT_LV ?= -O2
RISCV_GCC_OPTS ?= -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 $(GCC_OPT_LV) -ffast-math -fno-common -fno-builtin-printf -march=rv64gcv -mabi=lp64
RISCV_LINK ?= $(RISCV_GCC) -T $(src_dir)/common/test.ld $(incs)
RISCV_LINK_OPTS ?= -static -nostdlib -nostartfiles -lm -lgcc -T $(src_dir)/common/test.ld
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data
RISCV_SIM ?= spike --isa=rv$(XLEN)gcv_Zfh --varch="vlen:4096,elen:64,slen:4096" $(SPIKE_FLAG)
PYTHON ?= python3.7
DEFINES += -DSPIKE

incs  += -I$(src_dir)/../env -I$(src_dir)/common $(addprefix -I$(src_dir)/, $(bmarks))
objs  :=

# Commented out since each benchmark can have different recipes
# define compile_template
# $(1).riscv: $(wildcard $(src_dir)/$(1)/*) $(wildcard $(src_dir)/common/*)
# 	$$(RISCV_GCC) $$(incs) $$(RISCV_GCC_OPTS) -o $$@ $(wildcard $(src_dir)/$(1)/*.c) $(wildcard $(src_dir)/$(1)/common/*.S) $(wildcard $(src_dir)/common/*.c) $(wildcard $(src_dir)/common/*.S) $$(RISCV_LINK_OPTS)
# endef
#
# $(foreach bmark,$(bmarks),$(eval $(call compile_template,$(bmark))))

dropout.riscv: dropout_gen_data $(wildcard $(src_dir)/dropout/*.c) $(wildcard $(src_dir)/dropout/*.h) $(wildcard $(src_dir)/dropout/*.S)
	$(RISCV_GCC) $(incs) $(RISCV_GCC_OPTS) $(DEFINES) -o $@ $(wildcard $(src_dir)/dropout/*.c) $(wildcard $(src_dir)/dropout/*.S) $(wildcard $(src_dir)/common/*.c) $(wildcard $(src_dir)/common/*.S) $(RISCV_LINK_OPTS)

.PHONY: dropout_gen_data
dropout_gen_data: $(src_dir)/dropout/data.c
$(src_dir)/dropout/data.c: $(src_dir)/dropout/script/gen_data.py $(src_dir)/dropout/data.c
	$(PYTHON) $< > $@

conv2d.riscv: conv2d_gen_data $(wildcard $(src_dir)/conv2d/*.c) $(wildcard $(src_dir)/conv2d/*.h) $(wildcard $(src_dir)/conv2d/*.S)
	$(RISCV_GCC) $(incs) $(RISCV_GCC_OPTS) $(DEFINES) -o $@ $(wildcard $(src_dir)/conv2d/*.c) $(src_dir)/conv2d/data.S $(wildcard $(src_dir)/common/*.c) $(wildcard $(src_dir)/common/*.S) $(RISCV_LINK_OPTS)

FILTER_SIZE ?= 3
.PHONY: conv2d_gen_data
conv2d_gen_data:
	$(PYTHON) $(src_dir)/conv2d/script/gen_data.py $(FILTER_SIZE) > $(src_dir)/conv2d/data.S

#------------------------------------------------------------
# Build and run benchmarks on riscv simulator

bmarks_riscv_bin  = $(addsuffix .riscv,  $(bmarks))
bmarks_riscv_dump = $(addsuffix .riscv.dump, $(bmarks))
bmarks_riscv_out  = $(addsuffix .riscv.out,  $(bmarks))

$(bmarks_riscv_dump): %.riscv.dump: %.riscv
	$(RISCV_OBJDUMP) $< > $@

$(bmarks_riscv_out): %.riscv.out: %.riscv
	$(RISCV_SIM) $< > $@

riscv: $(bmarks_riscv_dump)
run: $(bmarks_riscv_out)

junk += $(bmarks_riscv_bin) $(bmarks_riscv_dump) $(bmarks_riscv_hex) $(bmarks_riscv_out)

#------------------------------------------------------------
# Default

all: riscv

#------------------------------------------------------------
# Install

date_suffix = $(shell date +%Y-%m-%d_%H-%M)
install_dir = $(instbasedir)/$(instname)-$(date_suffix)
latest_install = $(shell ls -1 -d $(instbasedir)/$(instname)* | tail -n 1)

install:
	mkdir $(install_dir)
	cp -r $(bmarks_riscv_bin) $(bmarks_riscv_dump) $(install_dir)

install-link:
	rm -rf $(instbasedir)/$(instname)
	ln -s $(latest_install) $(instbasedir)/$(instname)

#------------------------------------------------------------
# Clean up

clean:
	rm -rf $(objs) $(junk)
