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

if len(sys.argv) == 3:
  channels = int(sys.argv[1])
  innerSize = int(sys.argv[2])
else:
  print("Error. Give me two arguments: the number of channels and the inner size.")
  sys.exit()

# Vector of samples
i = rand_matrix(channels * innerSize, np.float32).astype(np.float32)

# Results buffer
buf = np.zeros(channels * innerSize, dtype=np.float32)
o_s = np.zeros(channels * innerSize, dtype=np.float32)
o_g = np.zeros(channels * innerSize, dtype=np.float32)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("channels", np.array(channels, dtype=np.uint64))
emit("innerSize", np.array(innerSize, dtype=np.uint64))
emit("i", i, 'NR_LANES*4')
emit("buf", i, 'NR_LANES*4')
emit("o_s", i, 'NR_LANES*4')
emit("o_v", i, 'NR_LANES*4')
