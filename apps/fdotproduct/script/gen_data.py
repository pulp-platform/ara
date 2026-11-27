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

# Args: vector length, then FP64/FP32/FP16 tokens
PRECISIONS = ("FP64", "FP32", "FP16")
args = sys.argv[1:]
prec = set(a.upper() for a in args if a.upper() in PRECISIONS)
nums = [a for a in args if a.upper() not in PRECISIONS]
if not prec:
  sys.stderr.write("Error. Give me at least one precision: %s.\n" % "/".join(PRECISIONS))
  sys.exit(1)

# Vector length (default: no stripmine)
vsize = int(nums[0]) if nums else 64

print(".section .data,\"aw\",@progbits")
emit("vsize", np.array(vsize, dtype=np.uint64))

# Golden sums in float64, rounded once (an fp16 running sum stalls at 2048)
if "FP64" in prec:
  v64a = np.random.rand(vsize).astype(np.float64)
  v64b = np.random.rand(vsize).astype(np.float64)
  emit("v64a", v64a, 'NR_LANES*8')
  emit("v64b", v64b, 'NR_LANES*8')
  emit("gold64", np.array(np.dot(v64a, v64b), dtype=np.float64))
  emit("res64_v", np.array(0, dtype=np.float64))
  emit("res64_s", np.array(0, dtype=np.float64))

if "FP32" in prec:
  v32a = np.random.rand(vsize).astype(np.float32)
  v32b = np.random.rand(vsize).astype(np.float32)
  emit("v32a", v32a, 'NR_LANES*8')
  emit("v32b", v32b, 'NR_LANES*8')
  emit("gold32", np.array(np.dot(v32a.astype(np.float64), v32b.astype(np.float64)), dtype=np.float32))
  emit("res32_v", np.array(0, dtype=np.float32))
  emit("res32_s", np.array(0, dtype=np.float32))

if "FP16" in prec:
  v16a = np.random.rand(vsize).astype(np.float16)
  v16b = np.random.rand(vsize).astype(np.float16)
  emit("v16a", v16a, 'NR_LANES*8')
  emit("v16b", v16b, 'NR_LANES*8')
  # Duplicated to fill a whole .word (main.c reads the first)
  gold16 = np.float16(np.dot(v16a.astype(np.float64), v16b.astype(np.float64)))
  emit("gold16", np.array([gold16, gold16]), 'NR_LANES*8')
  # float32-sized for the same reason
  emit("res16_v", np.array(0, dtype=np.float32))
  emit("res16_s", np.array(0, dtype=np.float32))
