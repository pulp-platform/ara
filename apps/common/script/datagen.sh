#!/usr/bin/env bash

# Define default values if they were not set before
OUTPUT_MATRIX_SIZE="${OUT_MTX_SIZE:-112}"
FILTER_SIZE="${F_SIZE:-7}"
# Generate options for gen_data.py
# OUT_MTX_SIZE F_SIZE
OPTIONS="$OUTPUT_MATRIX_SIZE $FILTER_SIZE"
# Generate the data
python3 script/gen_data.py ${OPTIONS} > data.S
