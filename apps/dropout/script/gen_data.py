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
import random
import sys

def rand_array(N, dtype):
  return np.random.rand(N).astype(dtype);

def rand_sel(N, dtype):
  return np.random.randint(0, 256, N, dtype)

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

if len(sys.argv) > 1:
  N = int(sys.argv[1])
else:
  N = 1024

# Generate inputs
I     = rand_array(N, np.float32)
SCALE = rand_array(1, np.float32)[0]
SEL   = rand_sel(N, np.uint8)

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
