#!/usr/bin/env python3
# Copyright 2021 ETH Zurich and University of Bologna.
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

# arg1: vector size, arg2: filter size

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

def rand_matrix(N, dtype):
  return np.random.rand(N).astype(dtype)

############
## SCRIPT ##
############

if len(sys.argv) == 4:
  num_runs = int(sys.argv[1])
  cols = int(sys.argv[2])
  rows = int(sys.argv[3])
else:
  print("Error. Give me three arguments: num_runs, cols, and rows.")
  sys.exit()

dtype = np.int32
dmax  = np.iinfo(dtype).max

# Vector of samples
wall = np.random.randint(10, size=rows * cols, dtype=dtype)

# Buffers
result_s = np.zeros(cols, dtype=dtype)
result_v = np.zeros(cols, dtype=dtype)
src      = np.zeros(cols, dtype=dtype)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("num_runs", np.array(num_runs, dtype=np.uint32))
emit("rows", np.array(rows, dtype=np.uint32))
emit("cols", np.array(cols, dtype=np.uint32))
emit("wall",   wall,   'NR_LANES*4')
emit("result_s", result_s, 'NR_LANES*4')
emit("result_v", result_v, 'NR_LANES*4')
emit("src", src, 'NR_LANES*4')
