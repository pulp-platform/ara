# Copyright 2024 ETH Zurich and University of Bologna.
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

# Author: Matteo Perotti, ETH Zurich

# Variables for sequence length and number of sequences
SEQ_LENGTH ?= 6
NUM_SEQS ?= 10

# Python
PYTHON ?= python3

# Directories
SRC_DIR = src
SCRIPT_DIR = script
OUTPUT_DIR = ../rand_seq_autogen

# Source files
INSTRUCTIONS_FILE = $(SRC_DIR)/vinsn_list.txt
PYTHON_SCRIPT = $(SCRIPT_DIR)/vinsn_trace_gen.py
# Output files
OUTPUT_SEQ_FILE = $(OUTPUT_DIR)/vinsn_rand_seq.S
OUTPUT_MAIN_FILE = $(OUTPUT_DIR)/main.c

# Target to generate the sequences and main file
all: $(OUTPUT_DIR) $(OUTPUT_SEQ_FILE) $(OUTPUT_MAIN_FILE)

# Target to create the output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

$(OUTPUT_SEQ_FILE) $(OUTPUT_MAIN_FILE): $(INSTRUCTIONS_FILE) $(PYTHON_SCRIPT)
	$(PYTHON) $(PYTHON_SCRIPT) $(INSTRUCTIONS_FILE) $(OUTPUT_SEQ_FILE) $(SEQ_LENGTH) $(NUM_SEQS) $(OUTPUT_MAIN_FILE)

.PHONY: all clean
