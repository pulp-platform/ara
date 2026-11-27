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

# Args: M_ROW [M_COL] (default square), then FP64/FP32/FP16 tokens
# res[M_COL] = vec[M_ROW] * mat[M_ROW][M_COL]
PRECISIONS = ("FP64", "FP32", "FP16")
args = sys.argv[1:]
prec = set(a.upper() for a in args if a.upper() in PRECISIONS)
nums = [a for a in args if a.upper() not in PRECISIONS]
if not prec:
  sys.stderr.write("Error. Give me at least one precision: %s.\n" % "/".join(PRECISIONS))
  sys.exit(1)
if len(nums) > 1:
  M_ROW, M_COL = int(nums[0]), int(nums[1])
elif len(nums) == 1:
  M_ROW = M_COL = int(nums[0])
else:
  # Default: no stripmine
  M_ROW = M_COL = 64

# Print information on file
print(".section .l2,\"aw\",@progbits")
emit("M_ROW", np.array(M_ROW, dtype=np.uint64))
emit("M_COL", np.array(M_COL, dtype=np.uint64))

# The golden output is computed in float64 and rounded once
for tag, dtype in (("64", np.float64), ("32", np.float32), ("16", np.float16)):
  if "FP" + tag not in prec:
    continue
  matrix = np.random.rand(M_ROW, M_COL).astype(dtype)
  vector = np.random.rand(M_ROW).astype(dtype)
  gold = (vector.astype(np.float64) @ matrix.astype(np.float64)).astype(dtype)
  result = np.zeros(M_COL, dtype=dtype)
  emit("gold" + tag, gold, 'NR_LANES*8')
  emit("mat" + tag, matrix, 'NR_LANES*8')
  emit("vec" + tag, vector, 'NR_LANES*8')
  emit("res" + tag, result, 'NR_LANES*8')
