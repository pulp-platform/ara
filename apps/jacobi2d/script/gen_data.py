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
  R = int(sys.argv[1])
  C = int(sys.argv[2])
else:
  print("Error. Give me one argument: the number of vector elements.")
  sys.exit()

dtype = np.float64

TSTEPS = 1

# Fill in the extra data to align the matrices to 4*NrLanes in SW
maxNrLanes   = 16
maxAlignment = 4*maxNrLanes              # [B]
sizeOfDType  = np.dtype(dtype).itemsize  # [B]
R_ext = int(R + (maxAlignment / sizeOfDType))
C_ext = int(C + (maxAlignment / sizeOfDType))

# Vector of samples (padding is random since it does not impact performance)
A = np.random.rand(R_ext, C_ext).astype(dtype)
B = np.zeros([R_ext, C_ext], dtype=dtype)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("R", np.array(R, dtype=np.uint64))
emit("C", np.array(C, dtype=np.uint64))
emit("TSTEPS", np.array(TSTEPS, dtype=np.uint64))
emit("A_v", A, 'NR_LANES*4')
emit("B_v", B, 'NR_LANES*4')
emit("A_s", A, 'NR_LANES*4')
emit("B_s", B, 'NR_LANES*4')
