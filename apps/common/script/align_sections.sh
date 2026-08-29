#!/usr/bin/env bash

# Takes as input the number of lanes ($1) and the linker script to process ($2)
# Align the sections by AxiWideBeWidth
# NB: this script modify ALL the ALIGN directives
let ALIGNMENT=4*$1;
tmp=$(mktemp)
sed "s/ALIGNMENT/$ALIGNMENT/g" "$2" > "$tmp" && mv "$tmp" "$2"
