# Copyright 2021 ETH Zurich and University of Bologna.
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

#
# Parameters
#

# Element width
SEW ?= 64
# Matrix size
SIZE ?= 64
# Exercises
EX1 ?= 0
EX2 ?= 0
EX3 ?= 0
EX4 ?= 0

#
# Defines
#

DEFINES += "-DSIZE=$(SIZE) -DSEW=$(SEW) -DEX1=$(EX1) -DEX2=$(EX2) -DEX3=$(EX3) -DEX4=$(EX4)"

# Default target
.PHONY: all
all: compile run

.PHONY: compile
compile: clean
	DEFINES=$(DEFINES) make -C .. bin/ara_training

.PHONY: run
run:
	app=ara_training make -C ../../hardware simv

.PHONY: clean
clean:
	rm -rf `find . -name "*.o"`
