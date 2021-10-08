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

# arg1: image size, arg2: filter size

import numpy as np
import scipy.signal
import sys

def rand_array(N, type, seed):
  np.random.seed(seed)
  if   type == 'float32_t':
    return np.ndarray.astype(np.random.rand(N) * 3.141, np.float32)
  elif type == 'int32_t':
    return np.ndarray.astype(np.random.rand(N) * 3.141, np.int32)

def rand_matrix(N, M, seed):
	return np.arange(seed, seed+N*M, dtype=np.float64).reshape(N, M) * 3.141

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

# Variables
Seed = 3

if len(sys.argv) > 1:
  N = sys.argv[1]
else:
  N = 1024

# Generate inputs
I     = rand_array(N, 'float32_t', Seed)
SCALE = rand_array(1, 'float32_t', Seed+1)[0]
SEL   = rand_array(N, 'int32_t', Seed)

# Create the empty o matrix
o = np.zeros(N).astype(np.float32)
o_gold = o

# Print information on file
print(".section .data,\"aw\",@progbits")
emit("N", np.array(N, dtype=np.uint64))
emit("SCALE", np.array(SCALE, dtype=np.float32))
emit("I", I, 'NR_LANES*4')
emit("SEL", SEL, 'NR_LANES*4')
emit("o", o, 'NR_LANES*4')
emit("o_gold", o_gold, 'NR_LANES*4')
