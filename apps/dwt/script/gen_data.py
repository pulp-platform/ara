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

############
## SCRIPT ##
############

if len(sys.argv) == 2:
  NDWT = int(sys.argv[1])
else:
  print("Error. Give me one argument: the number of vector elements.")
  sys.exit()

dtype = np.float32

# Vector of samples
data = np.random.rand(NDWT).astype(dtype);

# Buffer
buf = np.zeros(int(NDWT/2), dtype=dtype)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("DWT_LEN", np.array(NDWT, dtype=np.uint64))
emit("data_s", data, 'NR_LANES*4')
emit("data_v", data, 'NR_LANES*4')
emit("buf", buf, 'NR_LANES*4')
