#!/usr/bin/env bash

# Takes as input the number of lanes ($1), the num of cores ($2), and the linker script to process ($3)
# Align the sections by AxiWideBeWidth
# NB: this script modify ALL the ALIGN directives
let ALIGNMENT=4*$1*$2;
sed -i "s/ALIGNMENT/$ALIGNMENT/g" $3
