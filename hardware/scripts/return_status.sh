#!/usr/bin/env bash

# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Samuel Riedel <sriedel@iis.ee.ethz.ch>

RET=$(grep 'Info: Core Test' $1 | grep -Poh -- '(?<=\(tohost = )-?[0-9]+(?=\))')
[[ -z "${RET}" ]] && echo "Simulation did not finish" && exit 1
echo "Simulation returned ${RET}"
[[ "${RET}" -eq 0 ]] && exit 0 || exit 1
