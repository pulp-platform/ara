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
  N = int(sys.argv[1])
else:
  # Default: no stripmine
  N = 64

# Create the vectors
v64a = np.random.randn(N).astype(np.float64)
v64b = np.random.randn(N).astype(np.float64)
v32a = np.random.randn(N).astype(np.float32)
v32b = np.random.randn(N).astype(np.float32)
v16a = np.random.randn(N).astype(np.float16)
v16b = np.random.randn(N).astype(np.float16)

# Create the golden output
gold64 = reduce(lambda a, b: a+b, np.multiply(v64a, v64b))
gold32 = reduce(lambda a, b: a+b, np.multiply(v32a, v32b))
gold16 = reduce(lambda a, b: a+b, np.multiply(v16a, v16b))
gold16 = np.array([gold16, gold16])

# Create the empty result vectors
res64 = 0
res32 = 0
res16 = 0

# Print information on file
print(".section .data,\"aw\",@progbits")
emit("N", np.array(N, dtype=np.uint64))
emit("v64a", v64a, 'NR_LANES*4')
emit("v64b", v64b, 'NR_LANES*4')
emit("v32a", v32a, 'NR_LANES*4')
emit("v32b", v32b, 'NR_LANES*4')
emit("v16a", v16a, 'NR_LANES*4')
emit("v16b", v16b, 'NR_LANES*4')
emit("gold64", np.array(gold64, dtype=np.float64));
emit("gold32", np.array(gold32, dtype=np.float32));
emit("gold16", gold16, 'NR_LANES*4');
emit("res64_v", np.array(res64, dtype=np.float64));
emit("res32_v", np.array(res32, dtype=np.float32));
emit("res16_v", np.array(res16, dtype=np.float32));
emit("res64_s", np.array(res64, dtype=np.float64));
emit("res32_s", np.array(res32, dtype=np.float32));
emit("res16_s", np.array(res16, dtype=np.float32));
