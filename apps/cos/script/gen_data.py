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

# Arguments: element count and FP64 and/or FP32 (same count for each)
PRECISIONS = ("FP64", "FP32")
args = sys.argv[1:]
prec = set(a.upper() for a in args if a.upper() in PRECISIONS)
nums = [a for a in args if a.upper() not in PRECISIONS]
if not prec:
  sys.stderr.write("Error. Give me at least one precision: %s.\n" % "/".join(PRECISIONS))
  sys.exit(1)
if not nums:
  sys.stderr.write("Error. Give me the number of vector elements.\n")
  sys.exit(1)
N = int(nums[0])

# Create the file
print(".section .data,\"aw\",@progbits")

# Align the arrays to NR_LANES*8 (AxiWideBeWidth)
for tag, dtype in (("f64", np.float64), ("f32", np.float32)):
  if "FP" + tag[1:] not in prec:
    continue
  angles = rand_matrix(N, dtype).astype(dtype)
  emit("N_" + tag, np.array(N, dtype=np.uint64))
  emit("angles_" + tag, angles, 'NR_LANES*8')
  emit("results_" + tag, np.zeros(N, dtype=dtype), 'NR_LANES*8')
  emit("gold_results_" + tag, np.cos(angles, dtype=dtype), 'NR_LANES*8')
