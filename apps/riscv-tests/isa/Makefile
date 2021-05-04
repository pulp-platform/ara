#=======================================================================
# Makefile for riscv-tests/isa
#-----------------------------------------------------------------------

XLEN ?= 64

src_dir := .

ifeq ($(XLEN),64)
include $(src_dir)/rv64ui/Makefrag
include $(src_dir)/rv64uc/Makefrag
include $(src_dir)/rv64um/Makefrag
include $(src_dir)/rv64ua/Makefrag
include $(src_dir)/rv64uf/Makefrag
include $(src_dir)/rv64ud/Makefrag
include $(src_dir)/rv64uv/Makefrag
include $(src_dir)/rv64si/Makefrag
include $(src_dir)/rv64mi/Makefrag
endif
include $(src_dir)/rv32ui/Makefrag
include $(src_dir)/rv32uc/Makefrag
include $(src_dir)/rv32um/Makefrag
include $(src_dir)/rv32ua/Makefrag
include $(src_dir)/rv32uf/Makefrag
include $(src_dir)/rv32ud/Makefrag
include $(src_dir)/rv32si/Makefrag
include $(src_dir)/rv32mi/Makefrag

default: all

#--------------------------------------------------------------------
# Build rules
#--------------------------------------------------------------------

RISCV_PREFIX ?= riscv$(XLEN)-unknown-elf-
LLVM_ROOT ?= $(LLVM_INSTALL_DIR)/bin/
RISCV_LD ?= ld.lld
RISCV_LLVM ?= clang -fuse-ld=lld
RISCV_CC_OPTS ?= -mcmodel=medany -fvisibility=hidden -mno-relax
RISCV_CC_OPTS_C ?= -O2 -menable-experimental-extensions -mno-relax
LLVM_V_VERSION ?= v0p10
RISCV_LD_OPTS ?= -nostdlib -nostartfiles
RISCV_OBJDUMP ?= $(LLVM_ROOT)llvm-objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data
RISCV_SIM ?= spike

vpath %.S $(src_dir)

#------------------------------------------------------------
# Build assembly tests

%.dump: %
	$(RISCV_OBJDUMP) $< > $@

%.out: %
	$(RISCV_SIM) --isa=rv64gcv --varch="vlen:4096,elen:64,slen:4096" $< 2> $@

%.out32: %
	$(RISCV_SIM) --isa=rv32gcv $< 2> $@

%.cout: %
	$(RISCV_SIM) --isa=rv64gcv_zfh --varch="vlen:4096,elen:64,slen:4096" $< 2> $@

%.cout32: %
	$(RISCV_SIM) --isa=rv32gcv $< 2> $@

define compile_template

$$($(1)_p_tests): $(1)-p-%: $(1)/%.S
	$$(RISCV_LLVM) $(2) $(3) $$(RISCV_CC_OPTS) -I$(src_dir)/../env/p -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $$(RISCV_LD_OPTS) -T$(src_dir)/../env/p/link.ld $$< -o $$@
$(1)_tests += $$($(1)_p_tests)

$$($(1)_v_tests): $(1)-v-%: $(1)/%.S $(src_dir)/../env/v/entry.S $(wildcard $(src_dir)/../env/v/*.c)
	$$(RISCV_LLVM) $(2) $(3) $$(RISCV_CC_OPTS) -DENTROPY=0x$$(shell echo \$$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $$(RISCV_LD_OPTS) -T$(src_dir)/../env/v/link.ld $$^ -o $$@
$(1)_tests += $$($(1)_v_tests)

$(1)_tests_dump = $$(addsuffix .dump, $$($(1)_tests))

$(1): $$($(1)_tests_dump)

.PHONY: $(1)

tests += $$($(1)_tests)

endef

define compile_template_c

$$($(1)_p_tests): $(1)-p-%: $(1)/%.c ../benchmarks/common/crt.S ../benchmarks/common/syscalls.c
	$$(RISCV_LLVM) $$(RISCV_CC_OPTS_C) $(2)$$(LLVM_V_VERSION) $(3) -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 $$(RISCV_LD_OPTS) -static -O2 -nostdlib -T../benchmarks/common/test.ld -o $$@ $$^
$(1)_tests += $$($(1)_p_tests)

$$($(1)_v_tests): $(1)-v-%: $(1)/%.c ../benchmarks/common/crt.S ../benchmarks/common/syscalls.c
	$$(RISCV_LLVM) $$(RISCV_CC_OPTS_C) $(2)$$(LLVM_V_VERSION) $(3) -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 $$(RISCV_LD_OPTS) -static -O2 -nostdlib -T../benchmarks/common/test.ld -o $$@ $$^
$(1)_tests += $$($(1)_v_tests)

$(1)_tests_dump = $$(addsuffix .dump, $$($(1)_tests))

$(1): $$($(1)_tests_dump)

.PHONY: $(1)

tests += $$($(1)_tests)

endef

$(eval $(call compile_template,rv32ui,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32uc,-march=rv32gc, -mabi=ilp32))
$(eval $(call compile_template,rv32um,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32ua,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32uf,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32ud,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32si,-march=rv32g, -mabi=ilp32))
$(eval $(call compile_template,rv32mi,-march=rv32g, -mabi=ilp32))
ifeq ($(XLEN),64)
$(eval $(call compile_template,rv64ui,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64uc,-march=rv64gc, -mabi=lp64))
$(eval $(call compile_template,rv64um,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64ua,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64uf,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64ud,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template_c,rv64uv,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64si,-march=rv64g, -mabi=lp64))
$(eval $(call compile_template,rv64mi,-march=rv64g, -mabi=lp64))
endif

tests_dump = $(addsuffix .dump, $(tests))
tests_hex = $(addsuffix .hex, $(tests))
tests_o = $(addsuffix .o, $(tests))
tests_out = $(addsuffix .out, $(spike_tests))
tests32_out = $(addsuffix .out32, $(spike32_tests))
tests_cout = $(addsuffix .cout, $(spike_ctests))
tests32_cout = $(addsuffix .cout32, $(spike32_ctests))

run: $(tests_out) $(tests32_out) $(tests_cout) $(tests32_cout)

junk += $(tests) $(tests_dump) $(tests_hex) $(tests_out) $(tests32_out) $(tests_cout) $(tests32_cout) $(tests_o)

#------------------------------------------------------------
# Default

all: $(tests_dump)

#------------------------------------------------------------
# Clean up

clean:
	rm -rf $(junk)
