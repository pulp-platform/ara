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

# Precision tokens (FP64/FP32/FP16) after M N P select the emitted data
PRECISIONS = ("FP64", "FP32", "FP16")
args = sys.argv[1:]
prec = set(a.upper() for a in args if a.upper() in PRECISIONS)
nums = [a for a in args if a.upper() not in PRECISIONS]
if not prec or len(nums) != 3:
  print("Error. Give me three arguments M, N, P and at least one precision: %s."
        % "/".join(PRECISIONS), file=sys.stderr)
  print("C = AB with A=[MxN], B=[NxP], C=[MxP]", file=sys.stderr)
  sys.exit(1)
M, N, P = (int(x) for x in nums)

def gold(A, B, dtype):
  """Sequential fused multiply-accumulate, rounded to `dtype` after every step.

  This mirrors the hardware: vfmacc's destination is the accumulator itself, so
  each of the N steps rounds to the working precision. numpy's matmul instead
  accumulates in a wider type and rounds once, which at fp16 diverges far beyond
  rounding noise. float64 holds each fp16/fp32 product and partial sum exactly,
  so the only rounding is the deliberate one.
  """
  C = np.zeros([A.shape[0], B.shape[1]], dtype=dtype)
  A64 = A.astype(np.float64)
  B64 = B.astype(np.float64)
  for n in range(A.shape[1]):
    C = (C.astype(np.float64) + np.outer(A64[:, n], B64[n, :])).astype(dtype)
  return C

# Create the file
print(".section .data,\"aw\",@progbits")
emit("M", np.array(M, dtype=np.uint64))
emit("N", np.array(N, dtype=np.uint64))
emit("P", np.array(P, dtype=np.uint64))

for tag, dtype in (("64", np.float64), ("32", np.float32), ("16", np.float16)):
  if "FP" + tag not in prec:
    continue
  # Matrices and results
  A = np.random.rand(M, N).astype(dtype)
  B = np.random.rand(N, P).astype(dtype)
  C = np.zeros([M, P], dtype=dtype)
  emit("a" + tag, A, 'NR_LANES*8')
  emit("b" + tag, B, 'NR_LANES*8')
  emit("c" + tag, C, 'NR_LANES*8')
  emit("g" + tag, gold(A, B, dtype), 'NR_LANES*8')
