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
#
# Generate input data for fdotp benchmark
# arg: #elements per vector

import numpy as np
import random
from functools import reduce
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

# Vector length
if len(sys.argv) > 1:
  vsize = int(sys.argv[1])
else:
  # Default: no stripmine
  vsize = 64

avl64 = int(vsize)
# avl32 = int(vsize)
# avl16 = int(vsize)

# Create the vectors
v64x = np.random.rand(avl64).astype(np.float64)
v64y = np.random.rand(avl64).astype(np.float64)
# v32x = np.random.rand(avl32).astype(np.float32)
# v32y = np.random.rand(avl32).astype(np.float32)
# v16x = np.random.rand(avl16).astype(np.float16)
# v16y = np.random.rand(avl16).astype(np.float16)

# Create the scalar number a
a = np.random.rand(1).astype(np.float64)

# Create the golden output
gold64 = a * v64x + v64y
# gold32 = a * v32x + v32y
# gold16 = a * v16x + v16y

# Print information on file
print(".section .host,\"aw\",@progbits")
emit("vsize", np.array(vsize, dtype=np.uint64))
emit("a", np.array(a, dtype=np.float64))
emit("gold64", np.array(gold64, dtype=np.float64));
# emit("gold32", np.array(gold32, dtype=np.float32));
# emit("gold16", gold16, 'NR_LANES*8');
print(".section .vector,\"aw\",@progbits")
emit("v64x", v64x, 'NR_LANES*8')
emit("v64y", v64y, 'NR_LANES*8')
# emit("v32x", v32a, 'NR_LANES*8')
# emit("v32y", v32b, 'NR_LANES*8')
# emit("v16x", v16a, 'NR_LANES*8')
# emit("v16y", v16b, 'NR_LANES*8')
