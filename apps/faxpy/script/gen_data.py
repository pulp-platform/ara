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
  # Pad to whole .words (a lone fp16 scalar is 2 bytes)
  bs += b"\x00" * (-len(bs) % 4)
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

# Everything goes into .data: Ara's linker script (common/arch.link.ld) has no
# .host or .vector output section, and .data is already ALIGN(8*nr_lanes).
# Vectors are aligned to NR_LANES*8 = AxiWideBeWidth; scalars keep 8.
print(".section .data,\"aw\",@progbits")
emit("vsize", np.array(vsize, dtype=np.uint64))

# Per precision: scalar a, golden, x, y (golden is unfused, vfmacc fused)
for tag, dtype in (("64", np.float64), ("32", np.float32), ("16", np.float16)):
  if "FP" + tag not in prec:
    continue
  x = np.random.rand(vsize).astype(dtype)
  y = np.random.rand(vsize).astype(dtype)
  a = np.random.rand(1).astype(dtype)
  emit("a" + tag, a)
  emit("gold" + tag, (a * x + y).astype(dtype), 'NR_LANES*8')
  emit("v%sx" % tag, x, 'NR_LANES*8')
  emit("v%sy" % tag, y, 'NR_LANES*8')
