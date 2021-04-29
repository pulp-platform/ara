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
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_LD ?= ld.lld
RISCV_LLVM ?= clang --sysroot=/scratch/mperotti/processor/ara/install/riscv-gcc/riscv64-unknown-elf/
RISCV_CC_OPTS ?= -mcmodel=medany -fvisibility=hidden -mno-relax
RISCV_CC_OPTS_C ?= -O2 -menable-experimental-extensions -mno-relax
LLVM_V_VERSION ?= v0p10
RISCV_LD_OPTS ?=
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data
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

$(src_dir)/../env/v/%-64.o: $(src_dir)/../env/v/%.c
	$(RISCV_LLVM) -c -march=rv64g -mabi=lp64 $(RISCV_CC_OPTS) -DENTROPY=0x$(shell echo \$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $< -o $@
$(src_dir)/../env/v/entry-64.o: $(src_dir)/../env/v/entry.S
	$(RISCV_LLVM) -c -march=rv64g -mabi=lp64 $(RISCV_CC_OPTS) -DENTROPY=0x$(shell echo \$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $< -o $@

$(src_dir)/../env/v/%-32.o: $(src_dir)/../env/v/%.c
	$(RISCV_LLVM) -c -march=rv32g -mabi=ilp32 $(RISCV_CC_OPTS) -DENTROPY=0x$(shell echo \$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $< -o $@
$(src_dir)/../env/v/entry-32.o: $(src_dir)/../env/v/entry.S
	$(RISCV_LLVM) -c -march=rv32g -mabi=ilp32 $(RISCV_CC_OPTS) -DENTROPY=0x$(shell echo \$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $< -o $@

define compile_template

$(1)$(2)$(3)-p-%.o: $(1)$(2)$(3)/%.S
	$$(RISCV_LLVM) -c $(4) $$(RISCV_CC_OPTS) -I$(src_dir)/../env/p -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $$< -o $$@
$$($(1)$(2)$(3)_p_tests): $(1)$(2)$(3)-p-%: $(1)$(2)$(3)-p-%.o
	$$(RISCV_LD) $$(RISCV_LD_OPTS) -T$(src_dir)/../env/p/link.ld $$^ -o $$@
$(1)$(2)$(3)_tests += $$($(1)$(2)$(3)_p_tests)

$(1)$(2)$(3)-v-%.o: $(1)$(2)$(3)/%.S
	$$(RISCV_LLVM) -c $(4) $$(RISCV_CC_OPTS) -DENTROPY=0x$$(shell echo \$$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -I$(src_dir)/../env/v -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector $$< -o $$@
$$($(1)$(2)$(3)_v_tests): $(1)$(2)$(3)-v-%: $(1)$(2)$(3)-v-%.o $(src_dir)/../env/v/entry-$(2).o $(addsuffix -$(2).o, $(basename $(wildcard $(src_dir)/../env/v/*.c)))
	$$(RISCV_LD) $$(RISCV_LD_OPTS) -T$(src_dir)/../env/v/link.ld $$^ -o $$@
$(1)$(2)$(3)_tests += $$($(1)$(2)$(3)_v_tests)

$(1)$(2)$(3)_tests_dump = $$(addsuffix .dump, $$($(1)$(2)$(3)_tests))

$(1)$(2)$(3): $$($(1)$(2)$(3)_tests_dump)

.PHONY: $(1)$(2)$(3)

tests += $$($(1)$(2)$(3)_tests)

endef

../benchmarks/common/syscalls-64.o: ../benchmarks/common/syscalls.c
	$(RISCV_LLVM) $(RISCV_CC_OPTS_C) -c -march=rv64g -mabi=lp64 -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -o $@ $<
../benchmarks/common/crt-64.o: ../benchmarks/common/crt.S
	$(RISCV_LLVM) $(RISCV_CC_OPTS_C) -c -march=rv64g -mabi=lp64 -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -o $@ $<

../benchmarks/common/syscalls-32.o: ../benchmarks/common/syscalls.c
	$(RISCV_LLVM) $(RISCV_CC_OPTS_C) -c -march=rv32g -mabi=ilp32 -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -o $@ $<
../benchmarks/common/crt-32.o: ../benchmarks/common/crt.S
	$(RISCV_LLVM) $(RISCV_CC_OPTS_C) -c -march=rv32g -mabi=ilp32 -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -o $@ $<

define compile_template_c

$(1)$(2)$(3)-p-%.o: $(1)$(2)$(3)/%.c
	$$(RISCV_LLVM) $$(RISCV_CC_OPTS_C) -c $(4)$$(LLVM_V_VERSION) -mcmodel=medany -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I../benchmarks/../env -I../benchmarks/common -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -o $$@ $$<
$$($(1)$(2)$(3)_p_tests): $(1)$(2)$(3)-p-%: $(1)$(2)$(3)-p-%.o ../benchmarks/common/syscalls-64.o ../benchmarks/common/crt-64.o
	$$(RISCV_LD) -static -O2 -nostdlib -T../benchmarks/common/test.ld -o $$@ $$^
$(1)$(2)$(3)_tests += $$($(1)$(2)$(3)_p_tests)

$(1)$(2)$(3)-v-%.o: $(1)$(2)$(3)/%.c
	$$(RISCV_LLVM) $$(RISCV_CC_OPTS_C) -c $(4)$$(LLVM_V_VERSION) -I../benchmarks/../env -I../benchmarks/common -DPREALLOCATE=1 -D__FLOAT_SUPPORT__ -D__SPIKE__=1 -mcmodel=medany-std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf -I$(src_dir)/macros/scalar -I$(src_dir)/macros/vector -o $$@ $$<
$$($(1)$(2)$(3)_v_tests): $(1)$(2)$(3)-v-%: $(1)$(2)$(3)-v-%.o ../benchmarks/common/syscalls-64.o ../benchmarks/common/crt-64.o
	$$(RISCV_LD) -static -O2 ../benchmarks/common/syscalls-64.o -nostdlib ../benchmarks/common/crt-64.o -T../benchmarks/common/test.ld -o $$@ $$^
$(1)$(2)$(3)_tests += $$($(1)$(2)$(3)_v_tests)

$(1)$(2)$(3)_tests_dump = $$(addsuffix .dump, $$($(1)$(2)$(3)_tests))

$(1)$(2)$(3): $$($(1)$(2)$(3)_tests_dump)

.PHONY: $(1)$(2)$(3)

tests += $$($(1)$(2)$(3)_tests)

endef

$(eval $(call compile_template,rv,32,ui,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,uc,-march=rv32gc -mabi=ilp32))
$(eval $(call compile_template,rv,32,um,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,ua,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,uf,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,ud,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,si,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv,32,mi,-march=rv32g -mabi=ilp32))
ifeq ($(XLEN),64)
$(eval $(call compile_template,rv,64,ui,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv,64,uc,-march=rv64gc -mabi=lp64))
$(eval $(call compile_template,rv,64,um,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv,64,ua,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv,64,uf,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv,64,ud,-march=rv64g -mabi=lp64))
$(eval $(call compile_template_c,rv,64,uv,-mabi=lp64 -march=rv64g))
$(eval $(call compile_template,rv,64,si,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv,64,mi,-march=rv64g -mabi=lp64))
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
