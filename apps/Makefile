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
# This will overwrite the ROOT_DIR variable from the included makefile
include $(ROOT_DIR)/common/runtime.mk

APPS := $(patsubst $(APPS_DIR)/%/main.c,%,$(shell find $(APPS_DIR) -name "main.c"))
BINARIES := $(addprefix bin/,$(APPS))

# Make all applications
all: $(BINARIES)

$(APPS): % : bin/% $(APPS_DIR)/Makefile $(shell find common -type f)

.PHONY: $(BINARIES)
$(BINARIES): bin/%: %/main.c.o $(RUNTIME)
	mkdir -p $(shell dirname $@)
	$(RISCV_CC) -Iinclude $(RISCV_LDFLAGS) -o $@ $^ -T$(CURDIR)/common/link.ld
	$(RISCV_OBJDUMP) $(RISCV_OBJDUMP_FLAGS) -D $@ > $@.dump
	$(RISCV_STRIP) $@ -S --strip-unneeded

.PHONY: clean
clean:
	rm -vf $(BINARIES)
	rm -vf $(addsuffix .dump,$(BINARIES))
	rm -vf $(addsuffix /main.c.o,$(APPS))
	rm -vf $(RUNTIME)

.INTERMEDIATE: $(addsuffix /main.c.o,$(APPS))
