#!/usr/bin/env python3
# Copyright 2022 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
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

# arg1: box grid 1-dim size, arg2: alpha

import random as rand
import numpy as np
import sys

def emit(name, array, alignment='8'):
  print(".global %s" % name)
  print(".balign " + alignment)
  print("%s:" % name)
  bs = array.tobytes()
  for i in range(0, len(bs), 4):
    s = ""
    for n in range(4):
      s += "%02x" % bs[i+3-n]
    print("    .word 0x%s" % s)

############
## SCRIPT ##
############

if len(sys.argv) == 3:
  boxes1d = int(sys.argv[1])
  alpha   = sys.argv[2]
else:
  print("Error. Give me two arguments: one-dimension size of the grid, and alpha.")
  sys.exit()

dtype=np.float32

# Constants
NUMBER_PAR_PER_BOX = 96

##########################
## Dimension and memory ##
##########################

n_boxes  = boxes1d**3
n_elm    = n_boxes * NUMBER_PAR_PER_BOX
mem_elm  = n_elm * dtype(0).itemsize * 4
mem2_elm = n_elm * dtype(0).itemsize
# box_str is composed of 5 int, 1 long, 1 pointer
mem_box  = n_boxes * (5 * np.int32(0).itemsize + 2 * np.int64(0).itemsize)

###########
## Boxes ##
###########

range1d = np.arange(boxes1d, dtype=np.int32)

box_cpu_x      = np.reshape(np.transpose(np.tile(range1d, (         1, boxes1d**2))), (1, n_boxes))
box_cpu_y      = np.reshape(np.transpose(np.tile(range1d, (   boxes1d,    boxes1d))), (1, n_boxes))
box_cpu_z      = np.reshape(np.transpose(np.tile(range1d, (boxes1d**2,          1))), (1, n_boxes))
box_cpu_number = np.arange(n_boxes, dtype=np.int32)
box_cpu_offset = NUMBER_PAR_PER_BOX * box_cpu_number

# Check that this is not wider than int32, otherwise it's hard to print with the emit method!
assert all(np.iinfo(np.int32).min <= offset <= np.iinfo(np.int32).max for offset in box_cpu_offset)
# Append the MSbs to create a "long" dtype
box_cpu_offset_msb = np.zeros(np.shape(box_cpu_offset))

################
## Neighbours ##
################

n_nei_1d    = 3
n_nei       = n_nei_1d**3
range1d_nei = np.arange(-np.floor(n_nei_1d / 2), np.ceil(n_nei_1d / 2), dtype=np.int32)

# Helper vectors to find the neighbour coordinates
mod_nei_x = np.reshape(np.transpose(np.tile(range1d_nei, (          1, n_nei_1d**2))), (n_nei, 1))
mod_nei_y = np.reshape(np.transpose(np.tile(range1d_nei, (   n_nei_1d,    n_nei_1d))), (n_nei, 1))
mod_nei_z = np.reshape(np.transpose(np.tile(range1d_nei, (n_nei_1d**2,           1))), (n_nei, 1))

# Find the neighbour coordinates
nei_x          = np.tile(box_cpu_x, (n_nei, 1)) + mod_nei_x
nei_y          = np.tile(box_cpu_y, (n_nei, 1)) + mod_nei_y
nei_z          = np.tile(box_cpu_z, (n_nei, 1)) + mod_nei_z
nei_number     = nei_z * boxes1d**2 + nei_y * boxes1d + nei_x
nei_offset     = NUMBER_PAR_PER_BOX * nei_number

# Remove the neighbours equal to each reference particle
ref_idx        = int(np.floor(n_nei / 2))
nei_x          = np.delete(nei_x     , ref_idx, 0)
nei_y          = np.delete(nei_y     , ref_idx, 0)
nei_z          = np.delete(nei_z     , ref_idx, 0)
nei_number     = np.delete(nei_number, ref_idx, 0)
nei_offset     = np.delete(nei_offset, ref_idx, 0)

# Check that this is not wider than int32, otherwise it's hard to print with the emit method!
assert all(np.iinfo(np.int32).min <= offset <= np.iinfo(np.int32).max for col in nei_offset for offset in col)
# Append the MSbs to create a "long" dtype
nei_offset_msb = np.zeros(np.shape(nei_offset))

# Find how many neighbours are valid for each box
tmp0 = np.reshape(np.array([0 <= x < boxes1d for row in nei_x for x in row]), (n_nei-1, n_boxes))
tmp1 = np.reshape(np.array([0 <= y < boxes1d for row in nei_y for y in row]), (n_nei-1, n_boxes))
tmp2 = np.reshape(np.array([0 <= z < boxes1d for row in nei_z for z in row]), (n_nei-1, n_boxes))
tmp3 = np.logical_and(tmp0, tmp1)
is_valid_nn = np.logical_and(tmp2, tmp3)
box_nn_list = [sum(e[e==True]) for e in np.transpose(is_valid_nn)]
box_cpu_nn = np.array(box_nn_list).astype(np.int32)

# Fix wrongly calculated numbers and offsets
nei_number *= is_valid_nn
nei_offset *= is_valid_nn

############################################
## Parameters, distance, charge and force ##
############################################

rand.seed()
# Input distances
rv_cpu_v = np.random.uniform(low=0.1, high=1, size=(n_elm)).astype(dtype)
rv_cpu_x = np.random.uniform(low=0.1, high=1, size=(n_elm)).astype(dtype)
rv_cpu_y = np.random.uniform(low=0.1, high=1, size=(n_elm)).astype(dtype)
rv_cpu_z = np.random.uniform(low=0.1, high=1, size=(n_elm)).astype(dtype)

# Input charge
qv_cpu = np.random.uniform(low=0.1, high=1, size=(n_elm)).astype(dtype)

# Output forces
fv_cpu_v = np.zeros(n_elm).astype(dtype)
fv_cpu_x = np.zeros(n_elm).astype(dtype)
fv_cpu_y = np.zeros(n_elm).astype(dtype)
fv_cpu_z = np.zeros(n_elm).astype(dtype)

###################
## Final structs ##
###################

nn_mem = np.zeros((n_boxes * 6 * 26), dtype=np.int32)
nn_mem[0::6] = np.reshape(np.transpose(nei_x), 26 * n_boxes)
nn_mem[1::6] = np.reshape(np.transpose(nei_y), 26 * n_boxes)
nn_mem[2::6] = np.reshape(np.transpose(nei_z), 26 * n_boxes)
nn_mem[3::6] = np.reshape(np.transpose(nei_number), 26 * n_boxes)
nn_mem[4::6] = np.reshape(np.transpose(nei_offset), 26 * n_boxes)
nn_mem[5::6] = np.reshape(np.transpose(nei_offset_msb), 26 * n_boxes)

box_cpu_mem = np.zeros((7 + (6 * 26)) * n_boxes).astype(np.int32)
box_cpu_mem[0::(7 + (6 * 26))] = box_cpu_x
box_cpu_mem[1::(7 + (6 * 26))] = box_cpu_y
box_cpu_mem[2::(7 + (6 * 26))] = box_cpu_z
box_cpu_mem[3::(7 + (6 * 26))] = box_cpu_number
box_cpu_mem[4::(7 + (6 * 26))] = box_cpu_offset
box_cpu_mem[5::(7 + (6 * 26))] = box_cpu_offset_msb
box_cpu_mem[6::(7 + (6 * 26))] = box_cpu_nn
for i in range(0, n_boxes):
  box_cpu_mem[7 + i*(7 + 6 * 26):(i+1)*(7 + 6 * 26)] = nn_mem[i*(6 * 26):(i+1)*(6 * 26)];

rv_cpu_mem = np.zeros(4 * n_elm).astype(dtype)
rv_cpu_mem[0::4] = rv_cpu_v
rv_cpu_mem[1::4] = rv_cpu_x
rv_cpu_mem[2::4] = rv_cpu_y
rv_cpu_mem[3::4] = rv_cpu_z

qv_cpu_mem = qv_cpu.astype(dtype)

fv_cpu_mem = np.zeros(4 * n_elm).astype(dtype)
fv_cpu_mem[0::4] = fv_cpu_v
fv_cpu_mem[1::4] = fv_cpu_x
fv_cpu_mem[2::4] = fv_cpu_y
fv_cpu_mem[3::4] = fv_cpu_z

#####################
## Create the file ##
#####################

print(".section .data,\"aw\",@progbits")
emit("n_boxes", np.array(n_boxes, dtype=np.uint64))
emit("alpha", np.array(alpha, dtype=dtype))
emit("NUMBER_PAR_PER_BOX", np.array(NUMBER_PAR_PER_BOX, dtype=np.uint64))
emit("box_cpu_mem", box_cpu_mem, 'NR_LANES*4')
emit("rv_cpu_mem", rv_cpu_mem, 'NR_LANES*4')
emit("qv_cpu_mem", qv_cpu_mem, 'NR_LANES*4')
emit("fv_s_cpu_mem", fv_cpu_mem, 'NR_LANES*4')
emit("fv_v_cpu_mem", fv_cpu_mem, 'NR_LANES*4')
