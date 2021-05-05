#!/usr/bin/env bash

# Takes as input the number of lanes ($1) and the linker script to process ($2)
# Align the sections by AxiWideBeWidth
let ALIGNMENT=4*$1;
sed -i "s/: ALIGN([0-9]*) {/: ALIGN($ALIGNMENT) {/g" $2
