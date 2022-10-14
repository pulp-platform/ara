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

# Author: Matteo Perotti

# C = AB with A=[MxN], B=[NxP], C=[MxP]
# arg1, arg2, arg3: M, N, P

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

if len(sys.argv) == 4:
  M = int(sys.argv[1])
  N = int(sys.argv[2])
  P = int(sys.argv[3])
else:
  print("Error. Give me three argument: M, N, P.")
  print("C = AB with A=[MxN], B=[NxP], C=[MxP]")
  sys.exit()

dtype = np.float64

# Matrices and results
A = np.random.rand(M, N).astype(dtype)
B = np.random.rand(N, P).astype(dtype)
C = np.zeros([M, P], dtype=dtype)
# Golden result matrix
G = np.matmul(A, B).astype(dtype)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("M", np.array(M, dtype=np.uint64))
emit("N", np.array(N, dtype=np.uint64))
emit("P", np.array(P, dtype=np.uint64))
emit("a", A, 'NR_LANES*4')
emit("b", B, 'NR_LANES*4')
emit("c", C, 'NR_LANES*4')
emit("g", G, 'NR_LANES*4')
