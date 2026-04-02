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
# Generate input data for gemv benchmark
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

# Create the matrix
matrix64 = np.random.rand(avl64, avl64).astype(np.float64)

# Create the vector
vector64 = np.random.rand(avl64).astype(np.float64)

# Create the golden output
gold64 = vector64 @ matrix64

# Create the empty result vectors
result64 = np.zeros(avl64, dtype=np.float64)

# Print information on file
print(".section .l2,\"aw\",@progbits")
emit("M_ROW", np.array(vsize, dtype=np.uint64))
emit("V_LEN", np.array(vsize, dtype=np.uint64))
emit("gold64", gold64.astype(np.float64))
emit("mat64", matrix64, 'NR_LANES*4')
emit("vec64", vector64, 'NR_LANES*4')
emit("res64", result64, 'NR_LANES*4')
