# Copyright 2018 ETH Zurich and University of Bologna.
#
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Fabian Schuiki <fschuiki@iis.ee.ethz.ch>

# Compiling to 32 or 64 bits
ARCH    ?= 64

# Compilers
CC       = riscv$(ARCH)-unknown-elf-gcc
CXX      = riscv$(ARCH)-unknown-elf-g++

RVBLAS   ?= rvblas/rvblas

INCLUDES = -Iinclude/ -I$(RVBLAS)/include
CFLAGS   = -O2 -mcmodel=medany -march=rv64imav -std=gnu99 -ffast-math -fno-common -fno-builtin-printf -static -nostartfiles -nostdlib -lm -lgcc -T runtime/link.ld $(INCLUDES) -L$(RVBLAS)/lib/
LFLAGS   = runtime/crt.S runtime/syscalls.c

export CC
export CXX
export AR
export AS
export INCLUDES
export CFLAGS

SRCEXT   = c
SRCDIR   = src
OBJDIR   = obj
BINDIR   = bin
DATDIR   = datasets

export BINDIR

SRCS        := $(shell find $(SRCDIR) -name '*.$(SRCEXT)')
SRCDIRS     := $(shell find . -name '*.$(SRCEXT)' -exec dirname {} \; | uniq)
OBJS        := $(patsubst %.$(SRCEXT), $(OBJDIR)/%.o, $(SRCS))
DEPS        := $(OBJS:.o=.d)
SETS        := $(shell ls $(DATDIR))
APPS_SCALAR := $(addprefix scalar_,$(SETS))
APPS_VECTOR := $(addprefix vector_,$(SETS))

.PHONY: all kernel clean distclean

# all: $(addprefix $(BINDIR)/,$(APPS_VECTOR))
all: $(addprefix $(BINDIR)/,$(APPS_SCALAR)) $(addprefix $(BINDIR)/,$(APPS_VECTOR))

$(BINDIR)/scalar_%: buildrepo $(OBJS)
	@echo "Generating $@..."
	@mkdir -p `dirname $@`
	@$(CC) $(CFLAGS) -o $@ $(OBJDIR)/src/$(firstword $(subst _, ,$*)).o $(DATDIR)/$*/data.S $(LFLAGS) -lrvblasscalar

$(BINDIR)/vector_%: buildrepo $(OBJS)
	@echo "Generating $@..."
	@mkdir -p `dirname $@`
	@$(CC) $(CFLAGS) -o $@ $(OBJDIR)/src/$(firstword $(subst _, ,$*)).o $(DATDIR)/$*/data.S $(LFLAGS) -lrvblas

-include $(DEPS)

$(OBJDIR)/%.o: %.$(SRCEXT)
	@echo "Generating dependencies for $<..."
	@$(CC) -c $< -MM -MF $(patsubst %.o, %.d, $@) -MT $@ $(INCLUDES)
	@echo "Compiling $<..."
	@$(CC) -o $@ $(CFLAGS) -c $<

datasets: scripts/generate.py
	python3 $< $(DATDIR)

clean:
	@$(RM) -r $(OBJDIR)

distclean: clean
	@$(RM) -r $(BINDIR)

buildrepo:
	@$(call make-repo)

define make-repo
  for dir in $(SRCDIRS); do   \
    mkdir -p $(OBJDIR)/$$dir; \
  done
endef
